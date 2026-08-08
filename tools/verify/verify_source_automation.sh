#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

dart run melos run check
dart run tools/verify/verify_source_impact.dart
dart test apps/workspace_cli/test/workspace_cli_test.dart \
  --plain-name "CLI composes source impact, context, bundle verification, and seal"
dart test libs/execution_runtime/test/plugin_process_host_test.dart
echo "Source automation, bundle, plugin and MCP gate passed."
