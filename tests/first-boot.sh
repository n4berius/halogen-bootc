#!/bin/bash
# Runs the first-boot fetch against fake podman and hf commands.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/models" "$work/opt"
export FAKE="$work" HELPER_SRC="$repo/files/usr/libexec/halogen/fetch-in-container"

h="$(printf hello | sha256sum | cut -d' ' -f1)"
cat > "$work/opt/models.txt" <<S
model embed repo=org/embed revision=abc
model rerank repo=org/rerank revision=def devices=embed
model lfm3 repo=org/lfm3 revision=x
model lfm3-fast repo=org/lfm3-fast revision=y
file embed devices/d.hnpm 5 $h
file embed embed.hnpw 5 $h
file lfm3-fast devices/f.hnpm 5 $h
file rerank rerank.hnpw 5 $h
file lfm3 devices/p.hnpm 5 $h
file lfm3 lfm3.hnpw 5 $h
model lfm3-vl repo=org/lfm3-vl revision=z devices=lfm3
file lfm3-vl vis/v.hnpm 5 $h
file lfm3-vl lfm3-vl.hnpw 5 $h
model lfm3-omni repo= revision= devices=lfm3 vis=lfm3-vl
S

cat > "$work/bin/hf" <<'S'
#!/bin/bash
echo "hf $*" >> "$FAKE/hf.log"
echo "Hint: A new version of huggingface_hub (9.9) is available!" >&2
echo "Warning: You are sending unauthenticated requests to the HF Hub." >&2
[ ! -e "$FAKE/fail-hf" ] || { rm "$FAKE/fail-hf"; exit 1; }
shift; repo="$1"; shift; dest=""; files=()
while [ $# -gt 0 ]; do case "$1" in
  --local-dir) dest="$2"; shift 2 ;; --revision|--include) [ "$1" != --include ] || files+=("tokenizer/tokenizer.json"); shift 2 ;;
  *) files+=("$1"); shift ;; esac; done
for f in "${files[@]}"; do mkdir -p "$(dirname "$dest/$f")"; printf hello > "$dest/$f"; done
S
cat > "$work/bin/podman" <<'S'
#!/bin/bash
echo "podman $*" >> "$FAKE/podman.log"
case "$1" in
  image) [ -e "$FAKE/image-present" ] ;;
  pull) [ ! -e "$FAKE/fail-pull" ] || { rm "$FAKE/fail-pull"; exit 1; }; touch "$FAKE/image-present" ;;
  run)
    case " $* " in
      *" verify "*) [ ! -e "$FAKE/fail-verify" ] ;;
      *) echo "$*" > "$FAKE/last-run"
         npu=""; for a in "$@"; do case "$a" in NPU_MODELS=*) npu="${a#NPU_MODELS=}" ;; esac; done
         HALOGEN_PINS="$FAKE/opt/models.txt" HALOGEN_MODELS_ROOT="$FAKE/mount" WEIGHTS_REPO=r WEIGHTS_REVISION=main \
         HALOGEN_NPU_BIN="$FAKE/bin/halogen-npu" \
         NPU_MODELS="$npu" VISION="" bash "$HELPER_SRC" ;;
    esac ;;
esac
S
cat > "$work/bin/halogen-npu" <<'S'
#!/bin/bash
# Halogen's probe names the model a checkpoint was tuned from.
[ "$1" = probe ] && [ -f "$2/config.json" ] && echo "task=generate base=$(cat "$2/base" 2>/dev/null || echo lfm3)"
S
chmod +x "$work/bin/"*
ln -s "$work/models" "$work/mount"
export PATH="$work/bin:$PATH"
cat > "$work/release.env" <<'S'
HALOGEN_IMAGE=ghcr.io/x@sha256:1
HALOGEN_VERSION=9.9.9
HALOGEN_WEIGHTS_REPO=r
HALOGEN_WEIGHTS_REVISION=main
S
echo 'HALOGEN_NPU_MODELS=embed,rerank' > "$work/config.env"
echo HALOGEN_NPU_MODELS > "$work/allowed"
export XDG_RUNTIME_DIR="$work/run" HALOGEN_ALLOWED_FILE="$work/allowed" HALOGEN_RENDER="$repo/files/usr/libexec/halogen/render-config"
export HALOGEN_RELEASE_FILE="$work/release.env" HALOGEN_CONFIG_FILE="$work/config.env" HALOGEN_MODELS_DIR="$work/models" \
  HALOGEN_FETCH_HELPER="$HELPER_SRC" HALOGEN_MODELS_NEEDED_GIB=0 HALOGEN_RETRY_MAX_S=0 HALOGEN_PROGRESS_S=0 HALOGEN_HF_TOKEN_FILE="$work/hf-token"
