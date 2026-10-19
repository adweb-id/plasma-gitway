.pragma library
.import "repos.js" as Repos

// Everything Gitway asks GitHub or GitLab about one repo: the shell
// commands (always through the REST/GraphQL API, never interactive) and
// the parsers that turn both providers' answers into the same shapes.
//
// account: {provider, host, user}   repo: a row from repos.js toRow()

const TIMEOUT = 30; // seconds, PRD 4.9

const q = Repos.shellQuote;

// GitHub: the token of exactly this account, so several accounts on one host
// work without "gh auth switch" (which would change the terminal's account).
function ghScript(account, body) {
    return "export GH_TOKEN=\"$(gh auth token --hostname " + q(account.host) + " --user " + q(account.user) + ")\" GH_HOST="
        + q(account.host) + "; " + body;
}

function ghApi(path, args) {
    return "timeout " + TIMEOUT + " gh api " + q(path) + (args ? " " + args : "");
}

function glApi(account, path, args) {
    return "timeout " + TIMEOUT + " glab api --hostname " + q(account.host) + " " + q(path) + (args ? " " + args : "");
}

// GitHub accepts "/" inside branch names in URL paths, other characters are encoded
function branchInPath(name) {
    return encodeURIComponent(name).replace(/%2F/g, "/");
}

function project(repo) {
    return "projects/" + repo.id;
}

// "MR" on GitLab, "PR" on GitHub, and the number prefix that goes with it
function short(account) {
    return account.provider === "gitlab" ? "MR" : "PR";
}

function sigil(account) {
    return account.provider === "gitlab" ? "!" : "#";
}

// --- Branches, newest commit first ---------------------------------------------

const GH_BRANCHES = "query($owner:String!,$name:String!){repository(owner:$owner,name:$name){"
    + "refs(refPrefix:\"refs/heads/\",first:100,orderBy:{field:TAG_COMMIT_DATE,direction:DESC}){"
    + "nodes{name target{...on Commit{oid committedDate messageHeadline}}}}}}";

function branchesCommand(account, repo) {
    if (account.provider === "gitlab") {
        return glApi(account, project(repo) + "/repository/branches?per_page=100");
    }
    const slash = repo.path.indexOf("/");
    return ghScript(account, ghApi("graphql", "-f query=" + q(GH_BRANCHES)
        + " -f owner=" + q(repo.path.slice(0, slash)) + " -f name=" + q(repo.path.slice(slash + 1))));
}

// -> [{name, sha, date, title}] sorted by last commit, newest first
function parseBranches(account, stdout) {
    const data = JSON.parse(stdout);
    let list;
    if (account.provider === "gitlab") {
        list = data.map(b => ({
            name: b.name,
            sha: b.commit ? b.commit.id : "",
            date: b.commit ? b.commit.committed_date : "",
            title: b.commit ? b.commit.title : ""
        }));
    } else {
        list = data.data.repository.refs.nodes.map(n => ({
            name: n.name,
            sha: n.target ? n.target.oid : "",
            date: n.target ? n.target.committedDate : "",
            title: n.target ? n.target.messageHeadline : ""
        }));
    }
    return list.sort((a, b) => Date.parse(b.date || 0) - Date.parse(a.date || 0));
}

// --- Open merge / pull requests of the repo ----------------------------------------

function openMrsCommand(account, repo) {
    if (account.provider === "gitlab") {
        return glApi(account, project(repo) + "/merge_requests?state=opened&per_page=50");
    }
    return ghScript(account, ghApi("repos/" + repo.path + "/pulls?state=open&per_page=50"));
}

// -> [{number, title, source, target, url, draft, author}]
function parseMrs(account, stdout) {
    const data = JSON.parse(stdout);
    if (account.provider === "gitlab") {
        return data.map(m => ({
            number: m.iid, title: m.title, source: m.source_branch, target: m.target_branch,
            url: m.web_url, draft: !!(m.draft || m.work_in_progress), author: m.author ? m.author.username : ""
        }));
    }
    return data.map(m => ({
        number: m.number, title: m.title, source: m.head.ref, target: m.base.ref,
        url: m.html_url, draft: !!m.draft, author: m.user ? m.user.login : ""
    }));
}

// --- Commits of source that are not in target --------------------------------------

function compareCommand(account, repo, target, source) {
    if (account.provider === "gitlab") {
        // GitLab has no ahead/behind count: compare both ways in one call
        const path = (from, to) => project(repo) + "/repository/compare?straight=false&from="
            + encodeURIComponent(from) + "&to=" + encodeURIComponent(to);
        return "ahead=$(" + glApi(account, path(target, source)) + ") && behind=$("
            + glApi(account, path(source, target)) + ") && printf '{\"ahead\":%s,\"behind\":%s}' \"$ahead\" \"$behind\"";
    }
    return ghScript(account, ghApi("repos/" + repo.path + "/compare/" + branchInPath(target) + "..." + branchInPath(source)));
}

