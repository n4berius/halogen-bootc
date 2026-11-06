# Notes for Claude Code

halOS (formerly halogen-bootc) is a Fedora 45 bootc OS image, plus an Anaconda USB installer, for one job:
running [halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server) ("Halogen")
on a dedicated AMD Strix Halo 128 GB server. It configures and deploys Halogen. It never
modifies Halogen itself, which is closed source under Peonist's EULA.

The owner, n4berius, is not a programmer. Explain changes in plain language, keep pull
requests focused, and say what was and wasn't tested. Halogen's
[official docs](https://github.com/peonist-ai/halogen-flash-server/tree/main/docs) are the
authority on its settings and behaviour. Read them instead of guessing, and link to them in
our docs.

Naming: the project is **halOS** in prose and the installer, and `halos-flash` where a name
must be lowercase (the image `ghcr.io/n4berius/halos-flash`, ISO and asset names). Names that
refer to Halogen the server stay: `halogenctl`, the `halogen` user, `/srv/models`, the
`HALOGEN_*` settings. Peonist's trademark policy doesn't allow "halogen" in our product's
name, but allows saying halOS runs Halogen.

## Ground rules

- `main` is protected. Work on a branch and open a PR. Never push to `main`, force-push it,
  or move release tags.
- Never commit secrets. The API key and the HF token live only on the machine, under
  `/srv/configs`.
- Releases are cut by the owner (Actions > Release > Run workflow, picking alpha, beta, rc or
  stable; `scripts/next-tag.sh` numbers it, and beta/rc/stable promote the newest published
  release one step below). Don't create tags or releases yourself.
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
| `files/` | Copied into both editions: systemd units, `halosctl`, `halogenctl`, `halogen-enroll-tpm`, `/usr/libexec/halogen/*` |
| `variants/npu`, `variants/no-npu` | Per-edition kernel arguments, Quadlet drop-ins, the allowed-options list and default `halogen.env` |
| `scripts/` | `build.sh`, `build-iso.sh`, `package-iso.sh` (single-file release ISO), `release-info.sh`, `gen-options.py` (options from upstream `FLAGS.md`), `halogen-update.sh` (pins a new Halogen release), `size-report.sh`, `channels.sh` (which channel tags a release moves), `next-tag.sh` (the next release tag), `push-image.sh`, `sign-image.sh` (cosign signing) |
| `tests/` | `run.sh` (fast checks, no GPU or network), `iso-install.sh` + `vm-login.py` (QEMU install test) |
| `.claude/agents/` | Subagents: `code-reviewer` (QA review before merge) and `security-auditor` (audit, zero-cost hardening ideas). Both only read and report |
| `.github/workflows/` | `build.yml` (image, edge tag; also weekly, Thursday 05:37 UTC), `iso.yml` (ISO + VM install test), `release.yml`, `refresh.yml` (weekly rebuild of stable), `halogen-update.yml` (daily: opens a PR for a new Halogen release) |

## How the running system works

- Halogen runs as the rootless `halogen` user (UID 970) through a Quadlet in
  `/etc/containers/systemd/users/970/`, with linger on. `halogenctl` wraps it, so run it with
  `sudo`. `halogenctl model pull|list|remove` manages your own NPU checkpoints. `halogenctl selftest`
  (`/usr/libexec/halogen/selftest`, root) runs the beta hardware checklist read-only; the VM
  install test runs it too and checks what a VM can pass.
- First boot: `halogen-prepare` (root) creates `/srv/models`, `/srv/configs`, `halogen.env`
  and the API key. `halogen-fetch` (user) pulls the pinned image, downloads models with `hf`
  inside that image, and runs Halogen's `verify`. Then `halogen.service` starts read-only and
  offline. Each restart of `halogen.service` reruns the fetch, which only downloads what's
  missing or changed.
- Settings: users edit `/srv/configs/halogen.env`. `render-config` keeps only the names in
  `options.allowed`, and `locked.env` wins over it. `halogenctl config` shows the result.
  `halogen.env` is copied once and never changed by halOS. `prepare` rewrites
  `/srv/configs/halogen.env.example` (the edition's template) at every boot, `halogenctl options
  [--new]` lists every option as set, commented or new, and each release attaches both editions'
  templates as `halos-flash-<tag>-<edition>-halogen.env.example`.
- NPU models live in `/srv/models/npu/<model>`, with no version folder. Their files are
  checked against the hashes in the pinned image's `/opt/halogen/npu/models.txt`, so an
  upgrade downloads only what changed. Old `npu/<version>/` folders are moved across by
  `fetch-models`.
- Own NPU checkpoints live in `/srv/models/{decider,LFM,custom}/<name>`, put there by
  `halogenctl model pull` (`model-pull`, which uses Halogen's `halogen-npu probe` to pick the
  folder). The fetch probes each path in `HALOGEN_NPU_MODELS` and fetches its NPU programs.
  These folders are mounted writable, because Halogen keeps a conversion beside the
  checkpoint only on a writable folder (on a read-only one it converts into /tmp at every start).
- `/srv` is `/var/srv` on bootc. The installer makes LVM volumes for `/`, `/var`, `/var/log`,
  `/var/log/audit`, `/var/home`, `/var/srv/configs` and `/var/srv/models`.
- Updates are manual, since a reboot stops inference. `halosctl` (`files/usr/bin/halosctl`)
  handles the OS: `version`, `switch <channel>`, `upgrade`, `rollback [--to]`, `history`
  (`/var/lib/halos/history`). `halogenctl` handles the engine and models. Exact release tags
  never move. Channel tags (`alpha`, `beta`, `rc`, `stable`, `edge`) do, and each one points to
  the newest release at least that stable (`scripts/channels.sh`), so a channel never moves
  backwards. The version tag (`0.19.0`) moves with stable releases and weekly rebuilds. The
  image's release name is `HALOS_RELEASE` in `release.env` and its version label (#40).
- Root never works inside halogen's folders: `prepare`, `halogenctl` and `selftest` read and write
  there through `runuser -u halogen` (security audit P1/P2/P7). The two root boot units are
  sandboxed (`ProtectSystem=strict`, no network); verify and the model probe run with no network
  or capabilities; `sysctl.d/60-halos.conf` and `sshd_config.d/00-halos.conf` hold the no-cost
  hardening. The ISO builder is pinned by digest (`IMAGE_BUILDER` in `versions.env`).
- Every pushed image is signed keyless with cosign by `scripts/sign-image.sh` (from main's copy,
  also when promoting old code), and checked in the same job, including the classic `.sig` tag
  that containers/image reads. Machines don't enforce it yet (#46 phase 2).

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
- Halogen 0.18.x listened on IPv4 only, so we published `0.0.0.0:8731`. From 0.19.0 it listens
  on IPv6 too, and the port is published dual-stack.
- `HALOGEN_AGENT_GUARD=watch|hold` makes Halogen add `halogen-spotter-0.6b` and `decider-4b`
  at start. The server never downloads, so `fetch-models` adds them to the fetch.
- `hf` is noisy and shows no progress in the journal. `fetch-in-container` filters it, and
  `fetch-models` logs the size downloaded every minute.
- Own NPU checkpoints (`d1-2B`, `LFM3-*`) are named by path, need NPU programs fetched, and
  are converted at first start. `halogen-npu probe` links XRT, so the fetch mounts it, but it
  needs no NPU device and only the checkpoint's config and tokenizer (checked against 0.19.0's
  image). Some of Halogen's models have no download of their own and reuse others' programs
  (`lfm3-omni-2b`, the `-fast` VL and Audio): check the model is known, not that it has a repo.
- ISO install tests take about 25 to 40 minutes, and a new push cancels the previous run.
  Don't push mid-run unless you mean to.
- The OS image is flattened (`FROM scratch` + `COPY --from=os / /`) after its `dnf remove`
  step, with `/sysroot/ostree` deleted first, as Fedora's rechunker does. Otherwise the removed
  files still ship in the base image's layers inside the ISO. File capabilities survive the copy.
- GitHub release assets must be under 2 GiB. Since the trimmed, flattened image (#22, #26) the
  ISO ships as a plain `.iso` of about 1370 MiB; `package-iso.sh` falls back to `.iso.xz` if not.

## Where the work stands

Open issues are the source of truth, prioritised with the `priority: high/medium/low` labels
and tracked on the owner's project board. When this file was last updated (after
`v0.19.0-beta.1`):

- Released: `v0.19.0-beta.1`, promoted from alpha.4. Freyja passed the beta checklist (#25,
  closed): TPM unlock, `halosctl` switch, upgrade and rollback keeping `/srv`, selftest 30/30.
- Before RC, in this order: image signing (#46; phase 1 signs every push, phase 2 ships the
  machine-side policy in a later release), first-boot setup and "API ready" banner (#43), the
  guided installer with fixed `halos-*` volume names (#42), and a full `security-auditor` pass.
- Later: `halosctl` steps 2 and 3 (#40), a benchmark command (#15), tab completion (#14), unlock
  over SSH (#13) and clevis/tang (#44).
- Known upstream: bootc 1.17.1 rewrites `/etc/fstab` at every boot on Anaconda installs
  (bootc-dev/bootc#2592); `bootc-fstab-edit.service.d/10-halos.conf` skips it. `bootc switch` to
  the ref a machine already follows does nothing; use `bootc upgrade`.

The owner's test machine is "freyja": an AMD Ryzen AI Halo Developer Platform (128 GB,
2 TB NVMe), NPU edition, Secure Boot on.

## Commits and pull requests

Use plain, specific messages that explain why. PR descriptions have a summary and a test plan
with checkboxes, and say whether real hardware was involved.

Before asking the owner to merge a PR, run the `code-reviewer` subagent on it and fix or answer
what it finds. Run `security-auditor` too when the change touches services, permissions, the
firewall, containers, secrets, the installer or LUKS/TPM. Hardening it suggests goes in its own
PR, only once the owner agrees.
