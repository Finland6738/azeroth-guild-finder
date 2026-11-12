# Privacy and data

| Who sees it | What |
|---|---|
| Everyone using the addon (same faction and realm) | The listings Guild Masters publish, with **aggregate** statistics |
| Your guild | An anonymous token and the **number** of your active characters (never their names), to estimate unique players. Switch it off in the settings |
| The guild's Guild Master and officers | Your application: name, class, race, level, item level |

The addon has no server, sends nothing outside the game and collects no telemetry.

## Applications kept by officers

An application goes only to the guild's Guild Master and officers. Their addons keep a copy on their own characters and pass it to each other over the guild's **officer chat** as hidden addon messages, which plain members do not receive. The copy holds what the application holds (name, class, race, level, item level, the roles ticked), its status and which officer decided. A closed application is deleted 30 days after its last change. A character that is no longer an officer, or has left the guild, deletes its copy at its next login. (If the game turns out not to deliver addon messages on officer chat, they will travel on guild chat instead and the members' addons will ignore them; this is one of the checks made in the game before the release.)

## Guild statistics and the anonymous alt count

A guild's listing shows how alive the guild is with **numbers only**: members, characters active in the last 7 days, characters at max level, the class mix of the active characters and an estimate of the **unique players** behind them. Every member's addon counts them from the guild roster the game gives it; nobody's name is in them.

The game does not say which characters belong to the same person. To estimate it, your addon tells **your guild only** (over the guild's own addon channel, never the public one):

- an **anonymous token**: a code made from a random secret stored on your computer and the guild's name. It is different in every guild, so nobody can follow you from one guild to another, and the secret itself never leaves your computer;
- the **number** of your characters in that guild that played in the last 7 days. Never which ones.

It is sent when you log in and once a day, and when a guildmate who just logged in asks for it. Your guildmates' addons keep the tokens for **7 days**, then forget them. To remember which of your characters are in the guild, your addon saves a code made from each character's name, on your computer only.

When not every member uses the addon (or some switch this off), the guild page shows a **range** (*19–24*) instead of one number: the members who share are counted exactly, the others are estimated.

**Switching it off**: *Settings → Privacy → Share anonymous alt count with my guild*. From then on your addon sends nothing, and your own account is counted like a member without the addon (so every guildmate sees the same range). A token you sent before stays with your guildmates until its 7 days run out. Switch it on again whenever you like.
