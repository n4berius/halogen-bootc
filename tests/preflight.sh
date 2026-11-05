#!/bin/bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/dev/accel"; touch "$work/dev/kfd" "$work/dev/accel/accel0"
printf '#!/bin/sh\nexit %s\n' 0 > "$work/clock"; chmod +x "$work/clock"
echo 'HALOGEN_NPU_MODELS=embed' > "$work/effective"
echo 'MemTotal: 130000000 kB' > "$work/mem"
echo 'amdgpu.gttsize=1 ttm.pages_limit=1 iommu=pt' > "$work/cmd"
export HALOGEN_MEMLOCK=unlimited
run() { HALOGEN_DEV="$work/dev" HALOGEN_EFFECTIVE_FILE="$work/effective" HALOGEN_MEMINFO="$work/mem" HALOGEN_CMDLINE="$work/cmd" \
  HALOGEN_CLOCK="$work/clock" HALOGEN_SYSFS="$work/sys" "$repo/files/usr/libexec/halogen/preflight"; }
expect_fail() { if run >/dev/null 2>&1; then echo "not caught: $1" >&2; exit 1; fi; echo "ok: catches $1"; }
run >/dev/null; echo "ok: healthy host passes"
echo 'MemTotal: 62000000 kB' > "$work/mem"; expect_fail "a large BIOS carve-out"
echo 'MemTotal: 130000000 kB' > "$work/mem"
echo 'iommu=pt amd_iommu=off' > "$work/cmd"; expect_fail "amd_iommu=off"
echo 'iommu=pt' > "$work/cmd"
rm "$work/dev/accel/accel0"; expect_fail "a missing NPU"
touch "$work/dev/accel/accel0"
printf '#!/bin/sh\nexit 1\n' > "$work/clock"; expect_fail "an unheld fabric clock"
printf '#!/bin/sh\nexit 0\n' > "$work/clock"
HALOGEN_MEMLOCK=8192 expect_fail "limited memlock"
if [ "$(id -u)" != 0 ]; then chmod 000 "$work/dev/kfd"; expect_fail "a GPU node it cannot open"; chmod 644 "$work/dev/kfd"; fi

mkdir -p "$work/sys/class/drm/card0/device"
echo $((20 * 1073741824)) > "$work/sys/class/drm/card0/device/mem_info_gtt_used"
out="$(run 2>&1)"
grep -q 'GTT is already in use' <<< "$out" || { echo "leftover GTT not reported" >&2; exit 1; }
echo "ok: warns about GTT left in use"
out="$(HALOGEN_SERVER_RUNNING=1 run 2>&1)"
if grep -q 'already in use' <<< "$out" || ! grep -q 'by the running server' <<< "$out"; then
  echo "doctor warned about the running server's own GTT" >&2; exit 1
fi
echo "ok: GTT held by the running server is not a warning"
