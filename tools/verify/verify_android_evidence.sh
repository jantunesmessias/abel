#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$sdk_root" ]]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME is required." >&2
  exit 2
fi
sdk_root="$(cd "$sdk_root" && pwd)"
avdmanager="$sdk_root/cmdline-tools/latest/bin/avdmanager"
if [[ ! -x "$sdk_root/platform-tools/adb" || ! -x "$sdk_root/emulator/emulator" || ! -x "$avdmanager" ]]; then
  echo "Android SDK is missing adb, emulator, or latest avdmanager." >&2
  exit 2
fi

host_port="${GATEWAY_HOST_PORT:-45901}"
target_port="${GATEWAY_TARGET_PORT:-55901}"
emulator_port="${ANDROID_EMULATOR_PORT:-5556}"
system_image="${ANDROID_SYSTEM_IMAGE:-system-images;android-35;google_apis;x86_64}"
avd_parent="${ANDROID_AVD_PARENT:-/dev/shm}"
required_avd_bytes=$((8 * 1024 * 1024 * 1024))
available_avd_bytes="$(df --output=avail -B1 "$avd_parent" | tail -1 | tr -d ' ')"
if (( available_avd_bytes < required_avd_bytes )); then
  echo "AVD parent requires at least 8 GiB free: $avd_parent" >&2
  exit 3
fi
if ss -Hln "sport = :$host_port" | rg -q . || ss -Hln "sport = :$target_port" | rg -q .; then
  echo "Configured Android evidence Gateway ports are already in use." >&2
  exit 3
fi
if "$sdk_root/platform-tools/adb" devices | rg -q "^emulator-$emulator_port\\s+"; then
  echo "Configured emulator port is already in use." >&2
  exit 3
fi

avd_root="$(mktemp -d "$avd_parent/workspace-android-evidence-avd.XXXXXX")"
avd_name="AndroidEvidence_$$"
gateway_pid=""
cleanup_verified=0
evidence_dir="$repo_dir/.dart_tool/workspace/android-evidence-gate/run-$$"
mkdir -p "$evidence_dir"

workspace() {
  ANDROID_AVD_HOME="$avd_root" dart run apps/workspace_cli/bin/workspace.dart \
    --json target android "$@" --sdk-root "$sdk_root"
}

workspace_cli() {
  ANDROID_AVD_HOME="$avd_root" dart run apps/workspace_cli/bin/workspace.dart --json "$@"
}

cleanup() {
  local original_status=$?
  set +e
  workspace tls-remove --apply >/dev/null 2>&1
  workspace remove --apply >/dev/null 2>&1
  if workspace stop --apply >/dev/null 2>&1; then
    cleanup_verified=1
  fi
  if [[ -n "$gateway_pid" ]]; then
    kill -TERM -- "-$gateway_pid" >/dev/null 2>&1
    wait "$gateway_pid" >/dev/null 2>&1
  fi
  if [[ "$cleanup_verified" -eq 1 || ! -e .dart_tool/workspace/full-local/android/managed-emulator-v1.json ]]; then
    case "$avd_root" in
      "$avd_parent"/workspace-android-evidence-avd.*) find "$avd_root" -depth -delete 2>/dev/null ;;
      *) echo "Refusing to clean unexpected AVD path: $avd_root" >&2 ;;
    esac
  else
    echo "AVD recovery state preserved at $avd_root" >&2
  fi
  return "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

printf 'no\n' | ANDROID_AVD_HOME="$avd_root" "$avdmanager" create avd \
  --force --name "$avd_name" --package "$system_image" --device pixel_6

(
  cd examples/sample_flutter
  flutter build apk --debug --target tool/target_main.dart
  ./android/gradlew --stop >/dev/null 2>&1 || true
)
apk="$repo_dir/examples/sample_flutter/build/app/outputs/flutter-apk/app-debug.apk"
test -s "$apk"

setsid dart run tools/probes/android_gateway_probe.dart --port "$host_port" \
  >"$evidence_dir/gateway.log" 2>&1 &
gateway_pid=$!
for _ in $(seq 1 30); do
  if curl --fail --silent "http://127.0.0.1:$host_port/health" | rg -q '^android-ok$'; then
    break
  fi
  sleep 1
done
curl --fail --silent "http://127.0.0.1:$host_port/health" | rg -q '^android-ok$'

workspace start --avd "$avd_name" --port "$emulator_port" --headless --apply \
  | tee "$evidence_dir/android-start.json"
