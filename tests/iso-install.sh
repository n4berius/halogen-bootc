#!/bin/bash
# Install the ISO to a blank disk unattended, boot it with Secure Boot on, and report on it.
# Usage: tests/iso-install.sh path/to.iso os-image-reference output-dir variant
# The NPU edition installs on LUKS, so both encrypted and plain installs are tested. The VM has
# an emulated TPM: the LUKS install is bound to it with halogen-enroll-tpm, then rebooted to
# prove the disk unlocks with no passphrase.
set -euo pipefail
iso="$1"; target="$2"; out="$3"; variant="$4"; mkdir -p "$out/oem"
here="$(cd "$(dirname "$0")" && pwd)"
code=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd "$out/vars.fd"
qemu-img create -f qcow2 "$out/disk.qcow2" 300G >/dev/null

# Anaconda reads ks.cfg from a volume labelled OEMDRV. Test-only password, in a throwaway VM.
luks=""
[ "$variant" != npu ] || luks=" --encrypted --luks-version=luks2 --passphrase=halogentest"
cat > "$out/oem/ks.cfg" <<S
text
lang en_US.UTF-8
keyboard us
timezone Etc/UTC --utc
rootpw --plaintext halogentest --allow-ssh
zerombr
clearpart --all --initlabel
autopart --type=lvm$luks
bootc --source-imgref containers-storage:$target --target-imgref $target
poweroff
S
genisoimage -quiet -V OEMDRV -o "$out/oem.iso" "$out/oem/ks.cfg"

vm() {
  # A fresh swtpm per run; its state in $out/tpm lasts across the install and every boot.
  mkdir -p "$out/tpm"
  swtpm socket --tpm2 --daemon --terminate --tpmstate "dir=$out/tpm" \
    --ctrl "type=unixio,path=$out/tpm/sock"
  qemu-system-x86_64 -enable-kvm -cpu host -m 8G -smp 4 -machine q35,smm=on \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,unit=1,file=$out/vars.fd" \
    -drive "file=$out/disk.qcow2,if=virtio" \
    -chardev "socket,id=chrtpm,path=$out/tpm/sock" -tpmdev emulator,id=tpm0,chardev=chrtpm \
    -device tpm-tis,tpmdev=tpm0 \
    -vga virtio -display none -monitor "unix:$out/monitor.sock,server,nowait" "$@"
}

echo "=== installing ==="
timeout 1500 bash -c "$(declare -f vm); code=$code out=$out; vm -cdrom '$iso' -boot d \
  -drive file=$out/oem.iso,format=raw,if=virtio,readonly=on -serial file:$out/install.log"
echo "install finished"

echo "=== first boot from disk ==="
# No network: the fetch must not start a 125 GB download in CI.
vm -nic none -serial "file:$out/firstboot.log" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
python3 "$here/vm-login.py" "$out/monitor.sock" "$out/firstboot.log" "$out" "$([ -n "$luks" ] && echo luks-stale)"
cat "$out/report.txt"
grep -q 'amdgpu.gttsize=126976' "$out/report.txt"
if [ "$variant" = npu ]; then grep -q 'iommu=pt' "$out/report.txt"; else grep -q 'amd_iommu=off' "$out/report.txt"; fi
grep -qi 'secure boot.*enabled\|Secure Boot: enabled' "$out/report.txt"
grep -q 'Linger=yes' "$out/report.txt"
# bootc mounts the root volume at /sysroot; / itself is the read-only image.
for m in /sysroot /var /var/log /var/log/audit /var/home /var/srv/configs /var/srv/models; do
  grep -qE "^$m " "$out/report.txt" || { echo "no separate volume for $m" >&2; exit 1; }
done
# Anaconda names the volume group after the installer's product name (halOS).
grep -qi 'halos_' "$out/report.txt" || { echo "volume group name is not short" >&2; exit 1; }
if [ -n "$luks" ]; then grep -q 'crypto_LUKS' "$out/report.txt"; fi
grep -q 'halogen-fetch:' "$out/report.txt"
# halosctl reads bootc's status and the image's release file on a real install.
grep -qE "^halOS [0-9]+\.[0-9]+\.[0-9]+.*, $variant edition" "$out/report.txt" || { echo "halosctl version failed" >&2; exit 1; }
grep -qE '^Image: +[a-z]' "$out/report.txt" || { echo "halosctl did not read bootc status" >&2; exit 1; }
# Root never logs in over SSH (files/etc/ssh/sshd_config.d/00-halos.conf), as sshd itself reports,
# even with the installer's "allow root SSH" (rootpw --allow-ssh above) also written.
grep -q '01-permitrootlogin.conf' "$out/report.txt" || { echo "the installer did not write its allow-root file" >&2; exit 1; }
grep -qix 'permitrootlogin no' "$out/report.txt" || { echo "sshd allows root logins" >&2; exit 1; }
echo "installed system verified"

# halogenctl selftest, as people run it on hardware. Only what a VM can pass is required.
cat "$out/selftest.txt"
selftest_has() { grep -qE "^$1" "$out/selftest.txt" || { echo "selftest: expected '$1'" >&2; exit 1; }; }
selftest_has 'Summary: '
selftest_has 'PASS secure-boot:'
selftest_has 'PASS kernel-amdgpu.gttsize:'
selftest_has 'PASS kernel-iommu:'
selftest_has 'PASS firewall:'
selftest_has 'PASS prepare:'
if [ "$variant" = npu ]; then
  selftest_has 'PASS npu-folder:'
  for f in decider LFM custom; do selftest_has "PASS folder-$f:"; done
fi
if grep -qE 'SELFTEST-LEAK|Bearer' "$out/selftest.txt"; then echo "selftest printed the API key" >&2; exit 1; fi
echo "selftest verified"

if [ -n "$luks" ]; then
  # First boot left a TPM binding for a Secure Boot state this machine no longer has.
  echo "=== second boot: stale binding, so the passphrase is asked; re-enroll ==="
  timeout 180 tail --pid="$pid" -f /dev/null || { echo "the VM did not power off after enrolling" >&2; exit 1; }
  vm -nic none -serial "file:$out/secondboot.log" &
  pid=$!
  python3 "$here/vm-login.py" "$out/monitor.sock" "$out/secondboot.log" "$out" luks-enroll

  echo "=== third boot: the TPM must unlock the disk ==="
  timeout 180 tail --pid="$pid" -f /dev/null || { echo "the VM did not power off after re-enrolling" >&2; exit 1; }
  vm -nic none -serial "file:$out/thirdboot.log" &
  pid=$!
  python3 "$here/vm-login.py" "$out/monitor.sock" "$out/thirdboot.log" "$out" tpm
  cat "$out/report.txt"
  tokens="$(grep -cE '^[[:space:]]*[0-9]+: systemd-tpm2' "$out/report.txt" || true)"
  # One token means the re-enroll replaced the stale binding instead of adding a second.
  [ "$tokens" = 1 ] || { echo "expected one TPM token on the LUKS volume, found $tokens" >&2; exit 1; }
  echo "TPM unlock verified"
  cat "$out/selftest.txt"
  grep -q '^PASS luks-tpm:' "$out/selftest.txt" || { echo "selftest did not see the TPM unlock" >&2; exit 1; }
  # Anaconda writes ro for / without bootc's marker, so bootc creates its fstab edit unit at every
  # boot; ours must skip it (bootc-dev/bootc#2592).
  grep -qi "skipped due to 'exec-condition'" "$out/report.txt" || { echo "bootc-fstab-edit still rewrote fstab" >&2; exit 1; }
fi
