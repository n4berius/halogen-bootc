# HalogenOS

Halogen purpose-built operating system to run Halogen-built q38fn and its NPU models on a dedicated Strix Halo 128GB server.

It is an image-based Fedora 45 appliance that runs
[Halogen](https://github.com/peonist-ai/halogen-flash-server) with its NPU models,
pinned to one release, with the host already configured.

> **Status:** not yet built or booted. The logic tests pass, but the image, Quadlet,
> SELinux rules and real NPU path still need a first run on the hardware.

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

Pushing to `main` builds and pushes `ghcr.io/<owner>/halogenos:45`, and a weekly
build picks up Fedora updates. To build locally, you need Podman and Skopeo:

```bash
tests/run.sh
scripts/build.sh ghcr.io/n4berius/halogenos:45
podman push ghcr.io/n4berius/halogenos:45
```

The first build resolves Halogen 0.18.23 to a digest. To lock that in git, put it in
`HALOGEN_DIGEST` in `versions.env`.

## Install

The GHCR package is private by default, and the installer needs to pull it. Either make
that package public, which publishes only this OS layer and not the repo, or give the
installer a read-only token in `/etc/ostree/auth.json` from a `%pre` section. Never
commit that token.

1. Set the BIOS UMA frame buffer to its minimum and update the firmware.
2. Replace the SSH key in `kickstart/strix-halo.ks`. **This kickstart erases `nvme0n1`.**
3. Boot the Fedora 45 Everything netinstall ISO with `inst.ks=<url of the kickstart>`.
   Enter the LUKS passphrase when asked.
4. Optional: run `sudo halogen-enroll-tpm`, then reboot, to unlock LUKS with the TPM.

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

```bash
sudo bootc upgrade --apply   # update and reboot
sudo bootc rollback          # go back to the previous image
```

To move Halogen, update `HALOGEN_VERSION`, `HALOGEN_SOURCE_COMMIT` and the three hashes
in `versions.env`, then rebuild. A new version downloads its NPU files, about 15 GB, on
its first boot. Remove old `/srv/models/npu/<version>` folders once you no longer need
to roll back to them.

## First-run checklist

Run these on the hardware, and treat a failure as a repo bug:

- `sudo halogenctl doctor` passes, and `cat /proc/cmdline` shows the GTT settings and `iommu=pt`.
- `ls -lZ /dev/accel/accel0` shows group `render` and type `dri_device_t`.
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

HalogenOS is a private working name. Halogen's trademark policy does not allow "halogen"
in another machine-learning product or project name without written permission, so ask
legal@peonist.ai before publishing or distributing it under this name. This project is
not affiliated with or endorsed by Peonist.
