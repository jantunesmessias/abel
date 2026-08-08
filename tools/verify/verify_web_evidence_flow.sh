#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
run_dir="$(mktemp -d)"
server_pid=""

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill -TERM "$server_pid"
    wait "$server_pid" || true
  fi
  rm -rf -- "$run_dir"
}
trap cleanup EXIT INT TERM

(
  cd "$sample_dir"
  flutter build web --release --no-web-resources-cdn \
    --target tool/target_main.dart
)

ready_file="$run_dir/origin.txt"
dart run "$repo_dir/apps/workspace_host/bin/static_server.dart" \
  "$sample_dir/build/web" >"$ready_file" &
server_pid=$!

origin=""
for _ in {1..1200}; do
  if [[ -s "$ready_file" ]]; then
    origin="$(head -n 1 "$ready_file")"
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"
    exit 5
  fi
  sleep 0.05
done
if [[ -z "$origin" ]]; then
  echo "Static target origin did not become ready." >&2
  exit 5
fi

if command -v google-chrome-stable >/dev/null 2>&1; then
  chrome_executable="$(command -v google-chrome-stable)"
elif command -v google-chrome >/dev/null 2>&1; then
  chrome_executable="$(command -v google-chrome)"
elif command -v chromium >/dev/null 2>&1; then
  chrome_executable="$(command -v chromium)"
else
  echo "No supported Chrome/Chromium executable found." >&2
  exit 3
fi

capture_file="$run_dir/sample.png"
profile_dir="$run_dir/chrome-profile"
"$chrome_executable" \
  --headless=new \
  --disable-gpu \
  --hide-scrollbars \
  --no-first-run \
  --no-default-browser-check \
  --user-data-dir="$profile_dir" \
  --window-size=1280,720 \
  --virtual-time-budget=5000 \
  --screenshot="$capture_file" \
  "$origin"
test -s "$capture_file"

(
  cd "$sample_dir"
  dart run ../../apps/workspace_cli/bin/workspace.dart --json capture \
    --input "$capture_file" \
    --launch-profile sample-web \
    --target local-chrome \
    --platform web \
    --renderer canvaskit \
    --fidelity simulated
  dart run ../../apps/workspace_cli/bin/workspace.dart --json release build
)
