# Azeroth Guild Finder: Find Your Guild Without Leaving the Game

> **Unofficial addon.** Azeroth Guild Finder is a fan-made addon. It is not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc.

Azeroth Guild Finder is a guild finder for **World of Warcraft: Forever**, inspired by the guild finder of Albion Online. Players without a guild browse and filter guilds and apply with one click. Guild Masters publish a listing with an emblem, activities, requirements and honest statistics. Officers get an applications panel and a floating notification icon.

It has **no server**: the addon shares listings over a hidden chat channel, directly between players.

## Features

### For players without a guild

- **One search view**: search by guild name, then filter by role (Tank, Healer, Melee DPS, Ranged DPS), language, commitment (Casual, Softcore, Hardcore), activities, play days and hours (shown in *your* time zone), active members, requirements and new-player friendly guilds.
- **Always alphabetical**: no paid placement and no reward for posting again and again.
- **A clear guild page**: the classes and roles the guild is **looking for** come first, then the description, activities, schedule, statistics and the requirements checked against your character.
- **Apply with one click**: your name, class and level go to the officers. You see the status of your application and get the normal guild invite if accepted.
- **Contacts**: the guild's Discord link ready to copy, and whisper buttons.

### For Guild Masters

- **Publish a listing in about three minutes** with a guided editor and a live preview. The guild name comes from the game.
- **Emblem from your guild tabard**, or design one from the game's tabard pieces.
- Choose the **classes and roles you need**, your commitment, up to three activities, your schedule and your requirements.
- **Honest statistics**: active characters and unique players in the last 7 days.

### For officers

- A shared **applications inbox** with Invite, Decline and Whisper, kept in sync between officers, even if an application arrives while you are offline.
- A movable **notification icon** with a badge and a quick list.

## How it works

Every installation keeps a catalog of the listings it has seen and shares it with the others over a hidden chat channel. A guild's own members are the source of its listing: the Guild Master writes it, the guild channel spreads it to the members, and any member online announces it. Applications go straight to an online officer. There is no external server, no website and no internet connection.

Because it is peer to peer, a listing reaches the players who are online with the addon on your realm and faction; the more players use it, the better the list gets.

## Getting started

1. Install the addon (CurseForge app, or extract the `AzerothGuildFinder` folder into `World of Warcraft/_forever_/Interface/AddOns/`).
2. Log in and type `/gf` (or click the minimap button).
3. **No guild?** Open *Find a Guild*, filter, open a guild page and press **Apply**.
4. **Guild Master?** Open the listing editor and publish. **Officer?** Your applications panel appears automatically.

| Command | What it does |
|---|---|
| `/gf` | Open or close Guild Finder |
| `/gf notify` | Show or hide the notification icon |
| `/gf reset` | Reset the window position |
| `/gf scale 60` to `/gf scale 140` | Window size |
| `/gf debug` | Diagnostics report to paste in a bug report |

## Privacy

- **Public**: only the listings that Guild Masters choose to publish, with aggregate statistics.
- **Inside your guild**: an anonymous token and the *number* of your active characters, used to estimate unique players. You can switch it off in the settings.
- **An application** goes only to the Guild Master and officers of that guild.
- No external server, no telemetry, no analytics.

## Requirements

- **World of Warcraft: Forever** (Interface 16001). Other clients are not supported.
- No other addon is needed. The libraries (Ace3, LibDBIcon, LibDataBroker) are included.

## Development status

The addon is written and tested offline on a simulated client. **It has not yet been tested in the real game**, so some things may need fixing. The screenshots on this page are **design previews**, not in-game captures; real screenshots will replace them. Feedback and bug reports are very welcome.

## Links

- Source code: https://github.com/Finland6738/azeroth-guild-finder
- User manual (wiki): https://github.com/Finland6738/azeroth-guild-finder/wiki
- Bugs and ideas: https://github.com/Finland6738/azeroth-guild-finder/issues
- Support the project: https://ko-fi.com/finland6738

## Credits and license

- Libraries: Ace3 and LibDBIcon / LibDataBroker, each under its own license.
- Fonts: **Roboto** and **Roboto Mono**, by The Roboto Project Authors, under the SIL Open Font License 1.1.
- Emblem artwork on this page: original work for this project.

Azeroth Guild Finder is free software under the **GNU General Public License v3.0**: you may use, study, change and share it under the terms of that license. Full text: https://www.gnu.org/licenses/gpl-3.0.html
