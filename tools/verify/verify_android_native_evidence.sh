#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

dart run melos run check
dart test libs/experience_contracts/test/android_evidence_contracts_test.dart
dart test libs/execution_runtime/test/android_evidence_provider_test.dart \
  libs/execution_runtime/test/evidence_comparison_service_test.dart
dart test apps/workspace_cli/test/workspace_cli_test.dart \
  --plain-name "evidence comparisons apply explicit visual and semantic policies"
ANDROID_NATIVE_EVIDENCE=1 ./tools/verify/verify_android_evidence.sh
echo "Correlated Android evidence, sanitization, comparison, and bundle gate passed."
