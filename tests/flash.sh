#!/bin/bash
# halogenctl flash pull and verify's helper against fake podman (hf, Python, Halogen's tools).
# shellcheck disable=SC2016 # The fake commands expand their variables when they run.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/models/tokenizer" "$work/repo/tokenizer"
export FAKE="$work"
echo '{"official": true}' > "$work/models/tokenizer/tokenizer.json"

# The fake repository: its files, and the listing Hugging Face would give for them.
commit=0123456789abcdef0123456789abcdef01234567
put() { mkdir -p "$(dirname "$work/repo/$1")"; printf '%s' "$2" > "$work/repo/$1"; }
listing() {
  echo "commit $commit"
  (cd "$work/repo" && find . -type f | sed 's|^\./||' | sort) | while read -r f; do
    case "$f" in *.hgn) sha="$(sha256sum "$work/repo/$f" | cut -d' ' -f1)" ;; *) sha=- ;; esac
    echo "file $f $(stat -c %s "$work/repo/$f") $sha"
  done
}
reset_repo() {
  rm -rf "$work/repo"; mkdir -p "$work/repo"
  put model.hgn checkpoint; put qwen38-flash-next-ngram.hgn table; put qwen38-flash-next-vision.hgn eyes
  put tokenizer/tokenizer.json '{"custom": true}'; put README.md hello; put model.safetensors.bin pickle
}

cat > "$work/bin/podman" <<'S'
#!/bin/bash
# Plays the pinned image: /models is the test's folder, and the entrypoint picks the tool.
echo "podman $*" >> "$FAKE/podman.log"
[ "$1" = run ] || exit 0
shift; entry=""
while [ $# -gt 0 ]; do
  case "$1" in
    --entrypoint) entry="$2"; shift 2 ;;
    -v|-e|--tmpfs|--security-opt|--cap-drop|--device|--group-add|--ulimit) shift 2 ;;
    -*) shift ;;
    *) shift; break ;;
  esac
done
case "$entry" in
  python3) cat > /dev/null; if [ -n "${FAKE_HUB_ERROR:-}" ]; then echo "error $FAKE_HUB_ERROR"; else cat "$FAKE/listing"; fi ;;
  hf) shift; shift; files=(); dir=""; rev=""
      while [ $# -gt 0 ]; do case "$1" in
        --local-dir) dir="${2/\/models/$FAKE/models}"; shift 2 ;; --revision) rev="$2"; shift 2 ;;
        *) files+=("$1"); shift ;; esac; done
      echo "hf $rev ${files[*]}" >> "$FAKE/hf.log"
      echo "Hint: update hf"
      for f in "${files[@]}"; do mkdir -p "$(dirname "$dir/$f")"; cp "$FAKE/repo/$f" "$dir/$f"; done
      [ -z "${FAKE_CORRUPT:-}" ] || printf 'x' >> "$dir/$FAKE_CORRUPT" ;;
  /usr/local/bin/flash_serve) echo "loading"; echo "${FAKE_FACTS-61.2 0 1}" ;;
  "") [ "$1" = verify ] || exit 9; echo "verify $2" >> "$FAKE/verify.log"
      case "$2" in *"${FAKE_BAD:-none}"*) echo "FAIL $2"; exit 1 ;; *) echo "PASS $2" ;; esac ;;
  *) exit 9 ;;
esac
S
cat > "$work/bin/df" <<'S'
#!/bin/bash
printf 'Avail\n%s\n' "${FAKE_FREE:-999999999999}"
S
chmod +x "$work/bin/podman" "$work/bin/df"
printf 'HALOGEN_IMAGE=img@sha256:1\nHALOGEN_VERSION=9.9.9\nHALOGEN_VARIANT=no-npu\n' > "$work/release.env"
export PATH="$work/bin:$PATH" HALOGEN_RELEASE_FILE="$work/release.env" HALOGEN_MODELS_DIR="$work/models" \
  HALOGEN_HF_TOKEN_FILE="$work/none" HALOGEN_PROGRESS_S=0
tool="$repo/files/usr/libexec/halogen/flash-checkpoint"
ok() { echo "ok: $*"; }
fail() { echo "$*" >&2; [ ! -f "$work/out" ] || cat "$work/out" >&2; exit 1; }
info() { sed -n "s/^$2=//p" "$work/models/flash/$1/halos.info"; }
pull() { listing > "$work/listing"; : > "$work/hf.log"; : > "$work/verify.log"; "$tool" pull "$@" > "$work/out" 2>&1; }

