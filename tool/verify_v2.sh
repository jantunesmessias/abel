#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

./tool/check.sh
dart run tool/verify_v2_source_impact.dart
dart test apps/devex_cli/test/devex_cli_test.dart \
  --plain-name "V2 CLI composes source impact, context, bundle verification, and seal"
dart test packages/devex_runtime/test/plugin_process_host_test.dart
echo "V2 source/bundle/plugin/MCP gate passed."