workspace bootstrap --serial "emulator-$emulator_port" --host-port "$host_port" \
  --target-port "$target_port" --apply \
  | tee "$evidence_dir/android-bootstrap.json"
workspace verify | tee "$evidence_dir/android-verify.json"
workspace install --serial "emulator-$emulator_port" --apk "$apk" \
  | tee "$evidence_dir/android-install.json"
workspace launch --serial "emulator-$emulator_port" \
  --package io.github.jantunesmessias.sample_flutter --activity .MainActivity \
  --host-port "$host_port" --target-port "$target_port" \
  --overlay SESSION_ID=android-evidence-gate-session \
  --overlay SESSION_NONCE=0123456789abcdef \
  | tee "$evidence_dir/android-launch.json"

for _ in $(seq 1 30); do
  "$sdk_root/platform-tools/adb" -s "emulator-$emulator_port" \
    shell uiautomator dump /sdcard/workspace-v1-window.xml >/dev/null 2>&1 || true
  if "$sdk_root/platform-tools/adb" -s "emulator-$emulator_port" \
    shell cat /sdcard/workspace-v1-window.xml 2>/dev/null \
    | rg -q 'resource-id="gateway.health"[^>]+content-desc="Gateway: ready:android-ok"'; then
    break
  fi
  sleep 1
done
"$sdk_root/platform-tools/adb" -s "emulator-$emulator_port" \
  shell cat /sdcard/workspace-v1-window.xml \
  | rg -q 'resource-id="gateway.health"[^>]+content-desc="Gateway: ready:android-ok"'

workspace capture --serial "emulator-$emulator_port" \
  | tee "$evidence_dir/android-capture.json"
rg -q '"artifactDigest":"sha256:[0-9a-f]{64}"' "$evidence_dir/android-capture.json"

if [[ "${ANDROID_NATIVE_EVIDENCE:-0}" == "1" ]]; then
  workspace_cli compile --config examples/sample_flutter/workspace.yaml \
    | tee "$evidence_dir/android-v3-compile.json"
  catalog_digest="$(jq -r '.result.manifestDigest' "$evidence_dir/android-v3-compile.json")"
  apk_digest="sha256:$(sha256sum "$apk" | cut -d ' ' -f 1)"
  dart run tools/generators/generate_android_evidence_contracts.dart \
    --serial "emulator-$emulator_port" --output-dir "$evidence_dir/v3-contracts" \
    | tee "$evidence_dir/android-v3-contracts.json"
  workspace evidence --serial "emulator-$emulator_port" \
    --catalog-digest "$catalog_digest" \
    --evidence-workspace examples/sample_flutter \
    --containment-report "$evidence_dir/v3-contracts/containment.json" \
    --package io.github.jantunesmessias.sample_flutter --launch-profile android \
    --input-digest "apk=$apk_digest" --backend-mode isolated \
    --screen-recording --performance-trace --synthetic-data-confirmed \
    --duration-seconds 3 --output "$evidence_dir/android-evidence-manifest.json" \
    | tee "$evidence_dir/android-v3-evidence.json"
  jq -e '
    .result.evidence.fingerprint.runtimeFidelity == "hostNative" and
    .result.evidence.fingerprint.networkContainment == "gatewayOnly" and
    .result.androidManifest.syntheticDataConfirmed == true and
    (.result.androidManifest.observations | length == 5) and
    (.result.androidManifest.observations | all(
      if .role == "android.performance-trace"
      then (.status == "collected" or .status == "unavailable")
      else .status == "collected"
      end
    ))
  ' "$evidence_dir/android-v3-evidence.json" >/dev/null

  screenshot_digest="$(jq -r '.result.evidence.artifacts[] | select(.role == "android.screenshot") | .digest' "$evidence_dir/android-v3-evidence.json")"
  semantics_digest="$(jq -r '.result.evidence.artifacts[] | select(.role == "android.semantics") | .digest' "$evidence_dir/android-v3-evidence.json")"
  logcat_digest="$(jq -r '.result.evidence.artifacts[] | select(.role == "android.logcat") | .digest' "$evidence_dir/android-v3-evidence.json")"
  (cd examples/sample_flutter && dart run ../../apps/workspace_cli/bin/workspace.dart --json \
    evidence export-artifact --digest "$screenshot_digest" \
    --output "$evidence_dir/android-v3-screenshot.png" >/dev/null
  )
  (cd examples/sample_flutter && dart run ../../apps/workspace_cli/bin/workspace.dart --json \
    evidence export-artifact --digest "$semantics_digest" \
    --output "$evidence_dir/android-v3-semantics.json" >/dev/null
  )
  (cd examples/sample_flutter && dart run ../../apps/workspace_cli/bin/workspace.dart --json \
    evidence export-artifact --digest "$logcat_digest" \
    --output "$evidence_dir/android-v3-logcat.json" >/dev/null
  )
  jq -e '
    .privacy == "hashedTextV1" and
    ([.nodes[] | keys[]] | all(. != "text" and . != "content-desc" and . != "resource-id"))
  ' "$evidence_dir/android-v3-semantics.json" >/dev/null
  jq -e '
    .privacy == "hashedMessageV1" and
    ([.entries[] | keys[]] | all(. != "tag" and . != "message"))
  ' "$evidence_dir/android-v3-logcat.json" >/dev/null
  workspace_cli evidence compare-visual \
    --expected "$evidence_dir/android-v3-screenshot.png" \
    --actual "$evidence_dir/android-v3-screenshot.png" \
    --policy "$evidence_dir/v3-contracts/visual-policy.json" \
    --output "$evidence_dir/android-v3-visual-comparison.json" \
    | tee "$evidence_dir/android-v3-visual-gate.json"
  workspace_cli evidence compare-semantics \
    --expected "$evidence_dir/android-v3-semantics.json" \
    --actual "$evidence_dir/android-v3-semantics.json" \
    --policy "$evidence_dir/v3-contracts/semantic-policy.json" \
    --output "$evidence_dir/android-v3-semantic-comparison.json" \
    | tee "$evidence_dir/android-v3-semantic-gate.json"

  workspace_cli release build --config examples/sample_flutter/workspace.yaml \
    | tee "$evidence_dir/android-v3-release.json"
  release_directory="$(jq -r '.result.directory' "$evidence_dir/android-v3-release.json")"
  workspace_cli release bundle --directory "$release_directory" \
    --output "$evidence_dir/android-v3.evidence.zip" \
    | tee "$evidence_dir/android-v3-bundle.json"
  workspace_cli release verify-bundle --bundle "$evidence_dir/android-v3.evidence.zip" \
    | tee "$evidence_dir/android-v3-bundle-verify.json"
