#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_dir"

helm_version="v4.2.3"
helm_sha256="e9b88b4ee95b18c706839c28d3a0220e5bc470e9cd9262410c90793c45ff8b7c"
kubeconform_version="v0.8.0"
kubeconform_sha256="9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883"
kubernetes_version="1.36.2"
validation_root="$(mktemp -d /tmp/workspace-kubernetes-validation.XXXXXX)"

cleanup() {
  if [[ "${KEEP_VALIDATION_ARTIFACTS:-false}" == "true" ]]; then
    printf 'validation_artifacts=%s\n' "$validation_root"
  else
    rm -rf -- "$validation_root"
  fi
}
trap cleanup EXIT

verify_archive() {
  local archive="$1"
  local expected="$2"
  local actual
  actual="$(sha256sum "$archive" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    echo 'Downloaded validation tool failed its SHA-256 pin.' >&2
    exit 65
  fi
}

if [[ -n "${HELM_BIN:-}" ]]; then
  helm_bin="$HELM_BIN"
else
  helm_archive="$validation_root/helm.tar.gz"
  curl -fsSL \
    "https://get.helm.sh/helm-${helm_version}-linux-amd64.tar.gz" \
    -o "$helm_archive"
  verify_archive "$helm_archive" "$helm_sha256"
  bsdtar -xf "$helm_archive" -C "$validation_root"
  helm_bin="$validation_root/linux-amd64/helm"
fi

if [[ -n "${KUBECONFORM_BIN:-}" ]]; then
  kubeconform_bin="$KUBECONFORM_BIN"
else
  kubeconform_archive="$validation_root/kubeconform.tar.gz"
  curl -fsSL \
    "https://github.com/yannh/kubeconform/releases/download/${kubeconform_version}/kubeconform-linux-amd64.tar.gz" \
    -o "$kubeconform_archive"
  verify_archive "$kubeconform_archive" "$kubeconform_sha256"
  bsdtar -xf "$kubeconform_archive" -C "$validation_root"
  kubeconform_bin="$validation_root/kubeconform"
fi

"$helm_bin" version --short | rg -q "^${helm_version}([+]|$)"
[[ "$("$kubeconform_bin" -v)" == "$kubeconform_version" ]]

hosted_digest="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
web_image="registry.example.test/workspace/worker-web@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
android_image="registry.example.test/workspace/worker-android@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
android_digest="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
scrcpy_digest="sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
remote_values=(
  --set remote.enabled=true
  --set-string "remote.webWorkerImage=$web_image"
  --set-string "remote.androidWorkerImage=$android_image"
  --set-string "remote.androidImage.digest=$android_digest"
  --set-string "remote.androidScrcpyServerDigest=$scrcpy_digest"
  --set-string 'remote.allowedEgressCidrs[0]=10.0.0.0/24'
  --set-string 'networkPolicy.allowedEgressCidrs[0].cidr=10.0.0.0/24'
  --set-string 'networkPolicy.allowedEgressCidrs[0].ports[0].protocol=TCP'
  --set 'networkPolicy.allowedEgressCidrs[0].ports[0].port=443'
)

"$helm_bin" lint deploy/helm/control-plane \
  --set-string "image.digest=$hosted_digest"
"$helm_bin" lint deploy/helm/control-plane \
  --set-string "image.digest=$hosted_digest" \
  "${remote_values[@]}"
"$helm_bin" template workspace-default deploy/helm/control-plane \
  --set-string "image.digest=$hosted_digest" \
  --output-dir "$validation_root/chart-default"
"$helm_bin" template workspace-remote deploy/helm/control-plane \
  --set-string "image.digest=$hosted_digest" \
  "${remote_values[@]}" \
  --output-dir "$validation_root/chart-remote"

dart run tools/generators/render_remote_jobs.dart "$validation_root/remote-jobs"

for manifests in chart-default chart-remote; do
  "$kubeconform_bin" \
    -strict \
    -summary \
    -kubernetes-version "$kubernetes_version" \
    "$validation_root/$manifests"
done

mapfile -d '' core_job_manifests < <(
  find "$validation_root/remote-jobs" \
    -type f \
    ! -name '*-HTTPRoute.json' \
    -print0
)
mapfile -d '' route_manifests < <(
  find "$validation_root/remote-jobs" \
    -type f \
    -name '*-HTTPRoute.json' \
    -print0
)
[[ "${#core_job_manifests[@]}" -eq 26 ]]
[[ "${#route_manifests[@]}" -eq 2 ]]
"$kubeconform_bin" \
  -strict \
  -summary \
  -kubernetes-version "$kubernetes_version" \
  "${core_job_manifests[@]}"
for route in "${route_manifests[@]}"; do
  jq -e '
    .apiVersion == "gateway.networking.k8s.io/v1" and
    .kind == "HTTPRoute" and
    (.metadata.namespace | startswith("workspace-run-")) and
    (.spec.parentRefs | length == 1) and
    (.spec.rules | length == 1)
  ' "$route" >/dev/null
done

rg -Fq "REMOTE_ANDROID_SCRCPY_SERVER_DIGEST: \"${scrcpy_digest}\"" \
  "$validation_root/chart-remote"
printf 'Helm and remote Job manifests validated for Kubernetes %s.\n' \
  "$kubernetes_version"
printf '%s\n' \
  'HTTPRoute CRs passed structural checks; server-side Gateway API validation remains a cluster gate.'
