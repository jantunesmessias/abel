#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

temp_dir="$(mktemp -d /tmp/devex-modular-distribution.XXXXXX)"
cleanup() {
  local original_status=$?
  case "$temp_dir" in
    /tmp/devex-modular-distribution.*)
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

journey_a="$temp_dir/journey-a"
journey_b="$temp_dir/journey-b"
gateway="$temp_dir/gateway-headless"

dart run apps/devex_cli/tool/build_distribution.dart \
  --profile journey-preview \
  --output "$journey_a" \
  --version 0.2.0-preview.1
dart run apps/devex_cli/tool/build_distribution.dart \
  --profile journey-preview \
  --output "$journey_b" \
  --version 0.2.0-preview.1
cmp "$journey_a/distribution.json" "$journey_b/distribution.json"
test ! -e "$journey_a/bin/backend_gateway"
jq -e '
  .schemaVersion == 2 and
  .profiles == ["journey-preview"] and
  (.modules | index("evidence.auto-preview") != null) and
  (.modules | index("target.android") == null) and
  (.entrypoints.gateway == null)
' "$journey_a/distribution.json" >/dev/null
"$journey_a/bin/devex" --json distribution verify-bundle \
  --bundle "$journey_a" >/dev/null

dart run apps/devex_cli/tool/build_distribution.dart \
  --profile gateway-lab-headless \
  --output "$gateway" \
  --version 0.2.0-preview.1
test ! -e "$gateway/studio"
jq -e '
  .schemaVersion == 2 and
  .profiles == ["gateway-lab-headless"] and
  (.modules | index("gateway.interceptor") != null) and
  (.modules | index("studio.shell") == null) and
  (.entrypoints.studio == null)
' "$gateway/distribution.json" >/dev/null
"$gateway/bin/devex" --json distribution verify-bundle \
  --bundle "$gateway" >/dev/null

echo "Modular Distribution v2 slim and reproducibility gates passed."