reset_repo
pull someone/My-Flash-HGN --as mine || fail "a good pull failed"
d="$work/models/flash/mine"
{ [ "$(cat "$d/model.hgn")" = checkpoint ] && [ "$(cat "$d/qwen38-flash-next-ngram.hgn")" = table ]; } || fail "files missing"
{ [ -f "$d/qwen38-flash-next-vision.hgn" ] && grep -q custom "$d/tokenizer/tokenizer.json"; } || fail "vision or tokenizer missing"
{ [ ! -e "$d/README.md" ] && [ ! -e "$d/model.safetensors.bin" ]; } || fail "files Halogen doesn't load were downloaded"
grep -qx "hf $commit model.hgn qwen38-flash-next-vision.hgn tokenizer/tokenizer.json" "$work/hf.log" || fail "not fetched at the exact commit: $(cat "$work/hf.log")"
{ [ "$(info mine repo)" = someone/My-Flash-HGN ] && [ "$(info mine commit)" = "$commit" ] && [ "$(info mine checkpoint)" = model.hgn ]; } || fail "info wrong"
{ [ "$(info mine verified)" = pass ] && [ "$(info mine verified_with)" = 9.9.9 ]; } || fail "verify not recorded"
{ grep -qx "verify /models/flash/mine/model.hgn" "$work/verify.log" && grep -q ngram "$work/verify.log"; } || fail "not every file verified"
grep -qx 'name=mine' "$work/out" || fail "no name line"
if grep -q '^Hint' "$work/out"; then fail "hf noise reached the output"; fi
grep 'podman run' "$work/podman.log" | grep ' verify ' | grep -q -- '--network=none --cap-drop=all' || fail "verify was not offline and without capabilities"
grep 'podman run' "$work/podman.log" | grep -- '--entrypoint hf' | grep -q -- '--cap-drop=all' || fail "the download kept capabilities"
ok "a pull fetches only what Halogen loads, at the exact commit, checks it and records it"

# A checkpoint that carries its own lookup table doesn't need the 48 GB file.
FAKE_FACTS='61.2 1 1' pull someone/My-Flash-HGN --as own-table || fail "pull failed"
[ ! -e "$work/models/flash/own-table/qwen38-flash-next-ngram.hgn" ] || fail "the table was downloaded though the checkpoint carries one"
rm "$work/repo/qwen38-flash-next-ngram.hgn"
if FAKE_FACTS='61.2 0 1' pull someone/No-Table --as no-table; then fail "a checkpoint with no table anywhere was accepted"; fi
grep -q 'needs a lookup table' "$work/out" || fail "no explanation"
ok "the lookup table is fetched only when the checkpoint needs it, and a missing one is refused"

reset_repo; rm -r "$work/repo/tokenizer"
pull someone/No-Tokenizer --as no-tok || fail "pull failed"
{ grep -q official "$work/models/flash/no-tok/tokenizer/tokenizer.json" && [ ! -L "$work/models/flash/no-tok/tokenizer" ]; } || fail "official tokenizer not copied"
ok "a repository without a tokenizer gets a copy of the official one"

reset_repo
if FAKE_CORRUPT=model.hgn pull someone/Corrupt --as corrupt; then fail "a file with the wrong hash was accepted"; fi
{ grep -q "does not match" "$work/out" && [ ! -f "$work/models/flash/corrupt/halos.info" ]; } || fail "a bad file was recorded"
if FAKE_BAD=model.hgn pull someone/Bad --as bad; then fail "a file that fails verify was accepted"; fi
[ "$(info bad verified)" = fail ] || fail "the failed verify was not recorded"
ok "a file that differs from the repository or fails Halogen's verify can't be used"

put other.hgn second
if pull someone/Two; then fail "an ambiguous repository was accepted"; fi
grep -q 'several checkpoints.*model.hgn.*other.hgn' "$work/out" || fail "the choices were not listed"
pull someone/Two --file other.hgn --as two || fail "--file was refused"
{ [ "$(info two checkpoint)" = other.hgn ] && [ ! -e "$work/models/flash/two/model.hgn" ]; } || fail "the wrong checkpoint was fetched"
rm -rf "$work/repo"; mkdir -p "$work/repo"; put Model-Q4-00001-of-00002.gguf g
if pull someone/Gguf; then fail "a GGUF repository was accepted"; fi
grep -q "GGUF" "$work/out" || fail "no GGUF explanation"
ok "several checkpoints need --file, and GGUF repositories are explained"

reset_repo
for bad in '--as ../x' '--as official' '--as .hidden' '--revision -x' "--as a;b"; do
  # shellcheck disable=SC2086 # split on purpose: option and value
  if pull someone/Good $bad; then fail "accepted: $bad"; fi
done
if pull 'some one/x'; then fail "a bad repository name was accepted"; fi
if pull someone/Other --as mine; then fail "a name holding another repository was reused"; fi
grep -q 'already holds someone/My-Flash-HGN' "$work/out" || fail "no explanation"
{ [ ! -e "$work/models/flash/x" ] && [ ! -e "$work/models/x" ]; } || fail "something was created outside"
ok "names and revisions are checked, and a name holding another repository isn't overwritten"

if FAKE_FREE=1000 pull someone/Big --as big; then fail "a pull with no room was started"; fi
{ grep -q 'more and .* free' "$work/out" && [ ! -s "$work/hf.log" ]; } || fail "it downloaded before checking the room"
if FAKE_HUB_ERROR='401 Client Error' pull someone/Private --as private; then fail "a hub error was ignored"; fi
grep -q 'hf-token' "$work/out" || fail "no hint about a token"
ok "the free space is checked before the first byte, and hub errors are explained"

: > "$work/verify.log"
FAKE_BAD=model.hgn "$tool" verify bad > "$work/out" 2>&1 && fail "verify of a bad file passed"
[ "$(info bad verified)" = fail ]
"$tool" verify mine > "$work/out" 2>&1 || fail "verify of a good file failed"
{ [ "$(info mine verified)" = pass ] && [ "$(grep -c . "$work/verify.log")" -ge 3 ]; } || fail "verify again did not check every file"
"$tool" verify ../mine > "$work/out" 2>&1 && fail "verify took a path"
ok "verify checks a pulled checkpoint again and records the answer"
