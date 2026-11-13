# Commands and settings

| Command | What it does |
|---|---|
| `/gf` | Opens or closes Guild Finder |
| `/gf notify` | Shows or hides the applications notification icon (for the Guild Master and the officers of a guild with a listing; anyone else gets a note that it is not for them) |
| `/gf reset` | Puts the window back in the middle of the screen |
| `/gf scale` | Tells you the window size. `/gf scale 80` sets it to 80 %; the range is 60 to 140 |
| `/gf debug` | Opens the **diagnostics report** in a box: press **Select all** (or click in the text), then Ctrl+C, and paste it into a bug report. It holds the addon, client and interface versions, every game feature the addon needs as `available`, `missing`, `restricted` or `error`, the size of your list, the sync state, why the addon only listens (if it does), the last Lua errors of the addon (at most ten, without folders of your PC), your role, your settings and the state of the saved data. It never holds character, player or guild names, and never the account secret. Esc closes the box |
| `/gf debug ping` | Tests the Guild Finder channel: sends a ping to everyone who has the addon online and, after 5 seconds, tells you how many answered and how long the round trip took (never who). One ping every 10 seconds |
| `/gf debug announce` | **Development builds only** (a copy of the repository, not a packaged release): announces a test listing called *AGF Test &lt;your character&gt;* on the channel, to check that listings travel between two clients. Release builds ignore test listings and refuse the command. Do not use it on a character that announces a real guild: the other clients would ignore that character for a day |
| `/gf debug seed [number]` | **Development builds only**: adds up to 500 fake guilds (60 by default) to **your own** list, to try the list and its scrolling. They are marked as local: they are never sent to anyone and never given to another player's addon. `/gf debug seed clear` removes them. Release builds refuse the command |
| `/gf debug editor` | **Development builds only**: opens the listing editor even when your guild already has a listing (the Guild Master's normal way in is **Edit listing** in My Guild) |
| `/gf debug publish`, `/gf debug delist` | **Development builds only**, Guild Master only: publish your guild's listing (your draft, else the last listing, else a short sample) or withdraw it, to try the guild sync before the editor exists. The listing is **real**: every Guild Finder user on your realm and faction sees it, so withdraw it afterwards. The normal rules apply (one publication every 5 minutes). Release builds refuse the commands |
| `/gf debug gallery` | **Development builds only**: opens a page that shows one of every interface element (buttons, chips, switches, fields, badges, class icons, cards), to check how the window looks at 60 % and 140 %. Release builds refuse the command |
| `/gf help` | The list of commands |

Also: the minimap button (left click opens, right click settings), the Addon Compartment menu and a key binding under *Key Bindings → AddOns*. `/guildfinder` works like `/gf`. The [[Interface Tour|Interface-Tour]] describes the window.

## Settings

| Setting | Default |
|---|---|
| Show minimap button | on |
| Show applications notification icon | on (Guild Master and officers) |
| Only when something is pending | off |
| Sound on new application | on |
| Share anonymous alt count with my guild | on |
| Window size | 100 % (60 % to 140 %) |

The same options are in two places and always agree: the **Settings** tab of the Guild Finder window (the first tab of the rail; right click on the minimap button opens it), and, when your game has it, the **Guild Finder** panel in the game's own *Options → AddOns* window. A change takes effect at once and is saved; there is no Apply button.

- **Window** card: *Window size* (also `/gf scale`), *Show minimap button* (when it is off, open Guild Finder with `/gf`, the Addon Compartment or the key binding) and *Reset window position*, which puts the window **and the notification icon** back where they started. The size and the options are the same for all your characters; the window position, the notification icon's position and lock, and the minimap button's place on the minimap are saved per character.
- **Privacy** card: *Share anonymous alt count with my guild*: it tells your guild only how many of your characters played this week, never which ones (see [[Privacy and Data|Privacy-and-Data]]).
- **Notifications** card, shown to the Guild Master and the officers only: *Notification icon on screen*, *Only when something is pending* and *Sound on new application*. The same three switches are on the Applications tab and in the icon's right-click menu (see [[Managing Applications|Managing-Applications]]).

The game's own panel has a **Defaults** button: it restores every option in the table above and the window and icon positions. If your game has no such panel, Guild Finder simply does not add one and the Settings tab has everything; `/gf debug` shows whether the panel was registered.
