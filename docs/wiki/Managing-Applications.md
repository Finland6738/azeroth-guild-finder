# Managing applications

The Guild Master and the **officers** see the **Applications** tab (in the side rail, under *My Guild*). It exists once your guild has a listing; a plain member never has it.

> **Status:** the panel, the sync, the notification icon and the cases that close an application by themselves are written and tested offline, on a mock client and in a network simulator (an officer online, an officer coming online later, two officers in sync); nothing of it has been tried in WoW Forever yet. The addon of the Guild Master and of every officer **receives** applications by itself while they are online, and the officers' copies **stay in sync** (see below).

![Applications](../specs/mockups/img/clean/04-applications.webp)

## The list

On the left: the guild's emblem and your role, two counters (**Pending** and **Accepted · 30 days**), the **Pending (3) / History** switch, the three notification options and a note that the list is shared with the other officers. The tab in the rail carries a red number: the applications waiting for a decision (the same number is in the tooltip of the minimap button, and **My Guild** says how many wait and opens the tab).

**Pending** has one card per application, the newest first:

- the **class icon** in a ring of the class colour, and the **name** in the class colour;
- the **roles** the player ticked (Tank, Healer, Melee DPS, Ranged DPS), if any;
- **level, race** and **item level** (*iLvl —* when the game did not tell), and **how long ago** they applied;
- a **status**: *RECEIVED* for a young application, then *EXPIRES IN 11 DAYS* (amber when 3 days or fewer are left), *INVITING...* while an invite is on its way, and a gold *NEW* with a gold edge for what arrived since you last left the tab.

Scroll with the mouse wheel when there are more than six.

**History** keeps the accepted, declined, withdrawn and expired applications for **30 days**, one line each: *by Lyryn · 5 Nov 2026* (*by the player* when they withdrew, *after 14 days* when it expired). An application withdrawn before it reached you shows only the name.

Only the Guild Master and the officers see the data of an application, and it is only what the player's addon sent: name, class, race, level, item level and the roles they ticked.

## What you can do

- **Invite** sends the normal guild invite of the game (the player must be online). The application becomes *accepted* only when the invite really went out: the game says *You have invited …*, or nothing goes wrong in the next three seconds. If the player is offline the panel says *Name is offline. Try again later.* and the card stays; if the game refuses (already in a guild, no permission to invite) you read its own words.
- If the game does not let the addon send the invite (a protected action; this is still to be checked in the game), **Invite** opens the chat box with `/ginvite Name` already typed: press Enter, and the application is marked accepted when the game confirms; if it does not, press **Mark as invited**. If even the chat box cannot be opened, the panel tells you to invite the player by hand and to mark it afterwards.
- **Decline** asks for confirmation, then the application is declined. The other officers see it within seconds; the player learns it next time they meet an officer online (their addon asks), and cannot apply to your guild again for 7 days.
- **Whisper** opens the chat box with `/w Name` so you can talk to the player first.

Only one officer needs to act: when two officers decide on the same application at the same moment, **Invite wins over Decline** on every copy.

## Applications that close by themselves

You do not have to touch these:

- **The player joined the guild** by other means (you or another officer typed `/ginvite` by hand, for example): your addon reads the guild's member list and closes the application as *accepted*, with no *by* name in the history (nobody pressed the button). It looks at the list at most once a minute while an application is pending, so it can take a minute or two after the player accepted. Invite from the panel closes the card by itself, as before.
- **The Guild Master removes the guild from Guild Finder** (*Delist* in My Guild): every pending application is **declined** at once, on the Guild Master's and on every officer's list (the officers who are away get it at their next login). The applicants learn it from the removal itself, and it does **not** start the 7-day wait, since the guild did not turn them down. The Applications tab and the notification icon go away with the listing; an application that still reaches you for a removed guild is ignored.
- **14 days without a decision**: the application is *expired* in everybody's list at the same moment (the badge and the counters stop counting it).

## Notifications

Three options, on the left page of the Applications tab and, for the Guild Master and the officers, in a **Notifications** card of **Settings**:

- **Notification icon on screen**
- **Only when something is pending**
- **Sound on new application**

They are saved for your account and drive the notification icon described at the end of this page.

## How the officers stay in sync

Every officer and the Guild Master keep their **own copy** of the guild's applications, saved on their character. The copies talk to each other over the **officer chat** of the guild (as hidden addon messages: nothing appears in your chat, and plain members never receive them):

- When your addon receives an application, a withdrawal or a decision of yours, it tells the other officers online within a few seconds.
- When you log in, your addon compares its list with the officers who are online and fetches what it missed while you were away; they fetch what only you had. Each missing application comes from **one** officer, so a full inbox is copied in under a minute without flooding the chat.
- If two officers decided differently while they could not see each other, every copy ends the same way: **Invite wins over Decline**, and a closed application (invited, declined, withdrawn, expired) is never reopened.
- An application without a decision **expires after 14 days**; closed ones stay in the history for **30 days**, then they are deleted.
- At most **200** applications per guild are kept: when the list is full the oldest closed one makes room.
- If you **stop being an officer** (or leave the guild), your addon stops receiving them at once and **deletes its copy** a minute after your next login; the tab disappears.

Officers who are never online at the same time still converge: each one passes on what it has to whoever is online next.

## The notification icon

![Notification icon](../specs/mockups/img/clean/05-notification.webp)

A round metal button with the guild's emblem and a red badge with the number of pending applications. Only the Guild Master and the officers of a guild with a listing see it.

- **New application**: the badge goes up, the icon glows once, the chat says *New application from Elarin (Mage 32). [Open]* (click *Open* to go to the Applications tab) and, if the sound is on, a short sound plays. Applications that only reach you from another officer, for example when you log in, move the badge without the chat line or the sound.
- **Left click**: a quick list of the last 5 pending applications with **Invite** and **Decline** (it asks first, as in the panel) and *Open all applications*.
- **Drag**: moves the icon; the place is saved for each character. **Lock position** stops it from moving.
- **Right click**: a menu with *Lock position*, *Show only when something is pending*, *Sound on new application* and *Hide icon*.
- **`/gf notify`** hides the icon, and shows it again. The same switches are in Settings and on the Applications tab.

If you cannot see the icon: you must be the Guild Master or an officer, the guild must have a listing, *Notification icon on screen* must be on, and with *Show only when something is pending* it appears when an application waits.
