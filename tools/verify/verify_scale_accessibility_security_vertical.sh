#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
studio_assets="$repo_dir/apps/studio/build/jaspr"
host_port="${SCALE_HOST_PORT:-7677}"
studio_port="${SCALE_STUDIO_PORT:-7678}"
driver_port="${SCALE_DRIVER_PORT:-9518}"
capture_dir="${SCALE_CAPTURE_DIR:-}"
scenario_count="${SCALE_SCENARIOS:-2000}"
transition_count="${SCALE_TRANSITIONS:-20000}"
edge_count="${SCALE_EDGES:-20000}"
max_authoring_files="${SCALE_MAX_AUTHORING_FILES:-50000}"
max_authoring_file_bytes="${SCALE_MAX_AUTHORING_FILE_BYTES:-1048576}"
max_authoring_bytes="${SCALE_MAX_AUTHORING_BYTES:-33554432}"
max_elapsed_ms="${SCALE_MAX_ELAPSED_MS:-30000}"
max_rss_bytes="${SCALE_MAX_RSS_BYTES:-1610612736}"
max_export_bytes="${SCALE_MAX_EXPORT_BYTES:-16777216}"
max_window_p95_micros="${SCALE_MAX_WINDOW_P95_MICROS:-50000}"
runtime_root=""
dev_pid=""
driver_pid=""
stage="preflight"
toolchain=()
if command -v mise >/dev/null 2>&1; then
  toolchain=(mise exec --)
fi

is_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_port() {
  is_integer "$1" && ((10#$1 >= 1024 && 10#$1 <= 65535))
}

port_is_listening() {
  ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

stop_group() {
  local process_id="$1"
  if [[ -z "$process_id" || ! "$process_id" =~ ^[0-9]+$ ]]; then
    return
  fi
  kill -TERM -- "-$process_id" 2>/dev/null || true
  for _ in $(seq 1 100); do
    if ! kill -0 "$process_id" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done
  if kill -0 "$process_id" 2>/dev/null; then
    kill -KILL -- "-$process_id" 2>/dev/null || true
  fi
  wait "$process_id" 2>/dev/null || true
}

delete_runtime_root() {
  case "$1" in
    /tmp/studio-scale-vertical.*)
      if [[ -d "$1" && ! -L "$1" ]]; then
        find "$1" -depth -delete
      fi
      ;;
    *)
      echo "Refusing to delete an unexpected scale runtime root." >&2
      return 1
      ;;
  esac
}

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  stop_group "$dev_pid"
  stop_group "$driver_pid"
  for port in "$host_port" "$studio_port" "$driver_port"; do
    if is_port "$port" && port_is_listening "$port"; then
      status=1
    fi
  done
  if [[ -n "$runtime_root" ]]; then
    delete_runtime_root "$runtime_root" || status=1
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "Scale/accessibility/security vertical failed at $stage; private runtime artifacts were removed." >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

inject_failure() {
  if [[ "${SCALE_FAIL_AT:-}" == "$1" ]]; then
    exit 97
  fi
}

for command_name in chromedriver cmp cp curl diff find grep head jq mktemp setsid \
  sha256sum ss tail; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Scale vertical requires command: $command_name" >&2
    exit 1
  }
done
for value in "$scenario_count" "$transition_count" "$edge_count" \
  "$max_authoring_files" "$max_authoring_file_bytes" "$max_authoring_bytes" \
  "$max_elapsed_ms" "$max_rss_bytes" "$max_export_bytes" \
  "$max_window_p95_micros"; do
  is_integer "$value" || {
    echo "Scale vertical budgets must be positive integers." >&2
    exit 1
  }
done
if ((scenario_count < 2000 || transition_count < 20000 ||
  edge_count < 20000 || edge_count > transition_count)); then
  echo "Scale vertical cardinalities are below the required corpus." >&2
  exit 1
fi
for port in "$host_port" "$studio_port" "$driver_port"; do
  if ! is_port "$port" || port_is_listening "$port"; then
    echo "Scale vertical requires three unused valid local ports." >&2
    exit 1
  fi
done
case "${SCALE_FAIL_AT:-}" in
  "" | corpus | host-ready | browser) ;;
  *)
    echo "SCALE_FAIL_AT names an unknown boundary." >&2
    exit 1
    ;;
