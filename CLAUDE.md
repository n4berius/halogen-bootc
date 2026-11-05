# Notes for Claude Code

halogen-bootc is a Fedora 45 bootc OS image, plus an Anaconda USB installer, for one job:
running [halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server) ("Halogen")
on a dedicated AMD Strix Halo 128 GB server. It configures and deploys Halogen. It never
modifies Halogen itself, which is closed source under Peonist's EULA.

The owner, n4berius, is not a programmer. Explain changes in plain language, keep pull
requests focused, and say what was and wasn't tested. Halogen's
[official docs](https://github.com/peonist-ai/halogen-flash-server/tree/main/docs) are the
authority on its settings and behaviour. Read them instead of guessing, and link to them in
our docs.

## Ground rules

- `main` is protected. Work on a branch and open a PR. Never push to `main`, force-push it,
  or move release tags.
- Never commit secrets. The API key and the HF token live only on the machine, under
  `/srv/configs`.
- Releases are cut by the owner (Actions > Release > Run workflow, with a tag such as
  `v0.18.23-alpha.3`). Don't create tags or releases yourself.
- If GitHub or a registry refuses an action (403 from the session proxy), stop and tell the
  owner. Don't work around it.
- Run `tests/run.sh` before every push. CI also runs shellcheck, which may not be installed
  locally.

## Layout

| Path | What it is |
|---|---|
| `versions.env` | Every pinned input: Fedora base, Halogen version, digest and source commit, upstream file hashes, weights repo and revision, Debian image, XRT minimum |
| `Containerfile` | The OS image. XRT comes from Debian trixie-backports, because Halogen's container is Debian 13 |
| `Containerfile.installer`, `installer/` | The live installer image, Anaconda defaults (storage layout), branding and boot menu |
| `files/` | Copied into both editions: systemd units, `halogenctl`, `halogen-enroll-tpm`, `/usr/libexec/halogen/*` |
| `variants/npu`, `variants/no-npu` | Per-edition kernel arguments, Quadlet drop-ins, the allowed-options list and default `halogen.env` |
| `scripts/` | `build.sh`, `build-iso.sh`, `package-iso.sh` (single-file release ISO), `release-info.sh`, `gen-options.py` (options from upstream `FLAGS.md`), `halogen-update.sh` (pins a new Halogen release), `size-report.sh` |
| `tests/` | `run.sh` (fast checks, no GPU or network), `iso-install.sh` + `vm-login.py` (QEMU install test) |
| `.github/workflows/` | `build.yml` (image, edge tag), `iso.yml` (ISO + VM install test), `release.yml`, `refresh.yml` (weekly rebuild of stable), `halogen-update.yml` (daily: opens a PR for a new Halogen release) |

## How the running system works

- Halogen runs as the rootless `halogen` user (UID 970) through a Quadlet in
  `/etc/containers/systemd/users/970/`, with linger on. `halogenctl` wraps it, so run it with
  `sudo`.
- First boot: `halogen-prepare` (root) creates `/srv/models`, `/srv/configs`, `halogen.env`
  and the API key. `halogen-fetch` (user) pulls the pinned image, downloads models with `hf`
  inside that image, and runs Halogen's `verify`. Then `halogen.service` starts read-only and
  offline. Each restart of `halogen.service` reruns the fetch, which only downloads what's
  missing or changed.
- Settings: users edit `/srv/configs/halogen.env`. `render-config` keeps only the names in
  `options.allowed`, and `locked.env` wins over it. `halogenctl config` shows the result.
- NPU models live in `/srv/models/npu/<halogen-version>/<model>` (#18 plans to drop the
  version folder). Their files are checked against the hashes in the pinned image's
  `/opt/halogen/npu/models.txt`.
- `/srv` is `/var/srv` on bootc. The installer makes LVM volumes for `/`, `/var`, `/var/log`,
  `/var/log/audit`, `/var/home`, `/var/srv/configs` and `/var/srv/models`.
- Updates are manual (`bootc switch` / `upgrade`), since a reboot stops inference. Pre-release
  tags never move. The version tag (`0.18.23`) moves with stable releases and weekly rebuilds.

## Lessons already learned

- The initramfs must be built with `--no-hostonly` and the `crypt systemd-cryptsetup tpm2-tss
  lvm` modules, or LUKS fails at boot on real hardware. The Containerfile checks this.
- The root volume is mounted at `/sysroot`, not `/`.
- The Anaconda `.buildstamp` product name becomes the volume group name. Keep it short.
- `halogen-enroll-tpm` uses PCR 7 and `--wipe-slot=tpm2`, so re-enrolling replaces the old
  binding. Enrolling twice on the same boot is a no-op ("already enrolled").
- In the VM test, `systemd-pcrextend` needs `SYSTEMD_FORCE_MEASURE=1` on non-UKI boots.
- `vm-login.py` types through QEMU `sendkey`. Any new character in a typed command needs a
  key mapping, or it is silently dropped.
- Halogen 0.18.x listens on IPv4 only, hence `PublishPort=0.0.0.0:8731`. 0.19.0 adds IPv6.
- `hf` is noisy and shows no progress in the journal. `fetch-in-container` filters it, and
  `fetch-models` logs the size downloaded every minute.
- Own NPU checkpoints (`d1-2B`, `LFM3-*`) are named by path, need NPU programs fetched, and
  are converted at first start. This doesn't work yet (#19).
- ISO install tests take about 25 to 40 minutes, and a new push cancels the previous run.
  Don't push mid-run unless you mean to.
- GitHub release assets must be under 2 GiB. The ISO ships as `.iso.xz` (about 1981 MiB)
  with little headroom (#26).

## Where the work stands

Open issues and the **beta** milestone are the source of truth, prioritised with the
`priority: high/medium/low` labels. When this file was written:

- PR #22 (draft) adds `scripts/size-report.sh` to the ISO workflow. Its artifacts
  (`size-report-npu` / `size-report-no-npu`) drive trimming for #26.
- #23 waits for the weights commit hash freyja downloaded:
  `sudo head -n1 /srv/models/.cache/huggingface/download/qwen38-flash-next-v2.hgn.metadata`.
- #24: build the Halogen update workflow, then let it open the 0.19.0 update PR. The
  changelog notes are on the issue.
- #25 is the hardware checklist for beta.

The owner's test machine is "freyja": an AMD Ryzen AI Halo Developer Platform (128 GB,
2 TB NVMe), NPU edition, Secure Boot on.

## Commits and pull requests

Use plain, specific messages that explain why. PR descriptions have a summary and a test plan
with checkboxes, and say whether real hardware was involved.
