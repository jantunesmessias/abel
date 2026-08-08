#!/usr/bin/env bash

# shellcheck disable=SC2034,SC2329
set -euo pipefail

runner="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/verify_scenario_lab_vertical.sh"
# shellcheck disable=SC1090
source <(awk '/^trap cleanup EXIT$/ { exit } { print }' "$runner")

test_root="$(mktemp -d \
  /tmp/scenario-lab-captures.reversibility.XXXXXX)"
delete_test_root=""

cleanup_test() {
  unset -f mv 2>/dev/null || true
  if [[ -n "$delete_test_root" && -d "$delete_test_root" ]]; then
    command find "$delete_test_root" -depth -delete
  fi
  if [[ -d "$test_root" ]]; then
    command find "$test_root" -depth -delete
  fi
}
trap cleanup_test EXIT

fail() {
  echo "Scenario Lab reversibility test failed: $1" >&2
  exit 1
}

seed_tree() {
  local path="$1"
  mkdir -p -- "$path/nested"
  printf '%s\n' original >"$path/nested/sentinel"
}

assert_no_backup() {
  local pattern="$1"
  if compgen -G "$pattern" >/dev/null; then
    fail "an isolation failure orphaned a backup"
  fi
}

preflight_root="$test_root/preflight"
preflight_app_dir="$preflight_root/sample/lib"
preflight_layout_dir="$preflight_root/sample/.experience/topology"
preflight_target_root="$preflight_root/sample/build"
preflight_studio_root="$preflight_root/studio/build"
preflight_state_root="$preflight_root/sample/.dart_tool"
preflight_tmp_root="$preflight_root/tmp"
mkdir -p -- \
  "$preflight_app_dir" \
  "$preflight_layout_dir" \
  "$preflight_target_root" \
  "$preflight_studio_root" \
  "$preflight_state_root" \
  "$preflight_tmp_root"
app_source="$preflight_app_dir/app_factory.dart"
layout_source="$preflight_layout_dir/layout-delivery-journey.yaml"
target_build_root="$preflight_target_root"
studio_build_root="$preflight_studio_root"
sample_dir="$preflight_root/sample"
if ! require_no_preexisting_scenario_lab_artifacts "$preflight_tmp_root"; then
  fail "clean preflight roots were rejected"
fi
preflight_artifacts=(
  "$preflight_app_dir/.scenario-lab-app.abandoned"
  "$preflight_app_dir/.scenario-lab-restore.abandoned"
  "$preflight_layout_dir/.scenario-lab-layout.abandoned"
  "$preflight_layout_dir/.scenario-lab-restore.abandoned"
  "$preflight_target_root/.scenario-lab-web-backup.abandoned"
  "$preflight_target_root/.scenario-lab-web-baseline.abandoned"
  "$preflight_target_root/.scenario-lab-web-changed.abandoned"
  "$preflight_target_root/.scenario-lab-web-retired.abandoned"
  "$preflight_studio_root/.scenario-lab-jaspr-backup.abandoned"
  "$preflight_state_root/.scenario-lab-workspace-backup.abandoned"
  "$preflight_tmp_root/scenario-lab-source-backup.abandoned"
)
for preflight_artifact in "${preflight_artifacts[@]}"; do
  mkdir -- "$preflight_artifact"
  printf '%s\n' preserve >"$preflight_artifact/sentinel"
  preflight_before_digest="$(tree_digest "$preflight_artifact")"
  preflight_output=""
  if preflight_output="$(
    require_no_preexisting_scenario_lab_artifacts "$preflight_tmp_root" 2>&1
  )"; then
    fail "pre-existing gate artifact was accepted"
  fi
  [[ "$preflight_output" == \
    "Scenario Lab preflight rejected pre-existing gate backup or staging artifacts." ]] ||
    fail "preflight failure output was not the sanitized contract"
  [[ "$preflight_output" != *"$test_root"* &&
    "$preflight_output" != *"abandoned"* ]] ||
    fail "preflight failure output disclosed an artifact path"
  [[ -d "$preflight_artifact" &&
    "$(tree_digest "$preflight_artifact")" == "$preflight_before_digest" ]] ||
    fail "preflight modified a pre-existing gate artifact"
  command find "$preflight_artifact" -depth -delete
done

