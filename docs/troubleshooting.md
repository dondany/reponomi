---
title: Troubleshooting
layout: default
nav_order: 10
---

# Troubleshooting

Errors appear in orange in the panel's footer and at the bottom of the
Settings window. This page lists the common ones.

## The shortcut does nothing

- **Another app owns the combination.** Settings shows a warning under the
  shortcut when macOS refuses it. Click the shortcut and choose another.
- **The app isn't running.** Look for its icon in the menu bar. Turn on
  **Launch at login** to keep it running.

## Repositories are missing

| Symptom | Likely cause |
| --- | --- |
| Private repositories don't appear | Not signed in, or the token lacks access |
| An organization's repositories don't appear | The organization enforces single sign-on and the token or `gh` login isn't authorized for it |
| Archived repositories or forks don't appear | The filters in Settings › List |
| One specific repository is missing | It may be [ignored](ignoring.md); press `⌘⇧.` in the panel |
| Nothing from one host | See the footer: the host may be unreachable (VPN) or the sign-in rejected |

Press `⌘R` to refresh after fixing the cause.

## Messages about signing in

**"GitHub rejected the access token."** The token is wrong, expired or
revoked. Paste a new one, or switch to GitHub CLI sign-in.

**"The GitHub CLI (gh) isn't installed."** Install it (`brew install gh`),
or sign in with a token.

**"The GitHub CLI isn't logged in to …"** Run `gh auth login`, adding
`--hostname <host>` for an enterprise host.

**"An access token is required."** "Include every repository I can access"
needs a sign-in.

**"GitHub rate limit reached."** Without a sign-in GitHub allows 60 requests
an hour. Sign in, or wait until the time shown.

**"… isn't a valid hostname."** Enter only the host — `git.example.com` —
without `https://`, a port or a path.

**"No organization or user named …"** Check the spelling. For a private
organization, the sign-in must be able to see it.

## macOS asks for keychain access again

This happens after each rebuild when you sign in with a saved token: the
rebuilt app has a new signature. Click **Always Allow**, or switch to GitHub
CLI sign-in, which doesn't use the keychain.

## Local clones

**"No working directory is set for …"** Add one to that account in Settings.

**"Can't clone …: … already exists and isn't a clone of it."** A different
folder has that name. Rename or move it, or clone by hand under another
name — the app will recognize it by its remote.

**"Couldn't clone …"** followed by git's own message. Usually credentials:
try the other **Clone with** option, or run the same `git clone` in a
terminal to see the full error.

**A repository I have isn't tagged `local`.** It must be directly inside the
working directory, or one level down in a folder named after its owner. See
[which folders count](local-clones.md#which-folders-count-as-a-clone).

**⇧↩ opens Finder rather than my editor.** Set **Open with** in Settings ›
Local folders, then **Save & Refresh**.

## Terminal and iTerm

**"Reponomi isn't allowed to control iTerm."** Allow it in System Settings
› Privacy & Security › Automation. macOS may ask again after the app is
rebuilt.

**The command isn't found in the terminal.** The command runs in your normal
shell; if it works when you type it in a new terminal window, it works here.
If it doesn't work there either, fix your shell's `PATH`.

**iTerm opens but nothing is typed.** The command is typed into the window
iTerm opens with its default profile. If that profile starts something other
than a shell, the text goes there.

## Starting over

Quit the app and delete `~/Library/Application Support/Reponomi`. The next
launch starts from an empty configuration. A saved token stays in the
keychain under the name "Reponomi" until you remove it with Keychain Access.
