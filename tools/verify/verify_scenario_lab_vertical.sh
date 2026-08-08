#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
studio_assets="$repo_dir/apps/studio/build/jaspr"
studio_build_root="$repo_dir/apps/studio/build"
target_build_root="$sample_dir/build"
target_build="$target_build_root/web"
app_source="$sample_dir/lib/app_factory.dart"
layout_source="$sample_dir/.experience/topology/layout-delivery-journey.yaml"
runtime_state_root="$sample_dir/.dart_tool/workspace"
state_root="$sample_dir/.dart_tool/workspace/full-local"
baseline_asset="$sample_dir/.experience/lab/assets/dashboard-ready-baseline.png.base64"
baseline_authoring="$sample_dir/.experience/lab/artifact-dashboard-ready-baseline.yaml"
chrome_debug_port="${SCENARIO_LAB_CHROME_DEBUG_PORT:-9525}"
api_pid=""
dev_pid=""
chrome_pid=""
api_log=""
dev_log=""
probe_log=""
restart_dev_log=""
recovery_probe_log=""
identity_before_log=""
identity_after_log=""
currentness_probe_log=""
chrome_profile=""
capture_dir=""
capture_dir_owned=0
capture_dir_created=0
capture_targets_armed=0
capture_disposition="retained-by-request"
dialog_capture_path=""
quality_capture_path=""
state_backup_dir=""
state_was_present=0
state_isolated=0
state_before_digest="absent"
source_backup_dir=""
source_backup_armed=0
app_source_staging=""
layout_source_staging=""
source_restore_staging=""
app_source_before_digest=""
layout_source_before_digest=""
target_build_backup_dir=""
target_build_was_present=0
target_build_isolated=0
target_build_before_digest="absent"
target_build_temp=""
target_build_retired=""
target_build_root_was_present=0
studio_build_backup_dir=""
studio_build_was_present=0
studio_build_isolated=0
studio_build_before_digest="absent"
studio_build_root_was_present=0
target_port=""
target_ports=()
gateway_ports=()
deferred_signal_exit=0
sensitive_pattern='(?i)"(?:uri|resourceUri|gateway(?:Data)?Origin|grant(?:Id|Digest)?|[A-Za-z0-9_]*(?:token|nonce)[A-Za-z0-9_]*|authorization)"\s*:|(?:^|[^A-Za-z0-9_])(?:uri|resourceUri|gateway(?:Data)?Origin|grant(?:Id|Digest)?|[A-Za-z0-9_]*(?:token|nonce)[A-Za-z0-9_]*|authorization)\s*[=:]|(?:authorization\s*[=:]\s*)?bearer\s+[A-Za-z0-9._~+/-]+|[?&](?:token|nonce|grantId|grantDigest)=|#[[:space:]]*target-launch[[:space:]]*=|(?:SESSION_NONCE|GATEWAY_ORIGIN)\s*[=:]|/resources/(?:sha256/)?[A-Za-z0-9._~-]{16,}'
toolchain=()
if command -v mise >/dev/null 2>&1; then
  toolchain=(mise exec --)
fi

