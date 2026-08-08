#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
studio_assets="$repo_dir/apps/studio/build/jaspr"
host_port="${AUTHORING_HOST_PORT:-7567}"
studio_port="${AUTHORING_STUDIO_PORT:-7568}"
driver_port="${AUTHORING_DRIVER_PORT:-9516}"
runtime_root=""
capture_dir=""
capture_dir_owned=0
dev_pid=""
driver_pid=""
dev_log=""
driver_log=""
probe_log=""
probe_error=""
source_proof_log=""
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
    echo "Authoring vertical requires an unused valid local port." >&2
    exit 1
  fi
}

inject_failure() {
  local boundary="$1"
  if [[ "${AUTHORING_FAIL_AT:-}" == "$boundary" ]]; then
    echo "Injected authoring failure at $boundary." >&2
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
    /tmp/authoring-review.*)
      if [[ -d "$target" && ! -L "$target" ]]; then
        find "$target" -depth -delete
      fi
      ;;
    *)
      echo "Refusing to delete an unexpected authoring runtime root." >&2
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
    echo "Authoring review vertical failed at $stage; private runtime artifacts were removed." >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in chromedriver cp curl find grep head jq mktemp setsid \
  sha256sum sort ss stat xargs; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Authoring vertical requires command: $command_name" >&2
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
  echo "Authoring conformance requires matching Chrome and ChromeDriver majors." >&2
  exit 1
