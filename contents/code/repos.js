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
//   !text           also show hidden and archived repos
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

// Hidden patterns: a full "owner/repo", or "owner/group/*" for everything under it
function isHidden(path, patterns) {
    return patterns.some(p => p.endsWith("/*") ? path.startsWith(p.slice(0, -1)) : p === path);
}

function matches(repo, query, hideArchived, hidden) {
    if (!query.includeArchived && ((repo.archived && hideArchived) || isHidden(repo.path, hidden))) {
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

// Order of the "All repos" section. by: "pushed" | "name"
function compareRepos(a, b, by, descending) {
    const order = by === "name"
        ? a.name.toLowerCase().localeCompare(b.name.toLowerCase()) || a.path.localeCompare(b.path)
        : (a.pushed_at || "").localeCompare(b.pushed_at || "");
    return descending ? -order : order;
}

// Rows for the list, each with a "section": pinned repos first (in the
// order they were pinned), then recently opened ones (most recent first),
// then the rest in the chosen sort order (sort: {by, descending}). While
// searching, a repo whose own name starts with the first word goes first.
function buildRows(repos, text, recentPaths, hideArchived, pinnedPaths, hidden, sort) {
    sort = sort || { by: "pushed", descending: true };
    const query = parseQuery(text);
    const pinRank = {};
    pinnedPaths.forEach((path, i) => pinRank[path] = i);
    // Pinning a repo is explicit, so it beats a hidden "owner/*" pattern
    const shown = repos.filter(r => matches(r, query, hideArchived, pinRank[r.path] !== undefined ? [] : hidden));
    const pinned = shown.filter(r => pinRank[r.path] !== undefined)
        .sort((a, b) => pinRank[a.path] - pinRank[b.path]);
    const rank = {};
    recentPaths.forEach((path, i) => rank[path] = i);

    const recent = shown.filter(r => rank[r.path] !== undefined && pinRank[r.path] === undefined)
        .sort((a, b) => rank[a.path] - rank[b.path]);
    const first = query.words[0] || "";
    // Without a search the Recent section stays short; the rest is under "All repos"
    const recentShown = first || query.org || query.visibility ? recent : recent.slice(0, 5);
    const inRecent = {};
    recentShown.forEach(r => inRecent[r.path] = true);

    const rest = shown.filter(r => !inRecent[r.path] && pinRank[r.path] === undefined)
        .sort((a, b) => compareRepos(a, b, sort.by, sort.descending));
    if (first) {
        rest.sort((a, b) => {
            const aHit = a.name.toLowerCase().startsWith(first);
            const bHit = b.name.toLowerCase().startsWith(first);
            return aHit === bHit ? 0 : (aHit ? -1 : 1);
        });
    }
    const row = (r, section) => toRow(r, section, pinRank[r.path] !== undefined, isHidden(r.path, hidden));
    return pinned.map(r => row(r, "pinned"))
        .concat(recentShown.map(r => row(r, "recent")))
        .concat(rest.map(r => row(r, "all")));
}

function toRow(repo, section, pinned, hidden) {
    const slash = repo.path.lastIndexOf("/");
    return {
        section: section,
        id: repo.id,
        path: repo.path,
        owner: repo.path.slice(0, slash + 1),
        name: repo.path.slice(slash + 1),
        url: repo.url || "",
        ssh: repo.ssh || "",
        https: repo.https || "",
        visibility: repo.visibility || "public",
        archived: !!repo.archived,
        defaultBranch: repo.default_branch || "",
        pushedAt: repo.pushed_at || "",
        pinned: !!pinned,
        hidden: !!hidden
    };
}

// Target branch last used for a merge request, per account and repo:
// entries are "account<TAB>owner/repo<TAB>branch".
function lastTarget(entries, key, path) {
    const prefix = key + "\t" + path + "\t";
    const entry = entries.find(e => e.startsWith(prefix));
    return entry ? entry.slice(prefix.length) : "";
}

function setLastTarget(entries, key, path, branch, max) {
    const prefix = key + "\t" + path + "\t";
    return [prefix + branch].concat(entries.filter(e => !e.startsWith(prefix))).slice(0, max);
}

// Pinned and hidden lists use the same "account<TAB>value" entries as recent.
function toggleEntry(entries, key, value) {
    const entry = key + "\t" + value;
    return entries.indexOf(entry) !== -1 ? entries.filter(e => e !== entry) : entries.concat([entry]);
}

function removeEntry(entries, key, value) {
    return entries.filter(e => e !== key + "\t" + value);
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
