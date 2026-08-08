#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

runtime_root="$(mktemp -d /tmp/external-distribution.XXXXXX)"
host_pid=""
cleanup() {
  local original_status=$?
  if [[ -n "$host_pid" ]] && kill -0 "$host_pid" 2>/dev/null; then
    kill -TERM "$host_pid" 2>/dev/null || true
    wait "$host_pid" 2>/dev/null || true
  fi
  case "$runtime_root" in
    /tmp/external-distribution.*)
      find "$runtime_root" -depth -delete 2>/dev/null || true
      ;;
    *)
      echo "Refusing to clean unexpected external distribution root." >&2
      original_status=1
      ;;
  esac
  return "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

base_bundle="$runtime_root/base-headless"
external_root="$runtime_root/acme-external"
bundle_a="$runtime_root/acme-1.0.0-a"
bundle_b="$runtime_root/acme-1.0.0-b"
bundle_cli="$runtime_root/acme-1.0.0-cli"
bundle_update="$runtime_root/acme-1.0.1"
install_root="$runtime_root/install"

dart run apps/workspace_cli/tool/build_distribution.dart \
  --profile gateway-lab-headless \
  --output "$base_bundle" \
  --version 0.3.0-preview.1

dart run tools/generators/prepare_external_distribution_consumer.dart "$external_root"
if rg -n "package:[^'\"]+/src/|/src/" \
  "$external_root/consumer/bin/compose.dart"; then
  echo "External consumer imports a non-public library." >&2
  exit 1
fi

(
  cd "$external_root/consumer"
  dart run bin/compose.dart "$base_bundle" "$bundle_a" 1.0.0
  dart run bin/compose.dart "$base_bundle" "$bundle_b" 1.0.0
  dart run bin/compose.dart "$base_bundle" "$bundle_update" 1.0.1
)
diff -qr "$bundle_a" "$bundle_b" >/dev/null

jq -e '
  .schemaVersion == 2 and
  .distribution.id == "acme-experience" and
  .releaseVersion == "1.0.0" and
  .profiles == ["gateway-lab-headless"] and
  (.entrypoints | keys | sort) == ["cli", "gateway", "host"] and
  (.entrypoints.studio == null) and
  ([.files[].path] | index("consumer/inventory.json") != null) and
  ([.files[].path] | index("consumer/workspace/workspace.yaml") != null) and
  ([.files[].path] | index("consumer/workspace/.experience/ready.yaml") != null)
' "$bundle_a/distribution.json" >/dev/null
test ! -e "$bundle_a/studio"
jq -e '
  .kind == "ConsumerDistributionInventory" and
  .distributionId == "acme-experience" and
  .profileId == "gateway-lab-headless" and
  .studioAssets == "absent" and
  .compatibility.core == "^0.1.0" and
  .compatibility.distributionReleaseSchemaVersion == 2 and
  .compatibility.consumerConfigurationSchemaVersion == 2 and
  (.modules | map(.id) | index("studio.shell") == null) and
  (.files | map(.role) | index("content") != null)
' "$bundle_a/consumer/inventory.json" >/dev/null
jq -e '
  .distribution.id == "acme-experience" and
  .workspace.id == "acme-workspace" and
  (.scenarios | map(.id) | index("acme-ready") != null)
' "$bundle_a/consumer/catalog.json" >/dev/null

"$bundle_a/bin/workspace" --json distribution verify-bundle \
  --bundle "$bundle_a" >/dev/null
"$bundle_a/bin/workspace" --json distribution compose-consumer \
  --base-bundle "$base_bundle" \
  --workspace "$external_root" \
  --specification "$bundle_a/consumer/distribution-spec.json" \
  --output "$bundle_cli" >"$runtime_root/cli-compose.json"
jq -e '
  .ok == true and
  .result.distributionId == "acme-experience" and
  .result.studioAssets == "absent"
' "$runtime_root/cli-compose.json" >/dev/null
diff -qr "$bundle_a" "$bundle_cli" >/dev/null

"$bundle_a/bin/workspace" --json distribution install \
  --bundle "$bundle_a" \
  --install-root "$install_root" >"$runtime_root/install.json"
"$install_root/bin/acme-experience" --json distribution status \
  --install-root "$install_root" >"$runtime_root/status.json"
jq -e '
  .ok == true and
  .result.installed == true and
  .result.healthy == true and
  .result.distributionId == "acme-experience" and
  .result.currentVersion == "1.0.0"
