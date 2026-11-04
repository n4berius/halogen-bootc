#!/bin/bash
# Turn a git tag into release settings, and refuse tags that do not match versions.env.
# Usage: scripts/release-info.sh v0.18.23-beta.1
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
. ./versions.env
tag="${1:?usage: release-info.sh <tag>}"
if [[ ! "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)(-(alpha|beta|rc)\.([0-9]+)|-r([0-9]+))?$ ]]; then
  echo "bad tag: $tag. Use v1.2.3-alpha.1, v1.2.3-beta.1, v1.2.3-rc.1, v1.2.3 or v1.2.3-r2" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
pre="${BASH_REMATCH[3]}"
if [ "$version" != "$HALOGEN_VERSION" ]; then
  echo "tag is for Halogen $version, but versions.env pins $HALOGEN_VERSION" >&2
  exit 1
fi
if [ -n "$pre" ]; then
  echo "channel=$pre"
  echo "image_tag=${tag#v}"
  echo "prerelease=true"
else
  echo "channel=stable"
  echo "image_tag=$version"
  echo "prerelease=false"
fi
echo "version=$version"
