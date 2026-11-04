# halogen-bootc

Purpose-built operating system that runs halogen.

It is an image-based Fedora 45 appliance for one 128 GB AMD Strix Halo machine. It runs
[Halogen](https://github.com/peonist-ai/halogen-flash-server) with its NPU models,
pinned to one release, with the host already configured.

> **Status:** the image builds in CI, but it has not run on real hardware. The installer,
> Quadlet, SELinux rules and NPU path still need a first run on the machine.

Base image: Fedora's official `quay.io/fedora/fedora-bootc:45`. There is no separate
image-based Fedora Server edition, so this adds only what the appliance needs.

## What lives where

| Location | Contents | Changes through |
|---|---|---|
| OS image | Kernel arguments, XRT, services, firewall, Halogen digest | Rebuild and `bootc upgrade` |
| `/srv/configs` | `halogen.env`, `api-key` | Edit on the machine |
| `/srv/models` | Flash weights and NPU models, about 125 GB | Fetched on first boot |
| BIOS | UMA frame buffer at its explicit minimum, not Auto; newest firmware | Set by hand |

## First boot

1. `halogen-prepare` creates the directories, default config and API key.
2. `halogen-fabric-clock` holds the clock Halogen needs for GPU and NPU together.
3. `halogen-fetch` pulls the pinned image and downloads the models. Interrupted
   downloads resume, and network failures retry until they succeed.
4. Halogen's own `verify` mode checks the Flash checkpoint. The NPU files are checked
   against the hashes recorded in the pinned image.
5. Halogen starts read-only with no download settings, on port 8731.

Later boots skip the download. Changing the model list, or moving to a new Halogen
version, fetches only what is needed. Each version keeps its NPU files in
`/srv/models/npu/<version>`, so an OS rollback finds the files it expects.

## Build

Images are tagged with the Halogen version they carry, for example
`ghcr.io/n4berius/halogen-flash-bootc:0.18.23`. `latest` follows the newest build.

Pushing to `main` builds and pushes the image, and a weekly build refreshes the same tag
with Fedora updates. Changes to the image or installer also build the USB installer ISO,
which appears as a download on the workflow run.

To build locally, you need Podman and Skopeo:

```bash
tests/run.sh
sudo scripts/build.sh
sudo scripts/build-iso.sh    # writes the ISO under output/
```

The build resolves the Halogen tag to a digest. To lock that in git, put it in
`HALOGEN_DIGEST` in `versions.env`.

## Install from USB

1. In the BIOS, set the UMA frame buffer to its explicit minimum and update the firmware.
   Secure Boot can stay on.
2. Write the ISO to a USB drive with Fedora Media Writer or `dd`, then boot from it.
3. In the graphical installer, choose the disk. Tick the encryption option if you want
   LUKS, and create your administrator account there.
4. After the install, the machine reboots to a text login. It has no desktop.
5. The first boot downloads the Halogen container and about 125 GB of models, so it needs
   internet access. Follow it with `sudo halogenctl fetch-logs`.
6. If you chose LUKS, you can run `sudo halogen-enroll-tpm`, then reboot, to unlock it with
   the TPM. Keep the passphrase as your recovery key.

The installer's graphical environment exists only on the USB drive. The OS is copied from
the image inside the ISO, so the install itself needs no network or registry login.

**Secure Boot:** no MOK enrollment is needed. The image uses Fedora's signed boot chain
and kernel, and the NPU driver is part of that kernel. A MOK would only be needed if you
add your own kernel modules. TPM unlock uses PCR 7, so changing Secure Boot settings means
entering the passphrase and running `halogen-enroll-tpm` again.

For an unattended install, `kickstart/strix-halo.ks` is also available. It erases
`nvme0n1`, and it needs your SSH key and a registry the installer can read.

## Operate

```bash
sudo halogenctl status       # service state
sudo halogenctl fetch-logs   # first-boot download progress
sudo halogenctl logs         # server and fetch logs
sudo halogenctl doctor       # BIOS, kernel, NPU, clock and memlock checks
sudo halogenctl restart      # after editing /srv/configs/halogen.env
sudo halogenctl api-key      # print the API key
```

Clients use `http://<host>:8731/v1` with `Authorization: Bearer <api-key>`.

## Upgrade and roll back

Automatic updates are off because a reboot stops inference and takes the model reload.
If the GHCR package is private, the machine needs a read-only token in
`/etc/ostree/auth.json` to reach it.

```bash
sudo bootc upgrade --apply   # same Halogen version, newer Fedora updates
sudo bootc rollback          # go back to the previous image
```

Each machine stays on its Halogen version until you move it:

```bash
sudo bootc switch ghcr.io/n4berius/halogen-flash-bootc:0.18.24
sudo systemctl reboot
```

To publish a new version, update `HALOGEN_VERSION`, `HALOGEN_SOURCE_COMMIT` and the three
hashes in `versions.env`, plus the tag in the kickstart. A new version downloads its NPU
files, about 15 GB, on its first boot. Remove old `/srv/models/npu/<version>` folders once
you no longer need to roll back to them.

## First-run checklist

Run these on the hardware, and treat a failure as a repo bug:

- `sudo halogenctl doctor` passes, and `cat /proc/cmdline` shows the GTT settings and `iommu=pt`.
- `ls -lZ /dev/accel/accel0` shows group `render` and type `dri_device_t`.
- `mokutil --sb-state` reports Secure Boot enabled, if you left it on.
- `systemctl --failed` is clean. Upstream warns `systemd-remount-fs.service` can fail on
  Anaconda-installed bootc systems.
- `sudo ausearch -m avc -ts boot` is empty. If `/dev/kfd` shows `denied { map }`, run
  `sudo setsebool -P container_use_devices true`.
- `/v1/models` lists the Flash and NPU models.
- A soak test mixes Flash and NPU load for several hours. Kernel 7.2 has a reported GPU
  memory fault, and Halogen's reference host ran 7.1.8.

## Choices worth knowing

- **XRT comes from Debian.** Fedora's package appears only in Rawhide, and the libraries
  run inside Halogen's Debian 13 container, so Debian's build matches its C runtime.
- **The IOMMU stays on.** The NPU needs it, at the cost of Halogen's measured 13–16%
  prefill gain with `amd_iommu=off`.
- **Halogen's script and terms are fetched at build time** and checked by hash, so this
  repo redistributes none of them. Halogen's image and weights keep their own licenses.

## Name

halogen-bootc is a private working name. Halogen's trademark policy does not allow
"halogen" in another machine-learning product or project name without written permission,
so ask legal@peonist.ai before publishing or distributing it under this name. This project
runs halogen and is not affiliated with or endorsed by Peonist.
