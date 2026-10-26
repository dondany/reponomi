---
title: Locations
layout: default
nav_order: 4
---

# Locations

A location is a place inside a repository: its pull requests, its Actions
runs, its settings. There are two ways to get to one.

## Inline: add a key after a space

Type the repository, a space, and a location key:

<img src="assets/inline-location.png" alt="Typing 'sw pr' targets the pull requests of the top result" width="680">

`sw pr` `↩` opens the pull requests of the selected repository. The
selected row shows where Return will go. Arrow keys still choose among the
repositories.

## From a list: press Tab

`⇥` locks the selected repository and lists every location. Type to filter,
`↩` to open, `esc` to go back to the repository search with your query
intact.

## Built-in locations

| Keys | Location | Opens |
| --- | --- | --- |
| `c`, `code`, `home` | Code | the repository's front page |
| `l`, `local`, `clone` | Local folder | the [clone on your disk](local-clones.md) |
| `p`, `pr`, `prs`, `pulls` | Pull requests | `/pulls` |
| `i`, `issues` | Issues | `/issues` |
| `ci`, `build`, `builds` | CI build | the [CI build](#ci-build) of the latest commit |
| `ch`, `checks`, `status` | Checks | the [checks page](#checks) of the latest commit |
| `a`, `actions` | Actions | `/actions` |
| `r`, `rel` | Releases | `/releases` |
| `b` | Branches | `/branches` |
| `co`, `log` | Commits | `/commits` |
| `t` | Tags | `/tags` |
| `s` | Settings | `/settings` |
| `w` | Wiki | `/wiki` |
| `d` | Discussions | `/discussions` |
| `pj` | Projects | `/projects` |
| `se`, `sec` | Security | `/security` |
| `in`, `pulse` | Insights | `/pulse` |
| `mp`, `my` | My pull requests | open pull requests you authored |
| `np`, `compare` | New pull request | `/compare` |
| `ni` | New issue | `/issues/new` |

## CI build

`api ci↩` opens the CI build of the latest commit on
[the branch you're on](#which-branch): the build of the check you named.
When you press Return, Reponomi asks GitHub for that commit and for the
statuses and check runs reported on it, and follows the link of the check
whose name contains one of your **check names**.

Set them in **Settings › CI builds** (`ciChecks` in the
[config file](configuration.md#ci-checks)), separated by commas:

```
jenkins, ci/circleci: build
```

- Case is ignored. A check with exactly your name wins; otherwise a check
  whose name contains yours: `jenkins` matches
  `continuous-integration/jenkins/branch`, while `build` picks a check named
  `build` over `report-build-status`.
- Earlier names win. Among checks matching the same name, statuses come
  before check runs.
- Nothing is guessed: with no check names set, or none that matches this
  commit's checks, `ci` opens the [checks page](#checks).

The name to use is the one GitHub shows for the check, on the checks page
or next to the commit's status icon. The build opens a moment after the
panel closes.

### Which links it follows

Anyone who can post a status on the repository chooses its link, so:

- Links on the repository's own GitHub host, which covers GitHub Actions,
  open directly.
- Links on a CI host you've allowed open directly. Allowed hosts are under
  **Settings › CI builds** (`ciHosts` in the [config file](configuration.md#ci-hosts)).
- Links on any other host ask first: **Open links to ci.example.com?**
  shows the check and its full link. **Allow and Open** adds the host to
  the allowed ones and opens the build. **Use Checks Page** (or `esc`)
  opens the checks page this time and asks again next time.
- Links that aren't HTTPS, or that carry a user name or password, are never
  opened or offered; you get the checks page.

When no check has a link, you get the [checks page](#checks).

## Checks

`api ch↩` opens the checks page of the latest commit on
[the branch you're on](#which-branch). It lists the check runs reported for
that commit, from GitHub Actions or other CI services, each with a link to
its build.

## Which branch

CI build and Checks look at the branch checked out in the repository's
[clone](local-clones.md), and the selected row says which one when it isn't
the default branch: `→ CI build · feature/login`. Without a clone, or with
`⌥↩` (`⌥⌘↩` to copy), they use the default branch.

- The branch is read from the clone's `.git/HEAD`; git isn't run.
- A branch that isn't on GitHub yet falls back to the default branch. So
  does a detached HEAD at a commit GitHub doesn't have.
- The commit is looked up when you press Return. If the token isn't allowed
  to read the repository's code (a fine-grained token with only Metadata
  access), the default branch's commit page opens instead, where the
  commit's checks and statuses are behind the status icon.

## How a location is chosen from what you type

1. A key that matches exactly wins: `p` is always Pull requests.
2. Otherwise, a key that starts with what you typed: `pu` finds `pulls`.
3. Otherwise, the location names are searched the same fuzzy way as
   repositories: `sett` finds Settings, `disc` Discussions.

If nothing matches, the row says so and Return does nothing.

## Adding your own

Custom locations go in the [config file](configuration.md#custom-locations):

```json
"customLocations": [
  { "name": "Deployments", "path": "/deployments", "keys": ["dp"] },
  { "name": "Docs folder", "path": "/tree/{branch}/docs", "keys": ["docs"] }
]
```

- `path` is appended to the repository's URL.
- `{branch}` is replaced by the repository's default branch.
- `{sha}` is replaced by the latest commit on the checked-out branch,
  looked up when you press Return, as for [Checks](#which-branch). If the
  lookup fails, nothing opens.
- `keys` are optional; without them the location is still found by name.
- Custom locations are listed and matched ahead of the built-in ones, so
  giving one the key `d` takes `d` over from Discussions.

Restart the app after editing the file.