preflight_call_line="$(
  rg -n '^require_no_preexisting_scenario_lab_artifacts$' "$runner" |
    tail -n 1 | cut -d: -f1
)"
capture_prepare_line="$(
  rg -n '^prepare_visual_capture_directory$' "$runner" |
    tail -n 1 | cut -d: -f1
)"
source_backup_line="$(
  rg -n '^source_backup_dir="\$\(mktemp -d' "$runner" |
    tail -n 1 | cut -d: -f1
)"
[[ -n "$preflight_call_line" && -n "$capture_prepare_line" &&
  -n "$source_backup_line" &&
  "$preflight_call_line" -lt "$capture_prepare_line" &&
  "$preflight_call_line" -lt "$source_backup_line" ]] ||
  fail "preflight is not ordered before gate mutations"

delete_test_root="$(mktemp -d \
  /tmp/scenario-lab-captures.delete-known-tree.XXXXXX)"
seed_tree "$delete_test_root"
delete_known_tree "$delete_test_root"
[[ ! -e "$delete_test_root" ]] || fail "delete_known_tree retained its root"
delete_test_root=""

atomic_restore_root="$test_root/atomic-restore"
mkdir -p -- "$atomic_restore_root"
printf '%s\n' original >"$atomic_restore_root/backup"
printf '%s\n' changed >"$atomic_restore_root/target"
atomic_expected_digest="$(sha256sum "$atomic_restore_root/backup" |
  awk '{print $1}')"
source_restore_staging=""
mv() { return 70; }
if atomic_restore_file \
  "$atomic_restore_root/backup" \
  "$atomic_restore_root/target" \
  "$atomic_expected_digest"; then
  fail "atomic restore pre-move fault unexpectedly succeeded"
fi
unset -f mv
[[ "$(<"$atomic_restore_root/target")" == changed ]] ||
  fail "atomic restore pre-move fault changed the target"
[[ -z "$source_restore_staging" ]] ||
  fail "atomic restore pre-move fault retained staging state"
assert_no_backup "$atomic_restore_root/.scenario-lab-restore.*"

mv() {
  command mv "$@"
  return 71
}
if ! atomic_restore_file \
  "$atomic_restore_root/backup" \
  "$atomic_restore_root/target" \
  "$atomic_expected_digest"; then
  fail "atomic restore post-move completion was not recognized"
fi
unset -f mv
[[ "$(sha256sum "$atomic_restore_root/target" | awk '{print $1}')" == "$atomic_expected_digest" ]] ||
  fail "atomic restore post-move target digest changed"
[[ -z "$source_restore_staging" ]] ||
  fail "atomic restore post-move completion retained staging state"
assert_no_backup "$atomic_restore_root/.scenario-lab-restore.*"

target_build_root="$test_root/target-pre/build"
target_build="$target_build_root/web"
target_build_backup_dir=""
target_build_was_present=0
target_build_isolated=0
target_build_root_was_present=1
target_build_temp=""
target_build_retired=""
seed_tree "$target_build"
target_build_before_digest="$(tree_digest "$target_build")"
mv() { return 71; }
if isolate_target_build; then
  fail "Target pre-move fault unexpectedly succeeded"
fi
unset -f mv
[[ "$target_build_isolated" -eq 0 && "$target_build_was_present" -eq 0 &&
  -z "$target_build_backup_dir" ]] ||
  fail "Target pre-move fault armed destructive cleanup"
[[ "$(tree_digest "$target_build")" == "$target_build_before_digest" ]] ||
  fail "Target pre-move fault changed the original"
assert_no_backup "$target_build_root/.scenario-lab-web-backup.*"

target_build_root="$test_root/target-post/build"
target_build="$target_build_root/web"
target_build_backup_dir=""
target_build_was_present=0
target_build_isolated=0
target_build_root_was_present=1
target_build_temp=""
target_build_retired=""
seed_tree "$target_build"
target_build_before_digest="$(tree_digest "$target_build")"
mv() {
  command mv "$@"
  return 72
}
if isolate_target_build; then
  fail "Target post-move fault unexpectedly succeeded"
fi
unset -f mv
[[ "$target_build_isolated" -eq 1 && "$target_build_was_present" -eq 1 &&
  ! -e "$target_build" && -d "$target_build_backup_dir/web" ]] ||
  fail "Target post-move fault did not arm restoration"
