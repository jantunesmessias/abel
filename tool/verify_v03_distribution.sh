#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

temp_dir="$(mktemp -d /tmp/devex-v03-distribution.XXXXXX)"
cleanup() {
  local original_status=$?
  case "$temp_dir" in
    /tmp/devex-v03-distribution.*)
      find "$temp_dir" -depth -delete 2>/dev/null || true
      ;;
    *)
      echo "Refusing to clean unexpected distribution path: $temp_dir" >&2
      ;;
  esac
  return "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

bundle_dir="$temp_dir/devex-kit-0.1.0-preview.1"
repro_bundle_dir="$temp_dir/devex-kit-0.1.0-preview.1-rebuild"
second_bundle_dir="$temp_dir/devex-kit-0.1.0-preview.2"
install_dir="$temp_dir/install"

dart run apps/devex_cli/tool/build_distribution.dart \
  --output "$bundle_dir" \
  --version 0.1.0-preview.1
dart run apps/devex_cli/tool/build_distribution.dart \
  --output "$repro_bundle_dir" \
  --version 0.1.0-preview.1
cmp "$bundle_dir/distribution.json" "$repro_bundle_dir/distribution.json"
jq -e '
  .schemaVersion == 2 and
  (.profiles | index("full-local") != null) and
  (.entrypoints | keys | sort) == ["cli", "gateway", "host", "studio"]
' "$bundle_dir/distribution.json" >/dev/null

cd "$temp_dir"
"$bundle_dir/bin/devex" --json distribution verify-bundle \
  --bundle "$bundle_dir"
"$repro_bundle_dir/bin/devex" --json distribution verify-bundle \
  --bundle "$repro_bundle_dir" > "$temp_dir/repro-verify.json"
"$bundle_dir/bin/devex" --json distribution install \
  --bundle "$bundle_dir" \
  --install-root "$install_dir"

"$install_dir/bin/devex" --json version > "$temp_dir/canonical.json"
"$install_dir/bin/devex-kit" --json version > "$temp_dir/alias.json"
cmp "$temp_dir/canonical.json" "$temp_dir/alias.json"
"$install_dir/bin/backend_gateway" --version

cd "$repo_dir"
dart run apps/devex_cli/tool/repackage_distribution_rehearsal.dart \
  "$bundle_dir" "$second_bundle_dir" 0.1.0-preview.2
"$install_dir/bin/devex" --json distribution install \
  --bundle "$second_bundle_dir" \
  --install-root "$install_dir" > "$temp_dir/update.json"
rg -q '"currentVersion":"0.1.0-preview.2"' "$temp_dir/update.json"
"$install_dir/bin/devex" --json distribution rollback \
  --install-root "$install_dir" > "$temp_dir/rollback.json"
rg -q '"currentVersion":"0.1.0-preview.1"' "$temp_dir/rollback.json"

set +e
"$install_dir/bin/devex_host" > /dev/null 2> "$temp_dir/host.err"
host_status=$?
set -e
if [[ "$host_status" -ne 2 ]]; then
  echo "Standalone Host precondition returned $host_status, expected 2." >&2
  exit 1
fi

test -s "$bundle_dir/studio/index.html"
cd "$repo_dir"
dart run tool/verify_external_consumer.dart "$temp_dir/external"

echo "V0.3 distribution reproducibility, install, update, rollback, and external consumer gates passed."