port_open() {
  local port="$1"
  (exec 9<>"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1
}

require_port_free() {
  local port="$1"
  if port_open "$port"; then
    echo "Loopback port $port is already in use." >&2
    exit 1
  fi
}

wait_for_port_free() {
  local port="$1"
  for _ in $(seq 1 120); do
    if ! port_open "$port"; then
      return
    fi
    sleep 0.1
  done
  echo "Loopback listener on port $port survived cleanup." >&2
  return 1
}

record_target_port() {
  local port="$1"
  if [[ -z "$port" || "$port" == "null" ]]; then
    return
  fi
  if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] ||
    ((10#$port < 1 || 10#$port > 65535)); then
    echo "Scenario Lab relay returned an invalid target port." >&2
    return 1
  fi
  target_port="$port"
  local known
  for known in "${target_ports[@]}"; do
    if [[ "$known" == "$port" ]]; then
      return
    fi
  done
  target_ports+=("$port")
}

record_gateway_port() {
  local port="$1"
  if [[ -z "$port" || "$port" == "null" ]]; then
    return
  fi
  if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] ||
    ((10#$port < 1 || 10#$port > 65535)); then
    echo "Scenario Lab relay returned an invalid Gateway port." >&2
    return 1
  fi
  local known
  for known in "${gateway_ports[@]}"; do
    if [[ "$known" == "$port" ]]; then
      return
    fi
  done
  gateway_ports+=("$port")
}

record_relay_ports_from_payload() {
  local payload="$1"
  local candidate
  local candidates=()
  mapfile -t candidates < <(jq -r '.relayPorts.targetPorts[]? // empty' \
    <<<"$payload")
  for candidate in "${candidates[@]}"; do
    record_target_port "$candidate"
  done
  candidates=()
  mapfile -t candidates < <(jq -r '.relayPorts.gatewayPorts[]? // empty' \
    <<<"$payload")
  for candidate in "${candidates[@]}"; do
    record_gateway_port "$candidate"
  done
}

export_blocked_capture() {
  local blocked_payload="$1"
  local export_path="${SCENARIO_LAB_EXPORT_CAPTURE:-}"
  if [[ -z "$export_path" ]]; then
    return
  fi
  if [[ "$export_path" != /tmp/scenario-lab-* || -e "$export_path" ]]; then
    echo "Capture export must be a new /tmp/scenario-lab-* path." >&2
    return 1
  fi
  local artifact_digest
  artifact_digest="$(jq -r '
    .. | objects |
    select(.requiredEvidenceId? == "dashboard-ready-visual") |
    (.artifacts? // [])[] |
    .artifactDigest? // empty
  ' <<<"$blocked_payload" | sort -u | tail -n 1)"
  local artifact_hex="${artifact_digest#sha256:}"
  if [[ ! "$artifact_hex" =~ ^[0-9a-f]{64}$ ]]; then
    echo "Blocked run did not expose an exact Scenario Lab artifact digest." >&2
    return 1
  fi
  local artifact_path="$state_root/cas/sha256/$artifact_hex"
  if [[ ! -f "$artifact_path" || -L "$artifact_path" ]]; then
    echo "Blocked run artifact is absent from the temporary CAS." >&2
    return 1
  fi
  if [[ "sha256:$(sha256sum "$artifact_path" | awk '{print $1}')" != \
    "$artifact_digest" ]]; then
    echo "Blocked run artifact failed CAS verification." >&2
    return 1
  fi
  cp -- "$artifact_path" "$export_path"
  echo "[scenario-lab-vertical] exported exact blocked-run Evidence to $export_path" >&2
}

verify_cas_digest() {
  local digest="$1"
  local label="$2"
  local hex="${digest#sha256:}"
  if [[ ! "$hex" =~ ^[0-9a-f]{64}$ ]]; then
    echo "$label returned an invalid CAS digest." >&2
    return 1
  fi
  local path="$state_root/cas/sha256/$hex"
  if [[ ! -f "$path" || -L "$path" ]]; then
    echo "$label is absent from the temporary CAS." >&2
    return 1
  fi
  if [[ "sha256:$(sha256sum "$path" | awk '{print $1}')" != "$digest" ]]; then
    echo "$label failed exact CAS verification." >&2
    return 1
  fi
}

verify_visual_capture() {
  local path="$1"
  local expected_digest="$2"
  local label="$3"
  if [[ ! -f "$path" || -L "$path" ]]; then
    echo "$label capture is missing or is not a regular file." >&2
    return 1
  fi
  if [[ "sha256:$(sha256sum "$path" | awk '{print $1}')" != \
    "$expected_digest" ]]; then
    echo "$label capture failed exact digest verification." >&2
    return 1
  fi
}

prepare_visual_capture_directory() {
  local requested="${SCENARIO_LAB_CAPTURE_DIR:-}"
  if [[ -n "$requested" ]]; then
    if [[ "$requested" != /* || "$requested" == "/" ||
      "$requested" == *$'\n'* || "$requested" == *$'\r'* ]]; then
      echo "SCENARIO_LAB_CAPTURE_DIR must be a safe absolute directory." >&2
      return 1
    fi
    if [[ "$requested" == "$runtime_state_root" ||
      "$requested" == "$runtime_state_root/"* ]]; then
      echo "SCENARIO_LAB_CAPTURE_DIR must be outside isolated runtime state." >&2
      return 1
    fi
    if [[ -L "$requested" || (-e "$requested" && ! -d "$requested") ]]; then
      echo "SCENARIO_LAB_CAPTURE_DIR is not a real directory." >&2
      return 1
    fi
    capture_dir="$requested"
    if [[ ! -d "$requested" ]]; then
      defer_termination_signals
      mkdir -p -- "$requested"
      capture_dir_created=1
      resume_termination_signals
    fi
    if [[ -L "$requested" ]]; then
      echo "SCENARIO_LAB_CAPTURE_DIR must not be a symbolic link." >&2
      return 1
    fi
  else
    defer_termination_signals
    capture_dir="$(mktemp -d /tmp/scenario-lab-captures.XXXXXX)"
    capture_dir_owned=1
    resume_termination_signals
  fi
  dialog_capture_path="$capture_dir/scenario-quality-decision-dialog.png"
  quality_capture_path="$capture_dir/scenario-quality-final.png"
  for capture_path in "$dialog_capture_path" "$quality_capture_path"; do
    if [[ -e "$capture_path" || -L "$capture_path" ]]; then
      echo "Scenario Lab capture target already exists." >&2
      return 1
    fi
  done
  capture_targets_armed=1
}

redact_gate_output() {
  sed -E \
    -e 's|#[[:space:]]*target-launch[[:space:]]*=.*|#<redacted>|Ig' \
    -e 's#("(uri|resourceUri|gateway(Data)?Origin|grant(Id|Digest)?|[A-Za-z0-9_]*(token|nonce)[A-Za-z0-9_]*|authorization)"[[:space:]]*:[[:space:]]*)"[^"]*"#\1"<redacted>"#Ig' \
    -e 's#(Authorization[[:space:]]*[=:][[:space:]]*Bearer[[:space:]]+)[A-Za-z0-9._~+/-]+=*#\1<redacted>#Ig' \
    -e 's#(Bearer[[:space:]]+)[A-Za-z0-9._~+/-]+=*#\1<redacted>#Ig' \
    -e 's#((uri|resourceUri|gateway(Data)?Origin|grant(Id|Digest)?|[A-Za-z0-9_]*(token|nonce)[A-Za-z0-9_]*|authorization)[[:space:]]*[=:][[:space:]]*)"[^"]*"#\1<redacted>#Ig' \
    -e 's#((uri|resourceUri|gateway(Data)?Origin|grant(Id|Digest)?|[A-Za-z0-9_]*(token|nonce)[A-Za-z0-9_]*|authorization)[[:space:]]*[=:][[:space:]]*)[^,[:space:]"}]+#\1<redacted>#Ig' \
    -e 's#([?&](token|nonce|grantId|grantDigest)=)[^&[:space:]"}]+#\1<redacted>#Ig' \
    -e 's#/resources/(sha256/)?[A-Za-z0-9._~-]{16,}#/resources/<redacted>#Ig' \
    -e 's#((SESSION_NONCE|GATEWAY_ORIGIN)[[:space:]]*[=:][[:space:]]*)[^,[:space:]"}]+#\1<redacted>#Ig'
}

verify_gate_redactor() {
  local marker='REDACTION_SECRET_MARKER_0123456789'
  local sample
  local safe_sample
  local redacted
  local safe_redacted
  sample="$(printf '%s\n' \
    '"uri":"REDACTION_SECRET_MARKER_0123456789"' \
    '"grant": "REDACTION_SECRET_MARKER_0123456789"' \
    'uri=http://host/REDACTION_SECRET_MARKER_0123456789' \
    'uri : http://host/REDACTION_SECRET_MARKER_0123456789' \
    'resourceUri = "http://host/REDACTION_SECRET_MARKER_0123456789 path"' \
    'token = REDACTION_SECRET_MARKER_0123456789' \
    'sessionNonce: "REDACTION_SECRET_MARKER_0123456789"' \
    'gatewayDataOrigin: http://127.0.0.1:9999/REDACTION_SECRET_MARKER_0123456789' \
    'grantId=REDACTION_SECRET_MARKER_0123456789' \
    'Authorization : Bearer REDACTION_SECRET_MARKER_0123456789' \
    'https://host/path?token=REDACTION_SECRET_MARKER_0123456789' \
    'SESSION_NONCE = REDACTION_SECRET_MARKER_0123456789' \
    'GATEWAY_ORIGIN = http://127.0.0.1:9999/REDACTION_SECRET_MARKER_0123456789' \
    'https://host/#target-launch=REDACTION_SECRET_MARKER_0123456789' \
    '"url":"https://host/#target-launch=REDACTION_SECRET_MARKER_0123456789"' \
    "target='#target-launch = REDACTION_SECRET_MARKER_0123456789'" \
    'fragment=#target-launch="REDACTION_SECRET_MARKER_0123456789"' \
    'https://host/#target-launch=x.REDACTION_SECRET_MARKER_0123456789' \
    'https://host/#target-launch=x%2FREDACTION_SECRET_MARKER_0123456789' \
    'https://host/#target-launch=x/REDACTION_SECRET_MARKER_0123456789?tail=1' \
    'https://host/#target-launch=x+~REDACTION_SECRET_MARKER_0123456789/suffix' \
    '/resources/REDACTION_SECRET_MARKER_0123456789')"
  while IFS= read -r sample_line; do
    if ! printf '%s\n' "$sample_line" |
      rg --pcre2 "$sensitive_pattern" >/dev/null; then
      echo "Scenario Lab gate sensitive-output detector self-test failed." >&2
      return 1
    fi
  done <<<"$sample"
  redacted="$(redact_gate_output <<<"$sample")"
  if rg -F "$marker" <<<"$redacted" >/dev/null ||
    rg --pcre2 '(?i)#[[:space:]]*target-launch' \
      <<<"$redacted" >/dev/null; then
    echo "Scenario Lab gate redaction self-test failed." >&2
    return 1
  fi
  safe_sample="$(printf '%s\n' \
    'https://host/#target-launcher=public' \
    'https://host/#target-launch-preview=public' \
    'target-launch=public')"
  while IFS= read -r sample_line; do
    if printf '%s\n' "$sample_line" |
      rg --pcre2 "$sensitive_pattern" >/dev/null; then
      echo "Scenario Lab gate sensitive-output safe corpus failed." >&2
      return 1
    fi
  done <<<"$safe_sample"
  safe_redacted="$(redact_gate_output <<<"$safe_sample")"
  if [[ "$safe_redacted" != "$safe_sample" ]]; then
    echo "Scenario Lab gate redaction safe corpus failed." >&2
    return 1
  fi
}

require_no_preexisting_scenario_lab_artifacts() {
  local source_backup_parent="${1:-/tmp}"
  local pattern
  local patterns=(
    "$(dirname "$app_source")/.scenario-lab-*"
    "$(dirname "$layout_source")/.scenario-lab-*"
    "$target_build_root/.scenario-lab-*"
    "$studio_build_root/.scenario-lab-*"
    "$sample_dir/.dart_tool/.scenario-lab-*"
    "$source_backup_parent/scenario-lab-source-backup.*"
  )
  for pattern in "${patterns[@]}"; do
    if compgen -G "$pattern" >/dev/null; then
      echo "Scenario Lab preflight rejected pre-existing gate backup or staging artifacts." >&2
      return 1
    fi
  done
}

assert_payload_sanitized() {
  local payload="$1"
  local label="$2"
  if printf '%s\n' "$payload" | rg --pcre2 "$sensitive_pattern" >/dev/null; then
    echo "$label retained forbidden authority or resource material." >&2
    return 1
  fi
}

defer_termination_signals() {
  deferred_signal_exit=0
  trap 'deferred_signal_exit=130' INT
  trap 'deferred_signal_exit=143' TERM
}

resume_termination_signals() {
  trap 'exit 130' INT
  trap 'exit 143' TERM
  local pending_exit="$deferred_signal_exit"
  deferred_signal_exit=0
  if [[ "$pending_exit" -ne 0 ]]; then
    exit "$pending_exit"
  fi
}

process_group_alive() {
  local pid_value="$1"
  kill -0 -- "-$pid_value" 2>/dev/null
}

stop_process() {
  local pid_value="$1"
  if [[ -z "$pid_value" ]]; then
    return
  fi
  if ! process_group_alive "$pid_value"; then
    if kill -0 "$pid_value" 2>/dev/null; then
      echo "Tracked process $pid_value escaped its isolated process group." >&2
      return 1
    fi
    wait "$pid_value" 2>/dev/null || true
    return
  fi
  kill -INT -- "-$pid_value" 2>/dev/null || true
  for _ in $(seq 1 100); do
    if ! process_group_alive "$pid_value"; then
      wait "$pid_value" 2>/dev/null || true
      return
    fi
    sleep 0.1
  done
  kill -TERM -- "-$pid_value" 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! process_group_alive "$pid_value"; then
      wait "$pid_value" 2>/dev/null || true
      return
    fi
    sleep 0.1
  done
  kill -KILL -- "-$pid_value" 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! process_group_alive "$pid_value"; then
      wait "$pid_value" 2>/dev/null || true
      return
    fi
    sleep 0.1
  done
  echo "Tracked process group $pid_value survived SIGKILL." >&2
  wait "$pid_value" 2>/dev/null || true
  return 1
}

delete_known_tree() {
  local target="$1"
  case "$target" in
    "$state_root" | "$runtime_state_root" | "$target_build" | \
      "$studio_assets" | \
      /tmp/workspace-scenario-lab-chrome.* | \
      /tmp/scenario-lab-captures.* | \
      /tmp/scenario-lab-source-backup.* | \
      "$sample_dir/.dart_tool/.scenario-lab-workspace-backup."* | \
      "$target_build_root/.scenario-lab-web-"* | \
      "$studio_build_root/.scenario-lab-jaspr-"*)
      if [[ -d "$target" ]]; then
        find "$target" -depth -delete
      fi
      ;;
    *)
      echo "Refusing to delete unexpected gate path: $target" >&2
      return 1
      ;;
  esac
}

tree_digest() {
  local target="$1"
  if [[ ! -d "$target" ]]; then
    printf '%s\n' absent
    return
  fi
  if [[ -L "$target" ]]; then
    echo "Refusing to digest symbolic-link tree: $target" >&2
    return 1
  fi
  (
    cd "$target"
    while IFS= read -r -d '' path; do
      printf 'd\0%s\0' "$path"
    done < <(find . -type d -print0 | sort -z)
    while IFS= read -r -d '' path; do
      printf 'f\0%s\0' "$path"
      sha256sum -- "$path"
    done < <(find . -type f -print0 | sort -z)
    while IFS= read -r -d '' path; do
      printf 'l\0%s\0%s\0' "$path" "$(readlink -- "$path")"
    done < <(find . -type l -print0 | sort -z)
  ) | sha256sum | awk '{print $1}'
}

state_digest() {
  tree_digest "$1"
}

atomic_restore_file() {
  local source="$1"
  local target="$2"
  local expected_digest="$3"
  if ! source_restore_staging="$(mktemp \
    "$(dirname "$target")/.scenario-lab-restore.XXXXXX")"; then
    source_restore_staging=""
    return 1
  fi
  if ! cp -p -- "$source" "$source_restore_staging"; then
    rm -f -- "$source_restore_staging"
    source_restore_staging=""
    return 1
  fi
  if ! mv -f -- "$source_restore_staging" "$target"; then
    if [[ ! -e "$source_restore_staging" &&
      -f "$target" && ! -L "$target" &&
      "$(sha256sum "$target" | awk '{print $1}')" == "$expected_digest" ]]; then
      source_restore_staging=""
      return
    fi
    if [[ -f "$source_restore_staging" &&
      ! -L "$source_restore_staging" ]]; then
      rm -f -- "$source_restore_staging"
    fi
    source_restore_staging=""
    return 1
  fi
  source_restore_staging=""
  if [[ "$(sha256sum "$target" | awk '{print $1}')" != \
    "$expected_digest" ]]; then
    echo "Scenario Lab source restore digest mismatch: $target" >&2
    return 1
  fi
}

restore_source_bytes() {
  if [[ "$source_backup_armed" -ne 1 ]]; then
    if [[ -n "$source_backup_dir" && -d "$source_backup_dir" ]]; then
      delete_known_tree "$source_backup_dir"
    fi
    source_backup_dir=""
    return
  fi
  local failed=0
  if ! atomic_restore_file \
    "$source_backup_dir/app_factory.dart" \
    "$app_source" \
    "$app_source_before_digest"; then
    failed=1
  fi
  if ! atomic_restore_file \
    "$source_backup_dir/layout-delivery-journey.yaml" \
    "$layout_source" \
    "$layout_source_before_digest"; then
    failed=1
  fi
  for staging in "$app_source_staging" "$layout_source_staging" \
    "$source_restore_staging"; do
    if [[ -n "$staging" && -f "$staging" && ! -L "$staging" ]]; then
      rm -f -- "$staging"
    fi
  done
  app_source_staging=""
  layout_source_staging=""
  source_restore_staging=""
  if [[ "$failed" -ne 0 ]]; then
    return 1
  fi
  delete_known_tree "$source_backup_dir"
  source_backup_dir=""
  source_backup_armed=0
}

apply_ep4_mutations() {
  if [[ "$source_backup_armed" -ne 1 ]]; then
    echo "Scenario Lab source backup is not armed." >&2
    return 1
  fi
  defer_termination_signals
  app_source_staging="$(mktemp \
    "$(dirname "$app_source")/.scenario-lab-app.XXXXXX")"
  layout_source_staging="$(mktemp \
    "$(dirname "$layout_source")/.scenario-lab-layout.XXXXXX")"
  if ! sed 's/0xFF6750A4/0xFFFF0000/' \
      "$app_source" >"$app_source_staging" ||
    ! sed 's/zoom: 0[.]85/zoom: 0.84/' \
      "$layout_source" >"$layout_source_staging"; then
    rm -f -- "$app_source_staging" "$layout_source_staging"
    app_source_staging=""
    layout_source_staging=""
    resume_termination_signals
    return 1
  fi
  chmod --reference="$app_source" "$app_source_staging"
  chmod --reference="$layout_source" "$layout_source_staging"
  mv -f -- "$app_source_staging" "$app_source"
  app_source_staging=""
  mv -f -- "$layout_source_staging" "$layout_source"
  layout_source_staging=""
  resume_termination_signals
  if [[ "$(rg -o -F '0xFF6750A4' "$app_source" | wc -l)" -ne 0 ||
    "$(rg -o -F '0xFFFF0000' "$app_source" | wc -l)" -ne 1 ||
    "$(rg -o -F 'zoom: 0.85' "$layout_source" | wc -l)" -ne 0 ||
    "$(rg -o -F 'zoom: 0.84' "$layout_source" | wc -l)" -ne 1 ]]; then
    echo "Scenario Lab mutation was not exact." >&2
    return 1
  fi
}

handle_failed_tree_isolation() {
  local original="$1"
  local backup_member="$2"
  local backup_root="$3"
  local label="$4"
  local was_present_name="$5"
  local isolated_name="$6"
  local backup_dir_name="$7"

  if [[ ! -e "$original" && -d "$backup_member" ]]; then
    printf -v "$was_present_name" '%s' 1
    printf -v "$isolated_name" '%s' 1
    echo "$label move reported failure after isolation; restoration is armed." >&2
    return
  fi
  if [[ -d "$original" && ! -e "$backup_member" ]]; then
    if rmdir -- "$backup_root"; then
      printf -v "$backup_dir_name" '%s' ""
    else
      echo "$label move failed before isolation, but its non-empty backup directory was preserved." >&2
    fi
    return
  fi
  echo "$label move left an ambiguous state; both paths were preserved." >&2
}

isolate_target_build() {
  if [[ "$target_build_isolated" -eq 1 ]]; then
    return
  fi
  if [[ -L "$target_build_root" || -L "$target_build" ||
    (-e "$target_build_root" && ! -d "$target_build_root") ]]; then
    echo "Scenario Lab Target build paths must not be symbolic links." >&2
    return 1
  fi
  if [[ -e "$target_build" && ! -d "$target_build" ]]; then
    echo "Scenario Lab Target build is not a directory." >&2
    return 1
  fi
  defer_termination_signals
  if [[ ! -d "$target_build_root" ]] &&
    ! mkdir -p -- "$target_build_root"; then
    resume_termination_signals
    echo "Scenario Lab Target build root could not be created." >&2
    return 1
  fi
  if ! target_build_backup_dir="$(mktemp -d \
    "$target_build_root/.scenario-lab-web-backup.XXXXXX")"; then
    target_build_backup_dir=""
    resume_termination_signals
    echo "Scenario Lab Target build backup could not be allocated." >&2
    return 1
  fi
  if [[ -d "$target_build" ]]; then
    local move_failed=0
    if ! mv -- "$target_build" "$target_build_backup_dir/web"; then
      move_failed=1
    fi
    if [[ "$move_failed" -ne 0 || -e "$target_build" ||
      ! -d "$target_build_backup_dir/web" ]]; then
      handle_failed_tree_isolation \
        "$target_build" "$target_build_backup_dir/web" \
        "$target_build_backup_dir" "Scenario Lab Target build" \
        target_build_was_present target_build_isolated \
        target_build_backup_dir
      resume_termination_signals
      return 1
    fi
    target_build_was_present=1
  fi
  target_build_isolated=1
  resume_termination_signals
}

install_target_build() {
  local candidate="$1"
  if [[ ! -d "$candidate" || -L "$candidate" ||
    ! -f "$candidate/index.html" ]]; then
    echo "Scenario Lab candidate Target build is invalid." >&2
    return 1
  fi
  isolate_target_build
  defer_termination_signals
  if [[ -d "$target_build" ]]; then
    target_build_retired="$(mktemp -d \
      "$target_build_root/.scenario-lab-web-retired.XXXXXX")"
    rmdir -- "$target_build_retired"
    mv -- "$target_build" "$target_build_retired"
  fi
  mv -- "$candidate" "$target_build"
  resume_termination_signals
  if [[ -n "$target_build_retired" && -d "$target_build_retired" ]]; then
    delete_known_tree "$target_build_retired"
    target_build_retired=""
  fi
}

restore_target_build() {
  if [[ "$target_build_isolated" -ne 1 ]]; then
    return
  fi
  if [[ -d "$target_build" ]]; then
    delete_known_tree "$target_build"
  fi
  for candidate in "$target_build_temp" "$target_build_retired"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      delete_known_tree "$candidate"
    fi
  done
  target_build_temp=""
  target_build_retired=""
  if [[ "$target_build_was_present" -eq 1 ]]; then
    if [[ ! -d "$target_build_backup_dir/web" ]]; then
      echo "Scenario Lab Target build backup is missing." >&2
      return 1
    fi
    mv -- "$target_build_backup_dir/web" "$target_build"
  fi
  delete_known_tree "$target_build_backup_dir"
  target_build_backup_dir=""
  target_build_isolated=0
  target_build_was_present=0
  if [[ "$(tree_digest "$target_build")" != "$target_build_before_digest" ]]; then
    echo "Target build/web was not restored byte-for-byte." >&2
    return 1
  fi
  if [[ "$target_build_root_was_present" -eq 0 ]]; then
    rmdir -- "$target_build_root" 2>/dev/null || true
  fi
}

isolate_studio_build() {
  if [[ "$studio_build_isolated" -eq 1 ]]; then
    return
  fi
  if [[ -L "$studio_build_root" || -L "$studio_assets" ||
    (-e "$studio_build_root" && ! -d "$studio_build_root") ]]; then
    echo "Scenario Lab Studio build paths must not be symbolic links." >&2
    return 1
  fi
  if [[ -e "$studio_assets" && ! -d "$studio_assets" ]]; then
    echo "Scenario Lab Studio build is not a directory." >&2
    return 1
  fi
  defer_termination_signals
  if [[ -d "$studio_build_root" ]]; then
    studio_build_root_was_present=1
  elif ! mkdir -p -- "$studio_build_root"; then
    resume_termination_signals
    echo "Scenario Lab Studio build root could not be created." >&2
    return 1
  fi
  if ! studio_build_backup_dir="$(mktemp -d \
    "$studio_build_root/.scenario-lab-jaspr-backup.XXXXXX")"; then
    studio_build_backup_dir=""
    resume_termination_signals
    echo "Scenario Lab Studio build backup could not be allocated." >&2
    return 1
  fi
  if [[ -d "$studio_assets" ]]; then
    local move_failed=0
    if ! mv -- "$studio_assets" "$studio_build_backup_dir/jaspr"; then
      move_failed=1
    fi
    if [[ "$move_failed" -ne 0 || -e "$studio_assets" ||
      ! -d "$studio_build_backup_dir/jaspr" ]]; then
      handle_failed_tree_isolation \
        "$studio_assets" "$studio_build_backup_dir/jaspr" \
        "$studio_build_backup_dir" "Scenario Lab Studio build" \
        studio_build_was_present studio_build_isolated \
        studio_build_backup_dir
      resume_termination_signals
      return 1
    fi
    studio_build_was_present=1
  fi
  studio_build_isolated=1
  resume_termination_signals
}

restore_studio_build() {
  if [[ "$studio_build_isolated" -ne 1 ]]; then
    return
  fi
  if [[ -d "$studio_assets" ]]; then
    delete_known_tree "$studio_assets"
  fi
  if [[ "$studio_build_was_present" -eq 1 ]]; then
    if [[ ! -d "$studio_build_backup_dir/jaspr" ]]; then
      echo "Scenario Lab Studio build backup is missing." >&2
      return 1
    fi
    mv -- "$studio_build_backup_dir/jaspr" "$studio_assets"
  fi
  delete_known_tree "$studio_build_backup_dir"
  studio_build_backup_dir=""
  studio_build_isolated=0
  studio_build_was_present=0
  if [[ "$(tree_digest "$studio_assets")" != "$studio_build_before_digest" ]]; then
    echo "Studio build/jaspr was not restored byte-for-byte." >&2
    return 1
  fi
  if [[ "$studio_build_root_was_present" -eq 0 ]]; then
    rmdir -- "$studio_build_root" 2>/dev/null || true
  fi
}

isolate_workspace_state() {
  if [[ "$state_isolated" -eq 1 ]]; then
    return
  fi
  if [[ -L "$runtime_state_root" ||
    (-e "$runtime_state_root" && ! -d "$runtime_state_root") ]]; then
    echo "Scenario Lab runtime state root must be a real directory." >&2
    return 1
  fi
  defer_termination_signals
  if ! state_backup_dir="$(mktemp -d \
    "$sample_dir/.dart_tool/.scenario-lab-workspace-backup.XXXXXX")"; then
    state_backup_dir=""
    resume_termination_signals
    echo "Scenario Lab runtime state backup could not be allocated." >&2
    return 1
  fi
  if [[ -d "$runtime_state_root" ]]; then
    local move_failed=0
    if ! mv -- "$runtime_state_root" "$state_backup_dir/workspace"; then
      move_failed=1
    fi
    if [[ "$move_failed" -ne 0 || -e "$runtime_state_root" ||
      ! -d "$state_backup_dir/workspace" ]]; then
      handle_failed_tree_isolation \
        "$runtime_state_root" "$state_backup_dir/workspace" \
        "$state_backup_dir" "Scenario Lab runtime state" \
        state_was_present state_isolated state_backup_dir
      resume_termination_signals
      return 1
    fi
    state_was_present=1
  fi
  state_isolated=1
  resume_termination_signals
}

restore_workspace_state() {
  if [[ "$state_isolated" -ne 1 ]]; then
    return
  fi
  if [[ -d "$runtime_state_root" ]]; then
    delete_known_tree "$runtime_state_root"
  fi
  if [[ "$state_was_present" -eq 1 ]]; then
    local backup="$state_backup_dir/workspace"
    if [[ ! -d "$backup" ]]; then
      echo "Scenario Lab gate state backup is missing." >&2
      return 1
    fi
    mv -- "$backup" "$runtime_state_root"
  fi
  if [[ -n "$state_backup_dir" && -d "$state_backup_dir" ]]; then
    delete_known_tree "$state_backup_dir"
  fi
  state_backup_dir=""
  state_isolated=0
  state_was_present=0
  local restored_digest
  restored_digest="$(state_digest "$runtime_state_root")"
  if [[ "$restored_digest" != "$state_before_digest" ]]; then
    echo "Workspace state was not restored byte-for-byte." >&2
    return 1
  fi
}

cleanup() {
  local exit_code=$?
  local shutdown_verified=1
  trap - EXIT INT TERM
  stop_process "$dev_pid" || shutdown_verified=0
  stop_process "$api_pid" || shutdown_verified=0
  stop_process "$chrome_pid" || shutdown_verified=0
  dev_pid=""
  api_pid=""
  chrome_pid=""
  for port in 7367 7368 8181 "$chrome_debug_port" ${target_port:-} \
    "${target_ports[@]}" \
    "${gateway_ports[@]}"; do
    if [[ -n "$port" ]] && ! wait_for_port_free "$port"; then
      shutdown_verified=0
      exit_code=1
    fi
  done
  if [[ "$shutdown_verified" -eq 1 ]]; then
    if ! restore_source_bytes; then
      exit_code=1
    fi
    if ! restore_target_build; then
      exit_code=1
    fi
    if ! restore_studio_build; then
      exit_code=1
    fi
    if ! restore_workspace_state; then
      exit_code=1
    fi
  else
    echo "Writer shutdown was not proven; recoverable source, build, and state backups were preserved." >&2
    exit_code=1
  fi
  if [[ "$shutdown_verified" -eq 1 && -n "$chrome_profile" &&
    -d "$chrome_profile" ]]; then
    if ! delete_known_tree "$chrome_profile"; then
      exit_code=1
    fi
  fi
  if [[ "$capture_dir_owned" -eq 1 && -n "$capture_dir" &&
    -d "$capture_dir" ]]; then
    if ! delete_known_tree "$capture_dir"; then
      exit_code=1
    fi
  elif [[ "$exit_code" -ne 0 && "$capture_targets_armed" -eq 1 &&
    -n "$capture_dir" ]]; then
    for capture_path in "$dialog_capture_path" "$quality_capture_path"; do
      if [[ -f "$capture_path" && ! -L "$capture_path" ]]; then
        rm -f -- "$capture_path"
      fi
    done
    if [[ "$capture_dir_created" -eq 1 && -d "$capture_dir" ]]; then
      rmdir -- "$capture_dir" 2>/dev/null || true
    fi
  fi
  if [[ "$exit_code" -ne 0 ]]; then
    for log_path in "$currentness_probe_log" "$identity_after_log" \
      "$identity_before_log" "$recovery_probe_log" "$probe_log" \
      "$restart_dev_log" "$dev_log" "$api_log"; do
      if [[ -n "$log_path" && -f "$log_path" ]]; then
        echo "[scenario-lab-vertical] $(basename "$log_path")" >&2
        tail -n 240 "$log_path" | redact_gate_output >&2 || true
      fi
    done
  fi
  for log_path in "$currentness_probe_log" "$identity_after_log" \
    "$identity_before_log" "$recovery_probe_log" "$probe_log" \
    "$restart_dev_log" "$dev_log" "$api_log"; do
    if [[ -n "$log_path" && -f "$log_path" ]]; then
      rm -f -- "$log_path"
    fi
  done
  exit "$exit_code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_json_readiness() {
  local pid_value="$1"
  local log_path="$2"
  local label="$3"
  local ready=""
  for _ in $(seq 1 480); do
    ready="$(jq -c '
      select(
        .status == "ready" or
        (.ok == true and .result.status == "ready")
      )
    ' "$log_path" 2>/dev/null | tail -n 1 || true)"
    if [[ -n "$ready" ]]; then
      printf '%s\n' "$ready"
      return
    fi
    if ! kill -0 "$pid_value" 2>/dev/null; then
      redact_gate_output <"$log_path" >&2
      echo "$label exited before readiness." >&2
      exit 1
    fi
    sleep 0.25
  done
  redact_gate_output <"$log_path" >&2
  echo "$label timed out before readiness." >&2
  exit 1
}

start_full_local_dev() {
  local log_path="$1"
  require_port_free 7367
  require_port_free 7368
  echo "[scenario-lab-vertical] starting full-local Host and Studio" >&2
  defer_termination_signals
  (
    cd "$sample_dir"
    exec setsid "${toolchain[@]}" dart run \
      ../../apps/workspace_cli/bin/workspace.dart --json dev \
      --config workspace.yaml \
      --profile full-local \
      --host-port 7367 \
      --studio-port 7368 \
      --studio-assets "$studio_assets" \
      --no-open
  ) >"$log_path" 2>&1 &
  dev_pid=$!
  resume_termination_signals
  local ready
  ready="$(wait_for_json_readiness "$dev_pid" "$log_path" "workspace dev")"
  jq -e '
    .ok == true and
    .result.status == "ready" and
    .result.profileId == "full-local" and
    .result.hostOrigin == "http://127.0.0.1:7367" and
    .result.studioOrigin == "http://127.0.0.1:7368"
  ' <<<"$ready" >/dev/null
}

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Scenario Lab conformance requires Linux." >&2
  exit 1
fi
for command_name in base64 chmod cp curl find jq mktemp mv readlink rg rmdir \
  sed setsid sha256sum sort uname; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Scenario Lab conformance requires command: $command_name" >&2
    exit 1
  fi
done
verify_gate_redactor
require_no_preexisting_scenario_lab_artifacts
if ((${#toolchain[@]} == 0)); then
  command -v dart >/dev/null 2>&1
  command -v flutter >/dev/null 2>&1
  command -v jaspr >/dev/null 2>&1
fi
if command -v google-chrome-stable >/dev/null 2>&1; then
  chromium_executable="$(command -v google-chrome-stable)"
elif command -v google-chrome >/dev/null 2>&1; then
  chromium_executable="$(command -v google-chrome)"
elif command -v chromium >/dev/null 2>&1; then
  chromium_executable="$(command -v chromium)"
else
  echo "Chrome/Chromium is required for Scenario Lab conformance." >&2
  exit 1
fi

prepare_visual_capture_directory

for port in 7367 7368 8181 "$chrome_debug_port"; do
  require_port_free "$port"
done

if [[ ! -f "$app_source" || -L "$app_source" ||
  ! -f "$layout_source" || -L "$layout_source" ]]; then
  echo "Scenario Lab mutation anchors must be regular source files." >&2
  exit 1
fi
if [[ "$(rg -o -F '0xFF6750A4' "$app_source" | wc -l)" -ne 1 ||
  "$(rg -o -F '0xFFFF0000' "$app_source" | wc -l)" -ne 0 ]]; then
  echo "Scenario Lab app color mutation anchor is not exact." >&2
  exit 1
fi
if [[ "$(rg -o -F 'zoom: 0.85' "$layout_source" | wc -l)" -ne 1 ||
  "$(rg -o -F 'zoom: 0.84' "$layout_source" | wc -l)" -ne 0 ]]; then
  echo "Scenario Lab topology zoom mutation anchor is not exact." >&2
  exit 1
fi
app_source_before_digest="$(sha256sum "$app_source" | awk '{print $1}')"
layout_source_before_digest="$(sha256sum "$layout_source" | awk '{print $1}')"
target_build_before_digest="$(tree_digest "$target_build")"
studio_build_before_digest="$(tree_digest "$studio_assets")"
if [[ -d "$target_build_root" ]]; then
  target_build_root_was_present=1
fi
defer_termination_signals
source_backup_dir="$(mktemp -d \
  "/tmp/scenario-lab-source-backup.XXXXXX")"
cp -p -- "$app_source" "$source_backup_dir/app_factory.dart"
cp -p -- \
  "$layout_source" \
  "$source_backup_dir/layout-delivery-journey.yaml"
if [[ "$(sha256sum "$source_backup_dir/app_factory.dart" | awk '{print $1}')" != \
    "$app_source_before_digest" ||
  "$(sha256sum "$source_backup_dir/layout-delivery-journey.yaml" |
    awk '{print $1}')" != "$layout_source_before_digest" ]]; then
  echo "Scenario Lab source backup failed digest verification." >&2
  exit 1
fi
source_backup_armed=1
resume_termination_signals

mkdir -p "$sample_dir/.dart_tool"
if [[ -L "$runtime_state_root" ]]; then
  echo "Scenario Lab runtime state root must not be a symbolic link." >&2
  exit 1
fi
state_before_digest="$(state_digest "$runtime_state_root")"
isolate_workspace_state

if [[ "${SCENARIO_LAB_SKIP_BUILD:-0}" != "1" ]]; then
  echo "[scenario-lab-vertical] building release Studio and baseline Target" >&2
  isolate_studio_build
  (
    cd "$repo_dir"
    "${toolchain[@]}" dart run examples/tool/showcase.dart \
      --build-studio --check
  )
  mkdir -p -- "$target_build_root"
  defer_termination_signals
  target_build_temp="$(mktemp -d \
    "$target_build_root/.scenario-lab-web-baseline.XXXXXX")"
  resume_termination_signals
  (
    cd "$sample_dir"
    "${toolchain[@]}" flutter build web \
      --release \
      --target=tool/target_main.dart \
      --dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181 \
      --dart-define=TARGET_CONTROLLER_ORIGIN=http://127.0.0.1:7368 \
      --output="$target_build_temp"
  )
  install_target_build "$target_build_temp"
  target_build_temp=""
else
  echo "[scenario-lab-vertical] validating existing release artifacts" >&2
  (
    cd "$repo_dir"
    "${toolchain[@]}" dart run examples/tool/showcase.dart --check
  )
fi
[[ -f "$studio_assets/index.html" ]]
[[ -f "$target_build/index.html" ]]

baseline_input="$state_root/gate-input/dashboard-ready-baseline.png"
mkdir -p "$(dirname "$baseline_input")"
base64 --decode "$baseline_asset" >"$baseline_input"
expected_baseline_artifact="$(
  awk '$1 == "artifactDigest:" {print $2}' "$baseline_authoring"
)"
expected_baseline_provenance="$(
  awk '$1 == "provenanceDigest:" {print $2}' "$baseline_authoring"
)"
if [[ "sha256:$(sha256sum "$baseline_input" | awk '{print $1}')" != \
  "$expected_baseline_artifact" ]]; then
  echo "Consumer-owned Scenario Lab baseline failed digest verification." >&2
  exit 1
fi
echo "[scenario-lab-vertical] importing consumer-owned baseline" >&2
baseline_import="$(
  (
  cd "$sample_dir"
  "${toolchain[@]}" dart run ../../apps/workspace_cli/bin/workspace.dart \
    --json evidence import-artifact \
    --input "$baseline_input" \
    --media-type image/png \
    --classification internal \
    --source-id delivery-lab.dashboard-ready \
    --import-policy delivery-lab.baseline-v1 \
    --config workspace.yaml \
    --profile full-local
  )
)"
if ! jq -e \
  --arg artifact "$expected_baseline_artifact" \
  --arg provenance "$expected_baseline_provenance" '
    .ok == true and
    .result.artifactDigest == $artifact and
    .result.provenanceDigest == $provenance and
    .result.mediaType == "image/png" and
    .result.classification == "internal" and
    .result.sourceId == "delivery-lab.dashboard-ready" and
    .result.importPolicyId == "delivery-lab.baseline-v1"
  ' <<<"$baseline_import" >/dev/null; then
  echo "Consumer-owned Scenario Lab baseline import is not authoring-bound." >&2
  echo "Baseline import payload suppressed." >&2
  exit 1
fi
baseline_import_summary="$(jq -c '
  .result | {
    artifactDigest,
    provenanceDigest,
    mediaType,
    classification,
    sourceId,
    importPolicyId
  }
' <<<"$baseline_import")"

api_log="$(mktemp "${TMPDIR:-/tmp}/scenario-lab-api.XXXXXX.jsonl")"
dev_log="$(mktemp "${TMPDIR:-/tmp}/scenario-lab-dev.XXXXXX.jsonl")"
probe_log="$(mktemp "${TMPDIR:-/tmp}/scenario-lab-probe.XXXXXX.jsonl")"

echo "[scenario-lab-vertical] starting sample API" >&2
require_port_free 8181
defer_termination_signals
(
  cd "$repo_dir"
  exec setsid "${toolchain[@]}" dart run examples/sample_api/bin/server.dart \
    --port 8181
) >"$api_log" 2>&1 &
api_pid=$!
resume_termination_signals
api_ready="$(wait_for_json_readiness "$api_pid" "$api_log" "sample API")"
jq -e '
  .service == "sample-api" and
  .origin == "http://127.0.0.1:8181"
' <<<"$api_ready" >/dev/null

start_full_local_dev "$dev_log"

identity_before_log="$(mktemp \
  "${TMPDIR:-/tmp}/scenario-lab-identity-before.XXXXXX.jsonl")"
echo "[scenario-lab-vertical] opening exact pre-change content-set" >&2
if ! identity_before_payload="$(
  "${toolchain[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" \
    "http://127.0.0.1:7368" \
    2>"$identity_before_log"
)"; then
  echo "Pre-change content identity probe failed." >&2
  exit 1
fi
assert_payload_sanitized \
  "$identity_before_payload" \
  "Pre-change content identity proof"
if ! jq -e '
  .contentSet.describeOpenIdentityMatches == true and
  .contentSet.workspaceMatches == true and
  .contentSet.experienceMatches == true and
  .contentSet.workspaceSnapshotDigest == .snapshotDigest and
  .contentSet.workspaceContentDigest == .workspaceContentDigest and
  (.contentSet.scenarioLabManifestDigest | startswith("sha256:")) and
  .contentSet.resourcePurposes == (
    [
      "workspace-snapshot",
      "experience-topology-bundle",
      "scenario-facet-manifest",
      "scenario-lab-manifest"
    ] +
    (if .contentSet.motionManifestDigest == null
     then [] else ["motion-manifest"] end)
  ) and
  (.refresh? == null)
' <<<"$identity_before_payload" >/dev/null; then
  echo "Pre-change content identity/open proof is incomplete." >&2
  exit 1
fi

chrome_profile="$(mktemp -d /tmp/workspace-scenario-lab-chrome.XXXXXX)"
require_port_free "$chrome_debug_port"
defer_termination_signals
setsid "$chromium_executable" \
  --headless=new \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$chrome_debug_port" \
  --remote-allow-origins="http://127.0.0.1:$chrome_debug_port" \
  --user-data-dir="$chrome_profile" \
  --no-first-run \
  --disable-gpu \
  --window-size=1440,1000 \
  --noerrdialogs \
  about:blank >/dev/null 2>&1 &
chrome_pid=$!
resume_termination_signals
for _ in $(seq 1 100); do
  if ! kill -0 "$chrome_pid" 2>/dev/null; then
    echo "Tracked Chrome exited before CDP readiness." >&2
    exit 1
  fi
  if curl --fail --silent \
    "http://127.0.0.1:$chrome_debug_port/json/version" >/dev/null; then
    break
  fi
  sleep 0.1
done
if ! kill -0 "$chrome_pid" 2>/dev/null; then
  echo "Tracked Chrome exited before CDP readiness." >&2
  exit 1
fi
curl --fail --silent \
  "http://127.0.0.1:$chrome_debug_port/json/version" >/dev/null

echo "[scenario-lab-vertical] exercising browser-owned run and relay" >&2
if ! probe_payload="$(
  "${toolchain[@]}" dart run "$repo_dir/tools/probes/studio_jaspr_cdp_probe.dart" \
    "http://127.0.0.1:$chrome_debug_port" \
    "http://127.0.0.1:7368/lab/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab" \
    --scenario-lab-audit \
    "--dialog-screenshot=$dialog_capture_path" \
    "--screenshot=$quality_capture_path" \
    2>"$probe_log"
)"; then
  blocked_payload="$(jq -c '
    select(.status == "blocked" and .mode == "scenario-lab-audit")
  ' "$probe_log" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$blocked_payload" ]]; then
    record_relay_ports_from_payload "$blocked_payload"
    record_target_port "$(
      jq -r '.details.relayAtMount.targetPort // empty' \
        <<<"$blocked_payload"
    )"
    record_gateway_port "$(
      jq -r '.details.relayAtMount.gatewayPort // empty' \
        <<<"$blocked_payload"
    )"
    export_blocked_capture "$blocked_payload"
  fi
  echo "Scenario Lab browser proof stopped at a fail-closed boundary." >&2
  exit 1
fi
assert_payload_sanitized "$probe_payload" "Scenario Lab browser proof"
record_target_port "$(jq -r '.relay.targetPort' <<<"$probe_payload")"
record_gateway_port "$(jq -r '.relay.gatewayPort' <<<"$probe_payload")"

if ! jq -e \
  --arg baseline_artifact "$expected_baseline_artifact" \
  --arg baseline_provenance "$expected_baseline_provenance" \
  --argjson identity "$identity_before_payload" '
  .status == "passed" and
  .mode == "scenario-lab-audit" and
  .route == "/lab/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab" and
  (.runId | startswith("run-")) and
  (.secondRunId | startswith("run-")) and
  .runId != .secondRunId and
  .relay.relayCount == 1 and
  .relay.boundRelayCount == 1 and
  .relay.iframeCount == 1 and
  .relay.scopedIframeCount == 1 and
  .relay.runId == .runId and
  (.relay.targetPort | type) == "number" and
  .relay.targetPort >= 1 and
  .relay.targetPort <= 65535 and
  .relay.aboutBlank == true and
  .relay.childNavigationScrubbed == true and
  .relay.targetFrameBound == true and
  .relay.relayV2Ready == true and
  .relay.relayV2Fenced == true and
  .relay.mountAuthorized == true and
  .relay.controllerBound == true and
  .relay.helloAccepted == true and
  .relay.relayResultsAccepted == true and
  (.relay.relayResultCount | type) == "number" and
  .relay.relayResultCount > 0 and
  .relay.networkTraceComplete == true and
  .relay.gatewayRequestBound == true and
  .relay.gatewayRequestCount == 1 and
  .relay.gatewaySuccessfulResponseCount == 1 and
  .relay.directApiRequestCount == 0 and
  .relay.gatewayTrafficObserved == true and
  .relay.gatewayTrafficSucceeded == true and
  .relay.gatewayBound == true and
  .relay.gatewayRouted == true and
  (.relay.gatewayPort | type) == "number" and
  .relay.gatewayPort >= 1 and
  .relay.gatewayPort <= 65535 and
  .targetControl.semanticStates == ["disabled", "enabled"] and
  (.targetControl.disabledScreenshotDigest | startswith("sha256:")) and
  (.targetControl.enabledScreenshotDigest | startswith("sha256:")) and
  .targetControl.disabledScreenshotDigest !=
    .targetControl.enabledScreenshotDigest and
  .targetControl.captureErrors == [] and
  .terminal.state == "succeeded" and
  .terminal.cleanup == "succeeded" and
  .terminal.verification == "passed" and
  (.terminal.resultDigest | startswith("sha256:")) and
  (.terminal.snapshotDigest | startswith("sha256:")) and
  .terminal.contentSetDigest == $identity.contentSet.contentSetDigest and
  .terminal.catalogDigest == $identity.contentSet.catalogDigest and
  .terminal.scenarioLabManifestDigest ==
    $identity.contentSet.scenarioLabManifestDigest and
  .evidence.state == "collected" and
  .evidence.freshness == "fresh" and
  (.evidence.resultDigest | startswith("sha256:")) and
  (.evidence.evidenceDigest | startswith("sha256:")) and
  (.evidence.artifactDigest | startswith("sha256:")) and
  (.evidence.provenanceDigest | startswith("sha256:")) and
  .comparison.kind == "visual" and
  .comparison.verification == "passed" and
  (.comparison.resultDigest | startswith("sha256:")) and
  .comparison.comparedPixels > 0 and
  .comparison.changedPixels >= 0 and
  .comparison.changedPixels <= .comparison.comparedPixels and
  (.comparison.changedPixels / .comparison.comparedPixels) <= 0.005 and
  .comparison.maxChannelDeltaObserved >= 0 and
  .comparison.maxChannelDeltaObserved <= 255 and
  (.captures.decisionDialog.digest | startswith("sha256:")) and
  (.captures.decisionDialog | keys) == ["digest", "height", "width"] and
  .captures.decisionDialog.width >= 1000 and
  .captures.decisionDialog.height >= 700 and
  (.captures.qualityFinal.digest | startswith("sha256:")) and
  (.captures.qualityFinal | keys) == ["digest", "height", "width"] and
  .captures.qualityFinal.width >= 1000 and
  .captures.qualityFinal.height >= 700 and
  (.quality.states | index("passing")) != null and
  .quality.verification == "passed" and
  .quality.humanDecision == "rejected" and
  .quality.reviewAvailability == "available" and
  .quality.decisionOperation == "ready" and
  .quality.decisionCount == 2 and
  .quality.headDecisionDigest == .decisions.head.decisionDigest and
  .quality.decisionRequirement ==
    .decisions.head.attribution.requirementId and
  .quality.decisionPolicy == .decisions.head.attribution.accessPolicyId and
  ([.quality.resources[].state] | unique) == ["rendered"] and
  ([.quality.resources[].role] | sort) == [
    "comparisonBaseline",
    "comparisonCandidate",
    "requiredEvidence"
  ] and
  (.qualityReview.confirmBeforeAuthority | keys) == [
    "approve",
    "supersedingReject"
  ] and
  .qualityReview.confirmBeforeAuthority.approve == true and
  .qualityReview.confirmBeforeAuthority.supersedingReject == true and
  (.qualityReview.dialogAccessibility | keys) == [
    "approveEscapeClosedWithoutRpc",
    "approveFocusReturnedToOpener",
    "approveInitialFocus",
    "nativeModal",
    "supersedeEscapeClosedWithoutRpc",
    "supersedeFocusReturnedToOpener",
    "supersedeInitialFocus"
  ] and
  .qualityReview.dialogAccessibility.nativeModal == true and
  .qualityReview.dialogAccessibility.approveInitialFocus == "confirm" and
  .qualityReview.dialogAccessibility.supersedeInitialFocus == "confirm" and
  .qualityReview.dialogAccessibility.approveEscapeClosedWithoutRpc == true and
  .qualityReview.dialogAccessibility.approveFocusReturnedToOpener == true and
  .qualityReview.dialogAccessibility.supersedeEscapeClosedWithoutRpc == true and
  .qualityReview.dialogAccessibility.supersedeFocusReturnedToOpener == true and
  .qualityReview.automatedUnchanged == true and
  .qualityReview.humanTransitions == ["unreviewed", "approved", "rejected"] and
  (.qualityReview.automatedDigest | startswith("sha256:")) and
  (.qualityReview.qualitySurfaceDigest | startswith("sha256:")) and
  (.qualityReview.reviewSetDigest | startswith("sha256:")) and
  .qualityReview.reviewSet.resourceCount == 3 and
  ([.qualityReview.reviewSet.artifacts[].role] | sort) == [
    "comparisonBaseline",
    "comparisonCandidate",
    "requiredEvidence"
  ] and
  ([.qualityReview.reviewSet.artifacts[] |
    select(.role == "comparisonBaseline")][0].artifactDigest) ==
      $baseline_artifact and
  ([.qualityReview.reviewSet.artifacts[] |
    select(.role == "comparisonBaseline")][0].provenanceDigest) ==
      $baseline_provenance and
  ([.qualityReview.reviewSet.artifacts[] |
    select(.role == "comparisonBaseline")][0].provenanceKind) ==
      "supplementalArtifactImport" and
  ([.qualityReview.reviewSet.artifacts[] |
    select(.role == "requiredEvidence")][0].artifactDigest) ==
      .evidence.artifactDigest and
  ([.qualityReview.reviewSet.artifacts[] |
    select(.role == "requiredEvidence")][0].provenanceDigest) ==
      .evidence.provenanceDigest and
  ([.qualityReview.reviewSet.artifacts[] |
    select(.role == "requiredEvidence")][0].provenanceKind) ==
      "appAdapterCaptureReceipt" and
  .decisions.approved.decision == "approved" and
  .decisions.approved.state == "approved" and
  .decisions.approved.supersedesDecisionDigest == null and
  .decisions.head.decision == "rejected" and
  .decisions.head.state == "rejected" and
  .decisions.head.supersedesDecisionDigest ==
    .decisions.approved.decisionDigest and
  .decisions.oldAfterSupersession.recordId ==
    .decisions.approved.recordId and
  .decisions.oldAfterSupersession.decisionDigest ==
    .decisions.approved.decisionDigest and
  .decisions.oldAfterSupersession.state == "superseded" and
  .decisions.oldAfterSupersession.supersededByDecisionDigest ==
    .decisions.head.decisionDigest and
  .decisions.headView.recordId == .decisions.head.recordId and
  .decisions.headView.decisionDigest == .decisions.head.decisionDigest and
  .decisions.headView.state == "rejected" and
  .decisions.headView.supersededByDecisionDigest == null and
  .decisions.approved.attribution.role == "reviewer" and
  .decisions.head.attribution.role == "reviewer" and
  .decisions.approved.attribution.principalId ==
    .decisions.head.attribution.principalId and
  .decisions.approved.attribution.authorityId ==
    .decisions.head.attribution.authorityId and
  .decisions.approved.attribution.accessPolicyId ==
    .decisions.head.attribution.accessPolicyId and
  (.decisions.historyDigest | startswith("sha256:")) and
  .cancel.state == "cancelled" and
  (.cancel.cleanup == "notRequired" or .cancel.cleanup == "succeeded") and
  .semanticHtml.unnamedFocusableCount == 0 and
  .keyboard.uniqueTabStops >= 5 and
  .reflow200Percent.horizontalDocumentOverflow == false and
  .reducedMotion.queryMatches == true and
  .accessibilityNodes >= 20 and
  .severeBrowserLogs == 0 and
  (.labRpc.requestsByMethod | type) == "object" and
  (.labRpc.requestsByMethod | length) > 0 and
  (.labRpc.resultsByMethod | type) == "object" and
  .labRpc.failures == [] and
  .labRpc.resultsByMethod == .labRpc.requestsByMethod and
  .qualityRpc.failures == [] and
  .qualityRpc.requestsByMethod == {
    "quality.describe": 3,
    "quality.open": 3,
    "quality.decision.grant": 2,
    "quality.decision.append": 2,
    "quality.decision.get": 3
  } and
  .qualityRpc.resultsByMethod == .qualityRpc.requestsByMethod
' <<<"$probe_payload" >/dev/null 2>&1; then
  echo "Scenario Lab browser assertion failed:" >&2
  failed_assertion_groups=""
  if ! failed_assertion_groups="$(
    jq -c \
    --arg baseline_artifact "$expected_baseline_artifact" \
    --arg baseline_provenance "$expected_baseline_provenance" \
    --argjson identity "$identity_before_payload" '
    {
      basic: {
        status,
        mode,
        route,
        distinctRuns: (.runId != .secondRunId)
      },
      relay: {
        relayCount: .relay.relayCount,
        boundRelayCount: .relay.boundRelayCount,
        iframeCount: .relay.iframeCount,
        scopedIframeCount: .relay.scopedIframeCount,
        runBound: (.relay.runId == .runId),
        targetPortValid: (
          (.relay.targetPort | type) == "number" and
          .relay.targetPort >= 1 and
          .relay.targetPort <= 65535
        ),
        aboutBlank: .relay.aboutBlank,
        childNavigationScrubbed: .relay.childNavigationScrubbed,
        targetFrameBound: .relay.targetFrameBound,
        relayV2Ready: .relay.relayV2Ready,
        relayV2Fenced: .relay.relayV2Fenced,
        mountAuthorized: .relay.mountAuthorized,
        controllerBound: .relay.controllerBound,
        helloAccepted: .relay.helloAccepted,
        relayResultsAccepted: .relay.relayResultsAccepted,
        relayResultCount: .relay.relayResultCount,
        networkTraceComplete: .relay.networkTraceComplete,
        gatewayRequestBound: .relay.gatewayRequestBound,
        gatewayRequestCount: .relay.gatewayRequestCount,
        gatewaySuccessfulResponseCount:
          .relay.gatewaySuccessfulResponseCount,
        directApiRequestCount: .relay.directApiRequestCount,
        gatewayTrafficObserved: .relay.gatewayTrafficObserved,
        gatewayTrafficSucceeded: .relay.gatewayTrafficSucceeded,
        gatewayBound: .relay.gatewayBound,
        gatewayRouted: .relay.gatewayRouted,
        gatewayPortValid: (
          (.relay.gatewayPort | type) == "number" and
          .relay.gatewayPort >= 1 and
          .relay.gatewayPort <= 65535
        )
      },
      targetControl: {
        semanticStates: .targetControl.semanticStates,
        screenshotDigestsValid: (
          (.targetControl.disabledScreenshotDigest | startswith("sha256:")) and
          (.targetControl.enabledScreenshotDigest | startswith("sha256:"))
        ),
        screenshotsDiffer: (
          .targetControl.disabledScreenshotDigest !=
            .targetControl.enabledScreenshotDigest
        ),
        captureErrorCount: (.targetControl.captureErrors | length)
      },
      terminal: {
        state: .terminal.state,
        cleanup: .terminal.cleanup,
        verification: .terminal.verification,
        resultDigestValid: (.terminal.resultDigest | startswith("sha256:")),
        snapshotDigestValid:
          (.terminal.snapshotDigest | startswith("sha256:")),
        contentSetBound: (
          .terminal.contentSetDigest == $identity.contentSet.contentSetDigest
        ),
        catalogBound: (
          .terminal.catalogDigest == $identity.contentSet.catalogDigest
        ),
        labManifestBound: (
          .terminal.scenarioLabManifestDigest ==
            $identity.contentSet.scenarioLabManifestDigest
        )
      },
      evidence: {
        state: .evidence.state,
        freshness: .evidence.freshness,
        digestsValid: ([
          .evidence.resultDigest,
          .evidence.evidenceDigest,
          .evidence.artifactDigest,
          .evidence.provenanceDigest
        ] | all(startswith("sha256:")))
      },
      comparison: {
        kind: .comparison.kind,
        verification: .comparison.verification,
        resultDigestValid:
          (.comparison.resultDigest | startswith("sha256:")),
        comparedPixels: .comparison.comparedPixels,
        changedPixels: .comparison.changedPixels,
        maxChannelDeltaObserved: .comparison.maxChannelDeltaObserved
      },
      captures: {
        decisionDialogKeys: (.captures.decisionDialog | keys),
        decisionDialogWidth: .captures.decisionDialog.width,
        decisionDialogHeight: .captures.decisionDialog.height,
        qualityFinalKeys: (.captures.qualityFinal | keys),
        qualityFinalWidth: .captures.qualityFinal.width,
        qualityFinalHeight: .captures.qualityFinal.height
      },
      quality: {
        states: .quality.states,
        verification: .quality.verification,
        humanDecision: .quality.humanDecision,
        reviewAvailability: .quality.reviewAvailability,
        decisionOperation: .quality.decisionOperation,
        decisionCount: .quality.decisionCount,
        headBound: (
          .quality.headDecisionDigest == .decisions.head.decisionDigest
        ),
        resourceStates: ([.quality.resources[].state] | unique),
        resourceRoles: ([.quality.resources[].role] | sort)
      },
      review: {
        confirmBeforeAuthority: .qualityReview.confirmBeforeAuthority,
        dialogAccessibility: .qualityReview.dialogAccessibility,
        automatedUnchanged: .qualityReview.automatedUnchanged,
        humanTransitions: .qualityReview.humanTransitions,
        digestsValid: ([
          .qualityReview.automatedDigest,
          .qualityReview.qualitySurfaceDigest,
          .qualityReview.reviewSetDigest
        ] | all(startswith("sha256:"))),
        resourceCount: .qualityReview.reviewSet.resourceCount,
        resourceRoles:
          ([.qualityReview.reviewSet.artifacts[].role] | sort),
        provenanceKinds:
          ([.qualityReview.reviewSet.artifacts[].provenanceKind] | sort),
        baselineArtifactBound: (
          ([.qualityReview.reviewSet.artifacts[] |
            select(.role == "comparisonBaseline")][0].artifactDigest) ==
              $baseline_artifact
        ),
        baselineProvenanceBound: (
          ([.qualityReview.reviewSet.artifacts[] |
            select(.role == "comparisonBaseline")][0].provenanceDigest) ==
              $baseline_provenance
        ),
        evidenceArtifactBound: (
          ([.qualityReview.reviewSet.artifacts[] |
            select(.role == "requiredEvidence")][0].artifactDigest) ==
              .evidence.artifactDigest
        ),
        evidenceProvenanceBound: (
          ([.qualityReview.reviewSet.artifacts[] |
            select(.role == "requiredEvidence")][0].provenanceDigest) ==
              .evidence.provenanceDigest
        )
      },
      decisions: {
        approvedDecision: .decisions.approved.decision,
        approvedState: .decisions.approved.state,
        headDecision: .decisions.head.decision,
        headState: .decisions.head.state,
        oldState: .decisions.oldAfterSupersession.state,
        headViewState: .decisions.headView.state,
        supersessionBound: (
          .decisions.head.supersedesDecisionDigest ==
            .decisions.approved.decisionDigest and
          .decisions.oldAfterSupersession.supersededByDecisionDigest ==
            .decisions.head.decisionDigest
        ),
        historyDigestValid:
          (.decisions.historyDigest | startswith("sha256:")),
        roles: [
          .decisions.approved.attribution.role,
          .decisions.head.attribution.role
        ],
        principalStable: (
          .decisions.approved.attribution.principalId ==
            .decisions.head.attribution.principalId
        ),
        authorityStable: (
          .decisions.approved.attribution.authorityId ==
            .decisions.head.attribution.authorityId
        ),
        policyStable: (
          .decisions.approved.attribution.accessPolicyId ==
            .decisions.head.attribution.accessPolicyId
        )
      },
      finalChecks: {
        cancelState: .cancel.state,
        cancelCleanup: .cancel.cleanup,
        unnamedFocusableCount: .semanticHtml.unnamedFocusableCount,
        uniqueTabStops: .keyboard.uniqueTabStops,
        horizontalOverflow: .reflow200Percent.horizontalDocumentOverflow,
        reducedMotion: .reducedMotion.queryMatches,
        accessibilityNodes: .accessibilityNodes,
        severeBrowserLogs: .severeBrowserLogs,
        labRpcRequests: .labRpc.requestsByMethod,
        labRpcBalanced:
          (.labRpc.resultsByMethod == .labRpc.requestsByMethod),
        labRpcFailureCount: (.labRpc.failures | length),
        qualityRpcRequests: .qualityRpc.requestsByMethod,
        qualityRpcBalanced:
          (.qualityRpc.resultsByMethod == .qualityRpc.requestsByMethod),
        qualityRpcFailureCount: (.qualityRpc.failures | length)
      }
    }
  ' 2>/dev/null <<<"$probe_payload" |
    jq -c '[
      if (
        .basic.status == "passed" and
        .basic.mode == "scenario-lab-audit" and
        .basic.route ==
          "/lab/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab" and
        .basic.distinctRuns == true
      ) then empty else "basic" end,
      if (
        .relay.relayCount == 1 and
        .relay.boundRelayCount == 1 and
        .relay.iframeCount == 1 and
        .relay.scopedIframeCount == 1 and
        .relay.runBound == true and
        .relay.targetPortValid == true and
        .relay.aboutBlank == true and
        .relay.childNavigationScrubbed == true and
        .relay.targetFrameBound == true and
        .relay.relayV2Ready == true and
        .relay.relayV2Fenced == true and
        .relay.mountAuthorized == true and
        .relay.controllerBound == true and
        .relay.helloAccepted == true and
        .relay.relayResultsAccepted == true and
        .relay.relayResultCount > 0 and
        .relay.networkTraceComplete == true and
        .relay.gatewayRequestBound == true and
        .relay.gatewayRequestCount == 1 and
        .relay.gatewaySuccessfulResponseCount == 1 and
        .relay.directApiRequestCount == 0 and
        .relay.gatewayTrafficObserved == true and
        .relay.gatewayTrafficSucceeded == true and
        .relay.gatewayBound == true and
        .relay.gatewayRouted == true and
        .relay.gatewayPortValid == true
      ) then empty else "relay" end,
      if (
        .targetControl.semanticStates == ["disabled", "enabled"] and
        .targetControl.screenshotDigestsValid == true and
        .targetControl.screenshotsDiffer == true and
        .targetControl.captureErrorCount == 0
      ) then empty else "targetControl" end,
      if (
        .terminal.state == "succeeded" and
        .terminal.cleanup == "succeeded" and
        .terminal.verification == "passed" and
        .terminal.resultDigestValid == true and
        .terminal.snapshotDigestValid == true and
        .terminal.contentSetBound == true and
        .terminal.catalogBound == true and
        .terminal.labManifestBound == true
      ) then empty else "terminal" end,
      if (
        .evidence.state == "collected" and
        .evidence.freshness == "fresh" and
        .evidence.digestsValid == true
      ) then empty else "evidence" end,
      if (
        .comparison.kind == "visual" and
        .comparison.verification == "passed" and
        .comparison.resultDigestValid == true and
        .comparison.comparedPixels > 0 and
        .comparison.changedPixels >= 0 and
        .comparison.changedPixels <= .comparison.comparedPixels and
        (.comparison.changedPixels / .comparison.comparedPixels) <= 0.005 and
        .comparison.maxChannelDeltaObserved >= 0 and
        .comparison.maxChannelDeltaObserved <= 255
      ) then empty else "comparison" end,
      if (
        .captures.decisionDialogKeys == ["digest", "height", "width"] and
        .captures.decisionDialogWidth >= 1000 and
        .captures.decisionDialogHeight >= 700 and
        .captures.qualityFinalKeys == ["digest", "height", "width"] and
        .captures.qualityFinalWidth >= 1000 and
        .captures.qualityFinalHeight >= 700
      ) then empty else "captures" end,
      if (
        (.quality.states | index("passing")) != null and
        .quality.verification == "passed" and
        .quality.humanDecision == "rejected" and
        .quality.reviewAvailability == "available" and
        .quality.decisionOperation == "ready" and
        .quality.decisionCount == 2 and
        .quality.headBound == true and
        .quality.resourceStates == ["rendered"] and
        .quality.resourceRoles == [
          "comparisonBaseline",
          "comparisonCandidate",
          "requiredEvidence"
        ]
      ) then empty else "quality" end,
      if (
        .review.confirmBeforeAuthority == {
          approve: true,
          supersedingReject: true
        } and
        .review.dialogAccessibility.nativeModal == true and
        .review.dialogAccessibility.approveInitialFocus == "confirm" and
        .review.dialogAccessibility.supersedeInitialFocus == "confirm" and
        .review.dialogAccessibility.approveEscapeClosedWithoutRpc == true and
        .review.dialogAccessibility.approveFocusReturnedToOpener == true and
        .review.dialogAccessibility.supersedeEscapeClosedWithoutRpc == true and
        .review.dialogAccessibility.supersedeFocusReturnedToOpener == true and
        .review.automatedUnchanged == true and
        .review.humanTransitions == ["unreviewed", "approved", "rejected"] and
        .review.digestsValid == true and
        .review.resourceCount == 3 and
        .review.resourceRoles == [
          "comparisonBaseline",
          "comparisonCandidate",
          "requiredEvidence"
        ] and
        .review.provenanceKinds == [
          "appAdapterCaptureReceipt",
          "appAdapterCaptureReceipt",
          "supplementalArtifactImport"
        ] and
        .review.baselineArtifactBound == true and
        .review.baselineProvenanceBound == true and
        .review.evidenceArtifactBound == true and
        .review.evidenceProvenanceBound == true
      ) then empty else "review" end,
      if (
        .decisions.approvedDecision == "approved" and
        .decisions.approvedState == "approved" and
        .decisions.headDecision == "rejected" and
        .decisions.headState == "rejected" and
        .decisions.oldState == "superseded" and
        .decisions.headViewState == "rejected" and
        .decisions.supersessionBound == true and
        .decisions.historyDigestValid == true and
        .decisions.roles == ["reviewer", "reviewer"] and
        .decisions.principalStable == true and
        .decisions.authorityStable == true and
        .decisions.policyStable == true
      ) then empty else "decisions" end,
      if (
        .finalChecks.cancelState == "cancelled" and
        (
          .finalChecks.cancelCleanup == "notRequired" or
          .finalChecks.cancelCleanup == "succeeded"
        )
      ) then empty else "cancel" end,
      if (
        .finalChecks.unnamedFocusableCount == 0 and
        .finalChecks.uniqueTabStops >= 5 and
        .finalChecks.horizontalOverflow == false and
        .finalChecks.reducedMotion == true and
        .finalChecks.accessibilityNodes >= 20 and
        .finalChecks.severeBrowserLogs == 0
      ) then empty else "accessibility" end,
      if (
        (.finalChecks.labRpcRequests | type) == "object" and
        (.finalChecks.labRpcRequests | length) > 0 and
        .finalChecks.labRpcBalanced == true and
        .finalChecks.labRpcFailureCount == 0
      ) then empty else "labRpc" end,
      if (
        .finalChecks.qualityRpcRequests == {
          "quality.describe": 3,
          "quality.open": 3,
          "quality.decision.grant": 2,
          "quality.decision.append": 2,
          "quality.decision.get": 3
        } and
        .finalChecks.qualityRpcBalanced == true and
        .finalChecks.qualityRpcFailureCount == 0
      ) then empty else "qualityRpc" end
    ]' 2>/dev/null
  )"; then
    failed_assertion_groups='["diagnostic-evaluation"]'
  fi
  if ! jq -e '
    type == "array" and
    length > 0 and
    all(
      .[];
      . as $label |
      [
        "basic",
        "relay",
        "targetControl",
        "terminal",
        "evidence",
        "comparison",
        "captures",
        "quality",
        "review",
        "decisions",
        "cancel",
        "accessibility",
        "labRpc",
        "qualityRpc",
        "diagnostic-evaluation"
      ] |
      index($label) != null
    )
  ' >/dev/null 2>&1 <<<"$failed_assertion_groups"; then
    failed_assertion_groups='["unclassified-assertion"]'
  fi
  printf '%s\n' "$failed_assertion_groups" >&2
  echo "Raw browser payload suppressed." >&2
  exit 1
fi

verify_visual_capture \
  "$dialog_capture_path" \
  "$(jq -r '.captures.decisionDialog.digest' <<<"$probe_payload")" \
  "Scenario Quality decision dialog"
verify_visual_capture \
  "$quality_capture_path" \
  "$(jq -r '.captures.qualityFinal.digest' <<<"$probe_payload")" \
  "Scenario Quality final view"

artifact_digest="$(jq -r '.evidence.artifactDigest' <<<"$probe_payload")"
verify_cas_digest "$artifact_digest" "Scenario Lab Evidence artifact"
while IFS= read -r review_digest; do
  verify_cas_digest "$review_digest" "Scenario Quality review resource"
done < <(
  jq -r '
    .qualityReview.reviewSet.artifacts[] |
    .artifactDigest, .provenanceDigest
  ' <<<"$probe_payload" | sort -u
)

run_journal="$state_root/scenario-lab/runs/scenario-lab-runs.journal.json"
decision_journal="$state_root/scenario-quality/human-decisions.journal.json"
if [[ ! -f "$run_journal" || -L "$run_journal" ||
  ! -f "$decision_journal" || -L "$decision_journal" ]]; then
  echo "Scenario Lab or Quality decision journal is missing." >&2
  exit 1
fi
if ! jq -e --argjson browser "$probe_payload" '
  .schemaVersion == 1 and
  .kind == "ScenarioLabRunStoreJournal" and
  .entryCount == (.entries | length) and
  (.headDigest | startswith("sha256:")) and
  (.digest | startswith("sha256:")) and
  ([.entries[].runId] | unique | sort) ==
    ([$browser.runId, $browser.secondRunId] | sort) and
  ([.entries[] |
    select(.type == "result" and .runId == $browser.runId) |
    .payload.result.finalSnapshot.state] == ["succeeded"]) and
  ([.entries[] |
    select(.type == "result" and .runId == $browser.secondRunId) |
    .payload.result.finalSnapshot.state] == ["cancelled"])
' "$run_journal" >/dev/null; then
  echo "Scenario Lab run journal is not bound to both terminal runs." >&2
  exit 1
fi
if ! jq -e --argjson browser "$probe_payload" '
  .schemaVersion == 1 and
  .kind == "ScenarioQualityDecisionJournal" and
  (.entries | length) == 4 and
  ([.entries[].type] == ["grant", "append", "grant", "append"]) and
  ([.entries[].request.runId] | unique) == [$browser.runId] and
  ([.entries[].request.expectedRunResultDigest] | unique) ==
    [$browser.terminal.resultDigest] and
  .entries[0].request.decision == "approved" and
  .entries[0].request.expectedPreviousDecisionDigest == null and
  .entries[1].request.decision == "approved" and
  .entries[1].request.expectedPreviousDecisionDigest == null and
  .entries[1].result.record.digest ==
    $browser.decisions.approved.decisionDigest and
  .entries[1].result.record.supersedesDecisionDigest == null and
  .entries[1].result.attribution.role == "reviewer" and
  .entries[2].request.decision == "rejected" and
  .entries[2].request.expectedPreviousDecisionDigest ==
    $browser.decisions.approved.decisionDigest and
  .entries[3].request.decision == "rejected" and
  .entries[3].request.expectedPreviousDecisionDigest ==
    $browser.decisions.approved.decisionDigest and
  .entries[3].result.record.digest ==
    $browser.decisions.head.decisionDigest and
  .entries[3].result.record.supersedesDecisionDigest ==
    $browser.decisions.approved.decisionDigest and
  .entries[3].result.attribution.role == "reviewer"
' "$decision_journal" >/dev/null; then
  echo "Scenario Quality decision journal is not the exact two-decision chain." >&2
  exit 1
fi
run_journal_digest="$(sha256sum "$run_journal" | awk '{print $1}')"
decision_journal_digest="$(sha256sum "$decision_journal" | awk '{print $1}')"

stop_process "$dev_pid"
dev_pid=""
for port in 7367 7368 "${target_port:-}"; do
  if [[ -n "$port" ]]; then
    wait_for_port_free "$port"
  fi
done

restart_dev_log="$(mktemp \
  "${TMPDIR:-/tmp}/scenario-lab-dev-restart.XXXXXX.jsonl")"
echo "[scenario-lab-vertical] restarting Host and Studio over isolated state" >&2
start_full_local_dev "$restart_dev_log"

recovery_expectation="$(jq -c '
  {
    runId,
    runResultDigest: .terminal.resultDigest,
    snapshotDigest: .terminal.snapshotDigest,
    evidenceResultDigest: .evidence.resultDigest,
    evidenceDigest: .evidence.evidenceDigest,
    artifactDigest: .evidence.artifactDigest,
    provenanceDigest: .evidence.provenanceDigest,
    comparisonResultDigest: .comparison.resultDigest,
    automatedDigest: .qualityReview.automatedDigest,
    qualitySurfaceDigest: .qualityReview.qualitySurfaceDigest,
    reviewSetDigest: .qualityReview.reviewSetDigest,
    approvedDecisionDigest: .decisions.approved.decisionDigest,
    approvedRecordId: .decisions.approved.recordId,
    headDecisionDigest: .decisions.head.decisionDigest,
    headRecordId: .decisions.head.recordId,
    historyDigest: .decisions.historyDigest,
    requirementId: .decisions.head.attribution.requirementId,
    policyId: .decisions.head.attribution.accessPolicyId
  }
' <<<"$probe_payload")"
run_id="$(jq -r '.runId' <<<"$probe_payload")"
encoded_run_id="$(jq -nr --arg value "$run_id" '$value | @uri')"
recovery_probe_log="$(mktemp \
  "${TMPDIR:-/tmp}/scenario-lab-recovery.XXXXXX.jsonl")"
echo "[scenario-lab-vertical] reloading Quality in a new browser probe" >&2
if ! recovery_payload="$(
  "${toolchain[@]}" dart run "$repo_dir/tools/probes/studio_jaspr_cdp_probe.dart" \
    "http://127.0.0.1:$chrome_debug_port" \
    "http://127.0.0.1:7368/quality/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab?runId=$encoded_run_id" \
    "--scenario-quality-reload-audit=$recovery_expectation" \
    2>"$recovery_probe_log"
)"; then
  echo "Scenario Quality reload proof stopped at a fail-closed boundary." >&2
  exit 1
fi
assert_payload_sanitized "$recovery_payload" "Scenario Quality reload proof"

if ! jq -e --argjson initial "$probe_payload" '
  .status == "passed" and
  .mode == "scenario-quality-reload-audit" and
  .route == "/quality/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab" and
  .runId == $initial.runId and
  .terminal.state == "succeeded" and
  .terminal.resultDigest == $initial.terminal.resultDigest and
  .terminal.snapshotDigest == $initial.terminal.snapshotDigest and
  .quality.humanDecision == "rejected" and
  .quality.decisionCount == 2 and
  .quality.headDecisionDigest == $initial.decisions.head.decisionDigest and
  .quality.decisionRequirement ==
    $initial.decisions.head.attribution.requirementId and
  .quality.decisionPolicy ==
    $initial.decisions.head.attribution.accessPolicyId and
  .qualityReview.automatedDigest ==
    $initial.qualityReview.automatedDigest and
  .qualityReview.qualitySurfaceDigest ==
    $initial.qualityReview.qualitySurfaceDigest and
  .qualityReview.reviewSetDigest ==
    $initial.qualityReview.reviewSetDigest and
  .qualityReview.reviewSet == $initial.qualityReview.reviewSet and
  .decisions.historyDigest == $initial.decisions.historyDigest and
  .decisions.headView == $initial.decisions.headView and
  .decisions.oldAfterSupersession ==
    $initial.decisions.oldAfterSupersession and
  .reattach.newProbeExplicit == true and
  .reattach.postReloadExplicit == true and
  (.reattach.newProbeSurfaceDigest | startswith("sha256:")) and
  .reattach.postReloadSurfaceDigest ==
    .reattach.newProbeSurfaceDigest and
  .reattach.newProbeLabRpc.failures == [] and
  .reattach.newProbeLabRpc.resultsByMethod ==
    .reattach.newProbeLabRpc.requestsByMethod and
  (.reattach.newProbeLabRpc.requestsByMethod | keys) ==
    ["lab.reattach"] and
  .reattach.newProbeLabRpc.requestsByMethod["lab.reattach"] >= 1 and
  .reattach.newProbeLabRpc.requestsByMethod["lab.reattach"] <= 20 and
  .reattach.newProbeLabRpc.requestsByMethod == .labRpc.requestsByMethod and
  .reattach.newProbeQualityRpc.failures == [] and
  .reattach.newProbeQualityRpc.requestsByMethod == {
    "quality.describe": 1,
    "quality.open": 1,
    "quality.decision.grant": 0,
    "quality.decision.append": 0,
    "quality.decision.get": 2
  } and
  .reattach.newProbeQualityRpc.resultsByMethod ==
    .reattach.newProbeQualityRpc.requestsByMethod and
  .semanticHtml.unnamedFocusableCount == 0 and
  .keyboard.uniqueTabStops >= 5 and
  .reflow200Percent.horizontalDocumentOverflow == false and
  .reducedMotion.queryMatches == true and
  .accessibilityNodes >= 20 and
  .severeBrowserLogs == 0 and
  (.labRpc.failures | length) == 0 and
  .labRpc.resultsByMethod == .labRpc.requestsByMethod and
  (.labRpc.requestsByMethod | keys) == ["lab.reattach"] and
  .labRpc.requestsByMethod["lab.reattach"] >= 1 and
  .labRpc.requestsByMethod["lab.reattach"] <= 20 and
  .qualityRpc.failures == [] and
  .qualityRpc.requestsByMethod == {
    "quality.describe": 1,
    "quality.open": 1,
    "quality.decision.grant": 0,
    "quality.decision.append": 0,
    "quality.decision.get": 2
  } and
  .qualityRpc.resultsByMethod == .qualityRpc.requestsByMethod
' <<<"$recovery_payload" >/dev/null; then
  echo "Scenario Quality reload assertion failed:" >&2
  echo "Raw recovery payload suppressed." >&2
  exit 1
fi

if [[ "$(sha256sum "$run_journal" | awk '{print $1}')" != \
    "$run_journal_digest" ||
  "$(sha256sum "$decision_journal" | awk '{print $1}')" != \
    "$decision_journal_digest" ]]; then
  echo "Scenario Lab or Quality journal changed across read-only reload." >&2
  exit 1
fi
while IFS= read -r review_digest; do
  verify_cas_digest "$review_digest" "Reloaded Quality review resource"
done < <(
  jq -r '
    .qualityReview.reviewSet.artifacts[] |
    .artifactDigest, .provenanceDigest
  ' <<<"$recovery_payload" | sort -u
)

echo "[scenario-lab-vertical] applying exact temporary mutations" >&2
apply_ep4_mutations
defer_termination_signals
target_build_temp="$(mktemp -d \
  "$target_build_root/.scenario-lab-web-changed.XXXXXX")"
resume_termination_signals
echo "[scenario-lab-vertical] building changed Target outside build/web" >&2
(
  cd "$sample_dir"
  "${toolchain[@]}" flutter build web \
    --release \
    --target=tool/target_main.dart \
    --dart-define=EXAMPLE_API_URL=http://127.0.0.1:8181 \
    --dart-define=TARGET_CONTROLLER_ORIGIN=http://127.0.0.1:7368 \
    --output="$target_build_temp"
)
if [[ "$(rg -o -F '0xFFFF0000' "$app_source" | wc -l)" -ne 1 ||
  "$(rg -o -F 'zoom: 0.84' "$layout_source" | wc -l)" -ne 1 ]]; then
  echo "Scenario Lab source bytes drifted while building the changed Target." >&2
  exit 1
fi
wait_for_port_free "$target_port"
install_target_build "$target_build_temp"
target_build_temp=""
defer_termination_signals
app_source_restore_failed=0
if ! atomic_restore_file \
  "$source_backup_dir/app_factory.dart" \
  "$app_source" \
  "$app_source_before_digest"; then
  app_source_restore_failed=1
fi
resume_termination_signals
if [[ "$app_source_restore_failed" -ne 0 ]]; then
  echo "Scenario Lab app source could not be restored before workspace refresh." >&2
  exit 1
fi
if [[ "$(rg -o -F '0xFF6750A4' "$app_source" | wc -l)" -ne 1 ||
  "$(rg -o -F '0xFFFF0000' "$app_source" | wc -l)" -ne 0 ||
  "$(rg -o -F 'zoom: 0.84' "$layout_source" | wc -l)" -ne 1 ]]; then
  echo "Scenario Lab source staging drifted before workspace refresh." >&2
  exit 1
fi

identity_after_log="$(mktemp \
  "${TMPDIR:-/tmp}/scenario-lab-identity-after.XXXXXX.jsonl")"
echo "[scenario-lab-vertical] refreshing Host over changed layout with changed Target installed" >&2
if ! identity_after_payload="$(
  "${toolchain[@]}" dart run "$repo_dir/tools/probes/studio_rpc_probe.dart" \
    "http://127.0.0.1:7368" \
    --refresh \
    2>"$identity_after_log"
)"; then
  echo "Post-change content identity probe failed." >&2
  exit 1
fi
assert_payload_sanitized \
  "$identity_after_payload" \
  "Post-change content identity proof"
if ! jq -e --argjson before "$identity_before_payload" '
  .contentSet.describeOpenIdentityMatches == true and
  .contentSet.workspaceMatches == true and
  .contentSet.experienceMatches == true and
  .contentSet.revision > $before.contentSet.revision and
  .contentSet.contentSetDigest != $before.contentSet.contentSetDigest and
  .contentSet.experienceTopologyBundleDigest !=
    $before.contentSet.experienceTopologyBundleDigest and
  .experience.bundleDigest != $before.experience.bundleDigest and
  .experience.topologyDigest == $before.experience.topologyDigest and
  .experience.layoutDigests != $before.experience.layoutDigests and
  .contentSet.catalogDigest == $before.contentSet.catalogDigest and
  .contentSet.scenarioFacetManifestDigest ==
    $before.contentSet.scenarioFacetManifestDigest and
  .contentSet.scenarioLabManifestDigest ==
    $before.contentSet.scenarioLabManifestDigest and
  .contentSet.workspaceSnapshotDigest == .snapshotDigest and
  .contentSet.workspaceContentDigest == .workspaceContentDigest and
  .workspaceContentDigest == $before.workspaceContentDigest and
  .refresh.changed == false and
  .contentSet.resourcePurposes == (
    [
      "workspace-snapshot",
      "experience-topology-bundle",
      "scenario-facet-manifest",
      "scenario-lab-manifest"
    ] +
    (if .contentSet.motionManifestDigest == null
     then [] else ["motion-manifest"] end)
  )
' <<<"$identity_after_payload" >/dev/null 2>&1; then
  echo "Post-change content identity/current workspace proof failed." >&2
  identity_failure_labels=""
  if ! identity_failure_labels="$(
    jq -c --argjson before "$identity_before_payload" '
      def failed($label; condition):
        if (try (condition == true) catch false)
        then empty
        else $label
        end;
      [
        failed(
          "describe-open";
          .contentSet.describeOpenIdentityMatches == true
        ),
        failed(
          "workspace-binding";
          .contentSet.workspaceMatches == true
        ),
        failed(
          "experience-binding";
          .contentSet.experienceMatches == true
        ),
        failed(
          "revision";
          .contentSet.revision > $before.contentSet.revision
        ),
        failed(
          "content-set";
          .contentSet.contentSetDigest !=
            $before.contentSet.contentSetDigest
        ),
        failed(
          "topology-bundle";
          .contentSet.experienceTopologyBundleDigest !=
            $before.contentSet.experienceTopologyBundleDigest
        ),
        failed(
          "experience-bundle";
          .experience.bundleDigest != $before.experience.bundleDigest
        ),
        failed(
          "topology-stable";
          .experience.topologyDigest == $before.experience.topologyDigest
        ),
        failed(
          "layout-changed";
          .experience.layoutDigests != $before.experience.layoutDigests
        ),
        failed(
          "catalog-stable";
          .contentSet.catalogDigest == $before.contentSet.catalogDigest
        ),
        failed(
          "facets-stable";
          .contentSet.scenarioFacetManifestDigest ==
            $before.contentSet.scenarioFacetManifestDigest
        ),
        failed(
          "lab-stable";
          .contentSet.scenarioLabManifestDigest ==
            $before.contentSet.scenarioLabManifestDigest
        ),
        failed(
          "catalog-binding";
          .contentSet.catalogDigest == .catalogDigest
        ),
        failed(
          "snapshot-binding";
          .contentSet.workspaceSnapshotDigest == .snapshotDigest
        ),
        failed(
          "workspace-content-binding";
          .contentSet.workspaceContentDigest == .workspaceContentDigest
        ),
        failed(
          "workspace-content-stable";
          .workspaceContentDigest == $before.workspaceContentDigest
        ),
        failed(
          "topology-binding";
          .contentSet.experienceTopologyBundleDigest ==
            .experience.bundleDigest
        ),
        failed(
          "facets-binding";
          (.contentSet.scenarioFacetManifestDigest | startswith("sha256:"))
        ),
        failed(
          "refresh-catalog-stable";
          .refresh.changed == false
        ),
        failed(
          "resource-purposes";
          .contentSet.resourcePurposes == (
            [
              "workspace-snapshot",
              "experience-topology-bundle",
              "scenario-facet-manifest",
              "scenario-lab-manifest"
            ] +
            (if .contentSet.motionManifestDigest == null
             then [] else ["motion-manifest"] end)
          )
        )
      ] | if length == 0 then ["unclassified-identity"] else . end
    ' 2>/dev/null <<<"$identity_after_payload"
  )"; then
    identity_failure_labels='["diagnostic-evaluation"]'
  fi
  if ! jq -e '
    type == "array" and
    length > 0 and
    all(
      .[];
      . as $label |
      [
        "describe-open",
        "workspace-binding",
        "experience-binding",
        "revision",
        "content-set",
        "topology-bundle",
        "experience-bundle",
        "topology-stable",
        "layout-changed",
        "catalog-stable",
        "facets-stable",
        "lab-stable",
        "catalog-binding",
        "snapshot-binding",
        "workspace-content-binding",
        "workspace-content-stable",
        "topology-binding",
        "facets-binding",
        "refresh-catalog-stable",
        "resource-purposes",
        "unclassified-identity",
        "diagnostic-evaluation"
      ] |
      index($label) != null
    )
  ' >/dev/null 2>&1 <<<"$identity_failure_labels"; then
    identity_failure_labels='["unclassified-identity"]'
  fi
  printf '%s\n' "$identity_failure_labels" >&2
  exit 1
fi

currentness_expectation="$(jq -nc \
  --argjson old "$probe_payload" \
  --argjson current "$identity_after_payload" '
  {
    oldRunId: $old.runId,
    oldRunResultDigest: $old.terminal.resultDigest,
    oldSnapshotDigest: $old.terminal.snapshotDigest,
    oldContentSetDigest: $old.terminal.contentSetDigest,
    oldCatalogDigest: $old.terminal.catalogDigest,
    oldScenarioLabManifestDigest: $old.terminal.scenarioLabManifestDigest,
    oldEvidenceResultDigest: $old.evidence.resultDigest,
    oldEvidenceDigest: $old.evidence.evidenceDigest,
    oldArtifactDigest: $old.evidence.artifactDigest,
    oldProvenanceDigest: $old.evidence.provenanceDigest,
    oldComparisonResultDigest: $old.comparison.resultDigest,
    oldComparedPixels: $old.comparison.comparedPixels,
    oldChangedPixels: $old.comparison.changedPixels,
    oldMaxChannelDeltaObserved: $old.comparison.maxChannelDeltaObserved,
    currentContentSetDigest: $current.contentSet.contentSetDigest,
    currentCatalogDigest: $current.contentSet.catalogDigest,
    currentScenarioLabManifestDigest:
      $current.contentSet.scenarioLabManifestDigest
  }
')"
run_id="$(jq -r '.runId' <<<"$probe_payload")"
encoded_run_id="$(jq -nr --arg value "$run_id" '$value | @uri')"
currentness_probe_log="$(mktemp \
  "${TMPDIR:-/tmp}/scenario-lab-currentness.XXXXXX.jsonl")"
echo "[scenario-lab-vertical] proving stale history and changed recollection" >&2
if ! currentness_payload="$(
  "${toolchain[@]}" dart run "$repo_dir/tools/probes/studio_jaspr_cdp_probe.dart" \
    "http://127.0.0.1:$chrome_debug_port" \
    "http://127.0.0.1:7368/quality/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab?runId=$encoded_run_id" \
    "--scenario-currentness-audit=$currentness_expectation" \
    2>"$currentness_probe_log"
)"; then
  blocked_payload="$(jq -c '
    select(.status == "blocked" and .mode == "scenario-currentness-audit")
  ' "$currentness_probe_log" 2>/dev/null | tail -n 1 || true)"
  if [[ -n "$blocked_payload" ]]; then
    record_relay_ports_from_payload "$blocked_payload"
  fi
  echo "Scenario currentness browser proof stopped at a fail-closed boundary." >&2
  exit 1
fi
assert_payload_sanitized \
  "$currentness_payload" \
  "Scenario currentness browser proof"
record_target_port "$(jq -r '.current.relay.targetPort' \
  <<<"$currentness_payload")"
record_gateway_port "$(jq -r '.current.relay.gatewayPort' \
  <<<"$currentness_payload")"
if ! jq -e \
  --argjson old "$probe_payload" \
  --argjson identity "$identity_after_payload" '
  .status == "passed" and
  .mode == "scenario-currentness-audit" and
  .historical.runId == $old.runId and
  .historical.terminal.state == "succeeded" and
  .historical.terminal.cleanup == "succeeded" and
  .historical.terminal.resultDigest == $old.terminal.resultDigest and
  .historical.terminal.snapshotDigest == $old.terminal.snapshotDigest and
  .historical.terminal.contentSetDigest == $old.terminal.contentSetDigest and
  .historical.terminal.catalogDigest == $old.terminal.catalogDigest and
  .historical.terminal.scenarioLabManifestDigest ==
    $old.terminal.scenarioLabManifestDigest and
  .historical.evidence.state == "collected" and
  .historical.evidence.freshness == "fresh" and
  .historical.evidence.resultDigest == $old.evidence.resultDigest and
  .historical.evidence.evidenceDigest == $old.evidence.evidenceDigest and
  .historical.evidence.artifactDigest == $old.evidence.artifactDigest and
  .historical.evidence.provenanceDigest == $old.evidence.provenanceDigest and
  .historical.evidence.immutable == true and
  .historical.comparison.kind == "visual" and
  .historical.comparison.verification == "passed" and
  .historical.comparison.resultDigest == $old.comparison.resultDigest and
  .historical.comparison.comparedPixels == $old.comparison.comparedPixels and
  .historical.comparison.changedPixels == $old.comparison.changedPixels and
  .historical.comparison.maxChannelDeltaObserved ==
    $old.comparison.maxChannelDeltaObserved and
  .historical.quality.contentCurrentness == "stale" and
  (.historical.quality.states | index("stale")) != null and
  (.historical.quality.states | index("passing")) == null and
  .historical.quality.evidenceFreshness == "fresh" and
  .historical.quality.reviewAvailability == "unavailable" and
  .historical.reviewUnavailable == true and
  .historical.recollect == {
    linkCount: 1,
    path: "/lab/scenarios/dashboard-ready/scripts/exercise-dashboard-ready-lab",
    hasRunId: false,
    destinationSearch: ""
  } and
  .current.runId != $old.runId and
  .current.relay.runId == .current.runId and
  .current.relay.relayCount == 1 and
  .current.relay.boundRelayCount == 1 and
  .current.relay.iframeCount == 1 and
  .current.relay.scopedIframeCount == 1 and
  (.current.relay.targetPort | type) == "number" and
  .current.relay.targetPort >= 1 and
  .current.relay.targetPort <= 65535 and
  .current.relay.aboutBlank == true and
  .current.relay.childNavigationScrubbed == true and
  .current.relay.targetFrameBound == true and
  .current.relay.relayV2Ready == true and
  .current.relay.relayV2Fenced == true and
  .current.relay.mountAuthorized == true and
  .current.relay.controllerBound == true and
  .current.relay.helloAccepted == true and
  .current.relay.relayResultsAccepted == true and
  (.current.relay.relayResultCount | type) == "number" and
  .current.relay.relayResultCount > 0 and
  .current.relay.networkTraceComplete == true and
  .current.relay.gatewayRequestBound == true and
  .current.relay.gatewayRequestCount == 1 and
  .current.relay.gatewaySuccessfulResponseCount == 1 and
  .current.relay.directApiRequestCount == 0 and
  .current.relay.gatewayTrafficObserved == true and
  .current.relay.gatewayTrafficSucceeded == true and
  .current.relay.gatewayBound == true and
  .current.relay.gatewayRouted == true and
  (.current.relay.gatewayPort | type) == "number" and
  .current.relay.gatewayPort >= 1 and
  .current.relay.gatewayPort <= 65535 and
  .current.terminal.state == "failed" and
  .current.terminal.terminalCause == "acceptanceFailed" and
  .current.terminal.cleanup == "succeeded" and
  .current.terminal.verification == "passed" and
  .current.terminal.contentSetDigest ==
    $identity.contentSet.contentSetDigest and
  .current.terminal.catalogDigest == $identity.contentSet.catalogDigest and
  .current.terminal.scenarioLabManifestDigest ==
    $identity.contentSet.scenarioLabManifestDigest and
  .current.terminal.identityMatchesPostRefresh == true and
  .current.evidence.state == "collected" and
  .current.evidence.freshness == "fresh" and
  .current.evidence.artifactDigest != $old.evidence.artifactDigest and
  .current.comparison.kind == "visual" and
  .current.comparison.verification == "failed" and
  .current.comparison.comparedPixels > 0 and
  .current.comparison.changedPixels > 0 and
  .current.comparison.changedPixelRatio > 0.005 and
  .current.comparison.maxChannelDeltaObserved > 8 and
  .current.quality.contentCurrentness == "current" and
  .current.quality.verification == "passed" and
  (.current.quality.states | index("changed")) != null and
  (.current.quality.states | index("failing")) != null and
  (.current.quality.states | index("stale")) == null and
  (.current.quality.states | index("passing")) == null and
  .current.quality.evidenceState == "collected" and
  .current.quality.evidenceFreshness == "fresh" and
  .current.quality.comparisonState == "failed" and
  .severeBrowserLogs == 0
' <<<"$currentness_payload" >/dev/null; then
  echo "Scenario currentness browser assertion failed." >&2
  exit 1
fi
verify_cas_digest \
  "$(jq -r '.historical.evidence.artifactDigest' <<<"$currentness_payload")" \
  "Historical immutable Evidence artifact"
verify_cas_digest \
  "$(jq -r '.current.evidence.artifactDigest' <<<"$currentness_payload")" \
  "Current recollected Evidence artifact"

stop_process "$dev_pid"
dev_pid=""
stop_process "$api_pid"
api_pid=""
stop_process "$chrome_pid"
chrome_pid=""
for port in 7367 7368 8181 "$chrome_debug_port" "$target_port" \
  "${target_ports[@]}" \
  "${gateway_ports[@]}"; do
  wait_for_port_free "$port"
done

if printf '%s\n%s\n%s\n%s\n%s\n' \
  "$probe_payload" \
  "$recovery_payload" \
  "$identity_before_payload" \
  "$identity_after_payload" \
  "$currentness_payload" |
  rg --pcre2 "$sensitive_pattern" >/dev/null; then
  echo "Browser proof retained forbidden authority or resource material." >&2
  exit 1
fi
if rg --pcre2 "$sensitive_pattern" "$api_log" "$dev_log" \
  "$restart_dev_log" "$probe_log" "$recovery_probe_log" \
  "$identity_before_log" "$identity_after_log" \
  "$currentness_probe_log" >/dev/null; then
  echo "Scenario Lab gate logs retained forbidden authority or resource material." >&2
  exit 1
fi
if rg -n 'Unhandled exception|Application method failed|FATAL' \
  "$api_log" "$dev_log" "$restart_dev_log" "$probe_log" \
  "$recovery_probe_log" \
  "$identity_before_log" "$identity_after_log" \
  "$currentness_probe_log" >/dev/null; then
  echo "Scenario Lab services emitted an unexpected severe log." >&2
  exit 1
fi

restore_source_bytes
restore_target_build
restore_studio_build
restore_workspace_state

if [[ -n "$chrome_profile" && -d "$chrome_profile" ]]; then
  delete_known_tree "$chrome_profile"
fi
chrome_profile=""
if [[ "$capture_dir_owned" -eq 1 && -n "$capture_dir" &&
  -d "$capture_dir" ]]; then
  delete_known_tree "$capture_dir"
  capture_dir_owned=0
  capture_targets_armed=0
  capture_disposition="temporary-and-removed"
fi
for log_path in "$currentness_probe_log" "$identity_after_log" \
  "$identity_before_log" "$recovery_probe_log" "$probe_log" \
  "$restart_dev_log" "$dev_log" "$api_log"; do
  if [[ -n "$log_path" && -f "$log_path" ]]; then
    rm -f -- "$log_path"
  fi
done

if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo_dir" diff --check -- tools/probes/studio_rpc_probe.dart \
    tools/probes/studio_jaspr_cdp_probe.dart \
    tools/verify/verify_scenario_lab_vertical.sh
fi

public_proof="$(jq -nc \
  --argjson browser "$probe_payload" \
  --argjson recovery "$recovery_payload" \
  --argjson identityBefore "$identity_before_payload" \
  --argjson identityAfter "$identity_after_payload" \
  --argjson currentness "$currentness_payload" '
  def quality_rpc:
    {
      requestsByMethod: {
        "quality.describe":
          .requestsByMethod["quality.describe"],
        "quality.open":
          .requestsByMethod["quality.open"],
        "quality.decision.grant":
          .requestsByMethod["quality.decision.grant"],
        "quality.decision.append":
          .requestsByMethod["quality.decision.append"],
        "quality.decision.get":
          .requestsByMethod["quality.decision.get"]
      },
      resultsByMethod: {
        "quality.describe":
          .resultsByMethod["quality.describe"],
        "quality.open":
          .resultsByMethod["quality.open"],
        "quality.decision.grant":
          .resultsByMethod["quality.decision.grant"],
        "quality.decision.append":
          .resultsByMethod["quality.decision.append"],
        "quality.decision.get":
          .resultsByMethod["quality.decision.get"]
      },
      failureCount: (.failures | length)
    };
  def quality_surface:
    {
      verification,
      humanDecision,
      states,
      evidenceState,
      evidenceFreshness,
      evidenceVerification,
      comparisonState,
      comparisonKind,
      comparisonChangedUnits,
      reviewAvailability,
      decisionOperation,
      decisionCount,
      headDecisionDigest,
      decisionRequirement,
      decisionPolicy,
      resources: [.resources[] | {
        state,
        role,
        artifactDigest,
        provenanceKind
      }]
    };
  def attribution:
    {
      runId,
      runResultDigest,
      reviewDescriptorDigest,
      requirementId,
      requirementScope,
      reviewGuideId,
      reviewGuideStepId,
      authorityId,
      accessPolicyId,
      principalId,
      role
    };
  def decision:
    {
      recordId,
      decisionDigest,
      subjectDigest,
      principalId,
      decision,
      decidedAt,
      supersedesDecisionDigest,
      state,
      supersededByDecisionDigest,
      attribution: (.attribution | attribution)
    };
  def review_set:
    {
      runId,
      runResultDigest,
      requirementId,
      requirementScope,
      reviewGuideId,
      reviewGuideStepId,
      requiredEvidenceResultDigests,
      comparisonResultDigests,
      resourceCount,
      artifacts: [.artifacts[] | {
        descriptorDigest,
        requiredEvidenceId,
        requiredEvidenceResultDigest,
        role,
        artifactDigest,
        provenanceDigest,
        provenanceKind,
        classification,
        mediaType,
        size,
        comparisonResultDigest
      }]
    };
  {
    browser: {
      status: $browser.status,
      mode: $browser.mode,
      route: $browser.route,
      runId: $browser.runId,
      secondRunId: $browser.secondRunId,
      relay: ($browser.relay | {
        relayCount,
        boundRelayCount,
        iframeCount,
        scopedIframeCount,
        runId,
        relayState,
        targetId,
        launchProfileId,
        launchAttemptId,
        aboutBlank,
        targetPort,
        childNavigationScrubbed,
        targetFrameBound,
        relayV2Ready,
        relayV2Fenced,
        mountAuthorized,
        controllerBound,
        helloAccepted,
        relayResultsAccepted,
        relayResultCount,
        networkTraceComplete,
        gatewayRequestBound,
        gatewayRequestCount,
        gatewaySuccessfulResponseCount,
        directApiRequestCount,
        gatewayTrafficObserved,
        gatewayTrafficSucceeded,
        gatewayBound,
        gatewayRouted,
        gatewayPort
      }),
      targetControl: ($browser.targetControl | {
        semanticStates,
        disabledScreenshotDigest,
        enabledScreenshotDigest,
        captureErrors
      }),
      terminal: ($browser.terminal | {
        state,
        cleanup,
        resultDigest,
        snapshotDigest,
        verification
      }),
      evidence: ($browser.evidence | {
        state,
        freshness,
        evidenceDigest,
        resultDigest,
        artifactDigest,
        provenanceDigest,
        classification
      }),
      comparison: ($browser.comparison | {
        kind,
        verification,
        resultDigest,
        comparedPixels,
        changedPixels,
        maxChannelDeltaObserved
      }),
      captures: {
        decisionDialog: ($browser.captures.decisionDialog | {
          digest,
          width,
          height
        }),
        qualityFinal: ($browser.captures.qualityFinal | {
          digest,
          width,
          height
        })
      },
      quality: ($browser.quality | quality_surface),
      qualityReview: {
        confirmBeforeAuthority:
          ($browser.qualityReview.confirmBeforeAuthority | {
            approve,
            supersedingReject
          }),
        dialogAccessibility:
          ($browser.qualityReview.dialogAccessibility | {
            nativeModal,
            approveInitialFocus,
            approveEscapeClosedWithoutRpc,
            approveFocusReturnedToOpener,
            supersedeInitialFocus,
            supersedeEscapeClosedWithoutRpc,
            supersedeFocusReturnedToOpener
          }),
        automatedDigest: $browser.qualityReview.automatedDigest,
        automatedUnchanged: $browser.qualityReview.automatedUnchanged,
        qualitySurfaceDigest: $browser.qualityReview.qualitySurfaceDigest,
        reviewSet: ($browser.qualityReview.reviewSet | review_set),
        reviewSetDigest: $browser.qualityReview.reviewSetDigest,
        humanTransitions: $browser.qualityReview.humanTransitions
      },
      decisions: {
        approved: ($browser.decisions.approved | decision),
        head: ($browser.decisions.head | decision),
        oldAfterSupersession:
          ($browser.decisions.oldAfterSupersession | decision),
        headView: ($browser.decisions.headView | decision),
        historyDigest: $browser.decisions.historyDigest
      },
      cancel: ($browser.cancel | {state, cleanup}),
      accessibility: {
        unnamedFocusableCount:
          $browser.semanticHtml.unnamedFocusableCount,
        uniqueTabStops: $browser.keyboard.uniqueTabStops,
        horizontalDocumentOverflow:
          $browser.reflow200Percent.horizontalDocumentOverflow,
        reducedMotion: $browser.reducedMotion.queryMatches,
        nodeCount: $browser.accessibilityNodes,
        severeBrowserLogs: $browser.severeBrowserLogs
      },
      labRpc: {
        requestsEqualResults:
          ($browser.labRpc.requestsByMethod ==
            $browser.labRpc.resultsByMethod),
        failureCount: ($browser.labRpc.failures | length)
      },
      qualityRpc: ($browser.qualityRpc | quality_rpc)
    },
    recovery: {
      status: $recovery.status,
      mode: $recovery.mode,
      route: $recovery.route,
      runId: $recovery.runId,
      terminal: ($recovery.terminal | {
        state,
        resultDigest,
        snapshotDigest
      }),
      quality: ($recovery.quality | quality_surface),
      qualityReview: ($recovery.qualityReview | {
        automatedDigest,
        qualitySurfaceDigest,
        reviewSetDigest
      }),
      decisions: ($recovery.decisions | {
        historyDigest,
        headDecisionDigest: .headView.decisionDigest,
        oldDecisionDigest: .oldAfterSupersession.decisionDigest,
        oldDecisionState: .oldAfterSupersession.state,
        oldSupersededByDecisionDigest:
          .oldAfterSupersession.supersededByDecisionDigest
      }),
      reattach: {
        newProbeExplicit: $recovery.reattach.newProbeExplicit,
        postReloadExplicit: $recovery.reattach.postReloadExplicit,
        newProbeSurfaceDigest:
          $recovery.reattach.newProbeSurfaceDigest,
        postReloadSurfaceDigest:
          $recovery.reattach.postReloadSurfaceDigest,
        newProbeRequests:
          $recovery.reattach.newProbeLabRpc.requestsByMethod[
            "lab.reattach"
          ],
        newProbeResults:
          $recovery.reattach.newProbeLabRpc.resultsByMethod[
            "lab.reattach"
          ],
        postReloadRequests:
          $recovery.labRpc.requestsByMethod["lab.reattach"],
        postReloadResults:
          $recovery.labRpc.resultsByMethod["lab.reattach"],
        newProbeQualityRpc:
          ($recovery.reattach.newProbeQualityRpc | quality_rpc),
        postReloadQualityRpc: ($recovery.qualityRpc | quality_rpc)
      },
      accessibility: {
        unnamedFocusableCount:
          $recovery.semanticHtml.unnamedFocusableCount,
        uniqueTabStops: $recovery.keyboard.uniqueTabStops,
        horizontalDocumentOverflow:
          $recovery.reflow200Percent.horizontalDocumentOverflow,
        reducedMotion: $recovery.reducedMotion.queryMatches,
        nodeCount: $recovery.accessibilityNodes,
        severeBrowserLogs: $recovery.severeBrowserLogs
      }
    },
    identity: {
      before: ($identityBefore.contentSet | {
        revision,
        contentSetDigest,
        workspaceSnapshotDigest,
        workspaceContentDigest,
        catalogDigest,
        experienceTopologyBundleDigest,
        scenarioFacetManifestDigest,
        scenarioLabManifestDigest,
        describeOpenIdentityMatches
      }),
      after: ($identityAfter.contentSet | {
        revision,
        contentSetDigest,
        workspaceSnapshotDigest,
        workspaceContentDigest,
        catalogDigest,
        experienceTopologyBundleDigest,
        scenarioFacetManifestDigest,
        scenarioLabManifestDigest,
        describeOpenIdentityMatches
      }),
      currentness: {
        refreshChanged: $identityAfter.refresh.changed,
        contentSetChanged:
          ($identityAfter.contentSet.contentSetDigest !=
            $identityBefore.contentSet.contentSetDigest),
        workspaceSnapshotChanged:
          ($identityAfter.snapshotDigest != $identityBefore.snapshotDigest),
        workspaceContentChanged:
          ($identityAfter.workspaceContentDigest !=
            $identityBefore.workspaceContentDigest),
        topologyBundleChanged:
          ($identityAfter.contentSet.experienceTopologyBundleDigest !=
            $identityBefore.contentSet.experienceTopologyBundleDigest),
        topologyDocumentUnchanged:
          ($identityAfter.experience.topologyDigest ==
            $identityBefore.experience.topologyDigest),
        layoutChanged:
          ($identityAfter.experience.layoutDigests !=
            $identityBefore.experience.layoutDigests),
        catalogUnchanged:
          ($identityAfter.contentSet.catalogDigest ==
            $identityBefore.contentSet.catalogDigest),
        facetManifestUnchanged:
          ($identityAfter.contentSet.scenarioFacetManifestDigest ==
            $identityBefore.contentSet.scenarioFacetManifestDigest),
        labManifestUnchanged:
          ($identityAfter.contentSet.scenarioLabManifestDigest ==
            $identityBefore.contentSet.scenarioLabManifestDigest)
      }
    },
    currentness: {
      status: $currentness.status,
      mode: $currentness.mode,
      historical: {
        runId: $currentness.historical.runId,
        terminal: ($currentness.historical.terminal | {
          state,
          cleanup,
          resultDigest,
          snapshotDigest,
          contentSetDigest,
          catalogDigest,
          scenarioLabManifestDigest,
          verification
        }),
        evidence: ($currentness.historical.evidence | {
          state,
          freshness,
          resultDigest,
          evidenceDigest,
          artifactDigest,
          provenanceDigest,
          immutable
        }),
        comparison: ($currentness.historical.comparison | {
          kind,
          verification,
          resultDigest,
          comparedPixels,
          changedPixels,
          maxChannelDeltaObserved
        }),
        quality: ($currentness.historical.quality | {
          contentCurrentness,
          states,
          evidenceState,
          evidenceFreshness,
          comparisonState,
          reviewAvailability
        }),
        reviewUnavailable: $currentness.historical.reviewUnavailable,
        recollect: $currentness.historical.recollect
      },
      current: {
        runId: $currentness.current.runId,
        relay: ($currentness.current.relay | {
          relayCount,
          boundRelayCount,
          iframeCount,
          scopedIframeCount,
          relayState,
          targetPort,
          childNavigationScrubbed,
          targetFrameBound,
          relayV2Ready,
          relayV2Fenced,
          mountAuthorized,
          controllerBound,
          helloAccepted,
          relayResultsAccepted,
          relayResultCount,
          networkTraceComplete,
          gatewayRequestBound,
          gatewayRequestCount,
          gatewaySuccessfulResponseCount,
          directApiRequestCount,
          gatewayTrafficObserved,
          gatewayTrafficSucceeded,
          gatewayBound,
          gatewayRouted,
          gatewayPort
        }),
        terminal: ($currentness.current.terminal | {
          state,
          terminalCause,
          cleanup,
          resultDigest,
          snapshotDigest,
          contentSetDigest,
          catalogDigest,
          scenarioLabManifestDigest,
          identityMatchesPostRefresh,
          verification
        }),
        evidence: ($currentness.current.evidence | {
          state,
          freshness,
          resultDigest,
          evidenceDigest,
          artifactDigest,
          provenanceDigest
        }),
        comparison: ($currentness.current.comparison | {
          kind,
          verification,
          resultDigest,
          comparedPixels,
          changedPixels,
          changedPixelRatio,
          maxChannelDeltaObserved
        }),
        quality: ($currentness.current.quality | {
          contentCurrentness,
          states,
          verification,
          evidenceState,
          evidenceFreshness,
          comparisonState,
          comparisonKind,
          comparisonChangedUnits,
          reviewAvailability
        })
      },
      severeBrowserLogs: $currentness.severeBrowserLogs
    }
  }
')"

assert_payload_sanitized "$public_proof" "Public Scenario Lab proof"

if [[ "$capture_disposition" == "retained-by-request" ]]; then
  echo "[scenario-lab-vertical] retained requested visual captures" >&2
fi

final_payload="$(jq -nc \
  --argjson publicProof "$public_proof" \
  --argjson baselineImport "$baseline_import_summary" \
  --arg cas "temporary-and-restored" \
  --arg captures "$capture_disposition" \
  '{
    status: "passed",
    gate: "scenario-lab-vertical",
    baselineImport: $baselineImport,
    browser: $publicProof.browser,
    recovery: $publicProof.recovery,
    identity: $publicProof.identity,
    currentness: $publicProof.currentness,
    cleanup: {
      writers: "stopped",
      ports: "released",
      sourceBytes: "restored-byte-for-byte",
      targetBuild: "restored-byte-for-byte",
      studioBuild: "restored-byte-for-byte",
      workspaceState: "restored-byte-for-byte"
    },
    casIsolation: $cas,
    visualCaptures: $captures
  }')"
assert_payload_sanitized "$final_payload" "Final Scenario Lab proof"
trap - EXIT INT TERM
printf '%s\n' "$final_payload"
