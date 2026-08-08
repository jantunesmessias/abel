#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

flutter test libs/flutter_preview
dart test libs/experience_engine/test/preview_manifest_compiler_test.dart
dart test \
  libs/execution_runtime/test/preview_source_scanner_test.dart \
  libs/execution_runtime/test/preview_capture_runner_test.dart \
  libs/execution_runtime/test/preview_capture_runner_integration_test.dart
flutter test examples/sample_flutter/test/auto_preview_capture_test.dart

echo "AutoPreview compiler, isolated capture, PNG, and sample gates passed."
