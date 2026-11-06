#!/bin/bash
# Sign a pushed image with cosign, keyless (GitHub's OIDC identity, no key to keep), then check
# the signature the way machines will (#46). Run in a workflow job with `id-token: write`.
# Usage: scripts/sign-image.sh <pushed ref> [other tags of the same image to check ...]
# The first ref gives the digest; one signature covers every tag pointing at it.
set -euo pipefail
COSIGN_VERSION=v2.6.1
COSIGN_SHA256=064954c5d8c7e3b28188eee5b1727b31c411550bc5fefd41aa672d3c761d103a
# Who may sign: this repository's publishing workflows, on main or on a release tag.
IDENTITY='^https://github\.com/n4berius/halos-flash/\.github/workflows/(build|release|refresh)\.yml@refs/(heads/main|tags/v.+)$'
ISSUER=https://token.actions.githubusercontent.com
[ $# -ge 1 ] || { echo "usage: sign-image.sh <ref> [ref ...]" >&2; exit 2; }

bin="${RUNNER_TEMP:-/tmp}/cosign-$COSIGN_VERSION"
if [ ! -x "$bin" ]; then
  curl -fsSL -o "$bin" "https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/cosign-linux-amd64"
  echo "$COSIGN_SHA256  $bin" | sha256sum -c -
  chmod +x "$bin"
fi
cosign() { "$bin" "$@"; }
# cosign reads Docker's credentials file, not podman's.
[ -z "${GITHUB_TOKEN:-}" ] || echo "$GITHUB_TOKEN" | cosign login ghcr.io -u "${GITHUB_ACTOR:?}" --password-stdin

repo="${1%:*}"; repo="${repo%@*}"
digest="$(skopeo inspect --format '{{.Digest}}' "docker://$1")"
case "$digest" in sha256:[0-9a-f]*) ;; *) echo "no digest for $1: $digest" >&2; exit 1 ;; esac
echo "Signing $repo@$digest"
cosign sign --yes "$repo@$digest"

verify() { cosign verify --certificate-oidc-issuer "$ISSUER" --certificate-identity-regexp "$IDENTITY" "$1" > /dev/null; }
verify "$repo@$digest"
# Machines check through containers/image, which reads the classic "<digest>.sig" tag.
skopeo inspect --raw "docker://$repo:${digest/:/-}.sig" > /dev/null \
  || { echo "the signature is not in the .sig tag machines will read" >&2; exit 1; }
for ref in "$@"; do verify "$ref"; echo "verified $ref"; done