sleep() { :; }; export -f sleep
fetch="$repo/files/usr/libexec/halogen/fetch-models"
sed 's/^wait_s=15$/wait_s=0/' "$fetch" > "$work/fetch"; chmod +x "$work/fetch"
ok() { echo "ok: $*"; }

touch "$work/fail-pull" "$work/fail-hf"
"$work/fetch" > "$work/out" 2>&1 || { cat "$work/out" >&2; exit 1; }
[ -f "$work/models/qwen38-flash-next-v2.hgn" ] && [ -f "$work/models/tokenizer/tokenizer.json" ]
[ -f "$work/models/.fetch-stamp" ]
ok "first boot retries, then fetches everything and writes the stamp"
if grep -q 'Hint: \|unauthenticated requests' "$work/out"; then echo "hf noise reached the log" >&2; exit 1; fi
grep -q 'no Hugging Face token' "$work/out"
ok "hf's upgrade hints are filtered, and a missing token is explained once"
[ -f "$work/models/embed/devices/d.hnpm" ] || [ -f "$work/models/npu/embed/devices/d.hnpm" ]
ok "shared device files of a dependent NPU model are fetched"

: > "$work/podman.log"; "$work/fetch" >/dev/null
if grep -q ' run ' "$work/podman.log"; then echo "second boot ran a container" >&2; exit 1; fi
ok "second boot starts nothing and downloads nothing"

echo 'HALOGEN_NPU_MODELS=embed' > "$work/config.env"
"$work/fetch" >/dev/null
grep -q ' run ' "$work/podman.log"
ok "changing the model list triggers a fetch"

echo 'hf_secret123' > "$work/hf-token"; rm "$work/models/.fetch-stamp"; : > "$work/podman.log"
"$work/fetch" > "$work/out" 2>&1 || { cat "$work/out" >&2; exit 1; }
grep -q "$work/hf-token:/run/secrets/hf-token:ro" "$work/podman.log" && grep -q 'HF_TOKEN_PATH=/run/secrets/hf-token' "$work/podman.log"
if grep -q hf_secret123 "$work/podman.log" "$work/out"; then echo "the token leaked into a command line or log" >&2; exit 1; fi
rm "$work/hf-token"
ok "a Hugging Face token is passed as a read-only file, never as a value"

rm "$work/models/.fetch-stamp"; touch "$work/fail-verify"
if "$work/fetch" >/dev/null 2>&1; then echo "verify failure was ignored" >&2; exit 1; fi
[ ! -f "$work/models/.fetch-stamp" ]
ok "a failed checkpoint check keeps the server from starting"
rm "$work/fail-verify"

echo 'HALOGEN_NPU_MODELS=nonsense,embed,Rerank' > "$work/config.env"
if "$work/fetch" > "$work/out" 2>&1; then echo "unknown model was accepted" >&2; exit 1; fi
grep -q 'no record of NPU model nonsense' "$work/out" && grep -q 'no record of NPU model Rerank' "$work/out"
grep -q '^fetch:   rerank$' "$work/out"
ok "unknown models are all named, with the valid names, and do not retry forever"

echo 'HALOGEN_NPU_MODELS=' > "$work/config.env"
if HALOGEN_MODELS_NEEDED_GIB=999999999 "$work/fetch" >/dev/null 2>&1; then echo "low disk was accepted" >&2; exit 1; fi
ok "too little disk stops before downloading"

echo 'HALOGEN_NPU_MODELS=embed' > "$work/config.env"; echo HALOGEN_AGENT_GUARD >> "$work/allowed"
echo 'HALOGEN_AGENT_GUARD=Hold' >> "$work/config.env"
"$work/fetch" > "$work/out" 2>&1 || true
grep -q 'NPU_MODELS=embed,halogen-spotter-0.6b,decider-4b' "$work/podman.log" \
  || { echo "the agent guard's models were not fetched" >&2; exit 1; }
ok "the agent guard's models are fetched when it is turned on"

echo 'HALOGEN_NPU_MODELS=embed' > "$work/config.env"
rm -rf "$work/models/npu" "$work/models/.fetch-stamp"
mkdir -p "$work/models/npu/9.9.9/embed/devices" "$work/models/npu/9.9.8/embed/devices" "$work/models/npu/9.9.8/old"
printf hello > "$work/models/npu/9.9.9/embed/devices/d.hnpm"; printf hello > "$work/models/npu/9.9.9/embed/embed.hnpw"; printf stale > "$work/models/npu/9.9.8/embed/devices/d.hnpm"
: > "$work/hf.log"
"$work/fetch" > "$work/out" 2>&1 || { cat "$work/out" >&2; exit 1; }
[ "$(cat "$work/models/npu/embed/devices/d.hnpm")" = hello ] || { echo "the current version's copy did not win" >&2; exit 1; }
[ -d "$work/models/npu/old" ] || { echo "a model only in an old version folder was lost" >&2; exit 1; }
if [ -e "$work/models/npu/9.9.9" ] || [ -e "$work/models/npu/9.9.8" ]; then echo "version folders were left behind" >&2; exit 1; fi
if grep -q org/embed "$work/hf.log"; then echo "a moved model was downloaded again" >&2; exit 1; fi
ok "versioned NPU folders move into one folder, the current version's copy wins, and nothing is fetched again"

