#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_content="$repo_dir/examples/sample_flutter/.experience"
host_port=7577
studio_port=7578
driver_port=9517
log_path="$(mktemp /tmp/authoring-review-reversibility.XXXXXX)"

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

port_is_listening() {
  ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

for port in "$host_port" "$studio_port" "$driver_port"; do
  if port_is_listening "$port"; then
    echo "Reversibility test requires its fixed local ports to be free." >&2
    exit 1
  fi
done
if find /tmp -maxdepth 1 -type d -name 'authoring-review.*' -print -quit |
  grep -q .; then
  echo "Reversibility test requires no pre-existing authoring runtime root." >&2
  exit 1
fi

before="$(tree_digest "$sample_content")"
set +e
AUTHORING_HOST_PORT="$host_port" \
AUTHORING_STUDIO_PORT="$studio_port" \
AUTHORING_DRIVER_PORT="$driver_port" \
AUTHORING_FAIL_AT=browser-flow \
  "$repo_dir/tools/verify/verify_authoring_review_vertical.sh" >"$log_path" 2>&1
status=$?
set -e
if [[ "$status" -ne 97 ]]; then
  echo "Authoring vertical did not stop at the injected boundary (status $status)." >&2
  tail -n 5 "$log_path" >&2
  exit 1
fi
if ! rg -q '^Injected authoring failure at browser-flow\.$' "$log_path" ||
  ! rg -q '^Authoring review vertical failed at browser-flow; private runtime artifacts were removed\.$' "$log_path"; then
  echo "Authoring vertical did not report its fixed failure labels." >&2
  exit 1
fi
for port in "$host_port" "$studio_port" "$driver_port"; do
  if port_is_listening "$port"; then
    echo "Authoring vertical left a listener after injected failure." >&2
    exit 1
  fi
done
if find /tmp -maxdepth 1 -type d -name 'authoring-review.*' -print -quit |
  grep -q .; then
  echo "Authoring vertical left an isolated runtime root." >&2
  exit 1
fi
if [[ "$(tree_digest "$sample_content")" != "$before" ]]; then
  echo "Authoring vertical changed the reference content root." >&2
  exit 1
fi

echo "Authoring review reversibility passed after injected browser-flow failure."
