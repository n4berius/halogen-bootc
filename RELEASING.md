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

On GitHub, open **Actions > Release > Run workflow**. Keep the branch as `main`, enter the tag,
such as `v0.18.23-alpha.1`, and choose **Run workflow**. Do not use **Draft a new release**,
because the workflow creates the release itself.

You can also push a tag from your own computer:

```bash
git checkout main && git pull
git tag v0.18.23-alpha.1
git push origin v0.18.23-alpha.1
```

Either way, the workflow runs checks, builds both images, runs a full VM install of each ISO, and
then creates the GitHub release. Nothing is published as a release unless both installs pass, but the images are
pushed before the ISO tests run. If a run fails, fix it on `main` and cut the next number.

## Move to a new Halogen version

1. Read Halogen's changelog for host, NPU and flag changes.
2. Update `HALOGEN_VERSION`, `HALOGEN_SOURCE_COMMIT` and the three hashes in `versions.env`.
3. Run `scripts/gen-options.py` on the new `docs/FLAGS.md`, and review new options.
4. Open a pull request, merge it, and start again at alpha.

## Branch protection

The rules live in `.github/rulesets/`. To apply them, go to **Settings > Rules > Rulesets**,
choose **New ruleset > Import a ruleset**, pick a file, then choose **Create**. Do this once
for each file.

| File | What it does |
|---|---|
| `protect-main.json` | Changes go through a pull request with passing builds of both editions. No force-pushes or deleting `main` |
| `protect-release-tags.json` | Release tags cannot be moved or deleted, except by an admin |

The repository owner can still bypass both rules in an emergency. No approval is required,
because GitHub does not let you approve your own pull request. The ISO install test is not
a required check, because it only runs when certain files change, but check it before
merging anything that touches the image or installer.
