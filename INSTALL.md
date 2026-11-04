# Installing halogen-bootc

This guide covers a new install from USB, from choosing an edition to a working API.
For how Halogen itself behaves, see its
[official documentation](https://github.com/peonist-ai/halogen-flash-server/tree/main/docs).

> Neither edition has been tested on real hardware yet. Expect to work through the
> [checks](#check-the-install) on your first install.

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
2. Set the UMA frame buffer, or dedicated graphics memory, to its explicit minimum, not Auto.
3. Leave Secure Boot on if you want it. No MOK enrollment is needed.
4. Use the BIOS power settings you want. Halogen's published numbers assume about 85 W.

## 3. Get the ISO

Open the newest successful **Build USB installer** run in this repository's Actions tab, and
download the installer for your edition. To build one yourself, see
[Build](README.md#build) in the README.

## 4. Write the USB drive

Use [Fedora Media Writer](https://fedoraproject.org/workstation/download/) with its custom
image option, or use `dd` on Linux. Check the device name first, because `dd` overwrites it
without asking:

```bash
lsblk
sudo dd if=bootc-fedora-45-generic-iso-x86_64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

## 5. Run the installer

1. Boot from the USB drive and choose **Install halogen-flash-bootc**.
2. Pick your language.
3. Under **Installation Destination**, choose the disk. It defaults to LVM with XFS.
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

Later boots skip the download unless the model list or Halogen version changes.

## 7. Check the install

```bash
sudo halogenctl doctor
sudo halogenctl status
sudo halogenctl config
curl -H "Authorization: Bearer $(sudo halogenctl api-key)" http://localhost:8731/v1/models
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

## 8. Optional: unlock LUKS with the TPM

If you chose LUKS, you can avoid typing the passphrase at each boot:

```bash
sudo halogen-enroll-tpm
sudo systemctl reboot
```

Keep the passphrase as your recovery key. TPM unlock uses PCR 7, so changing Secure Boot
settings means entering the passphrase and running `halogen-enroll-tpm` again.

## Unattended install

`kickstart/strix-halo.ks` installs the NPU edition without prompts from the Fedora netinstall
ISO. **It erases `nvme0n1`.** Replace the SSH key first, and make sure the installer can read
the image, because Anaconda's `bootc` method cannot use a private registry.

## If something goes wrong

| Symptom | Check |
|---|---|
| Machine reports far less than 128 GB | Set the UMA frame buffer to its minimum, not Auto |
| `/dev/accel/accel0` is missing | Use the NPU edition, and check the IOMMU and firmware |
| Fabric clock is not held | `systemctl status halogen-fabric-clock` |
| Halogen stays down after a config edit | `sudo halogenctl status`, then check the NPU model names |
| Start hangs, or GTT stays in use after a crash | Reboot, as Halogen's troubleshooting guide explains |

For anything else, see Halogen's
[troubleshooting guide](https://github.com/peonist-ai/halogen-flash-server/blob/main/docs/troubleshooting.md).

Next: [configure the server](README.md#configure).
