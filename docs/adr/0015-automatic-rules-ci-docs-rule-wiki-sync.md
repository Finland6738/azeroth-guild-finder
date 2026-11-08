# 0015. Automatic rules: CI, a docs rule and the wiki sync

- Status: Accepted
- Date: 2026-11-08 (same approach as azeroth-unspoken, ADR 0022 there)

## Context

Automated merges ([ADR 0013](0013-git-flow-and-automated-shipping.md)) are only safe if the rules are enforced by machines.

## Decision

1. **CI** (`ci.yml`, job `Tests`): documentation checks (`tools/check_docs.py`: relative links, wiki sidebar and links, ADR index, privacy scan for emails and personal paths, LF endings, the docs rule's own cases) and, from milestone M1, the offline addon tests.
2. **Docs rule** (`docs-check.yml`, job `Docs rule`): a pull request that changes `AzerothGuildFinder/` must also change `CHANGELOG.md` and a documentation file, unless it has the label `no-docs-needed`.
3. **Wiki sync** (`wiki-sync.yml`) as in [ADR 0014](0014-github-wiki-generated-from-docs-wiki.md).
4. **DCO** (`dco.yml`): an advisory warning for external commits without a sign-off.
5. **Branch protection on `main`**: `Tests` and `Docs rule` required, also for administrators; no required reviews; no force pushes; no deletion.
6. Actions are pinned to a commit and declare the least permissions they need.

## Consequences

- Positive: no merge with failing checks; docs and wiki travel with the code.
- Negative: a pull request that touches the addon needs a changelog entry and a doc (or the label).
