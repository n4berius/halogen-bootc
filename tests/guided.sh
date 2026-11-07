#!/bin/bash
# The guided installer's questions and disk choice, against fake disk tools. Each run's kickstart
# lines are also parsed with pykickstart, the installer's own parser, when it is installed. The
# ISO workflow runs this again inside the installer image, with its own tools and parser.
# shellcheck disable=SC2016 # The fake commands expand their variables when they run.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
export FAKE="$work"
f() { printf '#!/bin/bash\n%s\n' "$2" > "$work/bin/$1"; chmod +x "$work/bin/$1"; }
# lsblk: the disk list as JSON, a disk's filesystems and partitions from files, and a parent.
f lsblk 'case "$*" in
  "-J -b -d -o NAME,TYPE,TRAN,RM,RO,SIZE,MODEL") cat "$FAKE/disks.json" ;;
  "-nro FSTYPE "*) cat "$FAKE/fs.${3#/dev/}" 2>/dev/null || true ;;
  "-nro TYPE "*) echo disk; cat "$FAKE/parts.${3#/dev/}" 2>/dev/null || true ;;
  "-ndo PKNAME "*) case "$3" in /dev/sdb1) echo sdb ;; /dev/nvme1n1p3) echo nvme1n1 ;; esac ;;
  *) echo "lsblk $*" >&2; exit 9 ;;
esac'
f wipefs 'cat "$FAKE/pt.${5#/dev/}" 2>/dev/null || true'
f blkid '[ -n "${FAKE_ANSWERS_DEV:-}" ] && [ "$2" = HALOS_ANSWERS ] && echo "$FAKE_ANSWERS_DEV" || exit 2'
f findmnt '[ "$3" = /run/install/repo ] && echo /dev/sdb1 || exit 1'
f mount 'echo "mount $*" >> "$FAKE/log"; cp "$FAKE/answers" "$4/answers"'
f umount 'true'
f systemctl 'echo "systemctl $*" >> "$FAKE/log"'
f getent '[ "$2" = sssd ]'
f pvs 'cat "$FAKE/pvs" 2>/dev/null || true'
export PATH="$work/bin:$PATH"
plan="$repo/installer/guided/plan-install"
ks="$work/plan.ks"
ok() { echo "ok: $*"; }
expect() { grep -qF -- "$2" "$1" || { echo "expected '$2' in $1:" >&2; cat "$1" >&2; exit 1; }; }
disk() { # name size tran model
  printf '{"name":"%s","type":"disk","tran":%s,"rm":false,"ro":false,"size":%s,"model":"%s"}' \
    "$1" "$([ -n "$3" ] && echo "\"$3\"" || echo null)" "$2" "$4"
}
disks() { local IFS=,; printf '{"blockdevices":[%s]}\n' "$*" > "$work/disks.json"; }
run() { # stdin: what is typed
  rm -f "$ks"; : > "$work/log"
  if "$plan" "$ks" > "$work/out" 2>&1; then rc=0; else rc=$?; fi
}
# A stop: exit 1 and no kickstart lines written.
stopped() { [ "$rc" = 1 ] && [ ! -e "$ks" ]; }
typed() { printf '%s\n' "$@" > "$work/in"; run < "$work/in"; }
# The kickstart as Anaconda reads it: the guided file with these lines in place of %include.
parse() {
  if ! python3 -c 'import pykickstart' 2>/dev/null; then
    # The ISO workflow runs this inside the installer image, where it must be there.
    [ -z "${HALOS_REQUIRE_PYKICKSTART:-}" ] || { echo "pykickstart is missing" >&2; exit 1; }
    return 0
  fi
  sed -e "s|^%include .*|cat $ks|e" "$repo/installer/guided/halos-guided.ks" > "$work/full.ks"
  python3 - "$work/full.ks" "$@" <<'PY'
import sys
from pykickstart.parser import KickstartParser
from pykickstart.version import makeVersion
h = makeVersion()
KickstartParser(h).readKickstart(sys.argv[1])
got = {
  "luks": [p.passphrase for p in h.partition.partitions if p.encrypted],
  "root": h.rootpw.password if not h.rootpw.lock else None,
  "allow_ssh": h.rootpw.allow_ssh,
  "admin": [(u.name, u.password, u.groups) for u in h.user.userList],
  "disk": h.ignoredisk.onlyuse,
  "lvs": sorted((l.name, l.mountpoint, l.grow) for l in h.logvol.lvList),
  "vg": [v.vgname for v in h.volgroup.vgList],
}
want = eval(sys.argv[2])
for k, v in want.items():
  if got[k] != v: sys.exit(f"pykickstart read {k} = {got[k]!r}, expected {v!r}")
PY
}
TB=2000398934016; SMALL=256060514304; STICK=32017047552