' "$runtime_root/status.json" >/dev/null

if [[ "${EXTERNAL_DISTRIBUTION_FAIL_AFTER_INSTALL:-0}" == "1" ]]; then
  exit 97
fi

plan_digest="$(jq -r '.resolvedPlanDigest' \
  "$install_root/current/consumer/inventory.json")"
catalog_digest="$(jq -r '.moduleCatalogDigest' \
  "$install_root/current/consumer/inventory.json")"
host_log="$runtime_root/host.jsonl"
env \
  WORKSPACE_HOST_TOKEN=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef \
  STUDIO_ORIGIN=http://127.0.0.1:19461 \
  WORKSPACE_ROOT="$external_root" \
  MODULE_CATALOG_PATH="$install_root/current/modules/module-catalog.json" \
  RESOLVED_COMPOSITION_PLAN="$install_root/current/consumer/resolved-kit-plan.json" \
  RESOLVED_COMPOSITION_PLAN_DIGEST="$plan_digest" \
  GATEWAY_COMMAND="$install_root/current/bin/gateway_sidecar" \
  "$install_root/bin/workspace_host" >"$host_log" 2>"$runtime_root/host.err" &
host_pid=$!
for _ in $(seq 1 120); do
  if jq -e '
    select(
      .status == "ready" and
      .planDigest == $plan and
      .moduleCatalogDigest == $catalog and
      .effectiveKitManifest.studioContributions == []
    )
  ' --arg plan "$plan_digest" --arg catalog "$catalog_digest" \
    "$host_log" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$host_pid" 2>/dev/null; then
    echo "Installed headless Host exited before readiness." >&2
    sed -n '1,80p' "$runtime_root/host.err" >&2
    exit 1
  fi
  sleep 0.25
done
jq -e '
  select(
    .status == "ready" and
    .planDigest == $plan and
    .moduleCatalogDigest == $catalog and
    .effectiveKitManifest.studioContributions == []
  )
' --arg plan "$plan_digest" --arg catalog "$catalog_digest" \
  "$host_log" >/dev/null
if [[ "${EXTERNAL_DISTRIBUTION_FAIL_WHILE_HOST_READY:-0}" == "1" ]]; then
  exit 98
fi
kill -TERM "$host_pid"
wait "$host_pid"
host_pid=""

"$install_root/bin/acme-experience" --json distribution install \
  --bundle "$bundle_update" \
  --install-root "$install_root" >"$runtime_root/update.json"
jq -e '
  .result.currentVersion == "1.0.1" and
  .result.previousVersion == "1.0.0" and
  .result.healthy == true
' "$runtime_root/update.json" >/dev/null
"$install_root/bin/acme-experience" --json distribution rollback \
  --install-root "$install_root" >"$runtime_root/rollback.json"
jq -e '
  .result.currentVersion == "1.0.0" and
  .result.previousVersion == "1.0.1" and
  .result.healthy == true
' "$runtime_root/rollback.json" >/dev/null

"$install_root/bin/acme-experience" --json distribution status \
  --install-root "$install_root" >"$runtime_root/final-status.json"
jq -e '
  .result.installed == true and
  .result.healthy == true and
  .result.currentVersion == "1.0.0"
' "$runtime_root/final-status.json" >/dev/null

jq -n \
  --arg releaseDigest "$(jq -r '.digest' "$bundle_a/distribution.json")" \
  --arg inventoryDigest "$(jq -r '.digest' "$bundle_a/consumer/inventory.json")" \
  --arg planDigest "$plan_digest" \
  --arg catalogDigest "$(jq -r '.catalogDigest' "$bundle_a/consumer/inventory.json")" \
  '{
    schemaVersion: 1,
    status: "passed",
    externalConsumer: true,
    publicApiOnly: true,
    deterministicBundles: true,
    distributionId: "acme-experience",
    profileId: "gateway-lab-headless",
    studioAssetsAbsent: true,
    cliIncluded: true,
    hostIncluded: true,
    installPassed: true,
    statusPassed: true,
    updatePassed: true,
    rollbackPassed: true,
    headlessHostPassed: true,
    releaseDigest: $releaseDigest,
    inventoryDigest: $inventoryDigest,
    resolvedPlanDigest: $planDigest,
    catalogDigest: $catalogDigest
  }'
