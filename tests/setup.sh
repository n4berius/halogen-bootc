#!/bin/bash
# First-boot setup: halosctl setup, the marker prepare leaves on a new install, and the fetch
# waiting for it. Fake runuser, lsblk, cryptsetup, halogen-enroll-tpm and halogenctl.
# shellcheck disable=SC2016 # The fake commands expand their variables when they run.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/state" "$work/configs" "$work/dev"
export FAKE="$work"
f() { printf '#!/bin/bash\n%s\n' "$2" > "$work/bin/$1"; chmod +x "$work/bin/$1"; }
f id 'echo 0'
f runuser 'echo "runuser $*" >> "$FAKE/log"; [ "$1 $2 $3" = "-u halogen --" ] || exit 9; shift 3; exec "$@"'
f lsblk 'printf "%s\n" "${FAKE_LSBLK-/dev/nvme0n1p3 crypto_LUKS}"'
f cryptsetup 'printf "Tokens:\n%s" "${FAKE_TOKENS:-}"'
f halogen-enroll-tpm 'echo "enroll-tpm" >> "$FAKE/log"'
f halogenctl 'echo "halogenctl $*" >> "$FAKE/log"'
f nano 'echo "nano $*" >> "$FAKE/log"'
printf 'HALOGEN_VARIANT=no-npu\n' > "$work/release.env"
export PATH="$work/bin:$PATH" HALOGEN_RELEASE_FILE="$work/release.env" HALOGEN_STATE_DIR="$work/state" HALOGEN_CONFIGS_DIR="$work/configs" HALOGEN_DEV="$work/dev"
ctl="$repo/files/usr/bin/halosctl"
ok() { echo "ok: $*"; }
# Answers the questions through a terminal, one line each.
answer() { printf '%s\n' "$@" > "$work/answers"; : > "$work/log"
  { sleep 1; cat "$work/answers"; } | script -qec "$ctl setup" /dev/null > "$work/out" 2>&1 || true; }

touch "$work/state/setup-pending" "$work/dev/tpmrm0"
answer y n n
grep -qx 'enroll-tpm' "$work/log" || { cat "$work/out" >&2; echo "TPM not enrolled" >&2; exit 1; }
if grep -q 'halogenctl hf-token\|nano' "$work/log"; then echo "a declined step ran" >&2; exit 1; fi
[ ! -e "$work/state/setup-pending" ] || { echo "setup didn't release the download" >&2; exit 1; }
grep -q "runuser -u halogen -- rm -f $work/state/setup-pending" "$work/log" || { echo "the marker was removed as root" >&2; exit 1; }
grep -q 'first download' "$work/out" || exit 1
ok "setup enrolls the TPM when asked, skips declined steps, and releases the first download as halogen"

touch "$work/state/setup-pending"
FAKE_TOKENS='  0: systemd-tpm2' answer y y
grep -q 'unlocks with the TPM already' "$work/out" || { cat "$work/out" >&2; exit 1; }
if grep -q enroll-tpm "$work/log"; then echo "enrolled again" >&2; exit 1; fi
grep -qx 'halogenctl hf-token' "$work/log" || { echo "no token step" >&2; exit 1; }
grep -q "runuser -u halogen -- nano $work/configs/halogen.env" "$work/log" || { echo "the editor didn't run as halogen" >&2; exit 1; }
FAKE_LSBLK='' answer n n
grep -q "isn't encrypted" "$work/out" || exit 1
ok "setup knows an existing TPM binding and an unencrypted disk, and edits settings as halogen"

# Run again later: nothing pending, so it offers a restart instead.
answer n n n y
grep -qx 'halogenctl restart' "$work/log" || { cat "$work/out" >&2; echo "no restart offered" >&2; exit 1; }
touch "$work/state/setup-pending"
"$ctl" setup --skip < /dev/null > "$work/out" 2>&1
[ ! -e "$work/state/setup-pending" ] || { echo "--skip kept the marker" >&2; exit 1; }
if "$ctl" setup < /dev/null > "$work/out" 2>&1; then echo "setup ran without a terminal" >&2; exit 1; fi
grep -q -- '--skip' "$work/out" || exit 1
ok "setup runs again any time, --skip releases the download at once, and without a terminal it says so"

# prepare marks setup pending only on a new install (no halogen.env yet), never on upgrades.
f install 'a=(); while [ $# -gt 0 ]; do case "$1" in -o|-g) shift 2 ;; *) a+=("$1"); shift ;; esac; done; exec /usr/bin/install "${a[@]}"'
f selinuxenabled 'exit 1'
echo 'HALOGEN_FLASH_CTX=1' > "$work/default.env"
rm -rf "$work/configs" "$work/state"; mkdir -p "$work/models"
prep() { HALOGEN_MODELS_DIR="$work/models" HALOGEN_RELEASE_FILE="$work/release.env" HALOGEN_ENV_DEFAULT="$work/default.env" \
  "$repo/files/usr/libexec/halogen/prepare" > /dev/null 2>&1; }
prep
[ -e "$work/state/setup-pending" ] || { echo "a new install got no marker" >&2; exit 1; }
rm "$work/state/setup-pending"; prep
[ ! -e "$work/state/setup-pending" ] || { echo "a later boot marked setup pending again" >&2; exit 1; }
ok "only a new install waits for setup"
