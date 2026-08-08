#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
studio_assets="$repo_dir/apps/devex_studio/build/jaspr"
chrome_debug_port="${DEVEX_CHROME_DEBUG_PORT:-9515}"
dev_pid=""
chrome_pid=""
chrome_profile=""
studio_origin=""
host_origin=""
stale_probe=""
dev_log=""

cleanup_dev() {
  if [[ -n "$dev_pid" ]] && kill -0 "$dev_pid" 2>/dev/null; then
    kill -INT "$dev_pid" 2>/dev/null || true
    for _ in $(seq 1 100); do
      if ! kill -0 "$dev_pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$dev_pid" 2>/dev/null; then
      kill -TERM "$dev_pid" 2>/dev/null || true
    fi
    wait "$dev_pid" 2>/dev/null || true
  fi
  dev_pid=""
}

cleanup() {
  cleanup_dev
  if [[ -n "$chrome_pid" ]] && kill -0 "$chrome_pid" 2>/dev/null; then
    kill -TERM "$chrome_pid" 2>/dev/null || true
    wait "$chrome_pid" 2>/dev/null || true
  fi
  if [[ -n "$chrome_profile" && -d "$chrome_profile" ]]; then
    case "$chrome_profile" in
      /tmp/devex-studio-chrome.*)
        find "$chrome_profile" -depth -delete 2>/dev/null || true
        ;;
      *)
        echo "Refusing to clean unexpected Chrome profile: $chrome_profile" >&2
        ;;
    esac
  fi
  if [[ -n "$stale_probe" && -f "$stale_probe" ]]; then
    rm -f -- "$stale_probe"
  fi
  if [[ -n "$dev_log" && -f "$dev_log" ]]; then
    rm -f -- "$dev_log"
  fi
}
trap cleanup EXIT INT TERM

if command -v google-chrome-stable >/dev/null 2>&1; then
  chromium_executable="$(command -v google-chrome-stable)"
elif command -v google-chrome >/dev/null 2>&1; then
  chromium_executable="$(command -v google-chrome)"
elif command -v chromium >/dev/null 2>&1; then
  chromium_executable="$(command -v chromium)"
else
  echo "Chrome/Chromium is required for Studio conformance." >&2
  exit 1
fi
command -v jq >/dev/null 2>&1

if [[ "${DEVEX_SKIP_STUDIO_BUILD:-0}" != "1" ]]; then
  (
    cd "$repo_dir/apps/devex_studio"
    jaspr build
  )
fi

chrome_profile="$(mktemp -d /tmp/devex-studio-chrome.XXXXXX)"
"$chromium_executable" \
  --headless=new \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$chrome_debug_port" \
  --remote-allow-origins="http://127.0.0.1:$chrome_debug_port" \
  --user-data-dir="$chrome_profile" \
  --no-first-run \
  --disable-gpu \
  --window-size=1440,1000 \
  --noerrdialogs \
  about:blank >/dev/null 2>&1 &
chrome_pid=$!
for _ in $(seq 1 100); do
  if curl --fail --silent "http://127.0.0.1:$chrome_debug_port/json/version" >/dev/null; then
    break
  fi
  sleep 0.1
done
curl --fail --silent "http://127.0.0.1:$chrome_debug_port/json/version" >/dev/null

