# Installing halogen-bootc

This guide covers a new install from USB, from choosing an edition to a working API.
For how Halogen itself behaves, see its
[official documentation](https://github.com/peonist-ai/halogen-flash-server/tree/main/docs).

> halogen-bootc is in alpha. The NPU edition runs on the hardware below; anything else is
> untested, so work through the [checks](#7-check-the-install) on your first install and
> [report how it went](https://github.com/n4berius/halogen-bootc/issues/new?template=hardware-report.yml).

## Tested hardware

| Machine | Memory | Disk | Release | Edition |
|---|---|---|---|---|
| [AMD Ryzen AI Halo Developer Platform](https://www.microcenter.com/product/711961/amd-ryzen-ai-halo-developer-platform-linux-os) (Micro Center) | 128 GB | 2 TB NVMe | `v0.18.23-alpha.2` | With NPU |

On that machine, these work:

- USB install with Secure Boot on, and no MOK enrollment
- Automatic storage, with each volume created
- First-boot download of the Halogen container and about 125 GB of models
- Halogen on the GPU, with all five NPU models loaded
- The API from other machines on the network, such as Hermes

Not yet confirmed on hardware: LUKS with TPM unlock (it passes in the VM test), the edition
without NPU, and a long soak under real load.

Its BIOS has no UMA frame buffer setting. That's fine: the GTT kernel settings give Halogen
its memory either way.

## What you need

- A dedicated AMD Strix Halo machine with 128 GB of memory. The GTT settings assume 128 GB.
- A USB drive of at least 4 GB. Writing the ISO erases it.
- A disk with at least 256 GB. The models take about 125 GB.
- Internet access on first boot, for the Halogen container and models.
- Another computer to download the ISO and write the USB drive.

## 1. Choose an edition

| | With NPU | Without NPU |
|---|---|---|
| Serves | Flash and NPU models | Flash only |
| IOMMU | On, with `iommu=pt` | Off, with `amd_iommu=off` |
| Trade-off | Slower prefill, keeps DMA protection | Halogen measured 13-16% more prefill, but DMA protection is off |
| Image | `halogen-flash-bootc:0.18.23` | `halogen-flash-bootc:0.18.23-no-npu` |

## 2. Prepare the BIOS

1. Update to your maker's newest BIOS. Halogen's
   [NPU docs](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/NPU.md#what-the-host-needs)
   explain why this matters.
2. If your BIOS offers a UMA frame buffer, or dedicated graphics memory, setting, set it to
   its explicit minimum, not Auto. Some machines don't have this setting, and that's fine.
3. Leave Secure Boot on if you want it. No MOK enrollment is needed.
4. Use the BIOS power settings you want. Halogen's published numbers assume about 85 W.

## 3. Get the ISO

Download your edition's ISO and its `.sha256` file from this repository's
[Releases page](https://github.com/n4berius/halogen-bootc/releases). Use the `-npu` files for
the NPU edition and the `-no-npu` files for the other. Alpha, beta and RC releases are
pre-releases, and [RELEASING.md](RELEASING.md) explains each channel.

GitHub limits release files to 2 GiB, so the ISO comes in one of three forms. Check it in the
folder you downloaded to; it must say `OK`:

| You downloaded | Do this |
|---|---|
| One `.iso` | `sha256sum -c *.iso.sha256` |
| One `.iso.xz` | `sha256sum -c *.iso.xz.sha256`, then unpack it with `xz -d` (7-Zip on Windows). balenaEtcher can write the `.xz` without unpacking |
| Several `.iso.partNN` files | Older releases only. Join them with `cat *.iso.part* > halogen.iso`, then check with `sha256sum -c *.iso.sha256` |

From `v0.18.23-alpha.3` on, each release ships one file whenever compression gets it under
the limit.

### Moving between releases later

A machine installed from a pre-release stays on that exact build, so `bootc upgrade` finds
nothing new. To move to a newer build, switch to its tag and reboot. For example, from
alpha.1 to alpha.2:

```bash
sudo bootc switch ghcr.io/n4berius/halogen-flash-bootc:0.18.23-alpha.2
sudo systemctl reboot
```

Add `-no-npu` to the tag on that edition. Once a stable release is out, switch to the plain
version tag, such as `:0.18.23`. From then on, `sudo bootc upgrade --apply` picks up Fedora
updates for that Halogen version. `sudo bootc status` shows which tag a machine follows.

To build an ISO yourself, see [BUILDING.md](BUILDING.md).

## 4. Write the USB drive

Use [Fedora Media Writer](https://fedoraproject.org/workstation/download/) with its custom
image option, or use `dd` on Linux. Check the device name first, because `dd` overwrites it
without asking:

```bash
lsblk
sudo dd if=halogen-flash-bootc-v0.18.23-alpha.1-npu.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## 5. Run the installer

1. Boot from the USB drive and choose **Install halogen-flash-bootc**.
2. Pick your language.
3. Under **Installation Destination**, choose the disk and keep **Automatic** storage. It
   creates LVM volumes with XFS for `/`, `/var`, `/var/log`, `/var/log/audit`, `/var/home`,
   `/var/srv/configs` and `/var/srv/models`, which takes the rest of the disk. **Custom** lets
   you change this, but keep at least 150 GiB for `/var/srv/models`.
4. Tick **Encrypt my data** if you want LUKS, and set a passphrase.
5. Create your administrator account, and make sure it has admin rights.
6. Start the install. It copies the OS from the ISO, so it needs no network here.
7. Reboot and remove the USB drive.

The installer's graphical environment exists only on the USB drive. The installed system
starts at a text login, and you don't need to create another account.

## 6. Let the first boot finish

The first boot runs in this order:

1. `halogen-prepare` creates `/srv/models`, `/srv/configs`, the config file and an API key.
2. On the NPU edition, `halogen-fabric-clock` holds the clock Halogen needs for GPU and NPU
   together.
3. `halogen-fetch` pulls the pinned Halogen container and downloads the models. Interrupted
   downloads resume, and network failures retry until they succeed.
4. Halogen's `verify` mode checks the Flash checkpoint. NPU files are checked against the
   hashes in the pinned container.
5. Halogen starts offline, with its models read-only, on port 8731.

Log in and follow it:

```bash
sudo halogenctl fetch-logs
```

It prints how much has downloaded every minute. Press Ctrl+C to stop watching; the download
carries on.

Downloads work without an account. A free Hugging Face read token raises the rate limits and
usually speeds them up. Create one at
[huggingface.co/settings/tokens](https://huggingface.co/settings/tokens), then:

```bash
sudo halogenctl hf-token     # paste the token; it isn't shown or printed
sudo halogenctl restart      # the download resumes with the token
```

The token is stored in `/srv/configs/hf-token`, readable only by the `halogen` service, and
used only for downloads. Remove it with `sudo halogenctl hf-token --remove`.

Later boots skip the download unless the model list or Halogen version changes.

## 7. Check the install

```bash
sudo halogenctl doctor
sudo halogenctl status
sudo halogenctl config
curl -H "Authorization: Bearer $(sudo halogenctl api-key)" http://127.0.0.1:8731/v1/models
```

The API should list the Flash model, plus the NPU models on that edition. Clients connect to
`http://<host>:8731/v1` with the same key.

Please confirm these on the first install:

- `cat /proc/cmdline` shows the GTT settings and your edition's IOMMU setting.
- `bootctl status` reports Secure Boot enabled, if you left it on.
- `systemctl --failed` is clean. Upstream warns `systemd-remount-fs.service` can fail on
  Anaconda-installed bootc systems. It stayed clean in our VM test.
- `ls -l /dev/kfd /dev/dri/renderD*` shows group `halogen`.
- `sudo ausearch -m avc -ts boot` is empty. If `/dev/kfd` shows `denied { map }`, run
  `sudo setsebool -P container_use_devices true`.
- A soak test mixes your real load for several hours. Kernel 7.2 has a reported GPU memory
  fault, and Halogen's reference host ran 7.1.8.

On the NPU edition, also confirm:

- `ls -lZ /dev/accel/accel0` shows group `halogen` and type `dri_device_t`.
- `/usr/libexec/halogen/halogen-fabric-clock status` reports the clock as held. With Secure
  Boot on, the kernel runs in lockdown, and this has not been tested on hardware.

### Tools on the machine

The OS is kept small, but these are included for looking after it:

| Command | What it's for |
|---|---|
| `amd-smi metric` | GPU temperature, power and clocks. On Strix Halo some fields show N/A |
| `nvtop` | Live GPU use, and which process holds GPU memory |
| `htop` | Live CPU and memory use |
| `tmux` | Keeps a long command running if your SSH connection drops |
| `lspci`, `lsusb` | List the hardware |
| `nvme list`, `sudo nvme smart-log /dev/nvme0` | Disk health |
| `fwupdmgr` | Firmware updates from the vendor, where the board supports it |

Firmware updates use [fwupd](https://fwupd.org/). Check for them with
`sudo fwupdmgr refresh && sudo fwupdmgr get-updates`, and apply them with
`sudo fwupdmgr update`. A BIOS update reboots the machine, which stops Halogen until it is back.

### Your own NPU checkpoints

On the NPU edition, Halogen also runs checkpoints you supply, such as LiquidAI's `d1-2B` and
the LFM3 family, or your own fine-tune of one of its NPU models. Halogen's
[NPU guide](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/NPU.md#your-own-model)
lists what runs. Download one from Hugging Face with:

```bash
sudo halogenctl model pull LiquidAI/LFM3-1.7B     # add --as <name> or --revision <commit> if you like
sudo halogenctl model list
sudo halogenctl model remove LFM3-1.7B
```

`model pull` uses your Hugging Face token if you saved one (gated repos need it), resumes if
interrupted, and puts the checkpoint in the folder that fits:

| Folder | What goes there | Named in `HALOGEN_NPU_MODELS` as |
|---|---|---|
| `/srv/models/decider` | `d1-2B`, fine-tunes of `decider-0.8b` | `/models/decider/<name>` |
| `/srv/models/LFM` | LFM3-1.7B, LFM3-VL-2B, LFM3-Audio-2B, LFM3-Omni-2B | `/models/LFM/<name>` |
| `/srv/models/custom` | Fine-tunes of the embedding, reranking or guard models | `/models/custom/<name>` |

It then prints the line to put in `/srv/configs/halogen.env`, and offers to make the change and
restart. Halogen serves the model under its folder's name. Its first start converts the
checkpoint for the NPU (about a minute) and keeps the result beside it. Halogen fetches only the
NPU programs it runs on, never the weights. These three folders are the only ones the server
can write to.

## 8. Optional: unlock LUKS with the TPM

If you chose LUKS, you can avoid typing the passphrase at each boot:

```bash
sudo halogen-enroll-tpm
sudo systemctl reboot
```

Keep the passphrase as your recovery key. TPM unlock uses PCR 7, which records the Secure Boot
state. OS updates and rollbacks don't change it. Turning Secure Boot off or on, changing its
keys, clearing the TPM, and some BIOS or Secure Boot revocation-list updates do. After one of
those, boot asks for the passphrase. Enter it, then run `halogen-enroll-tpm` again. It replaces
the old TPM binding rather than adding another. The CI install
test enrolls the TPM and reboots without a passphrase, but this hasn't been confirmed on
hardware yet. If the next boot still asks for the passphrase, report it.

## If something goes wrong

| Symptom | Check |
|---|---|
| Machine reports far less than 128 GB | Set the UMA frame buffer to its minimum, not Auto, if the BIOS offers it |
| `curl localhost:8731` gets "connection reset" | Releases before alpha.3 only. Use `127.0.0.1` instead of `localhost` |
| `/dev/accel/accel0` is missing | Use the NPU edition, and check the IOMMU and firmware |
| Fabric clock is not held | `systemctl status halogen-fabric-clock` |
| Halogen stays down after a config edit | `sudo halogenctl status`, then check the NPU model names |
| Start hangs, or GTT stays in use after a crash | Reboot, as Halogen's troubleshooting guide explains |

For anything else, see Halogen's
[troubleshooting guide](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md).

Next: [configure the server](README.md#configure).