# One empty internal disk: one yes/no, then the questions. The USB stick (the installer) and a
# small disk are never offered. The passphrase has a quote and spaces, which must survive.
disks "$(disk nvme0n1 $TB nvme 'WD_BLACK SN850X')" "$(disk sdb $STICK usb 'Cruzer')" "$(disk sda $SMALL sata 'Old SSD')"
typed yes '' yes "it's a secret" "it's a secret" no nab hunter2hunter2 hunter2hunter2 yes
[ "$rc" = 0 ] || { cat "$work/out" >&2; echo "guided install failed" >&2; exit 1; }
expect "$work/out" '2TB  WD_BLACK SN850X  (empty)'
if grep -q sdb "$work/out"; then echo "the USB stick was offered" >&2; exit 1; fi
expect "$work/out" '(Too small, not used:)'
expect "$ks" 'network --hostname=halos'
expect "$ks" 'ignoredisk --only-use=nvme0n1'
expect "$ks" 'clearpart --all --initlabel --disklabel=gpt --drives=nvme0n1'
expect "$ks" 'rootpw --lock'
expect "$ks" 'volgroup halos pv.halos'
expect "$ks" 'reboot'
[ "$(stat -c %a "$ks")" = 600 ] || { echo "the kickstart lines are readable by others" >&2; exit 1; }
if grep -q "secret\|hunter2" "$work/out"; then echo "a password was shown" >&2; exit 1; fi
parse "{'luks': [\"it's a secret\"], 'root': None, 'admin': [('nab', 'hunter2hunter2', ['wheel'])], 'disk': ['nvme0n1'],
  'vg': ['halos'], 'lvs': [('audit', '/var/log/audit', False), ('configs', '/var/srv/configs', False),
  ('home', '/home', False), ('log', '/var/log', False), ('models', '/var/srv/models', True),
  ('root', '/', False), ('var', '/var', False)]}"
ok "one empty disk: a yes, the questions, fixed halos-* volumes, and the passphrase survives quoting"

# Bad answers are asked again; root is enabled; no encryption.
typed yes 'Bad_Name' freyja maybe no yes short --allow-ssh --allow-ssh root halogen sssd nab pw12345678 pw12345678 yes
[ "$rc" = 0 ] || { cat "$work/out" >&2; exit 1; }
expect "$work/out" 'Please answer yes or no.'
expect "$work/out" 'It needs at least 8 characters.'
expect "$work/out" 'not a system name such as root or halogen'
expect "$ks" 'network --hostname=freyja'
if grep -q 'encrypted' "$ks"; then echo "encrypted without being asked to" >&2; exit 1; fi
# A password that looks like an option is still the password (rootpw ... -- '<password>').
parse "{'luks': [], 'root': '--allow-ssh', 'allow_ssh': False, 'admin': [('nab', 'pw12345678', ['wheel'])]}"
ok "bad answers and existing account names are asked again; root on, encryption off"

# A disk that holds data, or two disks: the disk's name must be typed. A wrong name asks again.
echo crypto_LUKS > "$work/fs.nvme0n1"; echo part > "$work/parts.nvme0n1"
disks "$(disk nvme0n1 $TB nvme 'WD_BLACK SN850X')" "$(disk sdb $STICK usb 'Cruzer')"
typed yes
stopped || { echo "a disk with data was taken on a yes" >&2; exit 1; }
expect "$work/out" '(has data: crypto_LUKS)'
typed nvme1n1 nvme0n1 '' no no nab pw12345678 pw12345678 yes
[ "$rc" = 0 ] || { cat "$work/out" >&2; exit 1; }
expect "$work/out" "'nvme1n1' isn't one of the disks above"
rm -f "$work/fs.nvme0n1" "$work/parts.nvme0n1"
disks "$(disk nvme0n1 $TB nvme A)" "$(disk nvme1n1 $TB nvme B)"
typed nvme1n1 '' no no nab pw12345678 pw12345678 yes
[ "$rc" = 0 ] || { cat "$work/out" >&2; exit 1; }
expect "$ks" 'ignoredisk --only-use=nvme1n1'
# An earlier install's halos volume group on the other disk stops it; on the chosen disk it doesn't.
echo '  /dev/nvme1n1p3 halos' > "$work/pvs"
typed nvme0n1 '' no no nab pw12345678 pw12345678 yes ''
stopped || { echo "a second halos volume group was allowed" >&2; exit 1; }
expect "$work/out" 'Disk nvme1n1 already has a halOS volume group'
typed nvme1n1 '' no no nab pw12345678 pw12345678 yes
[ "$rc" = 0 ] || { cat "$work/out" >&2; echo "reinstalling over halos was refused" >&2; exit 1; }
rm "$work/pvs"
ok "a disk with data, or a choice of two, needs its name typed; one halos volume group only"

