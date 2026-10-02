---
title: Accounts
layout: default
nav_order: 5
---

# Accounts

An account is one GitHub host, how you sign in to it, and which of its
repositories to list. Most people need one; add a second for a company
GitHub Enterprise.

## Signing in

Each account signs in one of two ways.

### GitHub CLI

Uses whatever account `gh` is logged in with on that host. The app runs
`gh auth token` each time it refreshes and stores nothing itself.

- Set up with `gh auth login` (or `gh auth login --hostname git.example.com`
  for an enterprise host).
- Settings shows whether `gh` was found and is logged in to the host.
- `gh` is looked for on your `PATH` and in the usual Homebrew, MacPorts, mise,
  asdf and Nix locations.

This is the recommended option: there is no token to create or paste, and no
keychain prompt after rebuilding the app.

### Access token

Paste a personal access token. It is stored in your login keychain.

- **Fine-grained token:** read-only access to **Metadata** is enough.
- **Classic token:** the `repo` scope, for private repositories.
- Leave the field empty to list public repositories on github.com
  anonymously. GitHub limits anonymous use to 60 requests an hour.

If your organization enforces single sign-on, authorize the token (or the
`gh` login) for the organization, or its repositories won't appear.

## Choosing repositories

- **Organizations or users** — a comma-separated list. Every repository of
  each is listed (those your sign-in can see).
- **Include every repository I can access** — everything you own,
  collaborate on, or reach through an organization. Requires signing in.

You can use either or both. Repositories found twice are listed once.

Two filters in the **List** section apply to all accounts: **Include archived
repositories** (off by default) and **Include forks** (on by default).

## GitHub Enterprise

Set an account's **Host** to the hostname you use in the browser:

| You use | Host |
| --- | --- |
| github.com | `github.com` |
| GitHub Enterprise Server | e.g. `git.example.com` |
| GitHub Enterprise Cloud with data residency | e.g. `acme.ghe.com` |

Enter the hostname only — no `https://`, port or path.

If the server's certificate comes from a company certificate authority, that
authority must be trusted by macOS (on a managed work Mac it usually is).

## Several hosts at once

Click **Add Another Account** to list github.com and an enterprise host
together. Each account has its own host, sign-in, repository choices and
[working directory](local-clones.md).

- Results from all accounts are searched as one list. Each row is tagged
  with its host once more than one account lists repositories.
- **One account per host.** Two accounts on the same host aren't supported.
- **When a host can't be reached** — an internal server while you are off
  the VPN — its repositories stay in the list from the last successful
  refresh. Other hosts refresh normally, and the footer names the host that
  failed.

Removing an account also removes its saved token from the keychain.