fi
if ((${#toolchain[@]} == 0)); then
  command -v dart >/dev/null 2>&1
fi
for port in "$host_port" "$studio_port" "$driver_port"; do
  require_port_free "$port"
done
case "${AUTHORING_FAIL_AT:-}" in
  "" | workspace-isolation | webdriver-startup | host-studio-startup | browser-flow) ;;
  *)
    echo "AUTHORING_FAIL_AT names an unknown boundary." >&2
    exit 1
    ;;
esac
if [[ ! -f "$studio_assets/index.html" ||
  ! -f "$studio_assets/main.client.dart.js" ]]; then
  echo "Build Studio with jaspr build before the Authoring vertical." >&2
  exit 1
fi

stage="workspace-isolation"
runtime_root="$(mktemp -d /tmp/authoring-review.XXXXXX)"
chmod 700 "$runtime_root"
workspace="$runtime_root/workspace"
mkdir -m 700 "$workspace"
cp -- "$sample_dir/workspace.yaml" "$workspace/workspace.yaml"
cp -a -- "$sample_dir/.experience" "$workspace/.experience"
original_tree_digest="$(tree_digest "$sample_dir/.experience")"
temporary_tree_before="$(tree_digest "$workspace/.experience")"
[[ "$original_tree_digest" == "$temporary_tree_before" ]]
layout_source="$workspace/.experience/topology/layout-delivery-journey.yaml"
layout_before="$(sha256sum "$layout_source" | cut -d ' ' -f 1)"
inject_failure "workspace-isolation"

if [[ -n "${AUTHORING_CAPTURE_DIR:-}" ]]; then
  capture_dir="$AUTHORING_CAPTURE_DIR"
  if [[ "$capture_dir" != /* || -L "$capture_dir" ]]; then
    echo "AUTHORING_CAPTURE_DIR must be an absolute non-link directory." >&2
    exit 1
  fi
  if [[ ! -e "$capture_dir" ]]; then
    mkdir -m 700 -- "$capture_dir"
  fi
  [[ -d "$capture_dir" && ! -L "$capture_dir" ]]
  if [[ "$(stat -c '%a' "$capture_dir")" != "700" ]]; then
    echo "AUTHORING_CAPTURE_DIR must have mode 0700." >&2
    exit 1
  fi
else
  capture_dir="$(mktemp -d /tmp/authoring-review.XXXXXX)"
  capture_dir_owned=1
  chmod 700 "$capture_dir"
fi
screenshot="$capture_dir/authoring-review.png"
if [[ -e "$screenshot" || -L "$screenshot" ]]; then
  echo "Authoring capture target must not already exist." >&2
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
  "${toolchain[@]}" dart run tools/probes/studio_authoring_browser_probe.dart \
    "http://127.0.0.1:$studio_port" \
    "http://127.0.0.1:$driver_port" \
    "$chromium_executable" \
    "$screenshot"
) >"$probe_log" 2>"$probe_error"; then
  if jq -e '
    (keys | sort) == ["failure", "publicFailureCode", "publicState", "stage"] and
    (.stage | IN(
      "primary-session", "secondary-session", "navigation", "author-ready", "draft-open",
      "stale-writer", "draft-history", "review-prepare", "finding",
      "concept", "comment", "acceptance", "rejection", "approval",
      "review-audit", "promotion", "final-audit", "screenshot"
    )) and
    (.failure | IN("timeout", "protocol", "state", "filesystem", "unexpected")) and
    (.publicState | IN(
      "unavailable", "conflict", "protocolViolation", "transportFailure",
      "author", "viewer", "unsupported", "submitting", "loading", "unknown"
    )) and
    (.publicFailureCode | IN(
      "none", "stale", "policyDenied", "ownerDenied", "capabilityUnavailable",
      "grantExpired", "grantRevoked", "grantConsumed", "grantMismatch",
      "requestConflict", "unsupported", "quotaExceeded", "unavailable",
      "invalidRequest"
    ))
  ' "$probe_error" >/dev/null 2>&1; then
    jq -c '{stage, failure, publicState, publicFailureCode}' "$probe_error" >&2
  else
    echo '{"stage":"unknown","failure":"diagnostic-unavailable"}' >&2
  fi
  exit 1
fi
inject_failure "browser-flow"

stage="browser-proof"
jq -e '
  (keys | sort) == ([
    "authorMode", "commentCount", "conceptCount", "decisionCount",
    "findingCount", "promotionCount", "reviewGuideMaterialized",
    "screenshotDigest", "screenshotHeight", "screenshotWidth",
    "severeBrowserLogs", "staleWriterRejected",
    "supersededDecisionCount", "transientAuthorityMarkers",
    "undoRedoResetExercised"
  ] | sort) and
  .authorMode == true and
  .staleWriterRejected == true and
  .undoRedoResetExercised == true and
  .reviewGuideMaterialized == true and
  .findingCount == 1 and
  .conceptCount == 1 and
  .commentCount == 1 and
  .decisionCount == 2 and
  .supersededDecisionCount == 1 and
  .promotionCount == 1 and
  .transientAuthorityMarkers == 0 and
  .severeBrowserLogs == 0 and
  (.screenshotDigest | startswith("sha256:")) and
  .screenshotWidth >= 1200 and
  .screenshotHeight >= 800
' "$probe_log" >/dev/null
if rg -i -q \
  'authorityId|policyId|principalId|grantId|grantDigest|capabilityDigest|contentRoot|/home/' \
  "$probe_log" "$probe_error"; then
  echo "Authoring probe emitted transient authority material." >&2
  exit 1
fi
[[ -f "$screenshot" && ! -L "$screenshot" && -s "$screenshot" ]]

stage="source-proof"
layout_after="$(sha256sum "$layout_source" | cut -d ' ' -f 1)"
[[ "$layout_before" != "$layout_after" ]]
source_proof_log="$runtime_root/source-proof.json"
(
  cd "$repo_dir"
  "${toolchain[@]}" dart run tools/verify/verify_authoring_promotion_source.dart \
    "$sample_dir" "$workspace" delivery-journey journey-dashboard-ready
) >"$source_proof_log" 2>/dev/null
jq -e '
  . == {
    catalogStable: true,
    topologyStable: true,
    unrelatedLayoutsStable: true,
    changedFrameCount: 1,
    movedRightByTwenty: true
  }
' "$source_proof_log" >/dev/null

stage="state-proof"
state_file="$workspace/.dart_tool/workspace/full-local/experience-authoring/authoring.journal.json"
if [[ ! -f "$state_file" || -L "$state_file" ]]; then
  echo "Authoring state proof failed: durable-journal-shape." >&2
  exit 1
fi
state_mode="$(stat -c '%a' "$state_file")"
state_size="$(stat -c '%s' "$state_file")"
if [[ "$state_mode" != "600" ]]; then
  echo "Authoring state proof failed: durable-journal-mode." >&2
  exit 1
fi
if [[ "$state_size" -le 0 || "$state_size" -gt 67108864 ]]; then
  echo "Authoring state proof failed: durable-journal-size." >&2
  exit 1
fi
if [[ "$(tree_digest "$sample_dir/.experience")" != "$original_tree_digest" ]]; then
  echo "Authoring state proof failed: source-isolation." >&2
  exit 1
fi

stage="complete"
jq -c '{
  authorMode,
  staleWriterRejected,
  undoRedoResetExercised,
  reviewGuideMaterialized,
  findingCount,
  conceptCount,
  commentCount,
  decisionCount,
  supersededDecisionCount,
  promotionCount,
  severeBrowserLogs,
  screenshotDigest,
  screenshotWidth,
  screenshotHeight
}' "$probe_log"
echo "Authoring and Review vertical passed with isolated source and state." >&2
