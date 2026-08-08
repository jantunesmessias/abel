#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
host_port=7777
studio_port=7778
driver_port=9519
log_path="$(mktemp /tmp/studio-scale-reversibility.XXXXXX)"

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

runtime_roots() {
  find /tmp -maxdepth 1 -type d -name 'studio-scale-vertical.*' -printf '%p\n' |
    LC_ALL=C sort
}

port_is_listening() {
  ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

for port in "$host_port" "$studio_port" "$driver_port"; do
  if port_is_listening "$port"; then
    echo "Scale reversibility requires its fixed local ports to be free." >&2
    exit 1
  fi
done

before_roots="$(runtime_roots)"
set +e
SCALE_SKIP_STUDIO_BUILD=1 \
SCALE_HOST_PORT="$host_port" \
SCALE_STUDIO_PORT="$studio_port" \
SCALE_DRIVER_PORT="$driver_port" \
SCALE_FAIL_AT=host-ready \
  "$repo_dir/tools/verify/verify_scale_accessibility_security_vertical.sh" \
  >"$log_path" 2>&1
status=$?
set -e
if [[ "$status" -ne 97 ]]; then
  echo "Scale vertical did not stop at the injected boundary (status $status)." >&2
  tail -n 8 "$log_path" >&2
  exit 1
fi
if ! rg -q '^Scale/accessibility/security vertical failed at host-startup; private runtime artifacts were removed\.$' "$log_path"; then
  echo "Scale vertical did not report its fixed failure boundary." >&2
  exit 1
fi
for port in "$host_port" "$studio_port" "$driver_port"; do
  if port_is_listening "$port"; then
    echo "Scale vertical left a listener after injected failure." >&2
    exit 1
  fi
done
if [[ "$(runtime_roots)" != "$before_roots" ]]; then
  echo "Scale vertical left an isolated runtime root." >&2
  exit 1
fi

echo "Scale reversibility passed after injected host-ready failure."
