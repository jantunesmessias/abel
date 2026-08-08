#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

temp_dir="$(mktemp -d /tmp/workspace-release.XXXXXX)"
cleanup() {
  local original_status=$?
  case "$temp_dir" in
    /tmp/workspace-release.*) find "$temp_dir" -depth -delete 2>/dev/null || true ;;
    *) echo "Refusing to clean unexpected release path: $temp_dir" >&2 ;;
  esac
  return "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

dart run melos run check
./tools/verify/verify_standards.sh
./tools/verify/verify_web_evidence_flow.sh
./tools/verify/verify_flutter_web_wasm.sh
./tools/benchmarks/gateway_benchmark.sh
./tools/verify/verify_distribution_lifecycle.sh
./tools/verify/verify_android_evidence.sh

bundle_dir="$temp_dir/full-local-0.1.0"
install_dir="$temp_dir/install"
dart run apps/workspace_cli/tool/build_distribution.dart \
  --output "$bundle_dir" --version 0.1.0
jq -e '.releaseVersion == "0.1.0"' "$bundle_dir/distribution.json" >/dev/null
"$bundle_dir/bin/workspace" --json distribution verify-bundle --bundle "$bundle_dir" \
  >"$temp_dir/verify.json"
"$bundle_dir/bin/workspace" --json distribution install --bundle "$bundle_dir" \
  --install-root "$install_dir" >"$temp_dir/install.json"
rg -q '"currentVersion":"0.1.0"' "$temp_dir/install.json"
dart run tools/verify/verify_external_consumer.dart "$temp_dir/external"
sha256sum "$bundle_dir/distribution.json"
echo "Stable web/Android release gate passed."
