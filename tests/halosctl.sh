#!/bin/bash
# shellcheck disable=SC2016 # The fake commands expand their variables when they run.
# halosctl against fake bootc, skopeo, systemctl and id.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FAKE="$work"
f() { printf '#!/bin/bash\n%s\n' "$2" > "$work/bin/$1"; chmod +x "$work/bin/$1"; }
f id 'echo "${FAKE_UID:-0}"'
# bootc status prints $FAKE/status.json; other commands are logged, and upgrade stages $FAKE/staged.json.
f bootc 'echo "bootc $*" >> "$FAKE/log"
case "$1" in
  status) cat "$FAKE/status.json" ;;
  upgrade) [ "${2:-}" = --check ] && { echo "Update available"; exit 0; }
           [ ! -f "$FAKE/next.json" ] || cp "$FAKE/next.json" "$FAKE/status.json" ;;
esac'
f skopeo 'echo "skopeo $*" >> "$FAKE/log"; case "$*" in *:beta|*:stable-no-npu|*:0.19.0-alpha.1) echo "sha256:feed 0.19.0-beta.1" ;; *) exit 1 ;; esac'
f systemctl 'echo "systemctl $*" >> "$FAKE/log"; case "$*" in *is-active*) echo "${FAKE_FETCH:-inactive}" ;; esac'
dep() { printf '{"image":{"image":{"image":"%s","transport":"registry"},"version":"%s","timestamp":"2026-11-05T16:58:48Z","imageDigest":"%s"}}' "$@"; }
host() { printf '{"status":{"booted":%s,"staged":%s,"rollback":%s}}' "$1" "${2:-null}" "${3:-null}"; }
host "$(dep ghcr.io/n4berius/halos-flash:0.19.0-alpha.1 0.19.0 sha256:aaa)" null \
  "$(dep ghcr.io/n4berius/halogen-flash-bootc:0.18.23-alpha.2 0.18.23 sha256:old)" > "$work/status.json"
printf 'HALOGEN_IMAGE=img@sha256:1\nHALOGEN_VERSION=0.19.0\nHALOGEN_VARIANT=npu\n' > "$work/release.env"
export PATH="$work/bin:$PATH" HALOGEN_RELEASE_FILE="$work/release.env" HALOS_HISTORY="$work/history" SUDO_USER=owner
ctl="$repo/files/usr/bin/halosctl"
ok() { echo "ok: $*"; }
has() { grep -qE -- "$1" "$2" || { echo "expected '$1' in $2:" >&2; cat "$2" >&2; exit 1; }; }
hasnt() { if grep -qE -- "$1" "$2"; then echo "did not expect '$1' in $2:" >&2; cat "$2" >&2; exit 1; fi; }

"$ctl" version > "$work/out"
has '^halOS 0\.19\.0, npu edition' "$work/out"; has '^Channel: +none, pinned' "$work/out"
has '^Rollback: +ghcr.io/n4berius/halogen-flash-bootc:0.18.23-alpha.2 \(0.18.23\)' "$work/out"
has '^Next boot: +no change staged' "$work/out"
echo HALOS_RELEASE=0.19.0-alpha.1 >> "$work/release.env"
"$ctl" > "$work/out"; has '^halOS 0\.19\.0-alpha\.1,' "$work/out"
ok "version shows the release, edition, channel and rollback image"

if FAKE_UID=1000 "$ctl" version > "$work/out" 2>&1; then echo "ran without root" >&2; exit 1; fi
has 'sudo' "$work/out"
: > "$work/log"
if "$ctl" switch beta < /dev/null > "$work/out" 2>&1; then echo "switched without confirming" >&2; exit 1; fi
has 'add --yes' "$work/out"; hasnt 'bootc switch' "$work/log"
if "$ctl" switch gamma --yes > "$work/out" 2>&1; then echo "took an unknown channel" >&2; exit 1; fi
if "$ctl" switch rc --yes > "$work/out" 2>&1; then echo "switched to a missing image" >&2; exit 1; fi
has 'not found' "$work/out"; hasnt 'bootc switch' "$work/log"
if "$ctl" rollback --to '0.19; reboot' --yes > "$work/out" 2>&1; then echo "took a bad version" >&2; exit 1; fi
[ ! -e "$work/history" ] || { echo "history written for refused changes" >&2; exit 1; }
ok "it needs root, a confirmation, a known channel and an image that exists"

