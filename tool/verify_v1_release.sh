#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

temp_dir="$(mktemp -d /tmp/devex-v1-release.XXXXXX)"
cleanup() {
  local original_status=$?
  case "$temp_dir" in
    /tmp/devex-v1-release.*) find "$temp_dir" -depth -delete 2>/dev/null || true ;;
    *) echo "Refusing to clean unexpected release path: $temp_dir" >&2 ;;
  esac
  return "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

./tool/check.sh
./tool/verify_standards.sh
./tool/verify_v0_flow.sh
./tool/verify_v01_gateway.sh
./tool/verify_v03_distribution.sh
./tool/verify_v1_android.sh

bundle_dir="$temp_dir/devex-kit-0.1.0"
install_dir="$temp_dir/install"
dart run apps/devex_cli/tool/build_distribution.dart \
  --output "$bundle_dir" --version 0.1.0
jq -e '.releaseVersion == "0.1.0"' "$bundle_dir/distribution.json" >/dev/null
"$bundle_dir/bin/devex" --json distribution verify-bundle --bundle "$bundle_dir" \
  >"$temp_dir/verify.json"
"$bundle_dir/bin/devex" --json distribution install --bundle "$bundle_dir" \
  --install-root "$install_dir" >"$temp_dir/install.json"
rg -q '"currentVersion":"0.1.0"' "$temp_dir/install.json"
cmp <("$install_dir/bin/devex" --json version) \
  <("$install_dir/bin/devex-kit" --json version)
dart run tool/verify_external_consumer.dart "$temp_dir/external"
sha256sum "$bundle_dir/distribution.json"
echo "V1 stable web/Android release gate passed."
