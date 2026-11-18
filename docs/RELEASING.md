# Releasing

How a version of Azeroth Guild Finder is built and published. The workflow is [release.yml](../.github/workflows/release.yml); the decisions are in [ADR 0022](adr/0022-release-packaging-with-the-bigwigs-packager.md). Only the repository owner tags and adds secrets.

## What a tag does

Pushing a tag `vMAJOR.MINOR.PATCH` (optionally `-alpha`, `-beta` or `-rc`, with `.N`: `v1.0.0`, `v0.9.0-beta.1`) starts the workflow **Release**, which:

1. checks what the package will contain (`tools/check_package.py`);
2. builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager): libraries from `.pkgmeta`, `## Version` filled in with the tag, `Tests/`, `docs/`, `tools/` and Markdown left out, `LICENSE` and the font licences kept, development code switched off;
3. checks the zip itself (`tools/check_package.py --zip`) and keeps it as a workflow artifact for 14 days;
4. creates the **GitHub Release** with that zip (a pre-release when the tag has `-alpha`, `-beta` or `-rc`);
5. uploads to **CurseForge**, only if both the `CF_API_KEY` secret and the project ID in the TOC are set (not for `-rc` tags). Otherwise it says "CurseForge skipped" and the run stays green.

Check the package locally at any time, with no network and no secrets:

```bash
python -I -X utf8 tools/check_package.py --list
```

## Try it without publishing anything

1. **Dry run**: Actions → *Release* → *Run workflow* on `main`, leave `draft_tag` empty. It builds and checks the zip; download it from the run's artifacts and look inside. Nothing is published.
2. **Draft release**: run it again with `draft_tag` = `v0.0.1-alpha.1`. It creates a **draft** GitHub Release with the zip; only you can see drafts. Open it, then delete the draft. No tag is pushed and CurseForge is not touched.
3. **Test tag** (this makes a real, public pre-release; delete the release and the tag afterwards):

   ```bash
   git tag -a v0.0.1-alpha.1 -m "Test tag for the release workflow"
   git push origin v0.0.1-alpha.1
   ```

   Afterwards: `gh release delete v0.0.1-alpha.1 --cleanup-tag --yes`.

## Setting up CurseForge (once)

The texts, images and a step-by-step guide for the project page are in [curseforge/SETUP.md](curseforge/SETUP.md) (Italian).

1. Create a project on [CurseForge](https://www.curseforge.com/wow/addons) for World of Warcraft addons: name *Azeroth Guild Finder*, licence GPL-3.0, the unofficial notice and the privacy summary on the description (SPEC-09 §4). Make sure the project's game versions include **WoW Forever**.
2. Copy the **Project ID** (a number, on the project's *About* panel) into the TOC: in `AzerothGuildFinder/AzerothGuildFinder.toc` replace the commented line `# ## X-Curse-Project-ID: 0` with `## X-Curse-Project-ID: 12345` (your number, two `#` signs, no space in front). Ship that in a normal pull request.
3. Create an API token at <https://www.curseforge.com/account/api-tokens>.
4. Add it in the GitHub repository: **Settings → Secrets and variables → Actions → New repository secret**, name `CF_API_KEY`, value the token. Do this yourself; never paste the token in an issue, a pull request or a chat.
5. Push a `-beta` tag (a pre-release) before the first real version, and look at the CurseForge file: its game version and release type (*Beta*).

Until steps 2 and 4 are both done, tags only publish on GitHub.

## Releasing a version

1. Everything merged on `main`, CI green, the in-game checklist passed (`docs/checklists/`).
2. Update `CHANGELOG.md` (move *Unreleased* under the new version) and the README and wiki status in a normal pull request.
3. Tag the merge commit and push the tag (as in the test above, with the real version).
4. Watch the run in the Actions tab, then open the GitHub Release (and CurseForge) and download the zip once: the folder must be `AzerothGuildFinder/` with the TOC inside.
5. Wrong release? Delete the GitHub Release and the tag (`gh release delete vX --cleanup-tag --yes`), remove the file on CurseForge, fix, and tag again with a new patch number; do not reuse a tag that was public.
