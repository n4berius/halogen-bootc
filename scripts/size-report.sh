#!/bin/bash
# Report what takes space in the OS image, the installer image and the ISO, to guide trimming.
# Needs root Podman with both images built. Usage: sudo scripts/size-report.sh [iso]
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=versions.env
. ./versions.env
os="$(scripts/image-ref.sh)"
installer="localhost/halos-flash-installer:$HALOGEN_VERSION-${HALOGEN_VARIANT:-npu}"
iso="${1:-}"

inspect() {
  podman run --rm --network=none --entrypoint bash "$1" -c '
    echo "--- total size of /usr, /etc, /opt"; du -sh /usr /etc /opt 2>/dev/null
    echo "--- largest directories under /usr (MiB)"
    du -m --max-depth=3 /usr 2>/dev/null | sort -rn | head -30
    echo "--- packages: count and total"
    rpm -qa | wc -l
    rpm -qa --qf "%{SIZE}\n" | awk "{s+=\$1} END {printf \"%d MiB\n\", s/1048576}"
    echo "--- 60 largest packages (MiB, name)"
    rpm -qa --qf "%{SIZE} %{NAME}\n" | sort -rn | head -60 | awk "{printf \"%6.1f %s\n\", \$1/1048576, \$2}"
    echo "--- firmware packages (MiB, name)"
    rpm -qa --qf "%{SIZE} %{NAME}\n" | grep -i firmware | sort -rn | awk "{printf \"%6.1f %s\n\", \$1/1048576, \$2}"
    echo "--- firmware directories (MiB)"
    du -m --max-depth=1 /usr/lib/firmware 2>/dev/null | sort -rn | head -40
    echo "--- documentation, man pages, locales (MiB)"
    du -sm /usr/share/doc /usr/share/man /usr/share/info /usr/share/locale /usr/lib/locale 2>/dev/null
    echo "--- kernel modules (MiB)"
    du -sm /usr/lib/modules/*/kernel/* 2>/dev/null | sort -rn | head -20
    echo "--- enabled units"
    systemctl list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null | awk "{print \$1}"
    echo "--- enabled user units (global)"
    systemctl --global list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null | awk "{print \$1}"
    echo "--- all installed package names"
    rpm -qa --qf "%{NAME}\n" | sort | tr "\n" " "; echo
  '
}

echo "===== OS image: $os"
podman image inspect --format '{{.Size}}' "$os" | awk '{printf "image size: %d MiB\n", $1/1048576}'
inspect "$os"

if podman image exists "$installer"; then
  echo; echo "===== Installer image: $installer"
  podman image inspect --format '{{.Size}}' "$installer" | awk '{printf "image size: %d MiB\n", $1/1048576}'
  inspect "$installer"
fi

if [ -n "$iso" ]; then
  echo; echo "===== ISO: $iso ($(du -m "$iso" | cut -f1) MiB)"
  mnt="$(mktemp -d)"; mount -o loop,ro "$iso" "$mnt"
  trap 'umount "$mnt" 2>/dev/null || true; rmdir "$mnt"' EXIT
  echo "--- files over 5 MiB on the ISO (MiB)"
  find "$mnt" -type f -size +5M -exec du -m {} + | sort -rn | sed "s|$mnt||"
  find "$mnt" -type f \( -name '*.img' -o -name '*.squashfs' \) -print0 | while IFS= read -r -d '' sq; do
    if unsquashfs -s "$sq" >/dev/null 2>&1; then
      echo "--- squashfs ${sq#"$mnt"}"
      unsquashfs -s "$sq" | grep -iE 'compression|block size|filesystem size' || true
      echo "--- largest top-level entries inside (by listing)"
      unsquashfs -lls "$sq" 2>/dev/null | awk '{print $3, $NF}' | sort -rn | head -25
    fi
  done
fi