"$ctl" switch beta --yes > "$work/out"
has '^bootc switch ghcr.io/n4berius/halos-flash:beta$' "$work/log"
has 'next reboot' "$work/out"; hasnt 'systemctl reboot' "$work/log"
has 'switch +ghcr.io/n4berius/halos-flash:0.19.0-alpha.1 \(0.19.0\) -> ghcr.io/n4berius/halos-flash:beta \(0.19.0-beta.1\) +\(by owner\)' "$work/history"
ok "switch beta stages the beta image, records it, and waits for a reboot"

sed -i 's/=npu/=no-npu/' "$work/release.env"
"$ctl" switch release --yes --reboot > "$work/out"
has '^bootc switch ghcr.io/n4berius/halos-flash:stable-no-npu$' "$work/log"; has '^systemctl reboot$' "$work/log"
: > "$work/log"
FAKE_FETCH=activating "$ctl" switch release --yes --reboot > "$work/out"
has 'Not rebooting' "$work/out"; hasnt '^systemctl reboot$' "$work/log"
sed -i 's/=no-npu/=npu/' "$work/release.env"
ok "release means stable, the no-NPU edition keeps its suffix, and no reboot during a download"

"$ctl" rollback --yes > "$work/out"
has '^bootc rollback$' "$work/log"; has 'rollback .*-> ghcr.io/n4berius/halogen-flash-bootc:0.18.23-alpha.2' "$work/history"
"$ctl" rollback --to 0.19.0-alpha.1 --yes > "$work/out"
has '^bootc switch ghcr.io/n4berius/halos-flash:0.19.0-alpha.1$' "$work/log"; has 'pins' "$work/out"
host "$(dep ghcr.io/n4berius/halos-flash:0.19.0-alpha.1 0.19.0 sha256:aaa)" > "$work/status.json"
if "$ctl" rollback --yes > "$work/out" 2>&1; then echo "rolled back to nothing" >&2; exit 1; fi
has 'no previous image' "$work/out"
ok "rollback goes to the previous image, --to to an exact release, and says when there is none"

host "$(dep ghcr.io/n4berius/halos-flash:beta 0.19.0-beta.1 sha256:bbb)" > "$work/status.json"
"$ctl" version > "$work/out"; has '^Channel: +beta' "$work/out"
"$ctl" upgrade --yes > "$work/out"; has 'No new update' "$work/out"
host "$(dep ghcr.io/n4berius/halos-flash:beta 0.19.0-beta.1 sha256:bbb)" \
  "$(dep ghcr.io/n4berius/halos-flash:beta 0.19.0-rc.1 sha256:ccc)" > "$work/next.json"
"$ctl" upgrade --yes > "$work/out"; has 'next reboot' "$work/out"
has 'upgrade .*:beta \(0.19.0-beta.1\) -> ghcr.io/n4berius/halos-flash:beta \(0.19.0-rc.1\)' "$work/history"
"$ctl" version > "$work/out"; has '^Next boot: +ghcr.io/n4berius/halos-flash:beta \(0.19.0-rc.1\)' "$work/out"
"$ctl" history > "$work/out"; [ "$(wc -l < "$work/out")" = 6 ] || { cat "$work/out" >&2; exit 1; }
"$ctl" switch beta > "$work/out"; has 'Already on beta' "$work/out"
: > "$work/log"; "$ctl" upgrade --yes > "$work/out"; has 'No new update' "$work/out"
"$ctl" history > "$work/out"; [ "$(wc -l < "$work/out")" = 6 ] || { echo "an unchanged upgrade was recorded" >&2; exit 1; }
host "$(dep ghcr.io/n4berius/halogen-flash-bootc:0.18.23-alpha.2 0.18.23 sha256:old)" > "$work/status.json"
"$ctl" switch beta --yes > /dev/null; has '^bootc switch ghcr.io/n4berius/halos-flash:beta$' "$work/log"
ok "upgrade stages the channel's newest release and records it; history lists every change; an old-name install switches to halos-flash"
