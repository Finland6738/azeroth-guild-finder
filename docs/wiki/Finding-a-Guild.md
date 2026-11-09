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

The left page will hold the filters: **Recruiting only**, **Looking for my class**, **Requirements met**, **New player friendly**, **My role** (Tank, Healer, Melee, Ranged), **Guild language**, **Commitment** (Casual, Softcore, Hardcore), **Activity**, **Play days and time** (in your time zone) and **Min. active members** (active in the last 7 days). The plate at the top will show how many filters are active, and its round arrow will reset them.

> The filters are not in this version yet: the left page says so. Search by name works today.

## The list

Guilds are **always in alphabetical order**: nobody can pay or post repeatedly to be first. Even with 500 guilds the list scrolls smoothly with the mouse wheel or the bar on the right. Each card shows:

- the **emblem** (a plain placeholder for now: the real emblems come with the listing editor), the **name**, the subtitle and the **language** tags;
- the **commitment** (Casual in green, Softcore in amber, Hardcore in red) and, when it applies to you, one more tag: **Looking for your class** (green) or **Requirements not met** (red; it wins when both are true);
- **May be inactive** (amber) when the guild has not announced itself for more than 14 days; after 30 days it leaves the list;
- an information band: active members (*31 active / 149*), the play days and times **in your time zone**, the classes they look for (up to four icons, then *+2*; *Looking for any class* when they take anyone), up to three activities, the requirement checked against your character (*Level 20+* with a check mark, or *Level 40+ (you are 32)* in red) and when the listing was last updated.

Hover a card to see its subtitle and requirement; click it to open [[The Guild Page|The-Guild-Page]] (the page arrives in a later version; until then the card says so). The Discord and Apply buttons of the cards arrive with the guild page and the applications.

Only guilds of **your faction and realm** are shown.

## When the list is empty

| You see | It means |
|---|---|
| a turning spinner and *Looking for guilds... this can take a minute the first time* | the addon is asking the other players that have it online for their catalog |
| *No other Guild Finder users online right now. Listings will appear as they come online.* | nobody answered and nobody is around; the list fills by itself as players log in |
| *No guild has published a listing for your realm and faction yet.* | other players are online but no guild master has published yet |
| *No guild name contains "..."* | your search matches nothing: change or clear it |
| *No guild matches your filters* and **Reset filters** | the filters (when they exist) leave nothing: reset them |

## The status bar

At the bottom: how many guilds your addon knows, when it last synced (*synced 2 min ago*, with a green dot; amber while it is syncing; grey if it has not synced yet) and a reminder that only guilds of your faction and realm are listed.
