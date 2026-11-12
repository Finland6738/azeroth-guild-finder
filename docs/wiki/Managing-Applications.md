# Managing applications

The Guild Master and the **officers** see the **Applications** section.

> **Status:** since M4.2 the addon of the Guild Master and of every officer **receives** applications by itself: while you are online, applicants' addons find you (your addon tells the hidden channel every 20 to 40 minutes that a contact of the guild is online), send their application by addon whisper and get the status back. The application is saved on your character. The panel below arrives with M4.4 and the sync between officers with M4.3: until then `/gf debug` (section Inbox) only counts them. Nothing of this has been tried in WoW Forever yet.

![Applications](../specs/mockups/img/clean/04-applications.webp)

- **Invite** sends the normal guild invite of the game (the player must be online).
- **Decline** asks for confirmation; the player learns it next time they meet an officer online.
- **Whisper** opens a whisper to the player.
- **History** keeps accepted, declined, withdrawn and expired applications for 30 days.
- The list is shared by all officers and stays in sync.

## The notification icon

![Notification icon](../specs/mockups/img/clean/05-notification.webp)

A round metal button with a red badge shows the pending applications. Left click: a quick list with Invite and Decline. Drag: move it. Right click: lock, show only when something is pending, sound, hide. `/gf notify` shows it again.
