#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
sample_dir="$repo_dir/examples/sample_flutter"
run_dir="$(mktemp -d)"

cleanup() {
  rm -rf -- "$run_dir"
}
trap cleanup EXIT INT TERM

output_dir="$run_dir/web"
(
  cd "$sample_dir"
  flutter build web --release --wasm --no-web-resources-cdn \
    --target tool/target_main.dart \
    --output "$output_dir"
)

test -s "$output_dir/main.dart.wasm"
test -s "$output_dir/main.dart.js"

echo "Flutter web Wasm and JavaScript fallback artifacts passed."