// -> {ahead, behind, commits: [{sha, title, author, date}] newest first}
function parseCompare(account, stdout) {
    const data = JSON.parse(stdout);
    const firstLine = text => (text || "").split("\n")[0];
    let ahead, behind, commits;
    if (account.provider === "gitlab") {
        commits = data.ahead.commits.map(c => ({
            sha: c.id, title: c.title || firstLine(c.message), author: c.author_name, date: c.committed_date
        }));
        ahead = commits.length;
        behind = data.behind.commits.length;
    } else {
        commits = data.commits.map(c => ({
            sha: c.sha, title: firstLine(c.commit.message),
            author: c.author ? c.author.login : c.commit.author.name, date: c.commit.author.date
        }));
        ahead = data.ahead_by;
        behind = data.behind_by;
    }
    commits.sort((a, b) => Date.parse(b.date) - Date.parse(a.date));
    return { ahead: ahead, behind: behind, commits: commits };
}

// --- Create a merge / pull request ----------------------------------------------------

// form: {title, source, target, description, draft, assignToMe, removeSource}
function createMrCommand(account, repo, form) {
    if (account.provider === "gitlab") {
        const title = form.draft && !/^draft:/i.test(form.title) ? "Draft: " + form.title : form.title;
        let args = "-X POST -f source_branch=" + q(form.source) + " -f target_branch=" + q(form.target)
            + " -f title=" + q(title) + " -f description=" + q(form.description)
            + " -F remove_source_branch=" + (form.removeSource ? "true" : "false");
        if (form.assignToMe) {
            args += " -F assignee_id=\"$(" + glApi(account, "user") + " | jq .id)\"";
        }
        return glApi(account, project(repo) + "/merge_requests", args);
    }
    const create = ghApi("repos/" + repo.path + "/pulls", "-f title=" + q(form.title) + " -f head=" + q(form.source)
        + " -f base=" + q(form.target) + " -f body=" + q(form.description) + " -F draft=" + (form.draft ? "true" : "false"));
    // Assigning is a second call; a failure there must not hide the new PR
    // The PR number is only known at run time, so this path is double-quoted
    // (single quotes would keep "$(...)" from expanding)
    const assignPath = "\"repos/" + repo.path.replace(/[\\"$`]/g, "\\$&")
        + "/issues/$(printf %s \"$out\" | jq .number)/assignees\"";
    const assign = form.assignToMe
        ? " && { timeout " + TIMEOUT + " gh api " + assignPath + " -f 'assignees[]='" + q(account.user)
          + " >/dev/null || true; }"
        : "";
    // $out is printed on failure too: it holds GitHub's reason, e.g.
    // "A pull request already exists for adweb-id:test/smoke."
    return ghScript(account, "out=$(" + create + "); rc=$?; [ $rc -eq 0 ]" + assign
                    + "; printf %s \"$out\"; (exit $rc)");
}

// -> {number, url}
function parseCreatedMr(account, stdout) {
    const data = JSON.parse(stdout);
    return account.provider === "gitlab"
        ? { number: data.iid, url: data.web_url }
        : { number: data.number, url: data.html_url };
}

// The web form with both branches filled in: the fallback when the API fails
function newMrUrl(account, repo, source, target) {
    if (account.provider === "gitlab") {
        return repo.url + "/-/merge_requests/new?merge_request%5Bsource_branch%5D=" + encodeURIComponent(source)
            + "&merge_request%5Btarget_branch%5D=" + encodeURIComponent(target);
    }
    return repo.url + "/compare/" + branchInPath(target) + "..." + branchInPath(source) + "?expand=1";
}

function compareUrl(account, repo, target, source) {
    return account.provider === "gitlab"
        ? repo.url + "/-/compare/" + branchInPath(target) + "..." + branchInPath(source)
        : repo.url + "/compare/" + branchInPath(target) + "..." + branchInPath(source);
}

// --- Create a branch on the remote ------------------------------------------------------

function createBranchCommand(account, repo, name, base) {
    if (account.provider === "gitlab") {
        return glApi(account, project(repo) + "/repository/branches",
                     "-X POST -f branch=" + q(name) + " -f ref=" + q(base));
    }
    return ghScript(account, "sha=$(" + ghApi("repos/" + repo.path + "/git/ref/heads/" + branchInPath(base), "--jq .object.sha")
        + ") && " + ghApi("repos/" + repo.path + "/git/refs", "-f ref=" + q("refs/heads/" + name) + " -f sha=\"$sha\""));
}

function branchUrl(account, repo, name) {
    return account.provider === "gitlab"
        ? repo.url + "/-/tree/" + branchInPath(name)
        : repo.url + "/tree/" + branchInPath(name);
}

// --- Errors ---------------------------------------------------------------------------

// The most useful line from a failed call: the API's own message when the
// body is JSON (e.g. "A pull request already exists for acme:fix/x."),
// otherwise the last line of stderr.
function errorText(stdout, stderr, exitCode) {
    if (exitCode === 124) {
        return "TIMEOUT";
    }
    try {
        const data = JSON.parse(stdout);
        const parts = [];
        const add = value => {
            if (typeof value === "string") {
                parts.push(value);
            } else if (Array.isArray(value)) {
                value.forEach(add);
            } else if (value && typeof value === "object") {
                Object.keys(value).forEach(k => add(value[k]));
            }
        };
        add(data.message);
        if (data.errors) {
            data.errors.forEach(e => add(e.message || e));
        }
        if (parts.length > 0) {
            return parts.join(" ");
        }
    } catch (e) {
        // not JSON
    }
    const lines = (stderr || "").trim().split("\n").filter(l => l.trim() !== "");
    return lines.length > 0 ? lines[lines.length - 1] : "";
}
