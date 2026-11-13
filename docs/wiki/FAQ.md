# FAQ

**The list is empty.** The catalog fills as you meet other players who use the addon. The first time it can take a few minutes.

**My application says "Waiting for an officer".** No officer of that guild has been online at the same time as you yet. It is delivered automatically when one is.

**I can't apply: "Your character can't send addon messages yet".** The game limits messages of very new or low-level characters. Contact the guild through Discord or a whisper.

**Why is the list alphabetical?** So that no guild can pay or post repeatedly to be first.

**Why can't I see guilds of the other faction?** Guilds belong to one faction: only the ones you can join are shown.

**I'm in a guild: why can't I search?** Guild Finder shows guild members their own guild's listing only.

**I joined the guild and my application still says "Waiting for an officer".** It should close by itself the moment you join: the chat says *You joined Aurora: your application was closed as accepted.* If it does not, open the Guild Finder window once and report it with `/gf debug` (see [[Reporting Bugs and Feedback|Reporting-Bugs-and-Feedback]]).

**The guild disappeared from the list and my application closed.** The Guild Master removed the guild from Guild Finder. That is not a refusal: there is no waiting time, and you can apply to the guild again if it is listed again.

**My application "expired".** Nobody decided in 14 days. Apply again, and keep an eye on the guild's contacts (Discord or a whisper) meanwhile.

**An officer: an applicant joined the guild, but the card is still pending.** The addon reads the member list at most once a minute, so give it a moment: the card then moves to History as *accepted*. If the player never joined, decline the card.

**How do I send a useful bug report?** Type `/gf debug`, press **Select all**, Ctrl+C, and paste the text into the *Lua errors and /gf debug output* field of the [Bug report form](https://github.com/Finland6738/azeroth-guild-finder/issues/new/choose). The report holds no player or guild names, but read it once before you send it. If the game shows a Lua error box, the last errors of Guild Finder are in the report too (section *Last errors*).
