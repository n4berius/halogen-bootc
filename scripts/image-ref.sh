#!/bin/bash
# Print the image name for an edition: 0.18.23 with the NPU, 0.18.23-no-npu without it.
# IMAGE_TAG replaces the version, such as 0.18.23-alpha.1 or edge.
# IMAGE_NAME replaces the repository, for builds pushed to your own registry.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
. ./versions.env
case "${HALOGEN_VARIANT:-npu}" in
  npu) suffix="" ;;
  no-npu) suffix="-no-npu" ;;
  *) echo "unknown edition: $HALOGEN_VARIANT" >&2; exit 1 ;;
esac
echo "${IMAGE_NAME:-ghcr.io/n4berius/halos-flash}:${IMAGE_TAG:-$HALOGEN_VERSION}$suffix"
