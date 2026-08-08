#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

before="$(find /tmp -maxdepth 1 -type d \
  -name 'external-distribution.*' -print | LC_ALL=C sort)"
set +e
EXTERNAL_DISTRIBUTION_FAIL_WHILE_HOST_READY=1 \
  ./tools/verify/verify_external_distribution_vertical.sh >/dev/null
status=$?
set -e
if [[ "$status" -ne 98 ]]; then
  echo "External distribution gate stopped with $status, expected 98." >&2
  exit 1
fi
after="$(find /tmp -maxdepth 1 -type d \
  -name 'external-distribution.*' -print | LC_ALL=C sort)"
if [[ "$after" != "$before" ]]; then
  echo "External distribution gate left a runtime root after failure." >&2
  diff -u <(printf '%s\n' "$before") <(printf '%s\n' "$after") >&2 || true
  exit 1
fi
if pgrep -af '[/]tmp/external-distribution\.[^ ]+/.*/workspace_host' \
  >/dev/null; then
  echo "External distribution gate left a Host process after failure." >&2
  exit 1
fi

echo "External distribution failure cleanup is reversible."
