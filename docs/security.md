---
title: Security
layout: default
nav_order: 9
---

# Security

Reponomi handles a GitHub credential and can run commands on your Mac, so
this page spells out what it does to stay safe and what it relies on you
for.

## What leaves your Mac

Only requests to the API of the GitHub hosts you configured, over HTTPS, to
list repositories. There is no Reponomi account, no telemetry, no update
check and nothing listening on the network.

## Credentials

- A pasted token is stored in your login keychain. With GitHub CLI sign-in
  the app stores nothing and asks `gh` each time.
- The token is sent only to the configured host's API. It is never written
  to the config file, logs, the clipboard or a command line.
- A redirect or "next page" link pointing at a different host does not
  receive the token.
- The app only reads. A fine-grained token with read-only Metadata access is
  all it needs.

## What the app refuses to trust

**The server.** A repository's address is always built as
`https://<host>/<owner>/<name>` from the account's host, never taken from a
response. Names with characters GitHub doesn't allow are dropped. Hosts must
be bare hostnames. Descriptions are stripped of control and text-direction
characters. Responses are size-limited, and no cookies or web cache are
kept; the only thing saved is the repository list itself (`repos.json`,
readable only by you).

**The cache.** The saved repository list is checked the same way each time
it is loaded.

**Folder names.** Repository and folder names are never spliced into shell
commands; paths are quoted, and a path containing control characters is not
sent to a terminal at all.

**Look-alike folders.** A folder only counts as the clone of a repository if
it sits directly in the working directory, or one level down in a folder
named after the repository's owner, and one of its `[remote]` URLs points at
that repository. See [Local clones](local-clones.md#which-folders-count-as-a-clone).

## The build

The app is built with the hardened runtime, which stops other processes
from loading code into it — and so from borrowing its keychain entry or its
permission to control iTerm.

It is ad-hoc signed, not signed with an Apple Developer ID. That is why
macOS asks for keychain access again after each rebuild when you use a saved
token.

## What it assumes

- **Your working directory is yours.** A folder there that looks like a
  clone is opened as one, and your Run command runs inside it. Don't unpack
  untrusted archives that contain a `.git` folder into it — the same care
  any git tool needs.
- **Your user account isn't compromised.** Anything running as you can edit
  the config file, which names the command to run, or replace `gh`, `git` or
  the app itself.
- **The hosts you add are ones you trust.** A hostile server can still list
  misleading repository names, though links and clones only ever go to that
  same host.
- **`git`, `gh` and macOS are up to date.** Cloning, credential storage and
  TLS are theirs.

## Permissions the app may ask for

| Prompt | When | Why |
| --- | --- | --- |
| Keychain access | After a rebuild, with token sign-in | To read the token it saved |
| Control iTerm | First `⇧↩` with iTerm and a Run command | To open a window and type the command |

It needs no Accessibility, Input Monitoring, Screen Recording or Full Disk
Access permission.

## Reporting a problem

If you find a security issue, please report it privately to the maintainer
rather than in a public issue.
