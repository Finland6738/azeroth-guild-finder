# Publishing a listing

Only the **Guild Master** can publish or edit the guild's listing. Open `/gf`: a Guild Master without a listing sees **Create Listing**.

![Listing editor, Activity step](../specs/mockups/img/clean/08-editor-activity.webp)

The editor, the draft and the checklist are described in [[Creating a Listing|Creating-a-Listing]]. In short, it has seven steps; the left page shows which ones are ready:

1. **Identity**: the guild name (taken from the game), subtitle, [[emblem|Emblems]] and banner.
2. **About**: description and languages.
3. **Activity**: commitment (**Casual**, **Softcore** or **Hardcore**), **up to 3 activities** in order of importance, play days and hours (in your time zone).
4. **Recruitment**: status (open to all, selected classes, closed) and the **Looking for** grid of classes and roles (Tank, Healer, Melee, Ranged); new player friendly; accept applications through the addon.
5. **Requirements**: minimum level, optional item level, a note.
6. **Contact**: the Discord invite code and up to three contact characters.
7. **Preview & publish**: the checklist must be all green. Until the steps arrive in the addon, publishing in a real client is not yet possible.

![Listing editor, Recruitment step](../specs/mockups/img/clean/03-listing-editor.webp)

The draft is saved automatically. After publishing, the listing reaches other players over the next minutes, through every member of your guild who uses the addon. **Delist** removes it.

## Announcements and statistics

Once the listing is out, your guild keeps it alive by itself: every member who uses the addon (you included) **announces** it on the shared channel about every **30 minutes** (a random time between 20 and 40). When a member hears a guildmate's announcement with the same or newer content and statistics, it skips its own turn, so a guild with many members online still sends about one announcement every half hour. Announcements from you and your officers also tell applicants that a contact is online.

Every announcement carries the guild's [[statistics|The-Guild-Page]] (members, active characters, at max level, class mix, unique players), counted from the guild roster at that moment. You see the same numbers on the preview card of the editor (*31 active / 149*). Nothing personal is in them; see [[Privacy and Data|Privacy-and-Data]].

## Good to know

- You can publish **one change every 5 minutes** (the limit keeps the shared channel quiet and survives `/reload`). The draft has no limit: change it as often as you like and publish when it is ready.
- Before saving, the addon checks again that you are still the Guild Master. If you are not, nothing is saved and you see *You are no longer the Guild Master: the change was not saved.*
- The members of your guild who use the addon receive the listing from you, over the guild channel, and show it in **My Guild**. They accept it **only from the Guild Master of the guild roster**: nobody else in the guild can change what they see. A member who logs in later asks for it, and your addon answers when you are online.
- When the guild changes Guild Master, the new one keeps the same listing and can edit it; the old one can no longer change it.
- **Delist** keeps your texts: the editor opens with the last listing, so you can publish it again with one click. Players who already saw your guild see it removed within minutes; a few may keep it until it ages out.
