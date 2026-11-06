# Roadmap

Where halOS is heading, and in what order. The [open issues](https://github.com/n4berius/halos-flash/issues)
hold the details and are the source of truth; this page is the order. Anything not listed here
waits until after the stable release.

How releases are used:

| Channel | Used for |
|---|---|
| edge | every change, always on the test machine |
| alpha | small milestones |
| beta | major milestones, after the hardware checklist |
| rc and stable | about quarterly, after a soak test |

## Now: v0.19.1-beta.1

Promote `v0.19.1-alpha.2` once the test machine has run it for a few days:
- normal use on the official checkpoint and on a custom one
- the selftest clean on both
- one rollback and back

## Before the release candidate

In this order. Each ships as an alpha, then is promoted to beta once tested.

1. **Machines refuse unsigned images** (#46, phase 2). Images are signed since `v0.19.0-alpha.5`.
   Until machines check the signature, it protects nothing.
2. **First-boot setup and an "API ready" line on the login screen** (#43). Today nothing tells a
   new owner when the 130 GB first download is done.
3. **Guided installer** (#42). It picks the disk, asks only for encryption, root and the admin user,
   and uses fixed `halos-*` volume names.
4. **A full security audit** of the whole image, not just of single changes.

## After the release candidate, before stable

- **Benchmark command** (#15). A fixed-length run with Halogen's `ignore_eos`, to compare
  releases and checkpoints fairly.
- **`halogenctl flash check`** (#56). Compare a custom checkpoint's quality with the official
  one's, on request.
- **`halosctl npu on|off`** (#40). Switch between the two editions.
- **Tab completion** (#14).

## Later, after stable

- Unlock the disk over SSH at boot (#13).
- Unlock the disk from a tang server on the network (#44).
- GGUF repositories in `flash pull` (#61).

## Always

- Each new Halogen release gets a pull request from the daily check. It ships as an alpha once
  its checks pass.
- A soak test on the test machine before every promotion.
