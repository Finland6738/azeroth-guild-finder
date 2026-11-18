# 0023. Discord link: fixed prefix, safe invite codes, own icon

- Status: Accepted, except the logo question (Q10 in [SPEC-10](../specs/SPEC-10-risks-open-questions.md)), which is the owner's decision
- Date: 2026-11-18

## Context

A listing can carry a Discord invite. A WoW addon cannot open a browser, so the player copies the link from the guild page and pastes it into a browser: whatever the page shows, the player will trust. The risk is a listing (from a modified client: the channel is open to everyone, [ADR 0003](0003-hidden-channel-and-versioned-protocol.md)) that makes players copy a look-alike or malicious address. The owner also asked for the Discord logo next to the field and a legal review.

## Decision: safety

1. **The data carries a code, never a link.** The prefix `https://discord.gg/` lives in code only (`Listing.DISCORD_PREFIX`). The guild page, the editor and every other place rebuild the link with `Listing.DiscordUrl(code)`, which returns nil for anything that is not a valid code.
2. **What a code is**: `^[A-Za-z0-9-]{2,32}$`, plain ASCII. Discord's own help says a custom (vanity) invite link has "up to 25 characters" of letters, digits or dashes; generated invites are about 7-10 letters and digits. The 2-32 range is deliberately wider than both so that a valid invite is never refused; the alphabet is what protects players. Case is kept as typed (codes are case sensitive).
3. **Input accepted** (editor, and on receive): the bare code, or `discord.gg/<code>`, `discord.com/invite/<code>`, `discordapp.com/invite/<code>`, with optional `http(s)://` and `www.`, a trailing `/`, `?query` or `#fragment`; all are **normalised to the code**. Matching is on the exact host followed by `/`, so `discord.gg.evil.com`, `discordd.gg`, `discord.gg` followed by an at sign and another host, or a user-info part before the host, `evil.com/discord.gg/x`, shorteners and ports are all "some other link" and refused.
4. **Nothing is cleaned up silently.** Before parsing, any byte outside printable ASCII (controls, NUL, DEL, no-break space, zero-width and bidi characters, byte-order mark, full-width or Cyrillic look-alikes, any Unicode) refuses the whole text; so does anything over 200 characters. The WoW escapes `|c`, `|H`, `|T`, `|r` fail because `|` is not in the alphabet. (Earlier versions stripped control characters and then parsed; stripping could join `ab<TAB>cd` into a "valid" `abcd`.)
5. **Validate on receive.** `Listing.SanitizeDetail` (and `SanitizeFull`) run the same function; an invalid `disc` is dropped (the listing stays, without Discord) and logged as an issue. A modified client can send anything; the receiver only ever stores a valid code and the page rebuilds the URL from it.
6. **What the addon cannot know.** It cannot check that an invite exists, has not expired, was not revoked, or points to the guild's own server: Discord invites expire (default 7 days, "never" is an option) and a Guild Master can delete them. The editor hint says to use a permanent invite; the guild page says nothing more than what it knows. A valid-looking code to a wrong server is a content problem, like a wrong description, handled by the existing report and delist paths, not by the addon.
7. **The copy field stays read-only with select-all**, so the player copies exactly the rebuilt link.

## Decision: icon

8. The field shows our own **generic speech-bubble glyph** (`glyph_chat`, drawn by `tools/make_media.py`, GPL-3.0 like every texture). `Skin.DISCORD_ICON` is the one line to change if the owner later decides to ship the official logo.

## Legal and permissions: what was read (2026-11-18), what is judgement

This is research, not legal advice; where a judgement is needed the safest option is chosen.

- **Discord brand guidelines** (<https://discord.com/branding>, read 2026-11-18). "You must have permission from Discord before using any of the Discord Marks or Brand Assets except as permitted here." Discord Marks include the name DISCORD and the Clyde logo. Permitted: saying you use Discord or have a Discord server, if the use "cannot imply that you are Discord, or somehow sponsored by or acting on behalf of Discord", digital-only. Not permitted: the marks in a **product name**, confusingly similar logos or domains, imitating the look and feel of Discord's apps, merchandise, editing/recolouring/distorting the logo (only colour, black or white), and use inconsistent with Discord's terms. The page says nothing about open-source software, redistributing the logo files, or a required disclaimer.
- **Developer Policy** (<https://docs.discord.com/developers/policies-and-agreements/developer-policy>): the page could **not be read** in this session (HTTP 403 for the automated fetch). It is written for apps that use Discord's API; this addon does not use the Discord API, tokens or user data, so it is probably outside it, but that is **not verified**. The owner should read it once.
- **Vanity and invite rules** (<https://support.discord.com/hc/en-us/articles/115001542132>): the page returned 403; the 25-character figure comes from a search snippet of that article and is a secondary source. Hence the wider 2-32 range.
- **Privacy**: an invite link is public by design; the Guild Master chooses to publish it and the addon only repeats it to other players of the same game, like the description. The addon sends nothing to Discord and never opens the link.

**Judgement:**

| Question | Conclusion |
|---|---|
| Mentioning "Discord" and the word `discord.gg` | Descriptive use ("a Discord invite link"): fine. We do not put it in the product name. |
| Showing the official logo in the addon | Not clearly permitted: permission is required "except as permitted here", the open-source case is not addressed. Showing it implies at least an association. **Not bundled.** |
| Bundling the logo file in a GPL-3.0 repository | A GPL repository invites copying and modification; the brand terms forbid editing and the logo cannot be relicensed as GPL. **Not bundled.** Also not in CurseForge gallery images. |
| Disclaimer | The brand page requires none, but it forbids implying affiliation: the README and CurseForge text say "not affiliated with or endorsed by Discord" (and Blizzard). |
| Our own icon | A generic speech bubble is not confusingly similar to the Clyde mark. Safe. |

**Recommendation:** keep the original icon. If the owner wants the official logo, the cleaner route is to ask Discord for written permission (their brand contact is on the branding page) and only then add the file and change `Skin.DISCORD_ICON`. Decision: owner (Q10).

## Consequences

- The Discord field of old listings keeps working (a code or a link in `disc` normalises as before); only invalid or non-ASCII text is now dropped.
- Tests: `Tests/test_listing.lua` ("hostile input") runs about fifty attack strings through extraction, URL building and detail sanitising; `Tests/test_editor_recruit.lua` through the editor check.
- Not verified in the real client: the icon rendering and its position, the copy field with the new layout.
