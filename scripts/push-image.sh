#!/bin/bash
# Push an image and move its channel tag. stable also moves latest.
# Usage: scripts/push-image.sh edge|alpha|beta|rc|stable
set -euo pipefail
cd "$(dirname "$0")/.."
channel="${1:?usage: push-image.sh <channel>}"
image="$(scripts/image-ref.sh)"
base="${image%:*}"
suffix=""
[ "${HALOGEN_VARIANT:-npu}" = npu ] || suffix="-no-npu"
podman push "$image"
podman push "$image" "$base:$channel$suffix"
[ "$channel" != stable ] || podman push "$image" "$base:latest$suffix"
