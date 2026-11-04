# halogen-bootc

Purpose-built operating system that runs halogen.

It is an image-based Fedora 45 appliance for one 128 GB AMD Strix Halo machine. It installs
from USB, boots with Secure Boot on, and runs
[halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server) pinned to one
release, with or without its NPU models. The host is already configured, and there is no
desktop after install.

> **Status:** both editions build, install and boot in a virtual machine with Secure Boot on.
> Neither has run on real hardware, so the GPU, NPU, model download, TPM enrollment and
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

## Install

See **[INSTALL.md](INSTALL.md)**. In short: write the ISO for your edition to USB, boot it, pick
a disk and optional LUKS in the installer, create your admin account, and let the first boot
download the models.

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

## Releases

Releases come in alpha, beta, RC and stable channels, published as git tags and matching
image tags. [RELEASING.md](RELEASING.md) defines them.

| Use | Image tag |
|---|---|
| Recommended | `stable`, or a version such as `0.18.23` |
| Testing a release | `beta`, `rc`, or an exact tag such as `0.18.23-beta.1` |
| Earliest testing | `alpha` |
| Newest `main` build | `edge` |

Add `-no-npu` for the edition without the NPU.

## Build

Images are tagged with the Halogen version they carry, for example
`ghcr.io/n4berius/halogen-flash-bootc:0.18.23`.

Pushing to `main` publishes the `edge` images, and tags publish releases. Each Monday, the
newest stable release is rebuilt with Fedora updates. Changes to the image or installer also
run the full ISO install test.

To build locally, you need Podman and Skopeo:

```bash
tests/run.sh
sudo scripts/build.sh
sudo scripts/build-iso.sh    # writes the ISO under output/
sudo HALOGEN_VARIANT=no-npu scripts/build.sh
sudo HALOGEN_VARIANT=no-npu scripts/build-iso.sh
```

`versions.env` pins Halogen by digest, so every build runs the same container until the pin
is changed on purpose.

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

To change what is allowed or locked, edit `files/usr/share/halogen/locked.env` or `BLOCKED` in
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

To publish a new version, follow [RELEASING.md](RELEASING.md). A new version downloads its
NPU files, about 15 GB, on its first boot. Remove old `/srv/models/npu/<version>` folders once
you no longer need to roll back to them.

## Choices worth knowing

- **XRT comes from Debian.** Fedora's package appears only in Rawhide, and the libraries
  run inside Halogen's Debian 13 container, so Debian's build matches its C runtime.
- **The NPU edition keeps the IOMMU on** because the NPU needs it, at the cost of the
  prefill gain the no-NPU edition takes.
- **Halogen's script and terms are fetched at build time** and checked by hash, so this
  repo redistributes none of them. Halogen's image and weights keep their own licenses.

## Name

Halogen's trademark policy does not allow "halogen" in another machine-learning product or
project name without written permission. This name is provisional until that is settled with
Peonist, LLC, and the project may be renamed.

## License

This project's own files are under the [MIT license](LICENSE). That license does not cover
Halogen, model weights, or the other components in the images. They keep their own terms,
listed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md). Halogen's
[EULA](https://github.com/peonist-ai/halogen-flash-server/blob/main/LICENSE.md) applies to
Halogen.
