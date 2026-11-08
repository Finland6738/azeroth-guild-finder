# Commands and settings

| Command | What it does |
|---|---|
| `/gf` | Opens or closes Guild Finder |
| `/gf notify` | Shows or hides the applications notification icon |
| `/gf reset` | Puts the window back in the middle of the screen |
| `/gf scale` | Tells you the window size. `/gf scale 80` sets it to 80 %; the range is 60 to 140 |
| `/gf debug` | Diagnostics: addon version, client build and project id, every game feature the addon needs as `available`, `missing`, `restricted` or `error`, and the state of the saved data (schema versions, read-only when it comes from a newer version, and any value that was repaired); no character or guild names, and never the account secret |
| `/gf debug ping` | Tests the Guild Finder channel: sends a ping to everyone who has the addon online and, after 5 seconds, tells you how many answered and how long the round trip took (never who). One ping every 10 seconds |
| `/gf debug announce` | **Development builds only** (a copy of the repository, not a packaged release): announces a test listing called *AGF Test &lt;your character&gt;* on the channel, to check that listings travel between two clients. Release builds ignore test listings and refuse the command. Do not use it on a character that announces a real guild: the other clients would ignore that character for a day |
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

In this version the **Settings** tab of the window has the window size and a *Reset window position* button; the other options of the table arrive with the full Settings page. The window position is saved per character, the window size for the whole account.