start_dev() {
  local config_path="$1"
  local profile_override="${2:-}"
  local profile_args=()
  if [[ -n "$profile_override" ]]; then
    profile_args=(--profile "$profile_override")
  fi
  dev_log="$(mktemp "${TMPDIR:-/tmp}/devex-studio-run.XXXXXX.jsonl")"
  (
    cd "$sample_dir"
    exec dart run ../../apps/devex_cli/bin/devex.dart --json dev \
      --config "$config_path" \
      "${profile_args[@]}" \
      --no-open \
      --studio-assets "$studio_assets"
  ) >"$dev_log" 2>&1 &
  dev_pid=$!

  local ready=""
  for _ in $(seq 1 240); do
    ready="$(jq -c 'select(.ok == true and .result.status == "ready")' "$dev_log" 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$ready" ]]; then
      break
    fi
    if ! kill -0 "$dev_pid" 2>/dev/null; then
      cat "$dev_log" >&2
      return 1
    fi
    sleep 0.25
  done
  if [[ -z "$ready" ]]; then
    cat "$dev_log" >&2
    echo "Timed out waiting for devex dev readiness." >&2
    return 1
  fi
  studio_origin="$(jq -r '.result.studioOrigin' <<<"$ready")"
  host_origin="$(jq -r '.result.hostOrigin' <<<"$ready")"
  [[ "$studio_origin" == http://127.0.0.1:* ]]
  [[ "$host_origin" == http://127.0.0.1:* ]]
}

assert_preview_snapshot() {
  local payload="$1"
  if ! jq -e '
    .applications == 1 and
    .journeys == 1 and
    .scenarios == 5 and
    .variants == 3 and
    .providers == ["evidence.auto-preview"] and
    .collected == 7 and
    .fresh == 7 and
    .validatedPngs == 7 and
    ([.projectionStates[] | select(.scenarioId != null)] | length) == 7 and
    ([.projectionStates[] | select(.scenarioId != null) | .freshness] | unique) == ["fresh"] and
    ([.projectionStates[] | select(.scenarioId != null) | .fidelity] | unique) == ["structural"] and
    ([.projectionStates[] | select(.scenarioId != null) | .capturePolicyId] | unique) == ["static-v1"] and
    ([.projectionStates[] | select(.scenarioId != null) | .executionFingerprintDigest |
      startswith("sha256:")] | all) and
    (.rpcMethods | index("devex.preview.collect")) != null
  ' <<<"$payload" >/dev/null; then
    echo "Preview snapshot assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
}

assert_stale_snapshot() {
  local payload="$1"
  if ! jq -e '
    .variants == 3 and
    .collected == 7 and
    .validatedPngs == 7 and
    ([.projectionStates[] | select(.scenarioId != null) | .freshness] | unique) == ["stale"]
  ' <<<"$payload" >/dev/null; then
    echo "Stale snapshot assertion failed:" >&2
    jq . <<<"$payload" >&2
    return 1
  fi
}

echo "[studio-vertical] starting journey-preview" >&2
start_dev "devex.yaml" "journey-preview"
echo "[studio-vertical] collecting seven AutoPreview captures" >&2
preview_payload="$(dart run "$repo_dir/tool/studio_rpc_probe.dart" "$studio_origin" --collect)"
assert_preview_snapshot "$preview_payload"
echo "[studio-vertical] validating release Studio in Chromium" >&2
browser_payload="$(dart run "$repo_dir/tool/studio_jaspr_cdp_probe.dart" \
  "http://127.0.0.1:$chrome_debug_port" \
  "$studio_origin/journeys/operate-delivery-workspace/scenarios/dashboard-ready")"
jq -e '
  .resourceRequests >= 1 and
  .severeBrowserLogs == 0 and
  .semanticHtml.flutterElementCount == 0 and
  .semanticHtml.unnamedFocusableCount == 0 and
  .keyboard.uniqueTabStops >= 5 and
  .reflow200Percent.horizontalDocumentOverflow == false and
  .reducedMotion.queryMatches == true and
  .performance.loadEventMs < 5000 and
  .mapInteraction.p95Ms < 100
' \
  <<<"$browser_payload" >/dev/null

stale_probe="$(mktemp "$sample_dir/lib/devex_stale_probe_XXXXXX.dart")"
printf '%s\n' '// Synthetic source-impact probe. Removed by the gate trap.' \
  >"$stale_probe"
echo "[studio-vertical] proving source edit marks evidence stale" >&2
stale_payload="$(dart run "$repo_dir/tool/studio_rpc_probe.dart" \
  "$studio_origin" --refresh)"
assert_stale_snapshot "$stale_payload"
echo "[studio-vertical] recollecting changed source to fresh" >&2
fresh_with_probe="$(dart run "$repo_dir/tool/studio_rpc_probe.dart" \
  "$studio_origin" --collect)"
assert_preview_snapshot "$fresh_with_probe"

rm -f -- "$stale_probe"
stale_probe=""
echo "[studio-vertical] proving source restoration marks evidence stale" >&2
restored_stale="$(dart run "$repo_dir/tool/studio_rpc_probe.dart" \
  "$studio_origin" --refresh)"
assert_stale_snapshot "$restored_stale"
echo "[studio-vertical] recollecting restored source to fresh" >&2
restored_fresh="$(dart run "$repo_dir/tool/studio_rpc_probe.dart" \
  "$studio_origin" --collect)"
assert_preview_snapshot "$restored_fresh"

first_studio_origin="$studio_origin"
first_host_origin="$host_origin"
cleanup_dev
if curl --silent --max-time 1 "$first_studio_origin/health" >/dev/null 2>&1 || \
   curl --silent --max-time 1 "$first_host_origin/health" >/dev/null 2>&1; then
  echo "Preview run left a listener behind." >&2
  exit 1
fi

echo "[studio-vertical] restarting with Journey Map and no provider" >&2
start_dev "devex.journey-no-evidence.yaml"
no_preview_payload="$(dart run "$repo_dir/tool/studio_rpc_probe.dart" "$studio_origin")"
jq -e '
  .variants == 0 and
  .providers == [] and
  .visualProjections == 0 and
  .validatedPngs == 0 and
  (.rpcMethods | map(startswith("devex.preview.")) | any) == false
' <<<"$no_preview_payload" >/dev/null
no_preview_browser="$(dart run "$repo_dir/tool/studio_jaspr_cdp_probe.dart" \
  "http://127.0.0.1:$chrome_debug_port" \
  "$studio_origin/journeys/operate-delivery-workspace/scenarios/dashboard-ready" \
  --no-preview)"
jq -e '
  .resourceRequests >= 1 and
  .severeBrowserLogs == 0 and
  .mode == "no-preview" and
  .semanticHtml.flutterElementCount == 0 and
  .reflow200Percent.horizontalDocumentOverflow == false
' \
  <<<"$no_preview_browser" >/dev/null

second_studio_origin="$studio_origin"
second_host_origin="$host_origin"
cleanup_dev
if curl --silent --max-time 1 "$second_studio_origin/health" >/dev/null 2>&1 || \
   curl --silent --max-time 1 "$second_host_origin/health" >/dev/null 2>&1; then
  echo "No-provider run left a listener behind." >&2
  exit 1
fi

jq -n \
  --arg previewSnapshot "$(jq -r '.snapshotDigest' <<<"$restored_fresh")" \
  --arg browserScreenshot "$(jq -r '.screenshotDigest' <<<"$browser_payload")" \
  --arg noPreviewSnapshot "$(jq -r '.snapshotDigest' <<<"$no_preview_payload")" \
  --argjson browserPerformance "$(jq -c '.performance' <<<"$browser_payload")" \
  --argjson mapInteraction "$(jq -c '.mapInteraction' <<<"$browser_payload")" \
  --argjson browserAccessibility "$(jq -c '{semanticHtml, keyboard, reflow200Percent, reducedMotion}' <<<"$browser_payload")" \
  '{
    status: "passed",
    previewSnapshotDigest: $previewSnapshot,
    browserScreenshotDigest: $browserScreenshot,
    noPreviewSnapshotDigest: $noPreviewSnapshot,
    variants: 3,
    validatedPngs: 7,
    fidelity: "structural",
    sourceImpact: "stale-to-fresh",
    cleanup: "verified",
    browserPerformance: $browserPerformance,
    mapInteraction: $mapInteraction,
    browserAccessibility: $browserAccessibility
  }'
