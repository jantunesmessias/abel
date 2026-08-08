#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$repo_root"

reversibility_root="$(mktemp -d /tmp/experience-mcp-reversibility.XXXXXX)"
chmod 700 "$reversibility_root"
cleanup() {
  if [[ -d "$reversibility_root" &&
        ! -L "$reversibility_root" &&
        "$reversibility_root" == /tmp/experience-mcp-reversibility.* ]]; then
    find "$reversibility_root" -depth -type f -delete
    find "$reversibility_root" -depth -type d -empty -delete
  fi
}
trap cleanup EXIT INT TERM

set +e
MCP_TEMP_ROOT="$reversibility_root" \
MCP_INJECT_FAILURE=after-copy \
  ./tools/verify/verify_mcp_experience_vertical.sh >/dev/null 2>&1
status=$?
set -e

[[ "$status" -eq 97 ]] || {
  printf 'Expected injected MCP failure status 97, got %s\n' "$status" >&2
  exit 1
}
[[ -z "$(find "$reversibility_root" -mindepth 1 -print -quit)" ]] || {
  printf 'MCP vertical left an isolated fixture after failure\n' >&2
  exit 1
}

printf 'MCP Experience reversibility passed after injected failure.\n'
