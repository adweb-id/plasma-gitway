.pragma library

// Everything about accounts and repo lists that does not need QML:
// the sync script's command lines, parsing its JSON, and the search.

function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'";
}

// script: absolute path of contents/scripts/sync-repos.sh
function accountsCommand(script) {
    return "bash " + shellQuote(script) + " accounts";
}

function readCommand(script, account) {
    return ["bash", shellQuote(script), "read", shellQuote(account.provider),
            shellQuote(account.host), shellQuote(account.user)].join(" ");
}

function syncCommand(script, account, includeOrgs) {
    return ["bash", shellQuote(script), "sync", shellQuote(account.provider),
            shellQuote(account.host), shellQuote(account.user)].join(" ")
        + (includeOrgs ? "" : " --no-orgs");
}

// "github/github.com/addin": how an account is stored in the settings
function accountKey(account) {
    return account ? account.provider + "/" + account.host + "/" + account.user : "";
}

// "addin - github.com": how an account is shown
function accountLabel(account) {
    return account ? account.user + " - " + account.host : "";
}

function parseAccounts(stdout) {
    try {
        const list = JSON.parse(stdout);
        return Array.isArray(list) ? list.filter(a => a.provider && a.host && a.user) : [];
    } catch (e) {
        return [];
    }
}

// Saved account if it is still signed in, else the first working one.
function pickAccount(accounts, savedKey) {
    return accounts.find(a => accountKey(a) === savedKey)
        || accounts.find(a => a.status === "ok")
        || accounts[0]
        || null;
}

function parseRepoFile(stdout) {
    try {
        const data = JSON.parse(stdout);
        return data && Array.isArray(data.repos) ? data : null;
    } catch (e) {
        return null;
    }
}

// Search text -> filter. Words must all appear in "owner/name".
//   org:acme        only repos under that owner or group
//   private: public:  by visibility (GitLab "internal" counts as private)
//   !text           also show archived repos
function parseQuery(text) {
    const query = { words: [], org: "", visibility: "", includeArchived: false };
    let rest = text.trim().toLowerCase();
    if (rest.startsWith("!")) {
        query.includeArchived = true;
        rest = rest.slice(1);
    }
    for (let part of rest.split(/\s+/)) {
        if (part.startsWith("org:")) {
            query.org = part.slice(4);
            continue;
        }
        for (const visibility of ["private", "public"]) {
            if (part.startsWith(visibility + ":")) {
                query.visibility = visibility;
                part = part.slice(visibility.length + 1);
            }
        }
        if (part) {
            query.words.push(part);
        }
    }
    return query;
}

function matches(repo, query, hideArchived) {
    if (repo.archived && hideArchived && !query.includeArchived) {
        return false;
    }
    if (query.org && !repo.owner.toLowerCase().startsWith(query.org)) {
        return false;
    }
    if (query.visibility === "public" && repo.visibility !== "public") {
        return false;
    }
    if (query.visibility === "private" && repo.visibility === "public") {
        return false;
    }
    const path = repo.path.toLowerCase();
    return query.words.every(w => path.includes(w));
}

// Rows for the list, each with a "section": recently opened repos first
// (most recent first), then the rest by last push. While searching, a
// repo whose own name starts with the first word goes before the others.
function buildRows(repos, text, recentPaths, hideArchived) {
    const query = parseQuery(text);
    const shown = repos.filter(r => matches(r, query, hideArchived));
    const rank = {};
    recentPaths.forEach((path, i) => rank[path] = i);

    const recent = shown.filter(r => rank[r.path] !== undefined)
        .sort((a, b) => rank[a.path] - rank[b.path]);
    const first = query.words[0] || "";
    // Without a search the Recent section stays short; the rest is under "All repos"
    const recentShown = first || query.org || query.visibility ? recent : recent.slice(0, 5);
    const inRecent = {};
    recentShown.forEach(r => inRecent[r.path] = true);

    const rest = shown.filter(r => !inRecent[r.path])
        .sort((a, b) => (b.pushed_at || "").localeCompare(a.pushed_at || ""));
    if (first) {
        rest.sort((a, b) => {
            const aHit = a.name.toLowerCase().startsWith(first);
            const bHit = b.name.toLowerCase().startsWith(first);
            return aHit === bHit ? 0 : (aHit ? -1 : 1);
        });
    }
    return recentShown.map(r => toRow(r, "recent")).concat(rest.map(r => toRow(r, "all")));
}

function toRow(repo, section) {
    const slash = repo.path.lastIndexOf("/");
    return {
        section: section,
        path: repo.path,
        owner: repo.path.slice(0, slash + 1),
        name: repo.path.slice(slash + 1),
        url: repo.url || "",
        ssh: repo.ssh || "",
        https: repo.https || "",
        visibility: repo.visibility || "public",
        archived: !!repo.archived,
        pushedAt: repo.pushed_at || ""
    };
}

// Recent list entries are "account<TAB>owner/repo", newest first.
function recentFor(recent, key) {
    return recent.filter(e => e.startsWith(key + "\t")).map(e => e.slice(key.length + 1));
}

function addRecent(recent, key, path, max) {
    const entry = key + "\t" + path;
    const next = [entry].concat(recent.filter(e => e !== entry));
    return next.slice(0, max);
}
