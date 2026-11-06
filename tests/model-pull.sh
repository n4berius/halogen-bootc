#!/bin/bash
# halogenctl model pull's helper against fake podman, hf and halogen-npu.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/models"
export FAKE="$work"

cat > "$work/bin/podman" <<'S'
#!/bin/bash
# Runs the requested program on the host, with /models mapped to the test's folder.
echo "podman $*" >> "$FAKE/podman.log"
[ "$1" = run ] || exit 0
shift; entry=""
while [ $# -gt 0 ]; do
  case "$1" in
    --entrypoint) entry="$2"; shift 2 ;;
    -v|-e|--tmpfs|--security-opt|--cap-drop|--device|--group-add) shift 2 ;;
    -*) shift ;;
    *) shift; break ;;
  esac
done
args=(); for a in "$@"; do args+=("${a//\/models/$FAKE/models}"); done
case "$entry" in
  hf) dir=""; for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[i]}" != --local-dir ] || dir="${args[i+1]}"; done
      echo "Hint: update hf"; mkdir -p "$dir"; echo '{}' > "$dir/config.json"; echo w > "$dir/model.safetensors" ;;
  /usr/local/bin/halogen-npu) echo "task=generate base=${FAKE_BASE:-lfm3-1.7b}" ;;
  awk) args[${#args[@]}-1]="$FAKE/models.txt"; awk "${args[@]}" ;;
esac
S
chmod +x "$work/bin/podman"
printf 'model lfm3-1.7b repo=a\nmodel lfm3-1.7b-fast repo=a\nmodel d1-2b repo=b\n' > "$work/models.txt"
printf 'HALOGEN_IMAGE=img@sha256:1\nHALOGEN_VARIANT=npu\n' > "$work/release.env"
export PATH="$work/bin:$PATH" HALOGEN_RELEASE_FILE="$work/release.env" HALOGEN_MODELS_DIR="$work/models" \
  HALOGEN_HF_TOKEN_FILE="$work/none" HALOGEN_XRT_DIR="$work/none" HALOGEN_PROGRESS_S=0
pull="$repo/files/usr/libexec/halogen/model-pull"
ok() { echo "ok: $*"; }

out="$("$pull" LiquidAI/LFM3-1.7B 2>&1)"
[ -f "$work/models/LFM/LFM3-1.7B/model.safetensors" ] && [ ! -e "$work/models/.pull" ]
grep -qx 'path=/models/LFM/LFM3-1.7B' <<< "$out" && grep -qx 'fast=1' <<< "$out"
if grep -q 'Hint:' <<< "$out"; then echo "hf noise reached the user" >&2; exit 1; fi
grep -q -- "--exclude \*.gguf" "$work/podman.log"
grep 'halogen-npu' "$work/podman.log" | grep -q -- '--network=none' || { echo "the probe of an untrusted checkpoint had network" >&2; exit 1; }
if grep 'entrypoint hf' "$work/podman.log" | grep -q -- '--network=none'; then echo "the download lost its network" >&2; exit 1; fi
ok "an LFM3 checkpoint lands in LFM, with its path and :fast named, and other formats skipped; only the download has network"

FAKE_BASE=d1-2b "$pull" LiquidAI/d1-2B --as my-d1 --revision abc > "$work/out" 2>&1
[ -d "$work/models/decider/my-d1" ] && grep -qx 'path=/models/decider/my-d1' "$work/out"
if grep -qx 'fast=1' "$work/out"; then echo "offered :fast where none exists" >&2; exit 1; fi
grep -q -- '--revision abc' "$work/podman.log"
ok "a d1-2B lands in decider under the chosen name and revision"

: > "$work/podman.log"
"$pull" LiquidAI/LFM3-1.7B > /dev/null 2>&1
grep -q -- "--local-dir $work/models/LFM/LFM3-1.7B\|--local-dir /models/LFM/LFM3-1.7B" "$work/podman.log"
ok "pulling a name you have updates it in place"

for bad in "nonsense" "a/b --as ../x" "a/b --as .hidden"; do
  # shellcheck disable=SC2086
  if "$pull" $bad > /dev/null 2>&1; then echo "accepted: $bad" >&2; exit 1; fi
done
sed -i 's/=npu/=no-npu/' "$work/release.env"
if "$pull" LiquidAI/LFM3-1.7B > /dev/null 2>&1; then echo "the no-NPU edition pulled an NPU checkpoint" >&2; exit 1; fi
ok "bad repos and names, and the no-NPU edition, are refused"
