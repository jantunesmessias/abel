#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repo_root"

for command in mise jq sha256sum find sort xargs; do
  command -v "$command" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 1
  }
done

fixture_source="$repo_root/examples/sample_flutter"
temp_parent="${MCP_TEMP_ROOT:-/tmp}"
[[ -d "$temp_parent" && ! -L "$temp_parent" ]] || {
  printf 'MCP temporary root is unavailable\n' >&2
  exit 1
}
fixture_root="$(mktemp -d "$temp_parent/experience-mcp.XXXXXX")"
chmod 700 "$fixture_root"

cleanup() {
  if [[ -n "${fixture_root:-}" &&
        -d "$fixture_root" &&
        ! -L "$fixture_root" &&
        "$fixture_root" == "$temp_parent"/experience-mcp.* ]]; then
    rm -rf -- "$fixture_root"
  fi
}
trap cleanup EXIT INT TERM

tree_digest() {
  local root="$1"
  (
    cd "$root"
    find . -type f -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 sha256sum \
      | sha256sum \
      | awk '{print $1}'
  )
}

source_before="$(tree_digest "$fixture_source/.experience")"
config_before="$(sha256sum "$fixture_source/workspace.yaml" | awk '{print $1}')"
app_before="$(sha256sum "$fixture_source/lib/app_factory.dart" | awk '{print $1}')"

cp "$fixture_source/workspace.yaml" "$fixture_root/workspace.yaml"
cp -a "$fixture_source/.experience" "$fixture_root/.experience"
mkdir -p "$fixture_root/lib" "$fixture_root/.dart_tool"
cp "$fixture_source/lib/app_factory.dart" "$fixture_root/lib/app_factory.dart"
cp "$repo_root/.dart_tool/package_config.json" \
  "$fixture_root/.dart_tool/package_config.json"

if [[ "${MCP_INJECT_FAILURE:-}" == "after-copy" ]]; then
  printf 'Injected MCP vertical failure after isolated copy\n' >&2
  exit 97
fi

probe_stderr="$fixture_root/probe.stderr"
if ! probe_output="$(
  mise exec -- dart run tools/probes/mcp_experience_stdio_probe.dart \
    --config "$fixture_root/workspace.yaml" \
    --workspace "$fixture_root" \
    2>"$probe_stderr"
)"; then
  printf 'MCP probe execution failed\n' >&2
  exit 1
fi

[[ ! -s "$probe_stderr" ]] || {
  printf 'MCP probe emitted stderr\n' >&2
  exit 1
}

printf '%s\n' "$probe_output" \
  | jq -e '
      type == "object" and
      keys == [
        "acceptanceSeparateFromHumanApproval",
        "authoringConceptProposed",
        "authoringFindingRecorded",
        "authoringGrantConsumed",
        "authoringMoved",
        "authoringOpened",
        "authoringReplayExact",
        "authoringReviewPrepared",
        "automatedAcceptancePassed",
        "capabilityMismatchConsumed",
        "capabilityRevoked",
        "captureDiffPassed",
        "captureHeight",
        "captureWidth",
        "catalogBound",
        "contextDeterministic",
        "contextItemCount",
        "contextOmissionCount",
        "pathConfinementProved",
        "queryCount",
        "resourceCount",
        "sourceRedactionProved",
        "testPassedCount",
        "toolCount"
      ] and
      .toolCount == 35 and
      .resourceCount == 6 and
      .queryCount == 9 and
      .contextItemCount > 0 and
      .contextOmissionCount >= 0 and
      .testPassedCount == 1 and
      .captureWidth == 1 and
      .captureHeight == 1 and
      .acceptanceSeparateFromHumanApproval == true and
      .authoringConceptProposed == true and
      .authoringFindingRecorded == true and
      .authoringGrantConsumed == true and
      .authoringMoved == true and
      .authoringOpened == true and
      .authoringReplayExact == true and
      .authoringReviewPrepared == true and
      .automatedAcceptancePassed == true and
      .capabilityMismatchConsumed == true and
      .capabilityRevoked == true and
      .captureDiffPassed == true and
      .catalogBound == true and
      .contextDeterministic == true and
      .pathConfinementProved == true and
      .sourceRedactionProved == true
    ' >/dev/null || {
  printf 'MCP public proof did not satisfy the canonical contract\n' >&2
  exit 1
}

audit_file="$fixture_root/.dart_tool/workspace/full-local/mcp/automation-audit.json"
[[ -f "$audit_file" && ! -L "$audit_file" ]] || {
  printf 'MCP automation audit was not persisted\n' >&2
  exit 1
}
jq -e '
  .schemaVersion == 1 and
  .kind == "McpAutomationAudit" and
  (.records | type == "array" and length >= 9) and
  ([.records[].sequence] == [range(1; (.records | length) + 1)])
' "$audit_file" >/dev/null || {
  printf 'MCP automation audit did not satisfy the durable contract\n' >&2
  exit 1
}

if printf '%s\n' "$probe_output" | rg -q \
  'MCP_REDACTION_SECRET|capabilityId|capabilityDigest|grantId|grantDigest|principalId|authorityId|contentRoot|/home/|file://'; then
  printf 'MCP public proof contains private material\n' >&2
  exit 1
fi

if [[ "$(tree_digest "$fixture_source/.experience")" != "$source_before" ||
      "$(sha256sum "$fixture_source/workspace.yaml" | awk '{print $1}')" != \
        "$config_before" ||
      "$(sha256sum "$fixture_source/lib/app_factory.dart" | awk '{print $1}')" != \
        "$app_before" ]]; then
  printf 'MCP isolated execution modified the reference consumer\n' >&2
  exit 1
fi

printf '%s\n' "$probe_output"
