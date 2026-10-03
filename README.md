# Reponomi

A macOS menu bar app that jumps to a GitHub repository — or a specific page
inside it, or its clone on your disk — in a few keystrokes. Press a global
shortcut, type a few letters, hit Return.

<img src="docs/assets/inline-location.png" alt="The Reponomi search panel: typing 'sw pr' targets the pull requests of the best match" width="680">

*Typing `sw pr` picks the best match for "sw" and goes straight to its pull
requests.*

The name is a Devil Fruit that One Piece never had: the *Repo Repo no Mi*,
whose user can appear at any repository instantly. Say it "re-po-no-mi".

The full guide is in [`docs/`](docs/index.md): searching, locations, accounts,
local clones, configuration, security and troubleshooting.

## Build and run

```sh
./scripts/build-app.sh            # builds build/Reponomi.app
./scripts/build-app.sh --install  # also copies it to /Applications and launches it
./scripts/test.sh                 # unit tests
```

Requires macOS 14+ and a Swift toolchain (Xcode or the Command Line Tools).

On first launch the Settings window opens. Enter the organizations or users
whose repositories you want listed. For private repositories, sign in with
an access token or with the GitHub CLI.

### Several GitHub hosts

To search github.com and a company GitHub Enterprise together, add one
account per host in Settings ("Add Another Account"). Each account has its
own host, sign-in and list of organizations; the results are merged into one
list, with a tag showing which host each repository is on.

If a host can't be reached — an internal server while you are off the VPN,
say — its repositories stay in the list from the last successful refresh.

## Using it

Press **⌃⌥R** (changeable in Settings) to open the search bar.

| Keys | Action |
| --- | --- |
| type | Fuzzy-filter repositories. `org/name` also matches the owner. |
| `↑` `↓`, `⌃P` `⌃N`, `⌃K` `⌃J` | Move the selection |
| `↩` | Open in the browser |
| `⇧↩` | Open the local clone, cloning it first if needed |
| `⌘↩` | Copy the URL instead |
| `⇥` | Pick a location inside the selected repository |
| `⌘⌫` | Ignore the selected repository (or restore an ignored one) |
| `⌘⇧.` | Show ignored repositories too |
| `esc`, `⇧⇥`, `⌫` on an empty field | Back to the repository list; `esc` again closes |
| `⌘R` | Refresh the repository list |
| `⌘,` | Settings |

Repositories you open often and recently rank higher.

### Locations

Add a location after a space to go straight to that page: `api pr↩` opens the
pull requests of the best match for `api`. `⇥` shows the full list instead.

| Key | Location | Key | Location |
| --- | --- | --- | --- |
| `c` | Code | `l` | Local folder |
| `w` | Wiki | | |
| `p`, `pr` | Pull requests | `d` | Discussions |
| `i` | Issues | `pj` | Projects |
| `a`, `ci` | Actions | `se` | Security |
| `r` | Releases | `in` | Insights |
| `b` | Branches | `mp` | My pull requests |
| `co` | Commits | `np` | New pull request |
| `t` | Tags | `ni` | New issue |
| `s` | Settings | | |

Anything else is matched fuzzily against the location names (`sett`, `wiki`).

### Local clones

Give an account a working directory in Settings and `⇧↩` (or the `l`
location, as in `api l↩`) opens the repository on disk instead of in the
browser. If it isn't cloned yet, it is cloned into
`<working directory>/<repository name>` first; the panel shows progress and
can be dismissed while the clone carries on.

- Each account has its own working directory, so work and personal
  repositories can live in different folders, and its own choice of SSH or
  HTTPS for cloning.
- Existing clones are recognized by their git remote, not their folder name,
  directly inside the working directory or one level down (`owner/name`).
  They are marked `local` in the list.
- "Open with" in Settings picks the app that folders open in — an editor, a
  terminal, or Finder.
- With Terminal or iTerm chosen, "Run command" opens a new window in the
  folder and runs a command there in your own shell, e.g. `lazygit`. When the
  command exits you are left at a prompt in the repository. The first time
  with iTerm, macOS asks whether Reponomi may control it.
