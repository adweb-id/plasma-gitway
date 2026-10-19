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

// A second GitLab account on the same host has its own glab config folder
// (account.configDir, found by sync-repos.sh accounts)
function glApi(account, path, args) {
    const env = account.configDir ? "GLAB_CONFIG_DIR=" + q(account.configDir) + " " : "";
    return env + "timeout " + TIMEOUT + " glab api --hostname " + q(account.host) + " " + q(path) + (args ? " " + args : "");
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

// --- Latest commits of one branch (repos with only their default branch) ---------

function commitsCommand(account, repo, branch, count) {
    if (account.provider === "gitlab") {
        return glApi(account, project(repo) + "/repository/commits?per_page=" + count
                     + "&ref_name=" + encodeURIComponent(branch));
    }
    return ghScript(account, ghApi("repos/" + repo.path + "/commits?per_page=" + count
                                   + "&sha=" + encodeURIComponent(branch)));
}

// -> [{sha, title, author, date}] newest first
function parseCommits(account, stdout) {
    const data = JSON.parse(stdout);
    const firstLine = text => (text || "").split("\n")[0];
    if (account.provider === "gitlab") {
        return data.map(c => ({ sha: c.id, title: c.title || firstLine(c.message), author: c.author_name, date: c.committed_date }));
    }
    return data.map(c => ({
        sha: c.sha, title: firstLine(c.commit.message),
        author: c.author ? c.author.login : c.commit.author.name, date: c.commit.author.date
    }));
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

// --- Queues across all repos of the account: My MRs, Reviews, Issues -----------
//
// kind: "mine" | "reviews" | "issues"
// Every item: {repoPath, projectId, number, title, url, updatedAt, ...}
// Merge requests add {source, target, draft, status}; issues add {labels}.
// status: ready | running | review | failed | conflict | draft

const GH_SEARCH_PRS = "query($q:String!){search(query:$q,type:ISSUE,first:50){nodes{...on PullRequest{"
    + "number title url isDraft headRefName baseRefName reviewDecision mergeable updatedAt "
    + "repository{nameWithOwner} commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}}";

const GH_SEARCH_ISSUES = "query($q:String!){search(query:$q,type:ISSUE,first:50){nodes{...on Issue{"
    + "number title url updatedAt repository{nameWithOwner} labels(first:5){nodes{name}}}}}}";

function queueCommand(account, kind) {
    if (account.provider === "gitlab") {
        const path = {
            mine: "merge_requests?scope=created_by_me&state=opened&per_page=50",
            reviews: "merge_requests?scope=all&state=opened&per_page=50&reviewer_username=" + encodeURIComponent(account.user),
            issues: "issues?scope=assigned_to_me&state=opened&per_page=50"
        }[kind];
        return glApi(account, path);
    }
    const query = {
        mine: "is:pr is:open archived:false author:" + account.user,
        reviews: "is:pr is:open archived:false review-requested:" + account.user,
        issues: "is:issue is:open archived:false assignee:" + account.user
    }[kind];
    return ghScript(account, ghApi("graphql", "-f query=" + q(kind === "issues" ? GH_SEARCH_ISSUES : GH_SEARCH_PRS)
                                   + " -f q=" + q(query)));
}

// GitHub: draft, failing or running checks, conflicts and missing approval,
// in that order. No review required (reviewDecision null) counts as approved.
function githubStatus(pr) {
    const commit = pr.commits && pr.commits.nodes.length > 0 ? pr.commits.nodes[0].commit : null;
    const checks = commit && commit.statusCheckRollup ? commit.statusCheckRollup.state : "";
    if (pr.isDraft) return "draft";
    if (checks === "FAILURE" || checks === "ERROR") return "failed";
    if (pr.mergeable === "CONFLICTING") return "conflict";
    if (checks === "PENDING" || checks === "EXPECTED") return "running";
    if (pr.reviewDecision === "REVIEW_REQUIRED" || pr.reviewDecision === "CHANGES_REQUESTED") return "review";
    return "ready";
}

// GitLab sums it up in detailed_merge_status
function gitlabStatus(mr) {
    switch (mr.detailed_merge_status) {
    case "mergeable": return "ready";
    case "draft_status": return "draft";
    case "ci_still_running": case "checking": case "unchecked": case "preparing": return "running";
    case "ci_must_pass": return "failed";
    case "conflict": case "need_rebase": case "broken_status": return "conflict";
    default: return mr.draft ? "draft" : "review"; // not_approved, discussions_not_resolved, ...
    }
}

function parseQueue(account, kind, stdout) {
    const data = JSON.parse(stdout);
    if (account.provider === "gitlab") {
        return data.map(x => {
            const item = {
                repoPath: x.references && x.references.full ? x.references.full.replace(/[!#]\d+$/, "") : "",
                projectId: String(x.project_id), number: x.iid, title: x.title, url: x.web_url,
                updatedAt: x.updated_at
            };
            if (kind === "issues") {
                item.labels = x.labels || [];
            } else {
                item.source = x.source_branch;
                item.target = x.target_branch;
                item.draft = !!x.draft;
                item.status = gitlabStatus(x);
            }
            return item;
        });
    }
    return data.data.search.nodes.filter(n => n && n.number).map(n => {
        const item = {
            repoPath: n.repository.nameWithOwner, projectId: "", number: n.number, title: n.title,
            url: n.url, updatedAt: n.updatedAt
        };
        if (kind === "issues") {
            item.labels = n.labels.nodes.map(l => l.name);
        } else {
            item.source = n.headRefName;
            item.target = n.baseRefName;
            item.draft = !!n.isDraft;
            item.status = githubStatus(n);
        }
        return item;
    });
}

// The repo an item belongs to, in the shape the repo calls expect
function itemRepo(item) {
    return { id: item.projectId, path: item.repoPath, url: "" };
}

// --- Merge and approve --------------------------------------------------------------

// Repo defaults for the merge panel: {squash, deleteSource}
function mergeDefaultsCommand(account, item) {
    return account.provider === "gitlab"
        ? glApi(account, "projects/" + item.projectId)
        : ghScript(account, ghApi("repos/" + item.repoPath));
}

function parseMergeDefaults(account, stdout) {
    const data = JSON.parse(stdout);
    if (account.provider === "gitlab") {
        return {
            squash: data.squash_option === "always" || data.squash_option === "default_on",
            squashLocked: data.squash_option === "always" || data.squash_option === "never",
            deleteSource: !!data.remove_source_branch_after_merge
        };
    }
    // Squash only when the repo allows nothing else, or allows it and not merge commits
    return {
        squash: !!data.allow_squash_merge && !data.allow_merge_commit,
        squashLocked: !data.allow_squash_merge || (!data.allow_merge_commit && !data.allow_rebase_merge),
        deleteSource: !!data.delete_branch_on_merge
    };
}

// options: {squash, deleteSource}
function mergeCommand(account, item, options) {
    if (account.provider === "gitlab") {
        return glApi(account, "projects/" + item.projectId + "/merge_requests/" + item.number + "/merge",
                     "-X PUT -F squash=" + options.squash + " -F should_remove_source_branch=" + options.deleteSource);
    }
    const merge = ghApi("repos/" + item.repoPath + "/pulls/" + item.number + "/merge",
                        "-X PUT -f merge_method=" + (options.squash ? "squash" : "merge"));
    // Deleting the branch is a second call; the merge itself already happened
    const remove = options.deleteSource
        ? " && { " + ghApi("repos/" + item.repoPath + "/git/refs/heads/" + branchInPath(item.source), "-X DELETE")
          + " >/dev/null 2>&1 || true; }"
        : "";
    return ghScript(account, "out=$(" + merge + "); rc=$?; [ $rc -eq 0 ]" + remove + "; printf %s \"$out\"; (exit $rc)");
}

function approveCommand(account, item) {
    if (account.provider === "gitlab") {
        return glApi(account, "projects/" + item.projectId + "/merge_requests/" + item.number + "/approve", "-X POST");
    }
    return ghScript(account, ghApi("repos/" + item.repoPath + "/pulls/" + item.number + "/reviews", "-f event=APPROVE"));
}

// --- Open issues of one repo (folded section on the repo page) ----------------------

function repoIssuesCommand(account, repo) {
    if (account.provider === "gitlab") {
        return glApi(account, project(repo) + "/issues?state=opened&per_page=50");
    }
    return ghScript(account, ghApi("repos/" + repo.path + "/issues?state=open&per_page=50"));
}

// -> [{number, title, url, labels, assignees}] (GitHub lists pull requests as issues too)
function parseRepoIssues(account, stdout) {
    const data = JSON.parse(stdout);
    if (account.provider === "gitlab") {
        return data.map(i => ({
            number: i.iid, title: i.title, url: i.web_url, labels: i.labels || [],
            assignees: (i.assignees || []).map(a => a.username)
        }));
    }
    return data.filter(i => !i.pull_request).map(i => ({
        number: i.number, title: i.title, url: i.html_url, labels: (i.labels || []).map(l => l.name),
        assignees: (i.assignees || []).map(a => a.login)
    }));
}
