# Fonts

The interface uses **Roboto** and, for links, codes, times and commands, **Roboto Mono** (SPEC-04 §5.2). No font file is shipped yet: until the files below are added, every text uses the client's own font (`/gf debug` shows `Fonts: ... on the client's font`), and nothing else changes when they are added.

Expected files (TrueType, exactly these names):

- `Roboto-Regular.ttf`, `Roboto-Medium.ttf`, `Roboto-Bold.ttf`, `Roboto-Black.ttf`
- `RobotoMono-Regular.ttf`, `RobotoMono-Medium.ttf`

Licence: Roboto and Roboto Mono are published by Google under an open licence (Apache License 2.0 for the releases of Roboto up to 2.x and for Roboto Mono; SIL Open Font License 1.1 for the newer Roboto releases: check the file that comes with the release you take). The licence text of that release must be added here as `LICENSE` and the fonts named in the credits of the README. Bundling the fonts is the owner's decision ([ADR 0020](../../../docs/adr/0020-original-media-own-nine-slice-and-font-fallback.md)).
