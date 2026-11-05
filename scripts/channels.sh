#!/bin/bash
# Print the release channels a release tag should move, most stable first.
# Usage: scripts/channels.sh v0.19.0-beta.1 [file with one tag per line; default: git tags]
#
# Each channel points to the newest release that is at least that stable: stable < rc < beta
# < alpha in how much each one takes. So a stable release also moves rc, beta and alpha, unless
# one of them already has something newer. A tag that is not the newest for any channel (an
# old release run again) moves none, so a channel never goes backwards.
set -euo pipefail
tag="${1:?usage: channels.sh <tag> [tags-file]}"
if [ -n "${2:-}" ]; then tags="$(cat "$2")"; else tags="$(git -C "$(dirname "$0")/.." tag -l 'v*')"; fi
# sort -V puts 0.19.0-alpha.1 after 0.19.0, so compare explicitly: version, then stage
# (alpha 0, beta 1, rc 2, stable 3), then its number (-rN rebuilds rank above the bare release).
printf '%s\n%s\n' "$tag" "$tags" | awk -v tag="$tag" '
  function key(t,   m, s, n) {
    if (!match(t, /^v[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+|-r[0-9]+)?$/)) return ""
    split(substr(t, 2), m, /[.-]/)
    s = 3; n = 0
    if (m[4] == "alpha") { s = 0; n = m[5] } else if (m[4] == "beta") { s = 1; n = m[5] }
    else if (m[4] == "rc") { s = 2; n = m[5] } else if (m[4] ~ /^r[0-9]+$/) n = substr(m[4], 2)
    stage[t] = s
    return sprintf("%06d.%06d.%06d.%d.%06d", m[1], m[2], m[3], s, n)
  }
  NF { k = key($1); if (k != "") keys[$1] = k }
  END {
    if (!(tag in keys)) { print "bad tag: " tag > "/dev/stderr"; exit 1 }
    split("alpha beta rc stable", name, " ")
    out = ""
    for (c = 3; c >= 0; c--) {
      if (stage[tag] < c) continue
      newest = 1
      for (t in keys) if (stage[t] >= c && keys[t] > keys[tag]) newest = 0
      if (newest) out = out (out == "" ? "" : " ") name[c + 1]
    }
    print out
  }'
