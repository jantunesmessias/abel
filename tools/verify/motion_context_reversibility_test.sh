#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_content="$repo_dir/examples/sample_flutter/.experience"
sample_config="$repo_dir/examples/sample_flutter/workspace.yaml"
host_port=7677
studio_port=7678
driver_port=9527
log_path="$(mktemp /tmp/motion-context-reversibility.XXXXXX)"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -f "$log_path" && ! -L "$log_path" ]]; then
    find "$log_path" -delete
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tree_digest() {
  (
    cd "$1"
    find . -type f -print0 |
      LC_ALL=C sort -z |
      xargs -0 sha256sum |
      sha256sum |
      cut -d ' ' -f 1
  )
}

runtime_roots() {
  find /tmp -maxdepth 1 -type d -name 'motion-context.*' -printf '%p\n' |
    LC_ALL=C sort
}

port_is_listening() {
  ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

for port in "$host_port" "$studio_port" "$driver_port"; do
  if port_is_listening "$port"; then
    echo "Motion/Context reversibility requires its fixed local ports to be free." >&2
    exit 1
  fi
done

before_content="$(tree_digest "$sample_content")"
before_config="$(sha256sum "$sample_config" | cut -d ' ' -f 1)"
before_roots="$(runtime_roots)"
set +e
MOTION_CONTEXT_HOST_PORT="$host_port" \
MOTION_CONTEXT_STUDIO_PORT="$studio_port" \
MOTION_CONTEXT_DRIVER_PORT="$driver_port" \
MOTION_CONTEXT_FAIL_AT=browser-flow \
  "$repo_dir/tools/verify/verify_motion_context_vertical.sh" >"$log_path" 2>&1
status=$?
set -e
if [[ "$status" -ne 97 ]]; then
  echo "Motion/Context vertical did not stop at the injected boundary (status $status)." >&2
  tail -n 5 "$log_path" >&2
  exit 1
fi
if ! rg -q '^Injected Motion/Context failure at browser-flow\.$' "$log_path" ||
  ! rg -q '^Motion/Context vertical failed at browser-flow; private runtime artifacts were removed\.$' "$log_path"; then
  echo "Motion/Context vertical did not report its fixed failure labels." >&2
  exit 1
fi
for port in "$host_port" "$studio_port" "$driver_port"; do
  if port_is_listening "$port"; then
    echo "Motion/Context vertical left a listener after injected failure." >&2
    exit 1
  fi
done
if [[ "$(runtime_roots)" != "$before_roots" ]]; then
  echo "Motion/Context vertical left an isolated runtime root." >&2
  exit 1
fi
if [[ "$(tree_digest "$sample_content")" != "$before_content" ||
  "$(sha256sum "$sample_config" | cut -d ' ' -f 1)" != "$before_config" ]]; then
  echo "Motion/Context vertical changed the reference workspace." >&2
  exit 1
fi

echo "Motion/Context reversibility passed after injected browser-flow failure."
