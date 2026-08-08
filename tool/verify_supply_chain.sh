#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

failed=0
while IFS= read -r dockerfile; do
  while IFS= read -r from; do
    image="${from#FROM }"
    image="${image%% AS *}"
    image="${image%% as *}"
    if [[ "$image" != "\${RUNTIME_IMAGE}" && ! "$image" =~ @sha256:[0-9a-f]{64}$ ]]; then
      echo "$dockerfile contains a mutable base image: $image" >&2
      failed=1
    fi
  done < <(sed -n 's/^[[:space:]]*\(FROM [^[:space:]]\+\([[:space:]]\+[Aa][Ss][[:space:]].*\)\?\)$/\1/p' "$dockerfile")
done < <(find apps -name Dockerfile -type f -print | sort)

if ! rg -q 'RUNTIME_IMAGE=.*@sha256|runtime_image.*sha256' \
  .github/workflows/release-images.yml; then
  echo 'Remote runtime image validation is absent.' >&2
  failed=1
fi

for required in 'SCRCPY_SERVER_DIGEST' "sha256sum \"\$SCRCPY_SERVER_PATH\"" \
  'android_scrcpy_server_digest'; do
  if ! rg -q --fixed-strings "$required" \
    apps/remote_worker/Dockerfile .github/workflows/release-images.yml; then
    echo "Android scrcpy supply-chain pin is missing: $required" >&2
    failed=1
  fi
done

if ! rg -q --fixed-strings \
  'remote.androidScrcpyServerDigest is required' \
  deploy/helm/devex-hosted/templates/configmap.yaml; then
  echo 'Helm does not require the pinned scrcpy server digest.' >&2
  failed=1
fi

for required in 'serviceAccountToken:' 'expirationSeconds: 600' \
  'kubernetes-api-token'; do
  if ! rg -q --fixed-strings "$required" \
    deploy/helm/devex-hosted/templates/deployment.yaml; then
    echo "Helm rotating Kubernetes token is missing: $required" >&2
    failed=1
  fi
done

if ! rg -q --fixed-strings 'resources: ["namespaces"]' \
  deploy/helm/devex-hosted/templates/remote-rbac.yaml; then
  echo 'Helm remote runtime RBAC is missing.' >&2
  failed=1
fi

if rg -q --fixed-strings 'namespaceSelector: {}' \
  deploy/helm/devex-hosted/templates/network-policy.yaml; then
  echo 'Helm ingress NetworkPolicy trusts every namespace.' >&2
  failed=1
fi

if rg -n 'uses:[[:space:]]+[^#[:space:]]+@(v[0-9]+|main|master)([[:space:]]|$)' \
  .github/workflows; then
  echo 'GitHub Actions must be pinned to immutable commit SHAs.' >&2
  failed=1
fi

for required in 'provenance: mode=max' 'sbom: true' 'cosign sign' \
  'cosign attest' 'cosign verify' 'attest-build-provenance@'; do
  if ! rg -q --fixed-strings "$required" .github/workflows/release-images.yml; then
    echo "Release workflow is missing: $required" >&2
    failed=1
  fi
done

if ! rg -q 'image.digest is required; mutable tags are forbidden' \
  deploy/helm/devex-hosted/templates/_helpers.tpl; then
  echo 'Helm deployment does not enforce an immutable control-plane image.' >&2
  failed=1
fi

if (( failed != 0 )); then
  exit 1
fi

echo 'Supply-chain policy verified: immutable bases/actions, SBOM, provenance, and signatures.'
