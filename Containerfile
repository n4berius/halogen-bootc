ARG DEBIAN_IMAGE
ARG FEDORA_BOOTC_IMAGE

# Fedora's XRT packaging does not reach Fedora 45, and XRT has to load inside
# Halogen's Debian 13 container. So the libraries come from Debian.
FROM ${DEBIAN_IMAGE} AS xrt
ARG XRT_MIN_VERSION
RUN set -eu; \
    echo 'deb http://deb.debian.org/debian trixie-backports main' > /etc/apt/sources.list.d/backports.list; \
    apt-get -qq update; \
    mkdir -p /debs /root-xrt /out/lib /out/licenses; \
    cd /debs; \
    apt-get -qq download -t trixie-backports libxrt2 libxrt-npu2; \
    for deb in ./*.deb; do dpkg-deb -x "$deb" /root-xrt; done; \
    lib=/root-xrt/usr/lib/x86_64-linux-gnu; \
    version="$(basename "$(readlink -f "$lib/libxrt_coreutil.so.2")" | sed 's/^libxrt_coreutil\.so\.//')"; \
    printf '%s\n%s\n' "$XRT_MIN_VERSION" "$version" | sort -V -C \
      || { echo "XRT $version is older than $XRT_MIN_VERSION" >&2; exit 1; }; \
    for f in libxrt_coreutil.so.2 libxrt_core.so.2 libxrt_driver_xdna.so.2; do cp -L "$lib/$f" "/out/lib/$f"; done; \
    cp -L /root-xrt/usr/share/doc/libxrt2/copyright /out/licenses/copyright; \
    echo "$version" > /out/VERSION; \
    (cd /debs && sha256sum ./*.deb) > /out/debs.sha256

FROM ${FEDORA_BOOTC_IMAGE} AS os
ARG HALOGEN_VARIANT
ARG HALOGEN_IMAGE
ARG HALOGEN_VERSION
ARG HALOGEN_SOURCE_COMMIT
ARG HALOGEN_CLOCK_SHA256
ARG HALOGEN_LICENSE_SHA256
ARG HALOGEN_NOTICES_SHA256
ARG HALOGEN_WEIGHTS_REPO
ARG HALOGEN_WEIGHTS_REVISION

# A headless AMD server: AMD GPU, NPU and CPU firmware, the network firmware Strix Halo boards
# use (Realtek, MediaTek, Qualcomm), the Wi-Fi channel rules (wireless-regdb, small, with iw;
# the Wi-Fi driver asks for them at boot) and a few admin tools. fwupd stays for firmware updates.
RUN dnf -y --setopt=install_weak_deps=False install \
      amd-gpu-firmware firewalld linux-firmware tpm2-tss \
      amdsmi nvtop htop pciutils usbutils tmux wireless-regdb && \
    dnf -y remove \
      nvidia-gpu-firmware intel-gpu-firmware intel-npu-firmware intel-audio-firmware \
      cirrus-audio-firmware brcmfmac-firmware tiwilink-firmware nxpwireless-firmware \
      qcom-wwan-firmware microcode_ctl \
      'qemu-user-static*' toolbox sos python3-boto3 python3-botocore python3-s3transfer \
      'sssd*' adcli libsmbclient 'samba-*' nfs-utils udisks2 libudisks2 \
      btrfs-progs nilfs-utils f2fs-tools ntfsprogs ntfs-3g exfatprogs udftools \
      fwupd-plugin-modem-manager ModemManager-glib libqmi libmbim && \
    dnf clean all && \
    rm -rf /var/log/dnf5.log /var/lib/dnf /var/cache/libdnf5 /run/dnf && \
    rpm -q fwupd skopeo jq amd-ucode-firmware realtek-firmware mt7xxx-firmware atheros-firmware && \
    ls -d /usr/lib/firmware/amdgpu /usr/lib/firmware/amdnpu && \
    command -v runuser

COPY files/ /
COPY variants/${HALOGEN_VARIANT}/ /
COPY LICENSE THIRD-PARTY-NOTICES.md /usr/share/licenses/halos-flash/
COPY --from=xrt /out/lib/ /usr/lib/halogen/xrt/
COPY --from=xrt /out/licenses/ /usr/share/licenses/halogen-xrt/
COPY --from=xrt /out/VERSION /usr/lib/halogen/xrt/VERSION
COPY --from=xrt /out/debs.sha256 /usr/lib/halogen/xrt/debs.sha256

# Upstream's clock script and terms, unmodified and checked by hash.
RUN set -eu; \
    base="https://raw.githubusercontent.com/peonist-ai/halogen-flash-server/${HALOGEN_SOURCE_COMMIT}"; \
    mkdir -p /usr/share/licenses/halogen; \
    curl -fsSL "$base/deploy/host/halogen-fabric-clock" -o /usr/libexec/halogen/halogen-fabric-clock; \
    curl -fsSL "$base/LICENSE.md" -o /usr/share/licenses/halogen/LICENSE.md; \
    curl -fsSL "$base/THIRD-PARTY-NOTICES.md" -o /usr/share/licenses/halogen/THIRD-PARTY-NOTICES.md; \
    { echo "$HALOGEN_CLOCK_SHA256  /usr/libexec/halogen/halogen-fabric-clock"; \
      echo "$HALOGEN_LICENSE_SHA256  /usr/share/licenses/halogen/LICENSE.md"; \
      echo "$HALOGEN_NOTICES_SHA256  /usr/share/licenses/halogen/THIRD-PARTY-NOTICES.md"; } | sha256sum -c -

# The halOS release (0.19.0-alpha.2, or 0.19.0-dev.<commit> for builds of main), for halosctl.
ARG HALOS_RELEASE
RUN set -eu; \
    chmod 0755 /usr/bin/halosctl /usr/bin/halogenctl /usr/bin/halogen-enroll-tpm /usr/libexec/halogen/*; \
    find /etc/containers/systemd/users/970 -type f -exec sed -i \
      -e "s|@HALOGEN_IMAGE@|${HALOGEN_IMAGE}|g" -e "s|@HALOGEN_VERSION@|${HALOGEN_VERSION}|g" {} +; \
    if grep -rq '@HALOGEN_' /etc/containers/systemd/users/970; then exit 1; fi; \
    { echo "HALOGEN_IMAGE=${HALOGEN_IMAGE}"; \
      echo "HALOGEN_VERSION=${HALOGEN_VERSION}"; \
      echo "HALOGEN_VARIANT=${HALOGEN_VARIANT}"; \
      echo "HALOS_RELEASE=${HALOS_RELEASE}"; \
      echo "HALOGEN_WEIGHTS_REPO=${HALOGEN_WEIGHTS_REPO}"; \
      echo "HALOGEN_WEIGHTS_REVISION=${HALOGEN_WEIGHTS_REVISION}"; } > /usr/share/halogen/release.env; \
    echo 'halogen:524288:65536' >> /etc/subuid; \
    echo 'halogen:524288:65536' >> /etc/subgid; \
    firewall-offline-cmd --add-service=halogen; \
    systemctl enable firewalld.service halogen-prepare.service; \
    if [ "$HALOGEN_VARIANT" = npu ]; then \
      systemctl enable halogen-fabric-clock.service; \
    else \
      rm -rf /usr/lib/halogen/xrt /usr/share/licenses/halogen-xrt /usr/lib/systemd/system/halogen-fabric-clock.service /usr/libexec/halogen/halogen-fabric-clock; \
    fi; \
    systemctl mask bootc-fetch-apply-updates.timer; \
    systemctl disable systemd-homed.service systemd-homed-activate.service

# Rebuild the initramfs with LUKS, TPM2 and LVM support, and fail the build without them.
RUN set -eu; \
    mkdir -p "$(realpath /root)"; \
    kver="$(ls /usr/lib/modules)"; \
    img="/usr/lib/modules/${kver}/initramfs.img"; \
    env DRACUT_NO_XATTR=1 dracut --no-hostonly -f "$img" "$kver"; \
    contents="$(lsinitrd "$img")"; \
    echo "$contents" | grep -E 'cryptsetup|bin/lvm|tpm2' | awk '{print $NF}' | sort -u; \
    for want in '/systemd-cryptsetup$' '/systemd-cryptsetup-generator$' 'libcryptsetup' 'bin/lvm$'; do \
      echo "$contents" | awk '{print $NF}' | grep -qE "$want" || { echo "initramfs is missing $want" >&2; exit 1; }; \
    done

# The base image's own OSTree copy of its files, which still holds everything removed above.
# A flattened image does not use it; Fedora's rechunker drops it the same way.
RUN rm -rf /sysroot/ostree && bootc container lint

# One layer, so the files removed above are not shipped in the base image's layers
# underneath. This keeps the installer ISO small. Labels and start-up as in the base image.
FROM scratch
COPY --from=os / /
LABEL containers.bootc=1 ostree.bootable=true
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
RUN bootc container lint
