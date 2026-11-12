# Applying

> **Status:** applying works in the addon since M4.1 and, since M4.2, the application **goes by itself to the guild's Guild Master or an officer** when one is online with Guild Finder. The officers' panel to read it arrives with M4.4. Nothing of this has been tried in WoW Forever yet.

## Apply in three steps

1. In **Find a Guild**, press **Apply** on a guild's card, or open the guild page and press **Apply to *Guild***.
2. A short question asks *Apply to Aurora with Elarin (Mage 32)?*. Tick the **roles you play** if you want (Tank, Healer, Melee DPS, Ranged DPS): only the roles your class can play are offered, and ticking none is fine. Press **Apply**.
3. Your character's name, class, race, level and item level are read from the game and saved as your application. There is no form and no message to write. A note says *Saved. It will be delivered when an officer of Aurora comes online.*

Only the Guild Master and the officers of that guild will see your application.

## The Apply button

The button tells you, in its text and in its tooltip, whether you can apply and why not:

| The button says | Why | What to do |
|---|---|---|
| **Apply** (red) | you can apply | press it |
| **Applied · Waiting for an officer** | you applied here; no officer has it yet | click it to see your application |
| **Applied · Received** | an officer of the guild has your application | click it to see your application |
| **You already applied to *Guild*** | you have an open application elsewhere | withdraw it first (one at a time) |
| **Requirements not met** | your level or item level is below the guild's minimum; the tooltip says which | level up, or contact the guild |
| **You can apply again on 15 Nov** | this guild declined you less than 7 days ago | wait until that day |
| **Your character can't send addon messages yet** | the game does not let this character send addon messages (often a new or low-level character) | use the guild's contacts meanwhile |
| **You are already in a guild** | only characters without a guild can apply | — |
| no button, *Applications via addon are closed. Use the contacts below.* | the Guild Master closed applications through the addon | use Discord or whisper a contact |

On the guild page a line under the button explains the same thing.

## My Application

The **My Application** tab shows your application: the guild, when you applied, its status with an explanation, the road *SENT > RECEIVED > ACCEPTED / DECLINED*, the roles you ticked and how many days are left before it expires.

| Status | Meaning |
|---|---|
| *Waiting for an officer to come online* | saved on your character; it goes out when an officer of the guild is online with Guild Finder |
| *Received by the guild* | an officer has it |
| *Accepted: check your guild invite* | you get the normal guild invite in game |
| *Declined* | you can apply to other guilds now, and to this one again after 7 days |
| *Withdrawing...* / *Withdrawn* | you withdrew it; *Withdrawing...* until an officer learns it |
| *Expired* | 14 days passed without a decision |

- **View guild** opens the guild page; **Back** returns to the tab.
- **Withdraw** asks first. After it you can apply to another guild at once (or to the same one again).
- When something changes that you did not do (an officer's answer, the expiry) a line appears in the chat and a dot on the tab until you open it.
- Without an application the tab says *You haven't applied to any guild* and has a button to Find a Guild.

![My Application](../specs/mockups/img/clean/06-states.webp)

## How your application reaches the guild

There is no server: your game hands the application directly to a **contact** of the guild, the Guild Master or an officer who is online with Guild Finder.

- Every 20 to 40 minutes the addon of a Guild Master or officer who is online says so on the addon's hidden channel. Your addon remembers those contacts for **30 minutes**.
- When you press **Apply**, or later when a contact of that guild shows up, your addon sends the application to the contact heard most recently, as an addon whisper (invisible in your chat). If no answer comes within 15 seconds it tries the next contact.
- The contact's addon answers with the status. That is when your application becomes *Received by the guild*.
- A contact that did not answer is tried again only after a while (1 minute, then 2, 4… up to 30 minutes), so nobody is flooded.
- Later, when a contact of the guild is online, your addon asks for news. That is how you learn **Accepted** or **Declined**, even days later.
- **Withdraw** works the same way: the withdrawal goes to the first contact available, before or after an officer received the application. Until then the tab says *Withdrawing...*, but you can already apply elsewhere.

**Stay online.** Your application only travels while you are in the game: if you and the guild's officers are never online at the same time it stays *Waiting for an officer*. The guild page always lists the guild's contacts (Discord and characters) as another way.

**When the game does not let your character send.** Some characters (often new or low-level ones) cannot send addon messages, or the game refuses them for a while. My Application then says so under the status: *Right now the game does not let this character send addon messages, so nothing can go out yet.* The application stays saved and goes out by itself when sending works again; meanwhile use the guild's contacts.

## Rules

- **One open application per character.** Your other characters can each have their own. To apply elsewhere, withdraw the current one first.
- An application **expires after 14 days** without a decision.
- After a **decline** you can apply to the same guild again after **7 days**; other guilds at once.
- Only a character **without a guild** can apply, and only to a guild that accepts applications through the addon.
- Your application stays on your computer (in your character's saved data) and goes only to the Guild Master and the officers of that guild, by whisper: other players never see it. Closed applications are forgotten after 30 days.
