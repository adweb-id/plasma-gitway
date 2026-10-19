# KDE Store listing

Text and files for the product page on store.kde.org. Copy each field as is.

## Basics

| Field | Value |
| --- | --- |
| Title | Gitway |
| Category | Plasma 6 Widgets |
| License | GPL-3.0-or-later |
| Source / Homepage | https://github.com/adweb-id/plasma-gitway |
| Tags | git, github, gitlab, merge-request, pull-request, developer, plasma6, widget, plasmoid |
| Logo | `docs/store/logo-512.png` (to be exported from `contents/icons/gitway.svg`) |
| File | `gitway-<version>.plasmoid` from the GitHub release |

## Screenshots (in this order)

To be taken for the release: repo search, repo page, new merge request form, My MRs with
the merge panel, Issues, account list with Add account.

## Summary (one line)

Find any GitHub or GitLab repo from the panel, then open a merge request, create a branch or check your issues in a few keystrokes.

## Description

Gitway puts every repository of your GitHub and GitLab accounts one keystroke away. Type a
few letters, press Enter, and open a merge request with the branch, target and title
already filled in. No browser tab, no hunting for the right group.

Features
- Search all repos of an account instantly, offline, from a local list (org:, private:, public:, ! for hidden and archived)
- Pin repos to the top, hide whole groups, sort by last update or name
- Repo page: new merge or pull request, new branch on the remote, open in browser, copy web, SSH or HTTPS links, recent commits, open issues and merge requests
- Merge request form filled for you: last pushed branch, the target you used last, the newest commit as title. Duplicates and empty compares are caught before anything is sent
- My MRs, Reviews and Issues tabs across all repos, with merge and approve confirmed in place
- Several accounts: GitHub, GitHub Enterprise, gitlab.com and self-hosted GitLab, one at a time, switched from the header. Add account opens the sign-in for you
- Badge on the panel icon with what waits for you (see FAQ)
- Keyboard first, smooth transitions, follows your Plasma theme

Requirements
- Plasma 6.0 or newer
- gh 2.40 or newer for GitHub, glab 1.53 or newer for GitLab (either one is enough)
- jq
- Konsole or another terminal, only to sign in

FAQ

What does the badge on the panel icon count?
Everything that waits for you to act: merge requests asking for your review, plus your own
merge requests that are ready to merge, have a failed pipeline or have conflicts. Running
pipelines and drafts are not counted, since they wait for someone or something else. Hover
the icon to see the three numbers. The badge refreshes when the widget loads, when you open
the popup and after Sync repos. You can add a check every few minutes in the settings.

Why does My MRs show more than the badge?
My MRs lists all your open merge requests. The badge leaves out the ones that are still
running or are drafts.

Where are my tokens stored?
Gitway never sees them. All sign-ins go through gh and glab, which keep the tokens as they
always do. Gitway only runs their commands.

How do I add a second GitLab account on the same host?
Choose Add account in the account list. glab keeps one account per host, so Gitway signs
the new one in to its own glab folder for you.

Does it work for repos I never cloned?
Yes. Everything goes through the GitHub and GitLab APIs. Nothing is read from local folders.

Bugs and ideas: https://github.com/adweb-id/plasma-gitway/issues

## Changelog for 0.1.0

First release.