fi

workspace reset --serial "emulator-$emulator_port" \
  --package io.github.jantunesmessias.sample_flutter \
  | tee "$evidence_dir/android-reset.json"
if "$sdk_root/platform-tools/adb" -s "emulator-$emulator_port" \
  shell pidof io.github.jantunesmessias.sample_flutter >/dev/null 2>&1; then
  echo "Application process remained after package reset." >&2
  exit 5
fi

workspace tls-install --apply | tee "$evidence_dir/android-tls-install.json"
workspace tls-verify | tee "$evidence_dir/android-tls-verify.json"
remote_path="$(jq -r '.remotePath' .dart_tool/workspace/full-local/android/tls-v1.json)"
"$sdk_root/platform-tools/adb" -s "emulator-$emulator_port" shell test -f "$remote_path"
workspace tls-remove --apply | tee "$evidence_dir/android-tls-remove.json"
test ! -e .dart_tool/workspace/full-local/android/tls-v1.json
test ! -e .dart_tool/workspace/full-local/android/tls
if "$sdk_root/platform-tools/adb" -s "emulator-$emulator_port" shell test -e "$remote_path"; then
  echo "Workspace CA remained after undo." >&2
  exit 5
fi

workspace remove --apply | tee "$evidence_dir/android-remove.json"
workspace stop --apply | tee "$evidence_dir/android-stop.json"
cleanup_verified=1
for _ in $(seq 1 15); do
  if ! "$sdk_root/platform-tools/adb" devices | rg -q "^emulator-$emulator_port\\s+device"; then
    break
  fi
  sleep 1
done
if "$sdk_root/platform-tools/adb" devices | rg -q "^emulator-$emulator_port\\s+device"; then
  echo "Managed emulator remained after stop." >&2
  exit 5
fi

jq -s '{schemaVersion: 1, gate: "v1-android", reports: map({command, ok, result})}' \
  "$evidence_dir"/android-*.json >"$evidence_dir/android-gate-summary.json"
sha256sum "$apk" "$evidence_dir/android-gate-summary.json"
echo "Evidence: $evidence_dir"
echo "Android lifecycle, Gateway health, capture, reset, TLS, and undo passed."
