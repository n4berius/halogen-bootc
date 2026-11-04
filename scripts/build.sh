#!/bin/bash
# Build the OS image, tagged with its Halogen version.
# Usage: scripts/build.sh [image-reference]
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
. ./versions.env
TAG="${1:-ghcr.io/n4berius/halogen-flash-bootc:$HALOGEN_VERSION}"
SOURCE=ghcr.io/peonist-ai/halogen-flash-server

if [ -z "$HALOGEN_DIGEST" ]; then
  HALOGEN_DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://$SOURCE:$HALOGEN_VERSION")"
  echo "Resolved $SOURCE:$HALOGEN_VERSION to $HALOGEN_DIGEST"
fi
case "$HALOGEN_DIGEST" in
  sha256:[0-9a-f]*) [ "${#HALOGEN_DIGEST}" = 71 ] || { echo "bad digest: $HALOGEN_DIGEST" >&2; exit 1; } ;;
  *) echo "bad digest: $HALOGEN_DIGEST" >&2; exit 1 ;;
esac

podman build --pull=newer -t "$TAG" \
  --label "org.opencontainers.image.source=https://github.com/n4berius/halogen-bootc" \
  --label "org.opencontainers.image.version=$HALOGEN_VERSION" \
  --build-arg "FEDORA_BOOTC_IMAGE=$FEDORA_BOOTC_IMAGE" \
  --build-arg "DEBIAN_IMAGE=$DEBIAN_IMAGE" \
  --build-arg "XRT_MIN_VERSION=$XRT_MIN_VERSION" \
  --build-arg "HALOGEN_IMAGE=$SOURCE@$HALOGEN_DIGEST" \
  --build-arg "HALOGEN_VERSION=$HALOGEN_VERSION" \
  --build-arg "HALOGEN_SOURCE_COMMIT=$HALOGEN_SOURCE_COMMIT" \
  --build-arg "HALOGEN_CLOCK_SHA256=$HALOGEN_CLOCK_SHA256" \
  --build-arg "HALOGEN_LICENSE_SHA256=$HALOGEN_LICENSE_SHA256" \
  --build-arg "HALOGEN_NOTICES_SHA256=$HALOGEN_NOTICES_SHA256" \
  --build-arg "HALOGEN_WEIGHTS_REPO=$HALOGEN_WEIGHTS_REPO" \
  --build-arg "HALOGEN_WEIGHTS_REVISION=$HALOGEN_WEIGHTS_REVISION" \
  .
echo "Built $TAG with Halogen $HALOGEN_VERSION ($HALOGEN_DIGEST)"