esac
if [[ -n "$capture_dir" ]]; then
  case "$capture_dir" in
    /tmp/studio-scale-capture.*)
      if [[ ! -d "$capture_dir" || -L "$capture_dir" ||
        -n "$(find "$capture_dir" -mindepth 1 -print -quit)" ]]; then
        echo "Scale capture directory must be an empty private directory." >&2
        exit 1
      fi
      chmod 700 "$capture_dir"
      ;;
    *)
      echo "Scale capture directory must use the dedicated /tmp prefix." >&2
      exit 1
      ;;
  esac
fi

driver_major="$(chromedriver --version | grep -oE '[0-9]+' | head -n 1)"
chromium_executable=""
for browser_name in google-chrome-stable google-chrome chromium; do
  if command -v "$browser_name" >/dev/null 2>&1; then
    candidate="$(command -v "$browser_name")"
    browser_major="$($candidate --version | grep -oE '[0-9]+' | head -n 1)"
    if [[ "$browser_major" == "$driver_major" ]]; then
      chromium_executable="$candidate"
      break
    fi
  fi
done
if [[ -z "$chromium_executable" ]]; then
  echo "Scale vertical requires matching Chrome and ChromeDriver majors." >&2
  exit 1
fi
if ((${#toolchain[@]} == 0)); then
  command -v dart >/dev/null 2>&1
  command -v jaspr >/dev/null 2>&1
fi

if [[ "${SCALE_SKIP_STUDIO_BUILD:-0}" != "1" ]]; then
  stage="studio-build"
  (
    cd "$repo_dir/apps/studio"
    "${toolchain[@]}" jaspr build
  ) >/dev/null
fi
if [[ ! -f "$studio_assets/index.html" ||
  ! -f "$studio_assets/main.client.dart.js" ]]; then
  echo "Scale vertical requires a built Studio." >&2
  exit 1
fi

stage="corpus"
runtime_root="$(mktemp -d /tmp/studio-scale-vertical.XXXXXX)"
chmod 700 "$runtime_root"
mkdir -m 700 "$runtime_root/out-a" "$runtime_root/out-b"
for suffix in a b; do
  "${toolchain[@]}" dart run tools/generators/generate_scale_corpus.dart \
    --output "$runtime_root/workspace-$suffix" \
    --scenarios "$scenario_count" \
    --transitions "$transition_count" \
    --edges "$edge_count" >"$runtime_root/generate-$suffix.json"
  "${toolchain[@]}" dart run tools/verify/verify_scale_corpus.dart \
    --workspace "$runtime_root/workspace-$suffix" \
    --export "$runtime_root/out-$suffix/export.json" \
    --report "$runtime_root/out-$suffix/report.json" \
    --scenarios "$scenario_count" \
    --transitions "$transition_count" \
    --edges "$edge_count" \
    --max-authoring-files "$max_authoring_files" \
    --max-authoring-file-bytes "$max_authoring_file_bytes" \
    --max-authoring-bytes "$max_authoring_bytes" \
    --max-elapsed-ms "$max_elapsed_ms" \
    --max-rss-bytes "$max_rss_bytes" \
    --max-export-bytes "$max_export_bytes" \
    --max-window-p95-micros "$max_window_p95_micros" \
    --max-rendered-items 64 \
    --max-renderable-edges 256 \
    --max-boundary-edges 256 >"$runtime_root/verify-$suffix.json"
done
diff -qr "$runtime_root/workspace-a" "$runtime_root/workspace-b" >/dev/null
cmp -s "$runtime_root/out-a/export.json" "$runtime_root/out-b/export.json"
jq -e \
  --argjson scenarios "$scenario_count" \
  --argjson transitions "$transition_count" \
  --argjson edges "$edge_count" '
    .status == "passed" and
    .corpus.scenarioCount == $scenarios and
    .corpus.nodeCount == $scenarios and
    .corpus.transitionCount == $transitions and
    .corpus.edgeCount == $edges and
    .virtualization.itemsBounded == true and
    .virtualization.edgesBounded == true and
    .virtualization.boundaryMemoryBounded == true and
    .incrementalCapture.complete == true and
    .incrementalCapture.directAndTransitive == true and
    .incrementalCapture.impactedCount == 8 and
    .descriptorBatches.workerStarts == 1 and
    .descriptorBatches.batchCount == 4 and
    .descriptorBatches.successCount == 255 and
    .descriptorBatches.failureCount == 1 and
    .descriptorBatches.successAfterFailure == true
  ' "$runtime_root/out-a/report.json" >/dev/null
inject_failure corpus

stage="webdriver-startup"
setsid chromedriver \
  --port="$driver_port" \
  --allowed-ips=127.0.0.1 \
  --allowed-origins="http://127.0.0.1:$driver_port" \
  >"$runtime_root/chromedriver.log" 2>&1 &
driver_pid=$!
for _ in $(seq 1 120); do
  if curl --fail --silent "http://127.0.0.1:$driver_port/status" |
    jq -e '.value.ready == true' >/dev/null 2>&1; then
    break
  fi
  kill -0 "$driver_pid" 2>/dev/null || exit 1
  sleep 0.1
done
curl --fail --silent "http://127.0.0.1:$driver_port/status" |
  jq -e '.value.ready == true' >/dev/null

stage="host-startup"
(
  cd "$repo_dir"
  exec setsid "${toolchain[@]}" dart run apps/workspace_cli/bin/workspace.dart \
    --json dev \
    --config "$runtime_root/workspace-a/workspace.yaml" \
    --profile journey-preview \
    --host-port "$host_port" \
    --studio-port "$studio_port" \
    --studio-assets "$studio_assets" \
    --no-open
) >"$runtime_root/dev.jsonl" 2>&1 &
dev_pid=$!
ready=""
for _ in $(seq 1 720); do
  ready="$(jq -c 'select(.ok == true and .result.status == "ready")' \
    "$runtime_root/dev.jsonl" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$ready" ]]; then
    break
  fi
  kill -0 "$dev_pid" 2>/dev/null || exit 1
  sleep 0.25
done
jq -e \
  --arg host "http://127.0.0.1:$host_port" \
  --arg studio "http://127.0.0.1:$studio_port" '
    .ok == true and
    .result.status == "ready" and
    .result.profileId == "journey-preview" and
    .result.hostOrigin == $host and
    .result.studioOrigin == $studio
  ' <<<"$ready" >/dev/null
inject_failure host-ready

stage="browser"
if ! "${toolchain[@]}" dart run tools/probes/studio_scale_browser_probe.dart \
  "http://127.0.0.1:$studio_port" \
  "http://127.0.0.1:$driver_port" \
  "$chromium_executable" \
  "$runtime_root/scale.png" >"$runtime_root/browser.json" \
  2>"$runtime_root/browser.stderr"; then
  if jq -e '
    (keys | sort) == ["failure", "stage"] and
    (.failure | IN("timeout", "protocol", "state", "filesystem", "unexpected"))
  ' "$runtime_root/browser.stderr" >/dev/null 2>&1; then
    jq -c '{stage, failure}' "$runtime_root/browser.stderr" >&2
  else
    echo '{"stage":"unknown","failure":"diagnostic-unavailable"}' >&2
  fi
  exit 1
fi
jq -e '
  .outlineTotal == 2000 and
  .outlineRendered > 0 and .outlineRendered <= 48 and
  .mapRenderedItems > 0 and .mapRenderedItems <= 64 and
  .mapRenderedEdges >= 0 and .mapRenderedEdges <= 256 and
  .mapBoundaryRetained >= 0 and .mapBoundaryRetained <= 256 and
  .mapBoundaryTotal >= .mapBoundaryRetained and
  .domElementCount <= 5000 and
  .landmarksNamed == true and
  .nonDragNavigation == true and
  .keyboardFocusVisible == true and
  .essentialControlCount >= 4 and
  .minimumTextContrast >= 4.5 and
  .reducedMotion == true and
  .textScale200Overflow == false and
  .horizontalOverflow360 == false and
  .transientMarkerCount == 0 and
  .severeBrowserLogs == 0 and
  (.screenshotDigest | startswith("sha256:"))
' "$runtime_root/browser.json" >/dev/null
if [[ -n "$capture_dir" ]]; then
  cp -- "$runtime_root/scale.png" "$capture_dir/scale-journey.png"
  chmod 600 "$capture_dir/scale-journey.png"
fi
inject_failure browser

jq -n \
  --slurpfile scale "$runtime_root/out-a/report.json" \
  --slurpfile browser "$runtime_root/browser.json" '
  {
    schemaVersion: 1,
    status: "passed",
    corpus: $scale[0].corpus,
    budgets: $scale[0].budgets,
    measurements: $scale[0].measurements,
    virtualization: $scale[0].virtualization,
    incrementalCapture: $scale[0].incrementalCapture,
    descriptorBatches: $scale[0].descriptorBatches,
    deterministicCleanExports: true,
    deterministicCleanCorpora: true,
    browser: $browser[0],
    noOrphanRuntimeArtifacts: true
  }'
