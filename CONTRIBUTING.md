# Contributing to Azeroth Guild Finder

Thank you for your interest! This guide explains how to report problems, propose ideas and change the project.

## Language

Issues, pull requests, commit messages and public documentation are in **English**. The internal specification in `docs/specs/` is in Italian ([ADR 0016](docs/adr/0016-english-first-ui-and-documentation-languages.md)). Discussions can be in English or Italian.

## Contents

1. [Before you start](#1-before-you-start)
2. [Reporting a problem or proposing an idea](#2-reporting-a-problem-or-proposing-an-idea)
3. [Changing the code](#3-changing-the-code)
4. [Checks and tests](#4-checks-and-tests)
5. [Git, issues and pull requests](#5-git-issues-and-pull-requests)
6. [What is not accepted](#6-what-is-not-accepted)
7. [Licensing of contributions](#licensing-of-contributions)

## 1. Before you start

- Read the [specification](docs/specs/README.md) and the [ADRs](docs/adr/README.md): they explain what the addon does and why.
- The addon targets **WoW Forever, Interface 16001**. Check every API in the Forever API dump ([ADR 0002](docs/adr/0002-wow-forever-target-and-api-dump.md)) and guard it with the Compat layer.

## 2. Reporting a problem or proposing an idea

- **Bugs**: open an issue with the *Bug report* form.
- **Ideas and questions**: start a topic in the [Feedback discussions](https://github.com/Finland6738/azeroth-guild-finder/discussions/categories/feedback); a concrete request can become a *Feature request* issue.
- **Checks in the real client**: use the *In-game test report* form.
- **Privacy**: never paste other players' names, whispers, account names or folder paths from your PC.

## 3. Changing the code

- Modules are isolated and talk through the internal event bus ([SPEC-01 §3](docs/specs/SPEC-01-platform-architecture.md)).
- Every visible string goes through AceLocale (`L["KEY"]`).
- Saved data changes need a schema migration ([ADR 0011](docs/adr/0011-savedvariables-and-schema-versions.md)).
- Never call game textures by copying files: reference them by fileID ([ADR 0007](docs/adr/0007-emblems-from-tabard-pieces.md)).
- The addon lives in `AzerothGuildFinder/` (Lua 5.1 only). Libraries are never committed: they are pinned in `.pkgmeta`; run `python -I -X utf8 tools/fetch_libs.py` to download them and `python -I -X utf8 tools/install_addon.py` to copy the addon into your AddOns folder (path in the git-ignored `tools/local.ini`).
- Mockups: edit `docs/specs/mockups/html/`, then run `bash docs/specs/mockups/render.sh` (Chrome and Python with Pillow).

## 4. Checks and tests

```
python -I -X utf8 tools/check_docs.py
```

It checks the addon TOC and `embeds.xml` (Interface 16001, every listed file exists), relative links, the wiki sidebar and links, the ADR index, personal data (emails and personal paths) and LF line endings. From milestone M1 the offline addon tests (`Tests/run_tests.py`, Lua 5.1 through lupa) run too. CI runs both on every pull request.

## 5. Git, issues and pull requests

- One branch per step or fix from an up-to-date `main`: `step/m<N>-<name>`, `fix/<name>`, `docs/<name>`, `chore/<name>`.
- Small commits with clear messages in English.
- Every pull request updates **in the same PR**: `CHANGELOG.md` ("Unreleased"), the affected docs (specs, ADRs and the ADR index, both READMEs) and **the wiki pages in `docs/wiki/` for any user-visible change**. The *Docs rule* check enforces it for changes under `AzerothGuildFinder/`; use the label `no-docs-needed` only for pure refactors or tests.
- The wiki is **never edited on GitHub**: it is published from `docs/wiki/` after every merge ([ADR 0014](docs/adr/0014-github-wiki-generated-from-docs-wiki.md)).
- `main` is protected: the checks `Tests` and `Docs rule` must be green; pull requests are squash merged.
- The maintainer's steps are shipped with `tools/ship_step.py` ([ADR 0013](docs/adr/0013-git-flow-and-automated-shipping.md)).
- A pull request that fixes an issue says `Closes #N`.

## 6. What is not accepted

- Code that sends anything outside the game, telemetry or external services.
- Files copied from the game client or from other games.
- Rankings, paid placement or features that publish data about single players.
- Personal data in the repository.

## Licensing of contributions

By submitting a contribution you agree that it is released under the project's licence, the [GNU GPL v3.0](LICENSE), and you certify that you have the right to submit it (Developer Certificate of Origin: sign off your commits with `git commit -s`).
