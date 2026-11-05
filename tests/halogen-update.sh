#!/bin/bash
# shellcheck disable=SC2016 # Backticks here are Markdown, not shell.
# The Halogen update script against a made-up upstream, with no network.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"; }

up="$work/upstream"
mkdir -p "$up/deploy/host" "$up/docs"
echo clock > "$up/deploy/host/halogen-fabric-clock"
echo license > "$up/LICENSE.md"
echo notices > "$up/THIRD-PARTY-NOTICES.md"
cat > "$up/docs/FLAGS.md" <<'F'
## Sampling

| Name | Default | What it does |
|---|---|---|
| `HALOGEN_TEMPERATURE` | `0.7` | Sampling temperature. |
| `HALOGEN_AGENT_GUARD` | `off` | A preview: reads tool results on the NPU. |
F
printf '# Changelog\n\n## 9.1.0\n\nNew things.\n\n### Fixed\n\n- A fix. Thanks @someone (#12).\n\n## 9.0.0\n\nOld things.\n' > "$up/CHANGELOG.md"
# A long history after the old version, as upstream's has: reading stops early, which must not fail.
for i in $(seq 1 20000); do echo "- an old change, number $i, with enough text to fill the pipe"; done >> "$up/CHANGELOG.md"
g -C "$up" init -q && g -C "$up" add -A && g -C "$up" commit -qm one && g -C "$up" tag v9.0.0
echo notices2 > "$up/THIRD-PARTY-NOTICES.md"
g -C "$up" commit -qam two && g -C "$up" tag v9.1.0 && g -C "$up" tag v9.2.0-rc.1

here="$work/here"
mkdir -p "$here"
cp -r "$repo/scripts" "$repo/variants" "$repo/versions.env" "$here/"
# Its own starting option lists, so the result does not depend on this checkout's (the update
# workflow runs this test after it has already regenerated them).
for e in npu no-npu; do echo HALOGEN_TEMPERATURE > "$here/variants/$e/usr/share/halogen/options.allowed"; done
sed -i -e 's/^HALOGEN_VERSION=.*/HALOGEN_VERSION=9.0.0/' \
  -e "s/^HALOGEN_SOURCE_COMMIT=.*/HALOGEN_SOURCE_COMMIT=$(g -C "$up" rev-parse v9.0.0)/" "$here/versions.env"
g -C "$here" init -q && g -C "$here" add -A && g -C "$here" commit -qm base

digest="sha256:$(printf '%064d' 7)"
HALOGEN_UPDATE_DIGEST="$digest" "$here/scripts/halogen-update.sh" "$up" "$work/body.md" > /dev/null
# shellcheck source=/dev/null
. "$here/versions.env"
[ "$HALOGEN_VERSION" = 9.1.0 ] || { echo "picked $HALOGEN_VERSION, not the newest release" >&2; exit 1; }
[ "$HALOGEN_DIGEST" = "$digest" ] && [ "$HALOGEN_SOURCE_COMMIT" = "$(g -C "$up" rev-parse v9.1.0)" ]
[ "$HALOGEN_NOTICES_SHA256" = "$(echo notices2 | sha256sum | cut -d' ' -f1)" ]
[ "$HALOGEN_CLOCK_SHA256" = "$(echo clock | sha256sum | cut -d' ' -f1)" ]
[ "$HALOGEN_WEIGHTS_REVISION" = "$(sed -n 's/^HALOGEN_WEIGHTS_REVISION=//p' "$repo/versions.env")" ]
echo "ok: the newest release's pins and hashes are written, and the weights stay pinned"

[ "$(cat "$here/variants/npu/usr/share/halogen/options.allowed")" = "$(printf 'HALOGEN_AGENT_GUARD\nHALOGEN_TEMPERATURE')" ]
[ "$(cat "$here/variants/no-npu/usr/share/halogen/options.allowed")" = HALOGEN_TEMPERATURE ]
echo "ok: options come from the new FLAGS.md, and NPU-only ones stay out of the no-NPU edition"

grep -q '^### Halogen 9.1.0$' "$work/body.md" && grep -q '^#### Fixed$' "$work/body.md"
! grep -q 'Old things' "$work/body.md" || { echo "notes include the old version" >&2; exit 1; }
grep -qF 'Thanks `@someone` (peonist-ai/halogen-flash-server#12)' "$work/body.md" \
  || { echo "upstream @names or #numbers would notify or mislink" >&2; exit 1; }
grep -qF 'added `HALOGEN_AGENT_GUARD`' "$work/body.md"
echo "ok: the description has only the new notes, with mentions and issue numbers made safe"

g -C "$here" commit -qam update
before="$(cat "$here/versions.env")"
HALOGEN_UPDATE_DIGEST="$digest" "$here/scripts/halogen-update.sh" "$up" "$work/again.md" > /dev/null
[ "$before" = "$(cat "$here/versions.env")" ] && [ ! -e "$work/again.md" ]
if HALOGEN_UPDATE_DIGEST=bad "$here/scripts/halogen-update.sh" "$up" "$work/x.md" 9.9.9 >/dev/null 2>&1; then
  echo "accepted a version upstream does not have" >&2; exit 1
fi
echo "ok: nothing changes when already up to date, and an unknown version fails"
