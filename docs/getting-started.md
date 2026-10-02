---
title: Getting started
layout: default
nav_order: 2
---

# Getting started

## Requirements

- macOS 14 or later
- The Xcode Command Line Tools (`xcode-select --install`) or Xcode, to build
- Optional: the [GitHub CLI](https://cli.github.com) (`gh`), the easiest way
  to sign in
- Optional: `git`, for [local clones](local-clones.md)

## Install

Reponomi is built from source. Clone the repository, then:

```sh
./scripts/build-app.sh --install
```

This builds the app, copies it to `/Applications/Reponomi.app` and starts
it. Without `--install` the app is only built, into `build/Reponomi.app`.

Because you built it yourself, macOS doesn't quarantine it and there is no
"unidentified developer" warning.

## First launch

The app lives in the menu bar; it has no Dock icon. On first launch the
Settings window opens so you can tell it which repositories to list.

1. **Sign in.** Under your account, choose **GitHub CLI** if you use `gh`
   (run `gh auth login` first if you haven't), or **Access token** and paste
   a token. Public repositories on github.com work without signing in.
2. **Choose repositories.** Either type the organizations or users whose
   repositories you want (`my-org, another-org`), or turn on **Include every
   repository I can access**.
3. Click **Save & Refresh**. The status line at the bottom shows how many
   repositories were found.

More on these choices in [Accounts](accounts.md).

## First search

Press **⌃⌥R** anywhere. The search panel appears; type a few letters of a
repository's name and press `↩` to open it in your browser. `esc` closes the
panel.

You can also open the panel from the menu bar icon, or by launching the app
again while it is running.

## Worth setting up next

- **A working directory**, so `⇧↩` opens repositories on your disk. See
  [Local clones](local-clones.md).
- **Launch at login**, in Settings under Shortcut. Install the app to
  `/Applications` first.
- **A different shortcut**, if ⌃⌥R clashes with something. Click the shortcut
  in Settings and press the new combination.
