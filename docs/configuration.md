---
title: Configuration
layout: default
nav_order: 8
---

# Configuration

Almost everything is set in the Settings window (`⌘,` in the panel, or
**Settings…** in the menu bar icon's menu). Custom locations are the one
thing that needs the config file.

## The Settings window

Changes take effect when you click **Save & Refresh**, except the shortcut,
launch at login and restoring ignored repositories, which apply at once.

### Per account

| Setting | What it does |
| --- | --- |
| Host | The GitHub host, e.g. `github.com` or `git.example.com` |
| Sign in with | **Access token** or **GitHub CLI** — see [Accounts](accounts.md) |
| Access token | Shown for token sign-in; stored in the keychain |
| Organizations or users | Whose repositories to list, comma-separated |
| Include every repository I can access | Also list everything your sign-in reaches |
| Working directory | Where this host's repositories are cloned — see [Local clones](local-clones.md) |
| Clone with | SSH or HTTPS; shown once a working directory is set |

### List

| Setting | Default | What it does |
| --- | --- | --- |
| Include archived repositories | Off | List archived repositories too |
| Include forks | On | List forks too |
| Refresh | Every hour | How stale the list may get before it is refreshed when you open the panel |
| Ignored repositories | — | Count, and **Manage…** to restore — see [Ignoring](ignoring.md) |

### Local folders

| Setting | Default | What it does |
| --- | --- | --- |
| Open with | Finder | The app that local clones open in |
| Run command | — | For Terminal and iTerm: a command to run in the folder |

### Shortcut

| Setting | Default | What it does |
| --- | --- | --- |
| Open Reponomi | ⌃⌥R | The global shortcut. Click it, then press a new combination that includes ⌘, ⌃ or ⌥; `esc` cancels |
| Launch at login | Off | Start the app when you log in |

## The config file

Settings are stored as JSON in

```
~/Library/Application Support/Reponomi/config.json
```

The app reads it at startup, so restart after editing it by hand. Every key
is optional.

```json
{
  "accounts": [
    {
      "host": "github.com",
      "auth": "gh",
      "owners": ["my-org"],
      "includeMyRepos": true,
      "workingDirectory": "~/Projects",
      "cloneProtocol": "ssh"
    },
    {
      "host": "git.example.com",
      "auth": "token",
      "owners": ["platform"],
      "workingDirectory": "~/work",
      "cloneProtocol": "https"
    }
  ],
  "includeArchived": false,
  "includeForks": true,
  "refreshMinutes": 60,
  "localApp": "/Applications/iTerm.app",
  "localCommand": "lazygit",
  "ignored": ["github.com/my-org/legacy-monolith"],
  "customLocations": [
    { "name": "Deployments", "path": "/deployments", "keys": ["dp"] }
  ]
}
```

| Key | Values |
| --- | --- |
| `accounts[].host` | A bare hostname |
| `accounts[].auth` | `"gh"` or `"token"` (the token itself is in the keychain, never here) |
| `accounts[].owners` | Organization and user names |
| `accounts[].includeMyRepos` | `true` or `false` |
| `accounts[].workingDirectory` | A folder path; `~` is allowed |
| `accounts[].cloneProtocol` | `"ssh"` or `"https"` |
| `includeArchived`, `includeForks` | `true` or `false` |
| `refreshMinutes` | Minutes between automatic refreshes |
| `localApp` | Path of the app to open clones with; leave out for Finder |
| `localCommand` | Command to run in the folder, when `localApp` is Terminal or iTerm |
| `ignored` | Repositories to hide, as `host/owner/name` in lower case |
| `customLocations` | See below |
| `hotkey` | Written by the shortcut recorder; change it in Settings |

### Custom locations

```json
"customLocations": [
  { "name": "Deployments", "path": "/deployments", "keys": ["dp"] },
  { "name": "Docs folder", "path": "/tree/{branch}/docs", "keys": ["docs"] }
]
```

`path` is appended to the repository's URL, with `{branch}` replaced by its
default branch. See [Locations](locations.md#adding-your-own).

## Other files

In the same folder:

| File | Contents |
| --- | --- |
| `repos.json` | The cached repository list, so the panel works at once and offline |
| `usage.json` | How often and how recently you opened each repository, for ranking |

Deleting either is safe: the list is fetched again, and ranking starts over.

Setting the environment variable `REPONOMI_HOME` makes the app use a
different folder for all three files — useful for trying a configuration
without touching your own.
