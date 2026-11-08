# 0018. Mockups as HTML and CSS, rendered to WebP

- Status: Accepted
- Date: 2026-11-08 ([docs/specs/README.md](../specs/README.md))

## Context

The first SVG wireframes were too plain to judge the look the owner wanted. Mockups must be easy to change, readable on GitHub and in the wiki, and light in the repository.

## Decision

1. Mockups are HTML and CSS in `docs/specs/mockups/html/`, sharing one stylesheet (`agf.css`, the design tokens) and one helper (`agf.js`: emblems, banner art, class icons).
2. `docs/specs/mockups/render.sh` renders every screen with headless Chrome at 1280 × 820, with callouts and without (`?clean`), and converts the results to WebP (quality 90) with Pillow: about 3 MB in total instead of 20 MB of PNG.
3. Class icons are the game's own, loaded from Wowhead's CDN **only while rendering**; no icon file is stored. Interface icons (Material Symbols) and banner art are placeholders for the client's icons and images.

## Consequences

- Positive: realistic mockups, quick to change, small in git.
- Negative: rendering needs Chrome, Python with Pillow and an internet connection.
