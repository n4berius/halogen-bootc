#!/bin/bash
# Print the image name for an edition: 0.18.23 with the NPU, 0.18.23-no-npu without it.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
. ./versions.env
case "${HALOGEN_VARIANT:-npu}" in
  npu) suffix="" ;;
  no-npu) suffix="-no-npu" ;;
  *) echo "unknown edition: $HALOGEN_VARIANT" >&2; exit 1 ;;
esac
echo "ghcr.io/n4berius/halogen-flash-bootc:$HALOGEN_VERSION$suffix"
