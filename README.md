# halogen-bootc

Purpose-built operating system that runs halogen.

It is an image-based Fedora 45 appliance for one 128 GB AMD Strix Halo machine. It installs
from USB, boots with Secure Boot on, and runs
[halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server) pinned to one
release, with or without its NPU models. The host is already configured, and there is no
desktop after install.

> **Status:** both editions build, install and boot in a virtual machine with Secure Boot on.
> Neither has run on real hardware yet, so the GPU, NPU, model download, TPM enrollment and
> Halogen itself are still untested on a Strix Halo.

This is an independent project. It is not made, endorsed or supported by Peonist, LLC.
For problems with this OS, use this repository's issues. Report problems in Halogen itself
to [Halogen](https://github.com/peonist-ai/halogen-flash-server/issues) only if you can
reproduce them on a supported host.

## AI usage disclaimer

The code, tests, CI workflows and documentation in this repository were written entirely by
[Claude](https://claude.ai), Anthropic's AI model, working from direction given by the
repository owner, [n4berius](https://github.com/n4berius). n4berius reviewed and merged the
code. AI-written software can contain mistakes, so read it and test it on your own hardware
before relying on it. This software comes with no warranty, as stated in the
[license](LICENSE).

## How it follows Halogen

This project tracks the official
[halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server) and does not fork
or change it.

- Each image tag names the Halogen release it carries, such as `0.18.23`.
- `versions.env` pins that release, the commit it matches, and hashes for the files taken
  from it. The build then pins the container by digest.
- The container runs unmodified, pulled from Halogen's own registry on first boot.
- The list of allowed options is generated from Halogen's `docs/FLAGS.md`.

New Halogen releases are not picked up automatically. Each one is a reviewed change to
`versions.env`, so this project can lag behind upstream.

## Official documentation

Halogen's own documentation is the reference for what each setting does and how the server
behaves. This README covers only what this OS adds or fixes in place. If they disagree on
how Halogen works, follow Halogen's documentation for your version.

| Topic | Official documentation |
|---|---|
| Every setting | [`docs/FLAGS.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/FLAGS.md) |
| Configuration and memory | [`docs/configuration.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/configuration.md) |
| NPU models and host needs | [`docs/NPU.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/NPU.md) |
| API | [`docs/api.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/api.md) |
| Host setup | [`docs/host-setup.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/host-setup.md) |
| Troubleshooting | [`docs/troubleshooting.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md) |
| Changes between releases | [`CHANGELOG.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/CHANGELOG.md) |

Those links follow Halogen's latest code, which may be newer than the version pinned here.
For an exact match, view the same file at the commit in `versions.env`.

Base image: Fedora's official `quay.io/fedora/fedora-bootc:45`. There is no separate
image-based Fedora Server edition, so this adds only what the appliance needs.

## What lives where

| Location | Contents | Changes through |
|---|---|---|
| OS image | Kernel arguments, XRT, services, firewall, Halogen digest | Rebuild and `bootc upgrade` |
| `/srv/configs` | `halogen.env` with every allowed option, `api-key` | Edit on the machine |
| `/usr/share/halogen` | Locked settings and the allowed-option list | Rebuild only, read-only |
| `/srv/models` | Flash weights and NPU models, about 125 GB | Fetched on first boot |
| BIOS | UMA frame buffer at its explicit minimum, not Auto; newest firmware | Set by hand |

## Editions

| | With NPU | Without NPU |
|---|---|---|
| Image | `halogen-flash-bootc:0.18.23` | `halogen-flash-bootc:0.18.23-no-npu` |
| Serves | Flash and NPU models | Flash only |
| IOMMU | `iommu=pt`, which the NPU needs | `amd_iommu=off`, for Halogen's measured 13-16% more prefill |
| Includes | XRT, the fabric clock service | Neither |
| KV pool | 262,144 positions, leaving room for NPU models | Halogen's default |

`amd_iommu=off` turns off DMA translation machine-wide. That suits a dedicated server,
but it is a real security trade-off. To keep the IOMMU on, change the edition's `kargs.d` file.

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
sudo HALOGEN_VARIANT=no-npu scripts/build.sh
sudo HALOGEN_VARIANT=no-npu scripts/build-iso.sh
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

Choose the ISO for the edition you want. For an unattended install of the NPU edition,
`kickstart/strix-halo.ks` is also available. It erases
`nvme0n1`, and it needs your SSH key and a registry the installer can read.

## Configure

Every option Halogen allows on this system is listed, commented out, in
`/srv/configs/halogen.env`. Uncomment a line, set its value, and apply it:

```bash
sudo nano /srv/configs/halogen.env
sudo halogenctl restart
sudo halogenctl config    # what is in effect, and the locked settings
```

Only listed options reach Halogen. Typos and locked settings are ignored and logged, so they
cannot change the server or stop it. The file is read as plain settings and never run as a
script. Locked values live in `/usr/share/halogen/locked.env`, on the read-only OS, and
upgrades keep your file. New options in a later release appear in
`/usr/share/halogen/halogen.env.default`.

See [`docs/FLAGS.md`](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/FLAGS.md)
for what each option does and how options interact.

To change what is allowed or locked, edit `config/locked.env` or `BLOCKED` in
`scripts/gen-options.py`, run that script on the new `docs/FLAGS.md`, and rebuild.

## Operate

```bash
sudo halogenctl status       # service state
sudo halogenctl fetch-logs   # first-boot download progress
sudo halogenctl logs         # server and fetch logs
sudo halogenctl doctor       # BIOS, kernel, NPU, clock and memlock checks
sudo halogenctl restart      # after editing /srv/configs/halogen.env
sudo halogenctl config       # show the settings in effect
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
- `ls -l /dev/kfd /dev/dri/renderD*` shows group `halogen`, and `ls -lZ /dev/accel/accel0`
  shows group `halogen` and type `dri_device_t`.
- With Secure Boot on, the kernel runs in lockdown. Confirm `halogen-fabric-clock status` holds
  the clock and that GPU and NPU requests work.
- `bootctl status` reports Secure Boot enabled, if you left it on.
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
- **The NPU edition keeps the IOMMU on** because the NPU needs it, at the cost of the
  prefill gain the no-NPU edition takes.
- **Halogen's script and terms are fetched at build time** and checked by hash, so this
  repo redistributes none of them. Halogen's image and weights keep their own licenses.

## Name

halogen-bootc is a private working name. Halogen's trademark policy does not allow "halogen"
in another machine-learning product or project name without written permission, so ask
legal@peonist.ai before publishing or distributing it under this name.

## License

This project's own files are under the [MIT license](LICENSE). That license does not cover
Halogen, model weights, or the other components in the images. They keep their own terms,
listed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Halogen's
[EULA](https://github.com/peonist-ai/halogen-flash-server/blob/main/LICENSE.md) applies to
Halogen.
