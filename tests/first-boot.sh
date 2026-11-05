#!/bin/bash
# Runs the first-boot fetch against fake podman and hf commands.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/models" "$work/opt"
export FAKE="$work" HELPER_SRC="$repo/files/usr/libexec/halogen/fetch-in-container"

printf 'model embed repo=org/embed revision=abc\nmodel rerank repo=org/rerank revision=def devices=embed\nfile embed devices/d.hnpm 5 %s\nfile rerank rerank.hnpw 5 %s\n' \
  "$(printf hello | sha256sum | cut -d' ' -f1)" "$(printf hello | sha256sum | cut -d' ' -f1)" > "$work/opt/models.txt"

cat > "$work/bin/hf" <<'S'
#!/bin/bash
echo "hf $*" >> "$FAKE/hf.log"
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
      *) mkdir -p "$FAKE/models/npu/9.9.9"
         HALOGEN_PINS="$FAKE/opt/models.txt" HALOGEN_MODELS_ROOT="$FAKE/mount" WEIGHTS_REPO=r WEIGHTS_REVISION=main \
         NPU_MODELS="$FAKE_NPU" VISION="" bash "$HELPER_SRC" ;;
    esac ;;
esac
S
chmod +x "$work/bin/"*
ln -s "$work/models" "$work/mount"
export PATH="$work/bin:$PATH" FAKE_NPU="embed,rerank"
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
  HALOGEN_FETCH_HELPER="$HELPER_SRC" HALOGEN_MODELS_NEEDED_GIB=0 HALOGEN_RETRY_MAX_S=0 HALOGEN_PROGRESS_S=0
sleep() { :; }; export -f sleep
fetch="$repo/files/usr/libexec/halogen/fetch-models"
sed 's/^wait_s=15$/wait_s=0/' "$fetch" > "$work/fetch"; chmod +x "$work/fetch"
ok() { echo "ok: $*"; }

touch "$work/fail-pull" "$work/fail-hf"
"$work/fetch" > "$work/out" 2>&1
[ -f "$work/models/qwen38-flash-next-v2.hgn" ] && [ -f "$work/models/tokenizer/tokenizer.json" ]
[ -f "$work/models/.fetch-stamp" ]
ok "first boot retries, then fetches everything and writes the stamp"
[ -f "$work/models/embed/devices/d.hnpm" ] || [ -f "$work/models/npu/embed/devices/d.hnpm" ]
ok "shared device files of a dependent NPU model are fetched"

: > "$work/podman.log"; "$work/fetch" >/dev/null
if grep -q ' run ' "$work/podman.log"; then echo "second boot ran a container" >&2; exit 1; fi
ok "second boot starts nothing and downloads nothing"

echo 'HALOGEN_NPU_MODELS=embed' > "$work/config.env"
"$work/fetch" >/dev/null
grep -q ' run ' "$work/podman.log"
ok "changing the model list triggers a fetch"

rm "$work/models/.fetch-stamp"; touch "$work/fail-verify"
if "$work/fetch" >/dev/null 2>&1; then echo "verify failure was ignored" >&2; exit 1; fi
[ ! -f "$work/models/.fetch-stamp" ]
ok "a failed checkpoint check keeps the server from starting"
rm "$work/fail-verify"

echo 'HALOGEN_NPU_MODELS=nonsense,embed,Rerank' > "$work/config.env"; export FAKE_NPU=nonsense,embed,Rerank
if "$work/fetch" > "$work/out" 2>&1; then echo "unknown model was accepted" >&2; exit 1; fi
grep -q 'no record of NPU model nonsense' "$work/out" && grep -q 'no record of NPU model Rerank' "$work/out"
grep -q '^fetch:   rerank$' "$work/out"
ok "unknown models are all named, with the valid names, and do not retry forever"

echo 'HALOGEN_NPU_MODELS=' > "$work/config.env"
if HALOGEN_MODELS_NEEDED_GIB=999999999 "$work/fetch" >/dev/null 2>&1; then echo "low disk was accepted" >&2; exit 1; fi
ok "too little disk stops before downloading"
