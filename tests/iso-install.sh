#!/bin/bash
# Install the ISO to a blank disk unattended, boot it with Secure Boot on, and report on it.
# Usage: tests/iso-install.sh path/to.iso os-image-reference output-dir
set -euo pipefail
iso="$1"; target="$2"; out="$3"; mkdir -p "$out/oem"
here="$(cd "$(dirname "$0")" && pwd)"
code=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd "$out/vars.fd"
qemu-img create -f qcow2 "$out/disk.qcow2" 80G >/dev/null

# Anaconda reads ks.cfg from a volume labelled OEMDRV. Test-only password, in a throwaway VM.
cat > "$out/oem/ks.cfg" <<S
text
lang en_US.UTF-8
keyboard us
timezone Etc/UTC --utc
rootpw --plaintext halogentest
zerombr
clearpart --all --initlabel
autopart --type=lvm --fstype=xfs
bootc --source-imgref containers-storage:$target --target-imgref $target
poweroff
S
genisoimage -quiet -V OEMDRV -o "$out/oem.iso" "$out/oem/ks.cfg"

vm() {
  qemu-system-x86_64 -enable-kvm -cpu host -m 8G -smp 4 -machine q35,smm=on \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" \
    -drive "if=pflash,format=raw,unit=1,file=$out/vars.fd" \
    -drive "file=$out/disk.qcow2,if=virtio" \
    -vga virtio -display none -monitor "unix:$out/monitor.sock,server,nowait" "$@"
}

echo "=== installing ==="
timeout 1500 bash -c "$(declare -f vm); code=$code out=$out; vm -cdrom '$iso' -boot d \
  -drive file=$out/oem.iso,format=raw,if=virtio,readonly=on -serial file:$out/install.log"
echo "install finished"

echo "=== first boot from disk ==="
vm -serial "file:$out/firstboot.log" &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
python3 "$here/vm-login.py" "$out/monitor.sock" "$out/firstboot.log" "$out"
cat "$out/report.txt"
grep -q 'amdgpu.gttsize=126976' "$out/report.txt"
grep -q 'iommu=pt' "$out/report.txt"
grep -qi 'secure boot.*enabled\|Secure Boot: enabled' "$out/report.txt"
echo "installed system verified"
