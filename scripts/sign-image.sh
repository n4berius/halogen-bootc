#!/bin/bash
# Sign a pushed image with cosign, keyless (GitHub's OIDC identity, no key to keep), then check
# the signature the way machines will (#46). Run in a workflow job with `id-token: write`.
# Usage: scripts/sign-image.sh <pushed repo:tag> [other tags of the same image to check ...]
#        scripts/sign-image.sh --verify <repo:tag> ...   (check only, sign nothing)
# The first ref gives the digest; one signature covers every tag pointing at it, so sign the
# exact tag first and move channel tags only after, then check them with --verify.
set -euo pipefail
COSIGN_VERSION=v2.6.1
COSIGN_SHA256=064954c5d8c7e3b28188eee5b1727b31c411550bc5fefd41aa672d3c761d103a
# Who may sign: this repository's publishing workflows, on main or on a release tag.
IDENTITY='^https://github\.com/n4berius/halos-flash/\.github/workflows/(build|release|refresh)\.yml@refs/(heads/main|tags/v.+)$'
ISSUER=https://token.actions.githubusercontent.com
verify_only=0; [ "${1:-}" != --verify ] || { verify_only=1; shift; }
[ $# -ge 1 ] || { echo "usage: sign-image.sh [--verify] <repo:tag> [repo:tag ...]" >&2; exit 2; }

bin="${RUNNER_TEMP:-/tmp}/cosign-$COSIGN_VERSION"
if [ ! -x "$bin" ]; then
  curl -fsSL --retry 3 -o "$bin" "https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/cosign-linux-amd64"
  echo "$COSIGN_SHA256  $bin" | sha256sum -c -
  chmod +x "$bin"
fi
cosign() { "$bin" "$@"; }
# cosign reads Docker's credentials file, not podman's.
[ -z "${GITHUB_TOKEN:-}" ] || echo "$GITHUB_TOKEN" | cosign login ghcr.io -u "${GITHUB_ACTOR:?}" --password-stdin

verify() { cosign verify --certificate-oidc-issuer "$ISSUER" --certificate-identity-regexp "$IDENTITY" "$1" > /dev/null; }
if [ "$verify_only" = 1 ]; then
  for ref in "$@"; do verify "$ref"; echo "verified $ref"; done
  exit 0
fi

# Refs are repo:tag (what the workflows push), with no registry port.
repo="${1%:*}"
digest="$(skopeo inspect --format '{{.Digest}}' "docker://$1")"
case "$digest" in sha256:[0-9a-f]*) ;; *) echo "no digest for $1: $digest" >&2; exit 1 ;; esac
echo "Signing $repo@$digest"
cosign sign --yes "$repo@$digest"
verify "$repo@$digest"
# Machines check through containers/image, which reads the classic "<digest>.sig" tag.
skopeo inspect --raw "docker://$repo:${digest/:/-}.sig" > /dev/null \
  || { echo "the signature is not in the .sig tag machines will read" >&2; exit 1; }
for ref in "$@"; do verify "$ref"; echo "verified $ref"; done
