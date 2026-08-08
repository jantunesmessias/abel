#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

if ! command -v unshare >/dev/null 2>&1; then
  echo "unshare is required for the V0.2 target containment gate." >&2
  exit 1
fi

unshare --user --map-root-user --net sh -c '
  set -eu
  ip link set lo up
  dart run packages/devex_runtime/tool/web_containment_probe.dart
'
