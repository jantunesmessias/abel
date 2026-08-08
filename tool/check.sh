#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

dart format --output=none --set-exit-if-changed \
  apps packages examples test tool
flutter analyze --fatal-infos --fatal-warnings
dart run tool/architecture_guard.dart
./tool/verify_supply_chain.sh

dart test packages/devex_contracts
dart test packages/devex_engine
dart test packages/devex_runtime
flutter test packages/devex_flutter
flutter test packages/devex_preview
dart test packages/devex_ux_system
dart test packages/devex_ui_system
dart test packages/devex_testkit
dart test apps/devex_studio/test
(
  cd apps/devex_studio
  jaspr build
)
dart test apps/devex_cli
dart test apps/devex_host
dart test apps/backend_gateway
dart test apps/hosted_control_plane
dart test apps/remote_session_gateway
dart test apps/remote_worker
dart test examples/sample_api
./tool/verify_v02_containment.sh
flutter test examples/sample_flutter
flutter test test/consumers/friction_flutter
dart run examples/tool/showcase.dart --check
