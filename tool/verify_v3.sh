#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

./tool/check.sh
dart test packages/devex_contracts/test/android_evidence_contracts_test.dart
dart test packages/devex_runtime/test/android_evidence_provider_test.dart \
  packages/devex_runtime/test/evidence_comparison_service_test.dart
dart test apps/devex_cli/test/devex_cli_test.dart \
  --plain-name "evidence comparisons apply explicit visual and semantic policies"
DEVEX_V3_EVIDENCE=1 ./tool/verify_v1_android.sh
echo "V3 correlated Android evidence, sanitization, comparison, and bundle gate passed."
