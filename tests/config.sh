#!/bin/bash
# The allowlist decides what reaches Halogen.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
export XDG_RUNTIME_DIR="$work/run" HALOGEN_CONFIG_FILE="$work/config"
export HALOGEN_ALLOWED_FILE="$repo/variants/npu/usr/share/halogen/options.allowed"
render="$repo/files/usr/libexec/halogen/render-config"
cat > "$work/config" <<'S'
# a comment
HALOGEN_KV_SLOTS=2
HALOGEN_KV_SLOTS=3
  HALOGEN_TEMPERATURE="1.0"
HALOGEN_API_PORT=9000
HALOGEN_DOWNLOAD=evil/repo
HALOGEN_CHECKPOINT=/tmp/other.hgn
HALOGEN_KV_SLTOS=8
HALOGEN_VISION_TOWER=/models/x
$(touch /tmp/halogen-config-injected)
not a setting
S
out="$("$render" --show 2>"$work/log")"
[ "$(printf '%s\n' "$out")" = "$(printf 'HALOGEN_KV_SLOTS=3\nHALOGEN_TEMPERATURE=1.0')" ] || { echo "unexpected: $out" >&2; exit 1; }
for word in HALOGEN_API_PORT HALOGEN_DOWNLOAD HALOGEN_CHECKPOINT HALOGEN_KV_SLTOS HALOGEN_VISION_TOWER; do
  grep -q "ignored $word" "$work/log" || { echo "no warning for $word" >&2; exit 1; }
done
[ ! -e /tmp/halogen-config-injected ] || { echo "the config ran as shell" >&2; exit 1; }
echo "ok: only allowed settings pass, the last value wins, and the file never runs as shell"

export HALOGEN_ALLOWED_FILE="$repo/variants/no-npu/usr/share/halogen/options.allowed"
echo 'HALOGEN_NPU_MODELS=decider-0.8b' > "$work/config"
[ -z "$("$render" --show 2>/dev/null)" ] || { echo "the no-NPU edition accepted NPU models" >&2; exit 1; }
echo "ok: the no-NPU edition ignores NPU settings"

rm "$work/config"
[ -z "$("$render" --show 2>/dev/null)" ] || exit 1
echo "ok: a missing config falls back to defaults"
