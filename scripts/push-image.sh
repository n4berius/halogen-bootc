#!/bin/bash
# Push an image under its exact tag and move the given channel tags. stable also moves latest.
# Usage: scripts/push-image.sh [edge|alpha|beta|rc|stable ...]
# Releases get their channels from scripts/channels.sh, so a channel never moves backwards.
set -euo pipefail
cd "$(dirname "$0")/.."
image="$(scripts/image-ref.sh)"
base="${image%:*}"
suffix=""
[ "${HALOGEN_VARIANT:-npu}" = npu ] || suffix="-no-npu"
podman push "$image"
for channel in "$@"; do
  case "$channel" in edge|alpha|beta|rc|stable) ;; *) echo "unknown channel: $channel" >&2; exit 1 ;; esac
  podman push "$image" "$base:$channel$suffix"
  [ "$channel" != stable ] || podman push "$image" "$base:latest$suffix"
done
