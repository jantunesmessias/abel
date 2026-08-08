#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
studio_assets="$repo_dir/apps/studio/build/jaspr"
host_port="${MOTION_CONTEXT_HOST_PORT:-7667}"
studio_port="${MOTION_CONTEXT_STUDIO_PORT:-7668}"
driver_port="${MOTION_CONTEXT_DRIVER_PORT:-9517}"
runtime_root=""
capture_dir=""
capture_dir_owned=0
dev_pid=""
driver_pid=""
stage="preflight"
toolchain=()
if command -v mise >/dev/null 2>&1; then
  toolchain=(mise exec --)
fi

is_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1024 && 10#$1 <= 65535))
}

port_is_listening() {
  ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

require_port_free() {
  if ! is_port "$1" || port_is_listening "$1"; then
    echo "Motion/Context vertical requires an unused valid local port." >&2
    exit 1
  fi
}

inject_failure() {
  local boundary="$1"
  if [[ "${MOTION_CONTEXT_FAIL_AT:-}" == "$boundary" ]]; then
    echo "Injected Motion/Context failure at $boundary." >&2
    exit 97
  fi
}

tree_digest() {
  local root="$1"
  (
    cd "$root"
    find . -type f -print0 |
      LC_ALL=C sort -z |
      xargs -0 sha256sum |
      sha256sum |
      cut -d ' ' -f 1
  )
}

delete_exact_tree() {
  local target="$1"
  case "$target" in
    /tmp/motion-context.*)
      if [[ -d "$target" && ! -L "$target" ]]; then
        find "$target" -depth -delete
      fi
      ;;
    *)
      echo "Refusing to delete an unexpected Motion/Context runtime root." >&2
      return 1
      ;;
  esac
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
    delete_exact_tree "$runtime_root" || status=1
  fi
  if [[ "$capture_dir_owned" -eq 1 && -n "$capture_dir" ]]; then
    delete_exact_tree "$capture_dir" || status=1
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "Motion/Context vertical failed at $stage; private runtime artifacts were removed." >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in chromedriver cp curl find grep head jq mktemp setsid \
  sha256sum sort ss stat xargs; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Motion/Context vertical requires command: $command_name" >&2
    exit 1
  }
done
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
  echo "Motion/Context conformance requires matching Chrome and ChromeDriver majors." >&2
  exit 1
