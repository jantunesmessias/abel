#!/usr/bin/env bash
set -euo pipefail

json_schema_commit="15fe552d6cf76e29cc8165306fb6a72503fd360b"
jcs_commit="19d51d7fe467d4706a3ff08adf8a748f29fc21e0"
standards_dir="$(mktemp -d /tmp/devex-standards.XXXXXX)"

cleanup() {
  case "$standards_dir" in
    /tmp/devex-standards.*) rm -rf -- "$standards_dir" ;;
    *) echo "Refusing to remove unexpected path: $standards_dir" >&2 ;;
  esac
}
trap cleanup EXIT

fetch_commit() {
  local repository="$1"
  local commit="$2"
  local destination="$3"
  git init --quiet "$destination"
  git -C "$destination" remote add origin "$repository"
  git -C "$destination" fetch --quiet --depth 1 origin "$commit"
  git -C "$destination" checkout --quiet --detach FETCH_HEAD
}

fetch_commit \
  https://github.com/json-schema-org/JSON-Schema-Test-Suite.git \
  "$json_schema_commit" \
  "$standards_dir/json-schema"
fetch_commit \
  https://github.com/cyberphone/json-canonicalization.git \
  "$jcs_commit" \
  "$standards_dir/jcs"

dart run packages/devex_contracts/tool/standards_conformance.dart \
  "$standards_dir/json-schema" \
  "$standards_dir/jcs"
