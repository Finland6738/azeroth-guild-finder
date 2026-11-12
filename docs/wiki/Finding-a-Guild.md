# Finding a guild

Open Guild Finder with `/gf` and choose **Find a Guild**.

![Find a Guild](../specs/mockups/img/clean/01-browse.webp)

## Search

Type in the box at the top of the page. The list narrows about a quarter of a second after your last key.

- Type at least **3 letters** of the guild name. With one or two letters the hint *Type at least 3 letters* appears and the list stays as it is.
- Accents, capitals, spaces, hyphens, digits and symbols are ignored, so `ordine` also finds *Ördine del Drago* and `nightwatch` finds *Night Watch*.
- The clear button (or deleting the text) brings the whole list back at once.
- Next to the box you read how many guilds match, for example *24 of 142 guilds*, and, under it, *Sorted A-Z*.

## Filters

The **left page** holds the filters. They narrow the same list the search narrows (a guild must pass the search **and** every filter that is on), they are **remembered for each of your characters**, and the list goes back to its top whenever you change one.

| Filter | What it keeps |
|---|---|
| **Recruiting only** | guilds that are recruiting, with or without a restriction to some classes or roles. **On the first time**, because a guild that is not recruiting cannot take you in |
| **Looking for my class** | guilds that name your class, or that take any class. The class is shown in the label, for example *(Mage)* |
| **Requirements met** | guilds whose minimum level and item level you meet. A requirement the game cannot tell you about (for example the item level) never hides a guild |
| **New player friendly** | guilds that say they welcome new players |
| **My role** (Tank, Healer, Melee DPS, Ranged DPS) | guilds that look for at least one of the roles you pick, for your class **or for any class**. Roles your class cannot play are dimmed (hover one to read why) |
| **Guild language** | guilds that speak at least one of the languages you pick (their main language counts). Click the field to open the list; it stays open while you tick several |
| **Commitment** (Casual, Softcore, Hardcore) | guilds with one of the commitments you pick. Hover a chip to read what each level means |
| **Activity** | guilds that list at least one of the activities you pick among their (up to three) activities. The field shows the names, or *3 selected* |
| **Play days** (seven squares, Monday first) | guilds that play on at least one of the days you pick, **in your time** |
| **Play time** (from and to, in steps of 30 minutes, in your time) | guilds whose play time overlaps the time you pick, see below |
| **Min. active members** (Any, 5, 10, 25, 50) | guilds with at least that many characters active in the last 7 days |

Guilds publish their days and times in UTC; the addon converts them to **your computer's time zone** before comparing, so a guild that plays 20:00 to 23:00 UTC matches *21:00 to 23:00* if you are one hour east of Greenwich, and a guild that plays on Monday at 23:30 UTC counts as Tuesday for someone two hours east.

How the play time is read:

- Pick **from** and **to** to ask for a window, for example 20:00 to 23:30. A guild matches when it plays during any part of it. A guild whose window only **touches** yours (it ends at 23:00 and yours starts at 23:00) does not match.
- A window may **cross midnight**: 22:00 to 02:00 is 22:00 to midnight and midnight to 02:00. A guild that plays across midnight is read the same way.
- Pick only **from** and the window runs to midnight; pick only **to** and it starts at midnight. Picking the same time twice means the whole day and filters nothing.
- A guild that plays **All day** matches every window.
- A guild that did not publish its days, times, languages, statistics or activities is **not** shown while the filter for that thing is on, because nobody can tell that it fits.

The plate at the top reads **Filters · 4 active** (one per filter that is on, however many choices it holds). The round **×** button at its right edge, and the **Reset filters** button of an empty result, turn **every** filter off, including *Recruiting only*, so the list shows all guilds.

## The list

Guilds are **always in alphabetical order**: nobody can pay or post repeatedly to be first. Even with 500 guilds the list scrolls smoothly with the mouse wheel or the bar on the right. Each card shows:

- the **emblem** (the guild tabard or a designed one, see [[Emblems|Emblems]]), the **name**, the subtitle and the **language** tags;
- the **commitment** (Casual in green, Softcore in amber, Hardcore in red) and, when it applies to you, one more tag: **Looking for your class** (green) or **Requirements not met** (red; it wins when both are true);
- **May be inactive** (amber) when the guild has not announced itself for more than 14 days; after 30 days it leaves the list;
- an information band: active members (*31 active / 149*), the play days and times **in your time zone**, the classes they look for (up to four icons, then *+2*; *Looking for any class* when they take anyone), up to three activities, the requirement checked against your character (*Level 20+* with a check mark, or *Level 40+ (you are 32)* in red) and when the listing was last updated.

Hover a card to see its subtitle and requirement; click it to open [[The Guild Page|The-Guild-Page]]; **Back** returns to the list with your search, filters and place. The **Apply** button at the bottom right of a card applies to that guild after a short question, or says why you cannot (see [[Applying|Applying]]); hover it for the full reason. The Discord button of the cards is not there yet: the guild page has the Discord link.

Only guilds of **your faction and realm** are shown.

## When the list is empty

| You see | It means |
|---|---|
| a turning spinner and *Looking for guilds... this can take a minute the first time* | the addon is asking the other players that have it online for their catalog |
| *No other Guild Finder users online right now. Listings will appear as they come online.* | nobody answered and nobody is around; the list fills by itself as players log in |
| *No guild has published a listing for your realm and faction yet.* | other players are online but no guild master has published yet |
| *No guild name contains "..."* | your search matches nothing: change or clear it |
| *No guild matches your filters* and **Reset filters** | the filters leave nothing: reset them (or switch one off) |

## The status bar

At the bottom: how many guilds your addon knows, when it last synced (*synced 2 min ago*, with a green dot; amber while it is syncing; grey if it has not synced yet) and a reminder that only guilds of your faction and realm are listed.