- Cloning uses your own git setup (SSH keys, credential helper). A clone that
  would have to ask for a password fails with git's message instead.

### Ignoring repositories

`⌘⌫` hides the selected repository from the search. To bring one back, press
`⌘⇧.` in the panel to show ignored repositories (as in Finder's "show hidden
files") and `⌘⌫` on it again, or use Settings › List › Ignored repositories ›
Manage….

## Configuration

Settings are stored in `~/Library/Application Support/Reponomi/config.json`.
The Settings window covers everything except custom locations, which you add
by hand (restart the app afterwards):

```json
{
  "accounts": [
    { "host": "github.com", "auth": "gh", "includeMyRepos": true,
      "workingDirectory": "~/Projects", "cloneProtocol": "ssh" },
    { "host": "git.example.com", "auth": "token", "owners": ["platform"],
      "workingDirectory": "~/work", "cloneProtocol": "https" }
  ],
  "localApp": "/Applications/iTerm.app",
  "localCommand": "lazygit",
  "ignored": ["github.com/my-org/legacy-monolith"],
  "customLocations": [
    { "name": "Deployments", "path": "/deployments", "keys": ["dp"] },
    { "name": "Docs folder", "path": "/tree/{branch}/docs", "keys": ["docs"] }
  ]
}
```

`{branch}` expands to the repository's default branch. Custom locations are
matched ahead of the built-in ones, so they can take over a built-in key.

### Signing in

Each account can authenticate in one of two ways:

- **Access token** — paste a classic token with the `repo` scope, or a
  fine-grained token with read access to Metadata. It is kept in the login
  keychain. Leave it empty to browse public repositories anonymously
  (limited to 60 requests per hour).
- **GitHub CLI** — reuse the account `gh` is logged in with on that host. The
  app runs `gh auth token` on each refresh and stores nothing itself. Settings
  shows whether `gh` was found and is logged in; if not, run `gh auth login`
  (`gh auth login --hostname git.example.com` for an enterprise host).

For organizations that enforce SSO, the token (or the `gh` login) must be
authorized for the organization.

Because the app is ad-hoc signed, macOS asks for keychain access again after
each rebuild when a saved token is in use. The GitHub CLI option avoids that.

For GitHub Enterprise, set an account's Host to the hostname you open in the
browser, such as `git.example.com` or `acme.ghe.com`.

## Security

What the app does to stay safe, and what it assumes.

- **Tokens** live in the login keychain, or are read from `gh` at refresh
  time. They are sent only to the configured host's API over HTTPS, and never
  written to the config, logs or command lines.
- **Server responses are not trusted.** A repository's address is always
  built as `https://<host>/<owner>/<name>` from the account's host; names with
  characters GitHub doesn't allow are dropped; pagination only follows links
  on the same API host. Hosts must be bare hostnames (no `user@`, port or
  path).
- **Local clones** are recognized only directly inside the working directory,
  or one level down in a folder named after the repository's owner, and only
  by their `[remote]` URLs. Repository data is never spliced into shell
  commands.
- **The build** uses the hardened runtime, so other processes can't load code
  into the app.

It assumes that:

- **Your working directory is yours.** A folder there that looks like a clone
  is opened as one, and "Run command" runs inside it. Don't unpack untrusted
  archives that contain a `.git` folder into it — the same caution any git
  tool needs.
- **Your user account is not compromised.** Anything running as you can edit
  the config (which names the command to run) or replace `gh` and `git`.
- **`git`, `gh` and macOS are up to date.** Cloning and credential handling
  are theirs.

## Documentation site

`docs/` is a ready-to-publish GitHub Pages site (Jekyll with the Just the
Docs theme). To publish it, push the repository to GitHub, then in the
repository's Settings › Pages choose **Deploy from a branch**, branch `main`,
folder `/docs`. The pages are plain Markdown and also read fine on GitHub
itself.

## License

MIT — see [LICENSE](LICENSE).
