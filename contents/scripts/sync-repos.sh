#!/usr/bin/env bash
# Gitway repo sync. Lists the accounts gh and glab are signed in to, and
# writes the repo list of one account to its own repos.json.
#
#   sync-repos.sh accounts
#   sync-repos.sh sync <github|gitlab> <host> <user> [--no-orgs] [--glab-config DIR]
#
# stdout is always JSON. Errors go to stderr with a non-zero exit, and an
# existing repos.json is never replaced by a failed sync.

set -euo pipefail

DATA_DIR="${GITWAY_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/gitway}"

die() { printf 'gitway: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found"; }

# ---------------------------------------------------------------- accounts

# One TSV line per account: provider, host, user, status (ok | error).
accounts_github() {
    command -v gh >/dev/null 2>&1 || return 0
    gh auth status 2>&1 | awk -v OFS='\t' '
        /Logged in to |Failed to log in to / {
            for (i = 1; i < NF; i++) if ($i == "account") { host = $(i-1); user = $(i+1) }
            print "github", host, user, (/Failed to log in/ ? "error" : "ok")
        }'
}

# glab auth status only gives the host list: its token check is unreliable
# (glab 1.53 says "Invalid token" for tokens that work). Each host is asked
# who it is instead, which also gives the exact username.
accounts_gitlab() {
    command -v glab >/dev/null 2>&1 || return 0
    local host user
    for host in $(glab auth status 2>&1 | awk '/^[^ \t]/ { print $1 }'); do
        user=$(glab api --hostname "$host" user 2>/dev/null | jq -r '.username // empty' || true)
        if [[ $user ]]; then
            printf 'gitlab\t%s\t%s\tok\n' "$host" "$user"
        else
            # Fall back to the name glab printed, so the account still shows up.
            user=$(glab auth status --hostname "$host" 2>&1 \
                | awk '/Logged in to .* as / { for (i = 1; i < NF; i++) if ($i == "as") print $(i+1) }')
            printf 'gitlab\t%s\t%s\terror\n' "$host" "$user"
        fi
    done
}

cmd_accounts() {
    need jq
    { accounts_github; accounts_gitlab; } | jq -R -s '
        split("\n") | map(select(length > 0) | split("\t")
          | {provider: .[0], host: .[1], user: .[2], status: .[3]})'
}

# ---------------------------------------------------------------- sync

# Both fetchers print one JSON array per page. The caller merges them.
fetch_github() {
    local host=$1 user=$2 aff=owner,collaborator,organization_member token
    [[ $NO_ORGS ]] && aff=owner
    need gh
    token=$(gh auth token --hostname "$host" --user "$user" 2>/dev/null) \
        || die "gh has no token for $user on $host"
    GH_TOKEN=$token GH_HOST=$host gh api --paginate \
        "user/repos?per_page=100&affiliation=$aff" --jq '[.[] | {
            id: (.id | tostring), path: .full_name, name: .name, owner: .owner.login,
            url: .html_url, ssh: .ssh_url, https: .clone_url,
            default_branch: .default_branch, visibility: .visibility,
            archived: .archived, pushed_at: .pushed_at }]'
}

# glab keeps one token per host, so check that it belongs to the requested
# user before listing anything under that user's name.
fetch_gitlab() {
    local host=$1 user=$2 scope=membership=true me
    [[ $NO_ORGS ]] && scope=owned=true
    need glab
    [[ $GLAB_DIR ]] && export GLAB_CONFIG_DIR=$GLAB_DIR
    me=$(glab api --hostname "$host" user 2>/dev/null | jq -r '.username // empty') \
        || die "glab cannot reach $host"
    [[ $me ]] || die "glab is not signed in to $host"
    [[ $me == "$user" ]] || die "glab on $host is signed in as $me, not $user"
    glab api --hostname "$host" --paginate "projects?$scope&per_page=100&order_by=last_activity_at" \
        | jq '[.[] | {
            id: (.id | tostring), path: .path_with_namespace, name: .path,
            owner: .namespace.full_path, url: .web_url, ssh: .ssh_url_to_repo,
            https: .http_url_to_repo, default_branch: .default_branch,
            visibility: .visibility, archived: .archived,
            pushed_at: .last_activity_at }]'
}

cmd_sync() {
    local provider=$1 host=$2 user=$3; shift 3
    NO_ORGS='' GLAB_DIR=''
    while (($#)); do
        case $1 in
            --no-orgs) NO_ORGS=1 ;;
            --glab-config) GLAB_DIR=${2:?--glab-config needs a directory}; shift ;;
            *) die "unknown option: $1" ;;
        esac
        shift
    done
    need jq

    local dir="$DATA_DIR/accounts/$provider/$host/$user" out pages
    case $provider in
        github) pages=$(fetch_github "$host" "$user") ;;
        gitlab) pages=$(fetch_gitlab "$host" "$user") ;;
        *) die "unknown provider: $provider" ;;
    esac

    mkdir -p "$dir"
    out=$(mktemp "$dir/.repos.json.XXXXXX")
    trap 'rm -f "$out"' EXIT
    jq -s --arg provider "$provider" --arg host "$host" --arg account "$user" '
        add // [] | unique_by(.id) | sort_by(.pushed_at) | reverse
        | map(. + {provider: $provider, host: $host, account: $account}) as $repos
        | {version: 1, provider: $provider, host: $host, account: $account,
           synced_at: (now | todate), count: ($repos | length), repos: $repos}' \
        <<<"$pages" >"$out"
    mv "$out" "$dir/repos.json"
    trap - EXIT
    jq -c --arg file "$dir/repos.json" '{ok: true, file: $file, count: .count}' "$dir/repos.json"
}

case ${1:-} in
    accounts) cmd_accounts ;;
    sync) (($# >= 4)) || die "usage: sync-repos.sh sync <github|gitlab> <host> <user> [--no-orgs] [--glab-config DIR]"
          shift; cmd_sync "$@" ;;
    *) die "usage: sync-repos.sh accounts | sync <github|gitlab> <host> <user> [options]" ;;
esac
