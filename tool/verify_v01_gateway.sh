#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_dir="$(mktemp -d)"

cleanup() {
  rm -rf -- "$run_dir"
}
trap cleanup EXIT INT TERM

(
  cd "$repo_dir/apps/backend_gateway"
  dart compile exe tool/benchmark_gateway.dart \
    -o "$run_dir/benchmark_gateway"
)
"$run_dir/benchmark_gateway"
