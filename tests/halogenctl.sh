#!/bin/bash
# halogenctl's root-side handling of files the halogen user owns (security audit P1/P2):
# every read and write in /srv/configs goes through runuser, and a crafted HALOGEN_NPU_MODELS
# value in halogen.env can't make root run anything. Fake runuser, systemctl and systemd-run.
# shellcheck disable=SC2016 # The fake commands expand their variables when they run.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/configs"
export FAKE="$work"
f() { printf '#!/bin/bash\n%s\n' "$2" > "$work/bin/$1"; chmod +x "$work/bin/$1"; }
# runuser -u halogen -- cmd...: log it, then run cmd (as this user; the test checks the routing).
f runuser 'echo "runuser $*" >> "$FAKE/log"; [ "$1 $2 $3" = "-u halogen --" ] || exit 9; shift 3; exec "$@"'
f systemctl 'echo "systemctl $*" >> "$FAKE/log"'
# model-pull and render-config, run through systemd-run as halogen.
f systemd-run 'case "$*" in
  *model-pull*) echo "path=/models/LFM/LFM3-1.7B"; echo "fast=1" ;;
  *render-config*) grep "^HALOGEN_NPU_MODELS=" "$FAKE/configs/halogen.env" || true ;;
esac'
export PATH="$work/bin:$PATH" HALOGEN_CONFIGS_DIR="$work/configs"
ctl="$repo/files/usr/bin/halogenctl"
ok() { echo "ok: $*"; }

echo secret-key > "$work/configs/api-key"
if ! { [ "$("$ctl" api-key)" = secret-key ] && grep -q "runuser -u halogen -- cat $work/configs/api-key" "$work/log"; }; then
  echo "api-key was not read as halogen" >&2; exit 1
fi
printf 'hf_abc123\n' | "$ctl" hf-token > /dev/null
if ! { [ "$(cat "$work/configs/hf-token")" = hf_abc123 ] && grep -q 'runuser -u halogen -- sh -c' "$work/log"; }; then
  echo "hf-token was not written as halogen" >&2; exit 1
fi
"$ctl" hf-token --remove > /dev/null; [ ! -e "$work/configs/hf-token" ]
ok "the API key and HF token are read and written as halogen"

# The audit's reproduction: a HALOGEN_NPU_MODELS value built to run a command through sed's e flag.
printf 'HALOGEN_FLASH_CTX=1\nHALOGEN_NPU_MODELS=a touch %s/pwned|e;#\n' "$work" > "$work/configs/halogen.env"
chmod 0640 "$work/configs/halogen.env"
: > "$work/log"
printf 'y\n' > "$work/answer"
{ sleep 2; cat "$work/answer"; } | script -qec "$ctl model pull LiquidAI/LFM3-1.7B" /dev/null > "$work/out" 2>&1 || true
[ ! -e "$work/pwned" ] || { echo "a value in halogen.env ran a command as root" >&2; exit 1; }
grep -qx 'HALOGEN_NPU_MODELS=a touch .*pwned|e;#,/models/LFM/LFM3-1.7B' "$work/configs/halogen.env" \
  || { echo "the new model was not added as plain text:" >&2; cat "$work/configs/halogen.env" "$work/out" >&2; exit 1; }
grep -qx 'HALOGEN_FLASH_CTX=1' "$work/configs/halogen.env" || { echo "other settings were lost" >&2; exit 1; }
[ "$(stat -c %a "$work/configs/halogen.env")" = 640 ] || { echo "halogen.env lost its 0640 mode" >&2; exit 1; }
grep -q 'runuser -u halogen -- sh -c' "$work/log" || { echo "halogen.env was not edited as halogen" >&2; exit 1; }
grep -q 'systemctl --user --machine=halogen@.host restart halogen.service' "$work/log"
ok "model pull edits halogen.env as halogen, and a crafted value stays plain text"

printf 'HALOGEN_FLASH_CTX=1\n' > "$work/configs/halogen.env"
{ sleep 2; cat "$work/answer"; } | script -qec "$ctl model pull LiquidAI/LFM3-1.7B" /dev/null > "$work/out" 2>&1 || true
[ "$(tail -n 1 "$work/configs/halogen.env")" = 'HALOGEN_NPU_MODELS=/models/LFM/LFM3-1.7B' ] \
  || { echo "no HALOGEN_NPU_MODELS line was added:" >&2; cat "$work/configs/halogen.env" >&2; exit 1; }
ok "model pull adds HALOGEN_NPU_MODELS when the file has none"

# model remove deletes as halogen, so a folder link planted by a container can't steer root's rm.
mkdir -p "$work/models/LFM/old-model"; echo w > "$work/models/LFM/old-model/x"
: > "$work/log"
{ sleep 2; echo y; } | HALOGEN_MODELS_DIR="$work/models" script -qec "$ctl model remove old-model" /dev/null > "$work/out" 2>&1 || true
[ ! -e "$work/models/LFM/old-model" ] || { echo "model remove didn't delete:" >&2; cat "$work/out" >&2; exit 1; }
grep -q "runuser -u halogen -- rm -rf -- $work/models/LFM/old-model" "$work/log" || { echo "model remove deleted as root" >&2; exit 1; }
ok "model remove deletes as halogen"

# model list: a clear "none yet" with no own checkpoints, then Halogen's NPU models one per line.
rm -rf "$work/models"; mkdir -p "$work/models/npu/d3-lite" "$work/models/npu/qwen3.5-2b" "$work/models/LFM" "$work/models/decider" "$work/models/custom"
printf 'HALOGEN_NPU_MODELS=qwen3.5-2b:fast\n' > "$work/configs/halogen.env"
HALOGEN_MODELS_DIR="$work/models" "$ctl" model list > "$work/out"
grep -q '^  None yet\. Add one with: sudo halogenctl model pull' "$work/out" || { cat "$work/out" >&2; echo "no 'none yet' line" >&2; exit 1; }
if ! grep -qE '^  d3-lite +no$' "$work/out" || ! grep -qE '^  qwen3\.5-2b +yes$' "$work/out"; then
  cat "$work/out" >&2; echo "NPU models not one per line with IN USE" >&2; exit 1
fi
mkdir -p "$work/models/LFM/my-lfm"; printf 'HALOGEN_NPU_MODELS=/models/LFM/my-lfm\n' > "$work/configs/halogen.env"
HALOGEN_MODELS_DIR="$work/models" "$ctl" model > "$work/out"
if ! grep -qE '^  NAME +FOLDER +SIZE +IN USE$' "$work/out" || ! grep -qE '^  my-lfm +LFM +[0-9.]+[KMG]? +yes$' "$work/out"; then
  cat "$work/out" >&2; echo "own checkpoint not listed" >&2; exit 1
fi
if grep -q 'None yet' "$work/out"; then echo "said none with a checkpoint present" >&2; exit 1; fi
ok "model list is readable: own checkpoints with size and use, then Halogen's models one per line"