mkdir -p "$work/models/LFM/mine"; echo '{}' > "$work/models/LFM/mine/config.json"
echo 'HALOGEN_NPU_MODELS=embed,/models/LFM/mine:fast,/models/LFM/mine' > "$work/config.env"
: > "$work/hf.log"
"$work/fetch" > "$work/out" 2>&1 || { cat "$work/out" >&2; exit 1; }
[ -f "$work/models/npu/lfm3/devices/p.hnpm" ] || { echo "the checkpoint's NPU programs were not fetched" >&2; exit 1; }
[ -f "$work/models/npu/lfm3-fast/devices/f.hnpm" ] || { echo "the :fast format's NPU programs were not fetched" >&2; exit 1; }
if [ -e "$work/models/npu/lfm3/lfm3.hnpw" ]; then echo "weights were fetched for your own checkpoint" >&2; exit 1; fi
grep -q 'mine is a lfm3' "$work/out" || { echo "the fetch did not say what the checkpoint is" >&2; exit 1; }
ok "your own checkpoint gets its NPU programs fetched, and no weights"

: > "$work/podman.log"; "$work/fetch" >/dev/null 2>&1
if grep -q ' run ' "$work/podman.log"; then echo "an unchanged checkpoint ran the fetch again" >&2; exit 1; fi
echo '{"changed": 1}' > "$work/models/LFM/mine/config.json"
"$work/fetch" >/dev/null 2>&1
grep -q ' run ' "$work/podman.log" || { echo "a changed checkpoint was not checked again" >&2; exit 1; }
ok "a changed checkpoint is checked again"

echo 'HALOGEN_NPU_MODELS=/models/LFM/missing' > "$work/config.env"
if "$work/fetch" > "$work/out" 2>&1; then echo "a missing checkpoint folder was accepted" >&2; exit 1; fi
grep -q 'not a checkpoint folder' "$work/out" || { echo "a missing checkpoint folder was not explained" >&2; exit 1; }
grep -q 'fix /srv/configs/halogen.env' "$work/out" || { echo "the fetch did not say what to fix" >&2; exit 1; }
ok "a missing checkpoint folder is explained and not retried forever"

echo 'HALOGEN_NPU_MODELS=rerank' > "$work/config.env"
rm -rf "$work/models/npu" "$work/models/.fetch-stamp"
"$work/fetch" > "$work/out" 2>&1 || { cat "$work/out" >&2; exit 1; }
[ -f "$work/models/npu/rerank/rerank.hnpw" ] || { echo "rerank was not fetched" >&2; exit 1; }
[ -f "$work/models/npu/embed/devices/d.hnpm" ] || { echo "the programs rerank runs on were not fetched" >&2; exit 1; }
if [ -e "$work/models/npu/embed/embed.hnpw" ]; then echo "the other model's weights were fetched too" >&2; exit 1; fi
ok "a model that runs on another's NPU programs fetches only those programs"

# Some of Halogen's models have no download of their own and reuse others' programs, as
# LFM3-Omni-2B does in 0.19.0. Your own checkpoint of one gets those programs.
mkdir -p "$work/models/LFM/omni"; echo '{}' > "$work/models/LFM/omni/config.json"; echo lfm3-omni > "$work/models/LFM/omni/base"
echo 'HALOGEN_NPU_MODELS=/models/LFM/omni' > "$work/config.env"
rm -rf "$work/models/npu" "$work/models/.fetch-stamp"
"$work/fetch" > "$work/out" 2>&1 || { cat "$work/out" >&2; exit 1; }
[ -f "$work/models/npu/lfm3/devices/p.hnpm" ] || { echo "the programs it runs on were not fetched" >&2; exit 1; }
[ -f "$work/models/npu/lfm3-vl/vis/v.hnpm" ] || { echo "its picture programs were not fetched" >&2; exit 1; }
if [ -e "$work/models/npu/lfm3-vl/lfm3-vl.hnpw" ]; then echo "another model's weights were fetched" >&2; exit 1; fi
ok "a checkpoint whose model has no download of its own gets the programs it reuses"
