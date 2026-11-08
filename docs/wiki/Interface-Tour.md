# Interface tour

The window is an open book: the **left page** holds the context (filters, the guild's actions, the editor's steps), the **right page** holds the content: a title bar, the page itself and a status line at the bottom. The metal **side rail** on the right switches between sections: **Settings** first, then the sections of your role, each with an icon and a label.

![Design system](../specs/mockups/img/clean/00-design-system.webp)

## Opening and closing

You can open the window in four ways; the same ways close it:

- type **`/gf`** (or `/guildfinder`);
- click the **minimap button** (left click opens or closes, right click opens Settings);
- click the addon in the **Addon Compartment** menu next to the minimap;
- press the key you assign to **Toggle Guild Finder** in *Key Bindings → AddOns* (no key is assigned by default).

Close it with **Esc** or with the round gold button at the top right corner.

## Moving and resizing

- Drag the window by its **left page** or by the **title bar**. It remembers where you left it; `/gf reset` puts it back in the middle of the screen.
- The window size goes from **60 % to 140 %**: use the size control on the **Settings** tab, or type `/gf scale 80`. On a small screen the window is made smaller than you asked, so that the whole book, the rail and the close button stay on the screen; your choice is kept.

## The side rail

The rail shows the sections your character can use, one under the other, **Settings** always first and in the same place:

| You are | Sections after Settings |
|---|---|
| not in a guild | Find a Guild, My Application |
| a guild member | My Guild |
| an officer | My Guild, and Applications once your guild has a listing |
| the Guild Master | Create Listing; once the guild has a listing: My Guild and Applications |

The active section is gold and sticks out of the rail; a red number on a section counts what is waiting there. If your role changes while the window is open (you join, leave or are promoted), the window starts again on the first section of the new role.

## Pages and Back

Opening a guild from the list replaces the list with the guild's page and shows a **Back** button in the title bar; **Backspace** does the same. When you come back, the list is as you left it.

## The building blocks

- **Red pill button**: the main action of the screen (Apply, Invite, Publish). Only one per screen.
- **Blue button**: Discord.
- **Parchment button**: secondary actions. **Grey button**: not available, with the reason written next to it.
- **Chips**: filters you switch on and off (a check mark shows when on).
- **Switches** and **segmented buttons**: settings with two or a few values.
- **Fields**: the search box and other text fields; a **copy field** (for example a Discord link) selects its whole text when you click it, and you press **Ctrl+C** to copy it.
- **Role badges**: blue shield Tank, green cross Healer, red swords Melee DPS, purple target Ranged DPS. Hover one to read its name.
- **Class icons** have a ring in the class colour; hover one to read the class.
- **Commitment tags**: Casual (green), Softcore (gold), Hardcore (red).
- **Snackbar**: a short message at the bottom of the window that goes away by itself (click it to dismiss).
- Times are always shown in **your** time zone.

## Fonts

The interface is designed for the Roboto font. Until the font files are part of the addon, it uses the game's own font, with the same sizes (never smaller than 12 pixels).
