#!/bin/bash
# Package an ISO for GitHub Releases, which refuses any file of 2 GiB or more.
# Ships the plain .iso when it fits, otherwise .iso.xz, and splits into parts only if
# neither fits. Writes the asset(s) and a .sha256 file into the output directory.
# Usage: scripts/package-iso.sh input.iso output-dir asset-name.iso
set -euo pipefail
iso="$1"; dir="$2"; name="$3"
limit="${ISO_ASSET_LIMIT:-$((2 * 1024 * 1024 * 1024 - 16 * 1024 * 1024))}"
mkdir -p "$dir"
size="$(stat -c %s "$iso")"

report() {
  echo "$1"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || echo "- $1" >> "$GITHUB_STEP_SUMMARY"
}
mib() { echo "$(( $1 / 1024 / 1024 )) MiB"; }

report "$name: ISO is $(mib "$size") (limit $(mib "$limit"))"
if [ "$size" -lt "$limit" ]; then
  mv "$iso" "$dir/$name"
  (cd "$dir" && sha256sum "$name" > "$name.sha256")
  report "$name: shipped as a plain .iso"
  exit 0
fi

xz -T0 -9 -c "$iso" > "$dir/$name.xz"
xsize="$(stat -c %s "$dir/$name.xz")"
report "$name: .iso.xz is $(mib "$xsize")"
if [ "$xsize" -lt "$limit" ]; then
  rm -f "$iso"
  (cd "$dir" && sha256sum "$name.xz" > "$name.xz.sha256")
  report "$name: shipped as .iso.xz"
  exit 0
fi

rm -f "$dir/$name.xz"
mv "$iso" "$dir/$name"
(cd "$dir" && sha256sum "$name" > "$name.sha256" && split -b 1900M -d "$name" "$name.part" && rm "$name")
report "$name: too large even compressed; shipped in parts"
