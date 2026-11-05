#!/bin/bash
# shellcheck disable=SC2016 # The fake commands expand their variables when they run.
# halogenctl selftest against fake hardware and fake system tools.
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
fake="$work/fake"; sysbin="$work/sysbin"
mkdir -p "$fake" "$sysbin" "$work/sys/class/dmi/id" "$work/sys/class/net/enp1s0/device" \
  "$work/dev/dri" "$work/dev/accel" "$work/models/npu/qwen3.5-2b" "$work/configs"
export FAKE="$work"

# Only basic tools, so a tool missing from the image really is missing here.
for t in bash sh cat head tail sed awk grep find df date paste wc sort uname basename readlink \
  mktemp chmod rm stat tr cut printf python3 timeout id ls env mkdir; do
  p="$(command -v "$t")" && ln -sf "$p" "$sysbin/$t"
done

echo "ASUS" > "$work/sys/class/dmi/id/board_vendor"; echo "board" > "$work/sys/class/dmi/id/board_name"
echo "1.02" > "$work/sys/class/dmi/id/bios_version"
echo up > "$work/sys/class/net/enp1s0/operstate"; echo 5000 > "$work/sys/class/net/enp1s0/speed"
touch "$work/dev/kfd" "$work/dev/dri/renderD128" "$work/dev/accel/accel0" "$work/dev/tpmrm0"
mkdir -p "$work/models/decider" "$work/models/LFM" "$work/models/custom"; touch "$work/models/.fetch-stamp"
echo 'SECRET-KEY-MARKER' > "$work/configs/api-key"; echo 'hf_SECRET-TOKEN-MARKER' > "$work/configs/hf-token"
printf 'MemTotal: 130000000 kB\n' > "$work/meminfo"
echo 'BOOT_IMAGE=x amdgpu.gttsize=126976 ttm.pages_limit=32505856 iommu=pt' > "$work/cmdline"
printf 'HALOGEN_VARIANT=npu\nHALOGEN_VERSION=9.9.9\nHALOGEN_WEIGHTS_REVISION=abc\n' > "$work/release.env"

f() { printf '#!/bin/bash\n%s\n' "$2" > "$fake/$1"; chmod +x "$fake/$1"; }
f mokutil 'echo "SecureBoot ${FAKE_SB:-enabled}"'
f getenforce 'echo "${FAKE_SELINUX:-Enforcing}"'
f journalctl 'cat "$FAKE/kernel.log" 2>/dev/null; true'
f firewall-cmd 'case "$1" in --state) echo "${FAKE_FIREWALL:-running}" ;; --get-default-zone) echo FedoraServer ;; *) cat "$FAKE/services" ;; esac'
f lsblk 'echo "/dev/nvme0n1p3 crypto_LUKS"'
f cryptsetup 'printf "Tokens:\n  0: systemd-tpm2\n"'
f amd-smi 'if [ -n "${FAKE_NOGPU:-}" ]; then echo "ERROR:root:Unable to detect any GPU devices"; exit 255; fi; printf "GPU: 0\n    BDF: 0000:c3:00.0\n"'
f systemd-run 'echo "preflight: ok"'
f bootc 'echo "Booted image: ghcr.io/n4berius/halos-flash:9.9.9"'
f systemctl 'case "$*" in *--failed*) cat "$FAKE/failed" 2>/dev/null ;; *"show -p Job"*) echo "${FAKE_JOB:-}" ;;
  *halogen-fetch*) echo "${FAKE_FETCH:-inactive}" ;; *) echo "${FAKE_STATE:-active}" ;; esac'
f fabric-clock 'exit 0'
# Group, owner and label as the real image sets them.
f stat 'case "$2" in %G|%U) echo halogen ;; %C) case "$3" in *accel*) echo system_u:object_r:dri_device_t:s0 ;; *) echo system_u:object_r:container_file_t:s0 ;; esac ;; *) exec /usr/bin/stat "$@" ;; esac'
f curl 'echo "curl $*" >> "$FAKE/curl.log"; case "$*" in *models*) echo "{\"data\":[{\"id\":\"halogen-qwen3.8-flash-next\"},{\"id\":\"qwen3.5-2b\"}]}" ;; *::1*) [ -n "${FAKE_NOIPV6:-}" ] && printf 000 || printf 200 ;; *) printf 200 ;; esac'
echo "halogen" > "$work/services"

export PATH="$fake:$sysbin" HALOGEN_RELEASE_FILE="$work/release.env" HALOGEN_SYSFS="$work/sys" \
  HALOGEN_DEV="$work/dev" HALOGEN_CMDLINE="$work/cmdline" HALOGEN_MEMINFO="$work/meminfo" \
  HALOGEN_MODELS_DIR="$work/models" HALOGEN_CONFIGS_DIR="$work/configs" HALOGEN_CLOCK="$fake/fabric-clock"
selftest="$repo/files/usr/libexec/halogen/selftest"
ok() { echo "ok: $*"; }
expect() { grep -qE "$1" "$work/out" || { echo "expected '$1' in:" >&2; cat "$work/out" >&2; exit 1; }; }
refuse() { if grep -qE "$1" "$work/out"; then echo "did not expect '$1' in:" >&2; cat "$work/out" >&2; exit 1; fi; }

"$selftest" > "$work/out" 2>&1 || { cat "$work/out" >&2; echo "a healthy machine failed" >&2; exit 1; }
for id in secure-boot kernel-iommu memory selinux-denials firewall luks-tpm gpu-kfd npu-device npu-label \
  fabric-clock server preflight api-ipv4 api-ipv6 api-models npu-folder folder-LFM; do
  expect "^PASS $id:"
