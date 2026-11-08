# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Design

- Specification of the first version in `docs/specs/` (SPEC-00 to SPEC-10, in Italian): scope and roles, platform and peer-to-peer architecture, network protocol, data model, interface, applications, emblems, quality and release, risks and open questions.
- Mockups v2 in `docs/specs/mockups/`: design system (Albion-like skin on a Material Design 3 skeleton, Roboto and Roboto Mono), Find a Guild, guild page, listing editor (recruitment and activity steps), emblem designer, applications, notification icon, role-based states. Rendered to WebP by `render.sh`.
- Four roles (Tank, Healer, Melee DPS, Ranged DPS), up to three activities per guild and a commitment level (Casual, Softcore, Hardcore).
- Architecture decisions 0001–0018 in `docs/adr/`.

### Planning

- Development roadmap in `docs/roadmap/`: one file per milestone (M0 spike to M5 release, 44 steps) with branch, dependencies, scope, acceptance criteria, tests, docs and real-client checks, plus the V2 backlog.
- Decisions confirmed by the owner: names (addon, channel `AzGuildFinder`, prefix `AzGF`, `/gf`), one open application per character, optional role checkboxes in the application, 14-day expiry, 7-day cooldown, unique players as a range, anonymous alt count on by default.

### Project

- README in English and Italian, CONTRIBUTING, Code of Conduct, roadmap, GPL-3.0 licence, funding link.
- Automation: CI (`Tests`), docs rule (`Docs rule`), wiki sync from `docs/wiki/`, advisory DCO check, issue and pull request templates, `tools/ship_step.py` (commit, push, pull request, CI, squash merge).
- User manual draft in `docs/wiki/`.
