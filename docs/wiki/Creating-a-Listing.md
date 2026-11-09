# Creating a listing

Only the **Guild Master** can create or edit the guild's listing. Open `/gf`: a Guild Master whose guild has no listing sees **Create Listing**. Everybody else never gets this page. If you reach it anyway, a note covers it and nothing can be saved.

![Listing editor, Recruitment step](../specs/mockups/img/clean/03-listing-editor.webp)

## The seven steps

The **left page** lists the seven steps. Each shows its state: a green check when it is ready, a red cross when something in it is wrong, *optional* when there is nothing you have to fill in. *n / 7 ready* counts them. Click a step to jump to it, or use **Back** and **Next** in the title bar.

1. **Identity**: the guild name (taken from the game, you cannot change it here), subtitle, [[emblem|Emblems]] and banner.
2. **About**: description and languages.
3. **Activity**: commitment (**Casual**, **Softcore** or **Hardcore**), up to 3 activities in order of importance, play days and hours.
4. **Recruitment**: status, the *Looking for* grid of classes and roles, new player friendly, applications through the addon.
5. **Requirements**: minimum level, optional item level, a note.
6. **Contact**: the Discord invite code and up to three contact characters.
7. **Preview & publish**: the card as other players will see it, and the checklist.

![Listing editor, Activity step](../specs/mockups/img/clean/08-editor-activity.webp)

> **Not all steps are there yet.** The steps arrive with the next versions of the addon (Identity and About first, then Activity, then Recruitment, Requirements and Contact, then emblems). Until then a step says that it arrives in a later version, and **Publish listing** cannot turn green. Nothing is lost: this page only grows.

## The live preview and the checklist

On the right of every step you see the **live preview**: the card other players will see in Find a Guild, updated as you type. Under it, the **Before publishing** checklist:

- You are the Guild Master
- Subtitle
- Description: at least 30 characters
- Main language
- Commitment (Casual, Softcore or Hardcore)
- 1 to 3 activities
- Emblem (tabard or designed)
- "Looking for" set, or recruitment closed
- Discord code valid (only if filled in)

A green check means done, an empty circle means nothing there yet, a red cross means something is wrong (the line under it says what). **Click an item to go to the step that fixes it.**

## The draft

Everything you type is saved as a **draft** at once, on your computer only. Close the window, log out, `/reload`: it is still there when you come back. Nothing is sent to anybody until you publish. **Discard changes** throws the draft away (after asking) and brings back the last published version, or an empty editor if there is none.

## Publish

**Publish listing** is the red button at the bottom of the left page. It stays grey, with the reason written under it, until:

- every required item of the checklist is green (the button tells you which step to fix: *Fix "Contact" to publish*; pressing it takes you there);
- you are still the Guild Master (the addon asks the game again before saving);
- five minutes have passed since your last published change (the time left counts down on the button's reason).

Once your listing is out, the same button says **Save changes** and is grey, with *Nothing has changed since the last published version*, until you change something. **Delist** (shown while the listing is out) removes your guild from Guild Finder after asking: pending applications will be closed, and the editor comes back filled with your last listing so you can publish it again with one click.

See [[Publishing a Listing|Publishing-a-Listing]] for what happens after you publish, the five-minute limit and a change of Guild Master.