restore_target_build
[[ "$(tree_digest "$target_build")" == "$target_build_before_digest" ]] ||
  fail "Target post-move restoration changed the original"
assert_no_backup "$target_build_root/.scenario-lab-web-backup.*"

studio_build_root="$test_root/studio-pre/build"
studio_assets="$studio_build_root/jaspr"
studio_build_backup_dir=""
studio_build_was_present=0
studio_build_isolated=0
studio_build_root_was_present=1
seed_tree "$studio_assets"
studio_build_before_digest="$(tree_digest "$studio_assets")"
mv() { return 73; }
if isolate_studio_build; then
  fail "Studio pre-move fault unexpectedly succeeded"
fi
unset -f mv
[[ "$studio_build_isolated" -eq 0 && "$studio_build_was_present" -eq 0 &&
  -z "$studio_build_backup_dir" ]] ||
  fail "Studio pre-move fault armed destructive cleanup"
[[ "$(tree_digest "$studio_assets")" == "$studio_build_before_digest" ]] ||
  fail "Studio pre-move fault changed the original"
assert_no_backup "$studio_build_root/.scenario-lab-jaspr-backup.*"

studio_build_root="$test_root/studio-post/build"
studio_assets="$studio_build_root/jaspr"
studio_build_backup_dir=""
studio_build_was_present=0
studio_build_isolated=0
studio_build_root_was_present=1
seed_tree "$studio_assets"
studio_build_before_digest="$(tree_digest "$studio_assets")"
mv() {
  command mv "$@"
  return 74
}
if isolate_studio_build; then
  fail "Studio post-move fault unexpectedly succeeded"
fi
unset -f mv
[[ "$studio_build_isolated" -eq 1 && "$studio_build_was_present" -eq 1 &&
  ! -e "$studio_assets" && -d "$studio_build_backup_dir/jaspr" ]] ||
  fail "Studio post-move fault did not arm restoration"
restore_studio_build
[[ "$(tree_digest "$studio_assets")" == "$studio_build_before_digest" ]] ||
  fail "Studio post-move restoration changed the original"
assert_no_backup "$studio_build_root/.scenario-lab-jaspr-backup.*"

sample_dir="$test_root/state-pre/sample"
runtime_state_root="$sample_dir/.dart_tool/workspace"
state_backup_dir=""
state_was_present=0
state_isolated=0
seed_tree "$runtime_state_root"
state_before_digest="$(state_digest "$runtime_state_root")"
mv() { return 75; }
if isolate_workspace_state; then
  fail "state pre-move fault unexpectedly succeeded"
fi
unset -f mv
[[ "$state_isolated" -eq 0 && "$state_was_present" -eq 0 &&
  -z "$state_backup_dir" ]] ||
  fail "state pre-move fault armed destructive cleanup"
[[ "$(state_digest "$runtime_state_root")" == "$state_before_digest" ]] ||
  fail "state pre-move fault changed the original"
assert_no_backup "$sample_dir/.dart_tool/.scenario-lab-workspace-backup.*"

sample_dir="$test_root/state-post/sample"
runtime_state_root="$sample_dir/.dart_tool/workspace"
state_backup_dir=""
state_was_present=0
state_isolated=0
seed_tree "$runtime_state_root"
state_before_digest="$(state_digest "$runtime_state_root")"
mv() {
  command mv "$@"
  return 76
}
if isolate_workspace_state; then
  fail "state post-move fault unexpectedly succeeded"
fi
unset -f mv
[[ "$state_isolated" -eq 1 && "$state_was_present" -eq 1 &&
  ! -e "$runtime_state_root" && -d "$state_backup_dir/workspace" ]] ||
  fail "state post-move fault did not arm restoration"
restore_workspace_state
[[ "$(state_digest "$runtime_state_root")" == "$state_before_digest" ]] ||
  fail "state post-move restoration changed the original"
assert_no_backup "$sample_dir/.dart_tool/.scenario-lab-workspace-backup.*"

printf '%s\n' \
  '{"ok":true,"preflightFailClosed":true,"preflightSanitized":true,"preflightPreservesArtifacts":true,"deleteKnownTree":true,"preMoveFailurePreservesOriginal":true,"postMoveFailureArmsRestore":true,"isolations":["target","studio","state"]}'
