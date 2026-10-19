# Gitway

A KDE Plasma 6 widget to find a repo, then open a merge/pull request, create a branch
or check your issues in two or three keystrokes. GitHub and GitLab, driven by the
`gh` and `glab` CLIs. Pure QML + JavaScript, nothing to compile.

> Work in progress: everything below works, polishing and the KDE Store release come next.

- **Search** the repos of one account at a time (`org:`, `private:`, `public:`, `!` for archived),
  recently opened ones first. Switch accounts from the list in the header.
- **Repo page**: new merge/pull request, new branch on the remote, open in browser, copy
  link, the commits of the last pushed branch, open issues and open merge requests.
- **Merge request form** filled in for you: source is the branch pushed last, target the
  one you used last in that repo, title the newest commit. Duplicates and empty compares
  are caught before anything is sent.
- **My MRs, Reviews and Issues** tabs across all repos, with merge and approve confirmed
  in place.

Everything goes through `gh api` and `glab api`, so it works for repos that were never
cloned on this machine.

## Install from source

```sh
kpackagetool6 -t Plasma/Applet -i .   # first time
kpackagetool6 -t Plasma/Applet -u .   # after changes
```

Then add **Gitway** to a panel. The popup shows one account at a time. Pick another
one from the account list in its header (`A` or `Ctrl+Shift+A`).

## Requirements

- `gh` 2.40 or newer (multi-account `gh auth token --user`), signed in with `gh auth login`
- `glab` 1.53 or newer, signed in with `glab auth login`
- `jq`

Either CLI is enough. The other one is skipped.

## Repo sync script

`contents/scripts/sync-repos.sh` is what the widget runs behind the **Sync repos**
button. It also works on its own, for example with `fzf`.

```sh
# Every account gh and glab are signed in to
contents/scripts/sync-repos.sh accounts

# Repo list of one account, written to
# ~/.local/share/gitway/accounts/<provider>/<host>/<user>/repos.json
contents/scripts/sync-repos.sh sync github github.com <user>
contents/scripts/sync-repos.sh sync gitlab gitlab.com <user>

# Only repos you own, no organisation/group repos
contents/scripts/sync-repos.sh sync github github.com <user> --no-orgs

# Pick a repo with fzf and open it
jq -r '.repos[] | "\(.path)\t\(.url)"' ~/.local/share/gitway/accounts/github/github.com/<user>/repos.json \
  | fzf --with-nth=1 | cut -f2 | xargs -r xdg-open
```

A failed sync exits non-zero with the reason on stderr and leaves the previous
`repos.json` untouched. Set `GITWAY_DATA_DIR` to write somewhere else.

Tested against github.com and gitlab.com. Self-hosted GitLab and GitHub Enterprise
should work (every command takes the host from the account), but are not tested.

## License

GPL-3.0-or-later. The GitHub and GitLab logos are trademarks of their owners and
are not covered by this license.
