#!/bin/bash
# The login screen and SSH status line, against fake systemctl, curl, du, halosctl and wall.
# shellcheck disable=SC2016 # The fake commands expand their variables when they run.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/models" "$work/run"
export FAKE="$work"
f() { printf '#!/bin/bash\n%s\n' "$2" > "$work/bin/$1"; chmod +x "$work/bin/$1"; }
f systemctl 'case "$*" in *halogen-fetch*) echo "${FAKE_FETCH:-inactive}" ;; *) echo "${FAKE_SERVER:-inactive}" ;; esac'
f curl 'echo "curl $*" >> "$FAKE/log"; printf "%s" "${FAKE_HEALTH:-000}"'
f runuser 'echo "runuser $*" >> "$FAKE/log"; [ "$1 $2 $3" = "-u halogen --" ] || exit 9; shift 3; exec "$@"'
f du 'printf "%s\t%s\n" "${FAKE_HAVE:-0}" "$*"'
f df 'printf "Avail\n 900\n"'
f halosctl 'echo "halosctl $*" >> "$FAKE/log"; printf "halOS x\nChannel:   edge\nHalogen:   0.19.1 (img)\nImage:     y\nNext boot: no change staged\nRollback:  z\n"'
f agetty 'echo "agetty $*" >> "$FAKE/log"'
f wall 'echo "wall $*" >> "$FAKE/log"'
f hostname 'echo freyja'
printf 'HALOS_RELEASE=0.19.1-beta.1\nHALOGEN_VARIANT=npu\n' > "$work/release.env"
export PATH="$work/bin:$PATH" HALOGEN_RELEASE_FILE="$work/release.env" HALOGEN_MODELS_DIR="$work/models" HALOS_RUN_DIR="$work/run"
status="$repo/files/usr/libexec/halogen/login-status"
issue="$work/run/issue.d/50-halos.issue"; motd="$work/run/motd.d/50-halos"
ok() { echo "ok: $*"; }
expect() { grep -qF -- "$2" "$1" || { echo "expected '$2' in $1:" >&2; cat "$1" >&2; exit 1; }; }
run() { : > "$work/log"; "$status" || { echo "login-status failed" >&2; exit 1; }; }

FAKE_FETCH=activating FAKE_HAVE=50 run
expect "$issue" 'halOS 0.19.1-beta.1 (npu edition) - downloading models 40%'
grep -q 'runuser -u halogen -- du' "$work/log" || { echo "du ran as root" >&2; exit 1; }
grep -q 'agetty --reload' "$work/log" || { echo "the login prompt was not redrawn" >&2; exit 1; }
FAKE_FETCH=activating FAKE_HAVE=50 run
if grep -q agetty "$work/log"; then echo "redrawn though nothing changed" >&2; exit 1; fi
touch "$work/models/.fetch-stamp"; FAKE_FETCH=activating run
expect "$issue" '- checking models'
FAKE_FETCH=failed run
expect "$issue" 'download failed: sudo halogenctl fetch-logs'
FAKE_SERVER=activating run
expect "$issue" '- starting'
FAKE_SERVER=active FAKE_HEALTH=503 run
expect "$issue" '- starting'
ok "the console line follows the download, the check and the start, and redraws only on a change"

FAKE_SERVER=active FAKE_HEALTH=200 run
expect "$issue" '- ready: http://\4:8731/v1'
expect "$motd" 'ready: http://freyja:8731/v1'
expect "$motd" 'Channel:   edge'
expect "$motd" '900 GiB free'
if grep -qE 'Image:|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$motd"; then echo "the SSH message shows more than it should" >&2; exit 1; fi
grep -q 'wall halOS: Halogen is ready at http://freyja:8731/v1' "$work/log" || { echo "no ready notice" >&2; exit 1; }
FAKE_SERVER=active FAKE_HEALTH=200 run
if grep -q wall "$work/log"; then echo "the ready notice repeated" >&2; exit 1; fi
if grep -q halosctl "$work/log"; then echo "halosctl ran again within 10 minutes" >&2; exit 1; fi
ok "ready shows the address on the console, the name over SSH, and is announced once"

FAKE_SERVER=failed run
expect "$issue" 'stopped: sudo halogenctl logs'
FAKE_SERVER=inactive run
expect "$issue" 'stopped: sudo halogenctl logs'
grep -q 'curl' "$work/log" && { echo "asked a stopped server for its health" >&2; exit 1; }
ok "a stopped or failed Halogen says where to look"
