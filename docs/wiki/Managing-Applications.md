# Managing applications

The Guild Master and the **officers** see the **Applications** section.

> **Status:** since M4.2 the addon of the Guild Master and of every officer **receives** applications by itself: while you are online, applicants' addons find you (your addon tells the hidden channel every 20 to 40 minutes that a contact of the guild is online), send their application by addon whisper and get the status back. The application is saved on your character. Since M4.3 the officers' copies **stay in sync** by themselves (see below). The panel arrives with M4.4: until then `/gf debug` (sections Inbox and InboxSync) only counts them. Nothing of this has been tried in WoW Forever yet.

![Applications](../specs/mockups/img/clean/04-applications.webp)

- **Invite** sends the normal guild invite of the game (the player must be online).
- **Decline** asks for confirmation; the player learns it next time they meet an officer online.
- **Whisper** opens a whisper to the player.
- **History** keeps accepted, declined, withdrawn and expired applications for 30 days.
- The list is shared by all officers and stays in sync.

## How the officers stay in sync

Every officer and the Guild Master keep their **own copy** of the guild's applications, saved on their character. The copies talk to each other over the **officer chat** of the guild (as hidden addon messages: nothing appears in your chat, and plain members never receive them):

- When your addon receives an application, a withdrawal or (from M4.4) a decision of yours, it tells the other officers online within a few seconds.
- When you log in, your addon compares its list with the officers who are online and fetches what it missed while you were away; they fetch what only you had. Each missing application comes from **one** officer, so a full inbox is copied in under a minute without flooding the chat.
- If two officers decided differently while they could not see each other, every copy ends the same way: **Invite wins over Decline**, and a closed application (invited, declined, withdrawn, expired) is never reopened.
- An application without a decision **expires after 14 days**; closed ones stay in the history for **30 days**, then they are deleted.
- At most **200** applications per guild are kept: when the list is full the oldest closed one makes room.
- If you **stop being an officer** (or leave the guild), your addon stops receiving them at once and **deletes its copy** a minute after your next login.

Officers who are never online at the same time still converge: each one passes on what it has to whoever is online next.

## The notification icon

![Notification icon](../specs/mockups/img/clean/05-notification.webp)

A round metal button with a red badge shows the pending applications. Left click: a quick list with Invite and Decline. Drag: move it. Right click: lock, show only when something is pending, sound, hide. `/gf notify` shows it again.
