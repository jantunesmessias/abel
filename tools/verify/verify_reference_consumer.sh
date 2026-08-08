#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
studio_assets="$repo_dir/apps/studio/build/jaspr"
api_pid=""
dev_pid=""
api_log=""
dev_log=""

stop_process() {
  local pid_value="$1"
  if [[ -z "$pid_value" ]] || ! kill -0 "$pid_value" 2>/dev/null; then
    return
  fi
  kill -INT "$pid_value" 2>/dev/null || true
  for _ in $(seq 1 100); do
    if ! kill -0 "$pid_value" 2>/dev/null; then
      wait "$pid_value" 2>/dev/null || true
      return
    fi
    sleep 0.1
  done
  kill -TERM "$pid_value" 2>/dev/null || true
  for _ in $(seq 1 30); do
    if ! kill -0 "$pid_value" 2>/dev/null; then
      wait "$pid_value" 2>/dev/null || true
      return
    fi
    sleep 0.1
  done
  kill -KILL "$pid_value" 2>/dev/null || true
  wait "$pid_value" 2>/dev/null || true
}

cleanup() {
  local exit_code=$?
  stop_process "$dev_pid"
  stop_process "$api_pid"
  if [[ $exit_code -ne 0 ]]; then
    if [[ -n "$api_log" && -f "$api_log" ]]; then
      echo "[reference-consumer] sample API log" >&2
      tail -n 120 "$api_log" >&2 || true
    fi
    if [[ -n "$dev_log" && -f "$dev_log" ]]; then
      echo "[reference-consumer] workspace log" >&2
      tail -n 240 "$dev_log" >&2 || true
    fi
  fi
  if [[ -n "$api_log" && -f "$api_log" ]]; then
    rm -f -- "$api_log"
  fi
  if [[ -n "$dev_log" && -f "$dev_log" ]]; then
    rm -f -- "$dev_log"
  fi
  return "$exit_code"
}
trap cleanup EXIT INT TERM

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
  for _ in $(seq 1 100); do
    if ! port_open "$port"; then
      return
    fi
    sleep 0.1
  done
  echo "Loopback listener on port $port survived cleanup." >&2
  exit 1
}

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
      cat "$log_path" >&2
      echo "$label exited before readiness." >&2
      exit 1
    fi
    sleep 0.25
  done
  cat "$log_path" >&2
  echo "$label timed out before readiness." >&2
  exit 1
}

command -v jq >/dev/null 2>&1
toolchain=()
if command -v mise >/dev/null 2>&1; then
  toolchain=(mise exec --)
fi

cd "$repo_dir"

echo "[reference-consumer] formatting and public-boundary audit" >&2
"${toolchain[@]}" dart format --output=none --set-exit-if-changed examples
"${toolchain[@]}" dart run tools/gates/architecture_guard.dart

echo "[reference-consumer] analyzing and testing the synthetic API" >&2
"${toolchain[@]}" dart analyze examples/sample_api
"${toolchain[@]}" dart test examples/sample_api

echo "[reference-consumer] analyzing and testing the Flutter consumer" >&2
"${toolchain[@]}" flutter analyze --fatal-infos --fatal-warnings \
  examples/sample_flutter
"${toolchain[@]}" flutter test examples/sample_flutter

echo "[reference-consumer] building Target and Studio, then compiling content" >&2
showcase_build_args=(--check)
if [[ "${REFERENCE_SKIP_TARGET_BUILD:-0}" != "1" ]]; then
  showcase_build_args=(--build-target "${showcase_build_args[@]}")
fi
if [[ "${REFERENCE_SKIP_STUDIO_BUILD:-0}" != "1" ]]; then
  showcase_build_args=(--build-studio "${showcase_build_args[@]}")
fi
"${toolchain[@]}" dart run examples/tool/showcase.dart \
  "${showcase_build_args[@]}"

for port in 7367 7368 8080 8181; do
  require_port_free "$port"
done

api_log="$(mktemp "${TMPDIR:-/tmp}/reference-consumer-api.XXXXXX.jsonl")"
dev_log="$(mktemp "${TMPDIR:-/tmp}/reference-consumer-dev.XXXXXX.jsonl")"

echo "[reference-consumer] starting the synthetic API" >&2
(
  cd "$repo_dir"
  exec "${toolchain[@]}" dart run examples/sample_api/bin/server.dart \
    --port 8181
) >"$api_log" 2>&1 &
api_pid=$!
api_ready="$(wait_for_json_readiness "$api_pid" "$api_log" "sample API")"
jq -e '
  .service == "sample-api" and
  .origin == "http://127.0.0.1:8181"
' <<<"$api_ready" >/dev/null

echo "[reference-consumer] starting Host and Studio from consumer config" >&2
(
  cd "$sample_dir"
  exec "${toolchain[@]}" dart run \
    ../../apps/workspace_cli/bin/workspace.dart --json dev \
    --config workspace.yaml \
    --host-port 7367 \
    --studio-port 7368 \
    --studio-assets "$studio_assets" \
    --no-open
) >"$dev_log" 2>&1 &
dev_pid=$!
dev_ready="$(wait_for_json_readiness "$dev_pid" "$dev_log" "workspace dev")"
jq -e '
  .ok == true and
  .result.hostOrigin == "http://127.0.0.1:7367" and
  .result.studioOrigin == "http://127.0.0.1:7368"
' <<<"$dev_ready" >/dev/null

echo "[reference-consumer] exercising states, Target, Evidence and Gateway" >&2
smoke_payload="$("${toolchain[@]}" dart run \
  examples/tool/showcase_smoke.dart)"
if ! jq -e '
  .status == "passed" and
  .consumer == "delivery-lab" and
  (.apiMatrix.states | map(.state)) == [
    "ready",
    "loading",
    "empty",
    "stale",
    "unavailable",
    "failure"
  ] and
  .apiMatrix.unknownStateRejected == true and
  .evidence.state == "completed" and
  .evidence.scenarios == 8 and
  .evidence.variants == 3 and
  .evidence.captures == 10 and
  .evidence.validatedPngs == 10 and
  .evidence.fidelity == "structural" and
  .evidence.freshness == "fresh" and
  .target.flutterEntrypoint == true and
  (.gatewayPresets | map(.presetId)) == [
    "showcase-hybrid",
    "showcase-offline",
    "showcase-unavailable",
    "showcase-failure"
  ] and
  ([.gatewayPresets[].trafficEvents > 0] | all) and
  .gatewayPresets[0].mutationObserved == true and
  .gatewayPresets[1].isolatedMutation == true and
  .gatewayPresets[2].state == "unavailable" and
  .gatewayPresets[2].recoverable == true and
  .gatewayPresets[3].state == "failure" and
  .gatewayPresets[3].recoverable == false
' <<<"$smoke_payload" >/dev/null; then
  echo "Reference consumer smoke assertion failed:" >&2
  jq . <<<"$smoke_payload" >&2
  exit 1
fi

stop_process "$dev_pid"
dev_pid=""
stop_process "$api_pid"
api_pid=""
for port in 7367 7368 8080 8181; do
  wait_for_port_free "$port"
done

if git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo_dir" diff --check -- examples \
    tools/verify/verify_reference_consumer.sh \
    tools/gates/architecture_guard.dart
fi

jq -n \
  --argjson smoke "$smoke_payload" \
  '{
    status: "passed",
    gate: "reference-consumer",
    publicApiBoundary: "verified",
    cleanup: "verified",
    smoke: $smoke
  }'