# Stopping: at the final question, with an empty name, or when no disk is big enough. Nothing is
# written, and the machine powers off.
disks "$(disk nvme0n1 $TB nvme A)"
typed yes '' no no nab pw12345678 pw12345678 no ''
stopped || { echo "the last no did not stop" >&2; exit 1; }
expect "$work/log" 'systemctl poweroff'
disks "$(disk nvme0n1 $TB nvme A)" "$(disk nvme1n1 $TB nvme B)"
typed '' ''
stopped || { echo "an empty disk name did not stop" >&2; exit 1; }
disks "$(disk sda $SMALL sata 'Old SSD')"
typed ''
stopped || { echo "a small disk was used" >&2; exit 1; }
expect "$work/out" 'needs an internal disk of at least 480GB'
ok "a no, an empty name or a small disk stops with nothing written"

# An answers volume alone changes nothing: without the unattended entry, the questions are asked.
export FAKE_ANSWERS_DEV=/dev/vdb
disks "$(disk vda $TB '' QEMU)" "$(disk vdb 376832 '' QEMU)"
echo disk=vda > "$work/answers"
typed no ''
stopped || { echo "the answers volume was used without the unattended entry" >&2; exit 1; }
expect "$work/out" 'Only the unattended menu'
expect "$work/out" 'Erase it and install halOS?'
if grep -q '^mount' "$work/log"; then echo "the answers volume was mounted" >&2; exit 1; fi
ok "an answers volume is ignored outside the unattended entry"

# Unattended (the VM test): answers from a labelled volume, never run as code, never offered as
# a disk. A disk with data needs confirm=<disk>.
export HALOS_UNATTENDED=1
cat > "$work/answers" <<'A'
disk=vda
hostname=halostest
luks_passphrase=halogentest
root_password=$(touch $FAKE/pwned)
admin_user=admin
admin_password=adminsecret
allow_root_ssh=yes
A
run < /dev/null
[ "$rc" = 0 ] || { cat "$work/out" >&2; exit 1; }
[ ! -e "$work/pwned" ] || { echo "an answer ran as a command" >&2; exit 1; }
expect "$work/log" 'mount -o ro,nosuid,nodev,noexec /dev/vdb'
expect "$ks" 'poweroff'
expect "$ks" ' --allow-ssh'
parse "{'luks': ['halogentest'], 'root': '\$(touch \$FAKE/pwned)', 'disk': ['vda']}"
echo xfs > "$work/fs.vda"
run < /dev/null
stopped || { echo "a disk with data was erased without confirm" >&2; exit 1; }
echo confirm=vda >> "$work/answers"
run < /dev/null
[ "$rc" = 0 ] || { cat "$work/out" >&2; exit 1; }
# Only an exact name: not two names, not the answers volume.
disks "$(disk vda $TB '' QEMU)" "$(disk vdc $TB '' QEMU)" "$(disk vdb 376832 '' QEMU)"
sed -i 's/^disk=vda/disk=vda vdc/' "$work/answers"
run < /dev/null
stopped || { echo "two disk names were accepted" >&2; exit 1; }
sed -i 's/^disk=vda vdc/disk=vdb/' "$work/answers"
run < /dev/null
[ "$rc" = 1 ] || { echo "the answers volume was accepted as the disk" >&2; exit 1; }
echo 'evil=1' >> "$work/answers"
run < /dev/null
stopped || { echo "an unknown answer was accepted" >&2; exit 1; }
if grep -q 'systemctl poweroff' "$work/log"; then echo "unattended stop powered off" >&2; exit 1; fi
ok "unattended answers are read as data, and a disk with data needs confirm"
