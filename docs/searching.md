---
title: Searching
layout: default
nav_order: 3
---

# Searching

Press the global shortcut (**⌃⌥R** by default) to open the panel, and start
typing.

<img src="assets/search.png" alt="Searching for 'syn' highlights the matching letters in each result" width="680">

## How matching works

- **You don't need to type the whole name, or type it in one piece.** `syn`
  finds `swift-syntax`; `ps` finds `payment-service`. The letters must appear
  in order; the ones that matched are shown in bold.
- **Case doesn't matter.**
- **The name is searched first.** The owner is only considered when the name
  doesn't match, or when your query contains a slash: `acme/api` narrows the
  search to that owner.

## How results are ranked

1. **Quality of the match.** An exact name beats a name that starts with
   your query, which beats a match at the start of a word (`web` in
   `my-web`), which beats letters scattered through the name.
2. **Your habits.** Repositories you open often and recently are lifted, by
   about as much as two or three well-placed letters.
3. **Recency.** Ties go to the repository pushed to most recently.

Archived repositories rank slightly lower. With an empty search field the
list shows the repositories you use most, then the most recently pushed. Up
to 50 results are shown.

## Keys

| Keys | Action |
| --- | --- |
| `↑` `↓` | Move the selection |
| `⌃N` `⌃P`, `⌃J` `⌃K` | Move the selection without leaving the home row |
| `↩` | Open in the browser |
| `⇧↩` | Open the [local clone](local-clones.md), cloning it first if needed |
| `⌘↩` | Copy the URL instead of opening it |
| `⇥` | Choose a [location](locations.md) inside the selected repository |
| `esc` | Step back from the location list; otherwise close the panel |
| `⇧⇥`, or `⌫` in an empty field | Step back from the location list |
| `⌘⌫` | [Ignore](ignoring.md) the selected repository, or restore an ignored one |
| `⌘⇧.` | Show ignored repositories too |
| `⌘R` | Refresh the repository list now |
| `⌘,` | Open Settings |

You can also click a row to open it.

## Reading the panel

**Tags** after a repository's name:

| Tag | Meaning |
| --- | --- |
| `local` | A clone exists in the account's working directory |
| `fork` | The repository is a fork |
| `archived` | The repository is archived |
| `ignored` | Hidden from normal searches; only visible after `⌘⇧.` |
| a hostname | Which GitHub host it is on — shown when you list more than one |

A lock icon marks private repositories.

**The footer** shows, on the left, how many repositories are listed and when
the list was last refreshed — or, in orange, what went wrong. On the right
are reminders of the main keys; `⇧↩` reads "Open folder" or "Clone"
depending on whether the selected repository is already on your disk.

## When the list is refreshed

- When the app starts
- When you open the panel, if the list is older than the refresh interval
  (an hour by default)
- When you press `⌘R`, choose **Refresh Repositories** from the menu bar
  icon, or click **Save & Refresh** in Settings

The list is kept on disk, so the panel is usable immediately and while
offline.
