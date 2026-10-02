---
title: Ignoring repositories
layout: default
nav_order: 7
---

# Ignoring repositories

Large organizations have repositories you will never open. Ignoring one
removes it from the search without affecting anything on GitHub.

## Ignoring

Select the repository in the search panel and press `⌘⌫`. It disappears from
the list immediately, and the footer confirms it.

## Restoring

There are two ways to bring a repository back.

**From the search panel.** Press `⌘⇧.` — the same shortcut Finder uses to
show hidden files. Ignored repositories appear in the results, dimmed and
tagged `ignored`. Select one and press `⌘⌫` again to restore it.

<img src="assets/show-ignored.png" alt="After ⌘⇧. ignored repositories are shown dimmed with an 'ignored' tag" width="680">

The panel goes back to hiding them the next time you open it.

**From Settings.** In the **List** section, **Ignored repositories** shows
how many are hidden. **Manage…** opens the full list, with a **Restore**
button for each and **Restore All**. A filter field appears once the list is
long.

<img src="assets/ignored-sheet.png" alt="The Manage sheet lists ignored repositories with a Restore button each" width="440">

## Details

- The ignore list is per repository and per host: ignoring `acme/api` on
  github.com doesn't hide an `acme/api` on your enterprise host.
- It is stored in the [config file](configuration.md) under `ignored`, as
  `host/owner/name`.
- Ignored repositories are still fetched, so restoring one is instant.
