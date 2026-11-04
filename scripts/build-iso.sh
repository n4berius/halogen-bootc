#!/bin/bash
# Build the USB installer. Needs root Podman and a built OS image in root's storage.
# Usage: sudo scripts/build-iso.sh [os-image-reference]
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
. ./versions.env
TARGET="${1:-ghcr.io/n4berius/halogen-flash-bootc:$HALOGEN_VERSION}"
INSTALLER="localhost/halogen-flash-bootc-installer:$HALOGEN_VERSION"
mkdir -p output

podman image exists "$TARGET" || { echo "build or pull $TARGET first" >&2; exit 1; }
podman build --pull=newer -t "$INSTALLER" -f Containerfile.installer \
  --build-arg "FEDORA_BOOTC_IMAGE=$FEDORA_BOOTC_IMAGE" \
  --build-arg "TARGET_IMAGE=$TARGET" .

# Upstream's build, because embedding the OS needs newer support than Fedora's package.
podman run --rm --privileged --security-opt label=disable \
  -v /dev:/dev -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$PWD/output:/output" "${IMAGE_BUILDER:-ghcr.io/osbuild/image-builder-cli:latest}" \
  build --bootc-ref "$INSTALLER" --bootc-installer-payload-ref "$TARGET" \
  --bootc-default-fs xfs --output-dir /output generic-iso
find output -name '*.iso' -exec ls -lh {} +
