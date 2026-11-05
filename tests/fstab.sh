#!/bin/bash
# fstab-needs-ro decides whether bootc-fstab-edit.service still has work (bootc-dev/bootc#2592).
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
check() {  # want-exit fstab-text
  printf '%b' "$2" > "$work/fstab"
  "$repo/files/usr/libexec/halogen/fstab-needs-ro" "$work/fstab" && got=0 || got=$?
  [ "$got" = "$1" ] || { echo "fstab-needs-ro gave $got, wanted $1, for:" >&2; cat "$work/fstab" >&2; exit 1; }
}
check 1 'UUID=7e84332e / xfs ro,x-systemd.device-timeout=0 0 0\n'     # as Anaconda writes it (freyja's line)
check 0 'UUID=a / xfs defaults,x-systemd.device-timeout=0 0 0\n'       # without ro: bootc's edit still runs
check 0 'UUID=a / xfs errors=remount-ro 0 0\nUUID=b /var xfs ro 0 0\n'  # ro elsewhere doesn't count
check 0 '# UUID=a / xfs ro 0 0\nUUID=a / xfs rw 0 0\n'                 # nor in a comment
grep -qx 'ExecCondition=/usr/libexec/halogen/fstab-needs-ro' \
  "$repo/files/usr/lib/systemd/system/bootc-fstab-edit.service.d/10-halos.conf"
echo "ok: bootc's fstab edit runs only when / still lacks ro"
