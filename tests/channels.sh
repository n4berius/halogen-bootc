#!/bin/bash
# Which channels a release moves, against a made-up list of tags (not this checkout's).
set -euo pipefail
cd "$(dirname "$0")/.."
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
check() {
  printf '%s\n' "${@:3}" > "$work/tags"
  got="$(scripts/channels.sh "$1" "$work/tags")"
  [ "$got" = "$2" ] || { echo "$1 with tags ${*:3}: moved '$got', expected '$2'" >&2; exit 1; }
}
check v0.19.0-alpha.1 "alpha"                        v0.18.23 v0.18.23-alpha.3
check v0.19.0-beta.1  "beta alpha"                   v0.18.23 v0.19.0-alpha.1
check v0.19.0-rc.1    "rc beta alpha"                v0.19.0-alpha.2 v0.19.0-beta.1
check v0.19.0         "stable rc beta alpha"         v0.19.0-rc.1 v0.19.0-alpha.3
check v0.19.0         "stable rc beta"               v0.19.0-rc.1 v0.19.1-alpha.1
check v0.19.0-r2      "stable rc beta alpha"         v0.19.0 v0.19.0-rc.1
check v0.19.1-alpha.1 "alpha"                        v0.19.0
check v0.19.0-alpha.3 ""                             v0.19.0-alpha.4 v0.19.0-beta.1
check v0.18.23        ""                             v0.19.0
check v0.19.0-beta.2  ""                             v0.19.0-beta.10 v0.18.23   # 10 is newer than 2
check v0.19.0-beta.11 "beta alpha"                   v0.19.0-beta.10 v0.19.0-alpha.9 junk v1.0
check v0.19.0-rc.1    "rc beta alpha"                # the tag is not created yet on a manual run
if scripts/channels.sh v0.19 "$work/tags" >/dev/null 2>&1; then echo "accepted a bad tag" >&2; exit 1; fi
echo "ok: a release moves its channel and every less stable one, never backwards"