fi
if ((${#toolchain[@]} == 0)); then
  command -v dart >/dev/null 2>&1
fi
for port in "$host_port" "$studio_port" "$driver_port"; do
  require_port_free "$port"
done
case "${MOTION_CONTEXT_FAIL_AT:-}" in
  "" | workspace-isolation | webdriver-startup | host-studio-startup | browser-flow | browser-proof) ;;
  *)
    echo "MOTION_CONTEXT_FAIL_AT names an unknown boundary." >&2
    exit 1
    ;;
esac
if [[ ! -f "$studio_assets/index.html" ||
  ! -f "$studio_assets/main.client.dart.js" ]]; then
  echo "Build Studio with jaspr build before the Motion/Context vertical." >&2
  exit 1
fi

stage="workspace-isolation"
runtime_root="$(mktemp -d /tmp/motion-context.XXXXXX)"
chmod 700 "$runtime_root"
workspace="$runtime_root/workspace"
mkdir -m 700 "$workspace"
cp -- "$sample_dir/workspace.yaml" "$workspace/workspace.yaml"
cp -a -- "$sample_dir/.experience" "$workspace/.experience"
original_content_digest="$(tree_digest "$sample_dir/.experience")"
temporary_content_digest="$(tree_digest "$workspace/.experience")"
original_config_digest="$(sha256sum "$sample_dir/workspace.yaml" | cut -d ' ' -f 1)"
[[ "$original_content_digest" == "$temporary_content_digest" ]]
inject_failure "workspace-isolation"

if [[ -n "${MOTION_CONTEXT_CAPTURE_DIR:-}" ]]; then
  capture_dir="$MOTION_CONTEXT_CAPTURE_DIR"
  if [[ "$capture_dir" != /* || -L "$capture_dir" ]]; then
    echo "MOTION_CONTEXT_CAPTURE_DIR must be an absolute non-link directory." >&2
    exit 1
  fi
  if [[ ! -e "$capture_dir" ]]; then
    mkdir -m 700 -- "$capture_dir"
  fi
  [[ -d "$capture_dir" && ! -L "$capture_dir" ]]
  if [[ "$(stat -c '%a' "$capture_dir")" != "700" ]]; then
    echo "MOTION_CONTEXT_CAPTURE_DIR must have mode 0700." >&2
    exit 1
  fi
else
  capture_dir="$(mktemp -d /tmp/motion-context.XXXXXX)"
  capture_dir_owned=1
  chmod 700 "$capture_dir"
fi
screenshot="$capture_dir/motion-context.png"
if [[ -e "$screenshot" || -L "$screenshot" ]]; then
  echo "Motion/Context capture target must not already exist." >&2
  exit 1
fi

stage="webdriver-startup"
driver_log="$runtime_root/chromedriver.log"
setsid chromedriver \
  --port="$driver_port" \
  --allowed-ips=127.0.0.1 \
  --allowed-origins="http://127.0.0.1:$driver_port" \
  >"$driver_log" 2>&1 &
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
inject_failure "webdriver-startup"

stage="host-studio-startup"
dev_log="$runtime_root/dev.jsonl"
(
  cd "$repo_dir"
  exec setsid "${toolchain[@]}" dart run apps/workspace_cli/bin/workspace.dart \
    --json dev \
    --config "$workspace/workspace.yaml" \
    --profile full-local \
    --host-port "$host_port" \
    --studio-port "$studio_port" \
    --studio-assets "$studio_assets" \
    --no-open
) >"$dev_log" 2>&1 &
dev_pid=$!
ready=""
for _ in $(seq 1 480); do
  ready="$(jq -c '
    select(.ok == true and .result.status == "ready")
  ' "$dev_log" 2>/dev/null | tail -n 1 || true)"
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
    .result.profileId == "full-local" and
    .result.hostOrigin == $host and
    .result.studioOrigin == $studio
  ' <<<"$ready" >/dev/null
inject_failure "host-studio-startup"

stage="browser-flow"
probe_log="$runtime_root/probe.json"
probe_error="$runtime_root/probe.stderr"
if ! (
  cd "$repo_dir"
  "${toolchain[@]}" dart run tools/probes/studio_motion_context_browser_probe.dart \
    "http://127.0.0.1:$studio_port" \
    "http://127.0.0.1:$driver_port" \
    "$chromium_executable" \
    "$screenshot"
) >"$probe_log" 2>"$probe_error"; then
  if jq -e '
    (keys | sort) == ["failure", "stage"] and
    (.stage | IN(
      "session", "motion-full", "motion-reduced", "motion-none",
      "context-first", "context-reload", "context-omission",
      "surface-audit", "screenshot"
    )) and
    (.failure | IN("timeout", "protocol", "state", "filesystem", "unexpected"))
  ' "$probe_error" >/dev/null 2>&1; then
    jq -c '{stage, failure}' "$probe_error" >&2
  else
    echo '{"stage":"unknown","failure":"diagnostic-unavailable"}' >&2
  fi
  exit 1
fi
inject_failure "browser-flow"

stage="browser-proof"
jq -e '
  (keys | sort) == ([
    "contextCategoryCount", "contextDeterministic", "contextItemCount",
    "contextOmissionCount", "evidenceOmissionProved", "motionModesProved",
    "motionObservationCount", "motionStepCount", "screenshotDigest",
    "screenshotHeight", "screenshotWidth", "severeBrowserLogs",
    "staticEquivalentPreserved", "transientAuthorityMarkers"
  ] | sort) and
  .motionModesProved == true and
  .motionStepCount == 2 and
  .motionObservationCount == 2 and
  .staticEquivalentPreserved == true and
  .contextCategoryCount == 5 and
  .contextItemCount > 0 and
  .contextOmissionCount > 0 and
  .contextDeterministic == true and
  .evidenceOmissionProved == true and
  .transientAuthorityMarkers == 0 and
  .severeBrowserLogs == 0 and
  (.screenshotDigest | startswith("sha256:")) and
  .screenshotWidth >= 1200 and
  .screenshotHeight >= 800
' "$probe_log" >/dev/null
if rg -i -q \
  'authorityId|policyId|principalId|grantId|grantDigest|capabilityDigest|contentRoot|/home/|Bearer |PRIVATE KEY|postgres(ql)?://|mysql://' \
  "$probe_log" "$probe_error"; then
  echo "Motion/Context probe emitted transient or secret material." >&2
  exit 1
fi
[[ -f "$screenshot" && ! -L "$screenshot" && -s "$screenshot" ]]
inject_failure "browser-proof"

stage="reversibility-proof"
[[ "$(tree_digest "$sample_dir/.experience")" == "$original_content_digest" ]]
[[ "$(sha256sum "$sample_dir/workspace.yaml" | cut -d ' ' -f 1)" == "$original_config_digest" ]]
[[ "$(tree_digest "$workspace/.experience")" == "$temporary_content_digest" ]]

stage="complete"
jq -c '{
  motionModesProved,
  motionStepCount,
  motionObservationCount,
  staticEquivalentPreserved,
  contextCategoryCount,
  contextItemCount,
  contextOmissionCount,
  contextDeterministic,
  evidenceOmissionProved,
  severeBrowserLogs,
  screenshotDigest,
  screenshotWidth,
  screenshotHeight
}' "$probe_log"
echo "Motion and Context vertical passed with isolated read-only content." >&2
