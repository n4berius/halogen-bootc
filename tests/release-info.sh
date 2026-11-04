#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
. ./versions.env
v="$HALOGEN_VERSION"
check() { [ "$(scripts/release-info.sh "$1" | sed -n "s/^$2=//p")" = "$3" ] || { echo "$1: wrong $2" >&2; exit 1; }; }
check "v$v-alpha.1" channel alpha
check "v$v-alpha.1" image_tag "$v-alpha.1"
check "v$v-beta.2" prerelease true
check "v$v-rc.1" channel rc
check "v$v" channel stable
check "v$v" prerelease false
check "v$v-r2" image_tag "$v"
for bad in "$v" "v$v-gamma.1" "v$v-alpha" "v0.0.1"; do
  if scripts/release-info.sh "$bad" >/dev/null 2>&1; then echo "accepted bad tag $bad" >&2; exit 1; fi
done
echo "ok: release tags are parsed, and bad or mismatched tags are refused"
