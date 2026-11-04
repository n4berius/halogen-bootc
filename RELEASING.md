# Releasing

## Channels

Git tags start a release. Each one must be on `main` and match `HALOGEN_VERSION` in
`versions.env`.

| Channel | Git tag | Image tag | Meaning | GitHub release |
|---|---|---|---|---|
| Edge | None, every push to `main` | `edge` | Newest build, for testing | None |
| Alpha | `v0.18.23-alpha.1` | `0.18.23-alpha.1`, `alpha` | Builds and installs in a VM, not proven on hardware | Pre-release |
| Beta | `v0.18.23-beta.1` | `0.18.23-beta.1`, `beta` | Passed the hardware checklist on one machine | Pre-release |
| RC | `v0.18.23-rc.1` | `0.18.23-rc.1`, `rc` | Passed a soak test, no known blockers | Pre-release |
| Stable | `v0.18.23` | `0.18.23`, `stable`, `latest` | Recommended | Release |
| Stable fix | `v0.18.23-r2` | `0.18.23`, `stable`, `latest` | Fix to this project on the same Halogen version | Release |

Add `-no-npu` to any image tag for the other edition, such as `0.18.23-beta.1-no-npu`.

`0.18.23` and the channel tags move. `0.18.23-alpha.1` and the like are never rebuilt. Each
Monday, the newest stable release is rebuilt with Fedora updates.

## Cut a release

```bash
git checkout main && git pull
git tag v0.18.23-alpha.1
git push origin v0.18.23-alpha.1
```

The tag triggers checks, both images, a full VM install of each ISO, and then the GitHub
release. Nothing is published as a release unless both installs pass, but the images are
pushed before the ISO tests run. If a run fails, fix it on `main` and cut the next number.

## Move to a new Halogen version

1. Read Halogen's changelog for host, NPU and flag changes.
2. Update `HALOGEN_VERSION`, `HALOGEN_SOURCE_COMMIT` and the three hashes in `versions.env`.
3. Update the image tag in `kickstart/strix-halo.ks`.
4. Run `scripts/gen-options.py` on the new `docs/FLAGS.md`, and review new options.
5. Open a pull request, merge it, and start again at alpha.

## Branch protection

GitHub needs Pro or a public repository for this. Once either is true, run
`scripts/apply-branch-protection.sh`.
