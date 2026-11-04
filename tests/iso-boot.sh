#!/bin/bash
# Boot the ISO in a VM with Secure Boot on and capture the installer's screen.
# Usage: tests/iso-boot.sh path/to.iso output-dir
set -euo pipefail
iso="$1"; out="$2"; mkdir -p "$out"
code=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd "$out/vars.fd"
monitor="$out/monitor.sock"
qemu-img create -f qcow2 "$out/disk.qcow2" 80G >/dev/null

qemu-system-x86_64 -enable-kvm -cpu host -m 8G -smp 4 -machine q35,smm=on \
  -global driver=cfi.pflash01,property=secure,value=on \
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=$code" \
  -drive "if=pflash,format=raw,unit=1,file=$out/vars.fd" \
  -drive "file=$out/disk.qcow2,if=virtio" -cdrom "$iso" -boot d \
  -vga virtio -display none -serial "file:$out/serial.log" \
  -monitor "unix:$monitor,server,nowait" &
vm=$!
trap 'kill "$vm" 2>/dev/null || true' EXIT

reached=0
for t in 60 120 180 240 300 360 420 480; do
  sleep 60
  printf 'screendump %s/screen-%ss.png -f png\n' "$out" "$t" | python3 -c '
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.send(sys.stdin.buffer.read()); time.sleep(2)
' "$monitor"
  text="$(tesseract "$out/screen-${t}s.png" - 2>/dev/null | grep -v '^[[:space:]]*$' | head -25 || true)"
  echo "=== screen at ${t}s ($(sha256sum "$out/screen-${t}s.png" | cut -c1-12)) ==="
  echo "$text"
  if echo "$text" | grep -qiE 'welcome to|installation summary|installation destination'; then reached=1; break; fi
done

echo "=== serial log ==="
tail -n 80 "$out/serial.log" | cut -c1-200
[ "$reached" = 1 ] || { echo "the installer did not appear" >&2; exit 1; }
echo "installer reached with Secure Boot on"