done
expect '^Summary: [0-9]+ passed, 0 warnings, 0 failed'
expect 'serving: halogen-qwen3.8-flash-next qwen3.5-2b'
ok "a healthy NPU machine passes every check"

refuse 'SECRET-KEY-MARKER|SECRET-TOKEN-MARKER'
if grep -q 'SECRET-KEY-MARKER' "$work/curl.log"; then echo "the API key was on a command line" >&2; exit 1; fi
ok "the API key and HF token never appear in the report or on a command line"

rm "$fake/mokutil" "$fake/amd-smi"
"$selftest" > "$work/out" 2>&1 || true
expect '^SKIP secure-boot:'; expect '^Summary:'
ok "a missing tool is skipped, and the rest still runs"

echo "public" > "$work/services"
cat > "$work/kernel.log" <<'L'
audit: type=1400 audit(1.2:3): avc:  denied  { map } for  pid=9 comm="halogen" path="/dev/kfd" dev="devtmpfs" scontext=system_u:system_r:container_t:s0 tcontext=system_u:object_r:kfd_device_t:s0 tclass=chr_file
audit: type=1400 audit(1.2:4): avc:  denied  { map } for  pid=9 comm="halogen" path="/dev/kfd" dev="devtmpfs" scontext=system_u:system_r:container_t:s0 tcontext=system_u:object_r:kfd_device_t:s0 tclass=chr_file
audit: type=1400 audit(1.2:5): avc:  denied  { recv } for  saddr=192.168.1.50 src=51234 daddr=192.168.1.10 dest=8731 netif=enp1s0 scontext=system_u:system_r:container_t:s0 tcontext=system_u:object_r:unlabeled_t:s0 tclass=packet
L
if "$selftest" > "$work/out" 2>&1; then echo "failures still exited 0" >&2; exit 1; fi
expect '^FAIL firewall:'; expect '^FAIL selinux-denials: 2 different'; expect 'kfd_device_t'; expect 'tclass=packet'
refuse '192\.168|saddr|path=|pid='
ok "a closed port and SELinux denials fail, each denial once, with no paths or addresses"
echo "halogen" > "$work/services"; rm "$work/kernel.log"

mkdir -p "$work/models/npu/0.18.23"
echo 'ath11k_pci: Direct firmware load for ath11k/WCN6855 failed with error -2' > "$work/kernel.log"
"$selftest" > "$work/out" 2>&1 || true
expect '^WARN npu-folder:.*0\.18\.23'; expect '^WARN firmware:'; expect '^ +ath11k/WCN6855$'
ok "leftover version folders and missing firmware are reported"
rm -r "$work/models/npu/0.18.23" "$work/kernel.log"

printf 'HALOGEN_VARIANT=no-npu\n' > "$work/release.env"
echo 'BOOT_IMAGE=x amdgpu.gttsize=126976 ttm.pages_limit=32505856 amd_iommu=off' > "$work/cmdline"
rm "$work/dev/accel/accel0"
"$selftest" > "$work/out" 2>&1 || { cat "$work/out" >&2; exit 1; }
expect '^PASS kernel-iommu:.*amd_iommu=off'
refuse 'npu-device|fabric-clock|folder-LFM'
ok "the no-NPU edition expects amd_iommu=off and skips the NPU checks"

f mokutil 'echo "SecureBoot ${FAKE_SB:-enabled}"'
f amd-smi 'if [ -n "${FAKE_NOGPU:-}" ]; then echo "ERROR:root:Unable to detect any GPU devices"; exit 255; fi; echo "GPU: 0"'
printf 'HALOGEN_VARIANT=npu\n' > "$work/release.env"
echo 'BOOT_IMAGE=x ttm.pages_limit=32505856 iommu=pt amd_iommu=off' > "$work/cmdline"
printf 'MemTotal: 60000000 kB\n' > "$work/meminfo"
echo 'halogen-fabric-clock.service loaded failed failed Hold the clock' > "$work/failed"
if FAKE_SB=disabled FAKE_SELINUX=Permissive FAKE_STATE=inactive FAKE_NOGPU=1 FAKE_NOIPV6=1 FAKE_FIREWALL=not-running \
    "$selftest" > "$work/out" 2>&1; then echo "an unhealthy machine passed" >&2; exit 1; fi
for line in 'WARN secure-boot' 'FAIL kernel-amdgpu.gttsize' 'FAIL kernel-iommu-off' 'FAIL memory' \
  'FAIL failed-units:.*halogen-fabric-clock' 'WARN selinux' 'FAIL firewall: firewalld is not running' \
  'WARN amd-smi' 'FAIL npu-device' 'FAIL prepare' 'FAIL server' 'WARN api-ipv6'; do
  expect "^$line"
done
ok "an unhealthy machine gets a FAIL or WARN for each problem"

rm "$work/failed"
for wait in FAKE_JOB=42 FAKE_FETCH=activating; do
  env FAKE_STATE=inactive "$wait" "$selftest" > "$work/out" 2>&1 || true
  expect '^WARN server:.*waiting.*fetch-logs'; refuse '^FAIL (server|api-)'
done
FAKE_STATE=inactive FAKE_JOB='Failed to connect to bus' "$selftest" > "$work/out" 2>&1 || true
expect '^FAIL server:.*halogenctl start'
FAKE_STATE=inactive FAKE_FETCH=failed "$selftest" > "$work/out" 2>&1 || true
expect '^FAIL server:.*download and check step failed.*fetch-logs'
FAKE_STATE=deactivating "$selftest" > "$work/out" 2>&1 || true
expect '^WARN server:.*deactivating'
ok "Halogen waiting for the fetch, or stopping, is a warning; a failed fetch or a stopped Halogen says what to do"
