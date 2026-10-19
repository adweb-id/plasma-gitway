import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.notification

import "../code/repos.js" as Repos
import "../code/forge.js" as Forge

PlasmoidItem {
    id: root

    // loading | noAccounts | ready
    property string phase: "loading"

    // Every account gh and glab are signed in to, and the one the popup shows
    property var accounts: []
    property var account: null
    readonly property string accountKey: Repos.accountKey(account)
    readonly property bool accountBroken: account !== null && account.status !== "ok"

    // Parsed repos.json of the active account; null until it is read or synced
    property var repoData: null
    readonly property int repoCount: repoData ? repoData.repos.length : 0

    // "Add account…": a terminal with gh/glab's own sign-in is open
    property bool addingAccount: false
    // Set when the terminal closed without a new account showing up
    property bool addFoundNothing: false

    property bool syncing: false
    property string syncError: ""

    property string searchText: ""

    // Merge requests and issues across all repos of the account (tabs My MRs,
    // Reviews, Issues). Always read from the API, never from a cache.
    property var mineItems: []
    property var reviewItems: []
    property var issueItems: []
    property var queueLoading: ({ mine: false, reviews: false, issues: false })
    property var queueErrors: ({ mine: "", reviews: "", issues: "" })
    property var queuesLoadedAt: null
    readonly property int queueMaxAge: 60 * 1000 // reopening the popup within a minute keeps them

    // Panel badge: what waits for the user, from the Reviews and My MRs tabs
    readonly property bool showBadge: Plasmoid.configuration.showBadge
    readonly property int readyCount: mineItems.filter(i => i.status === "ready").length
    readonly property int badgeCount: reviewItems.length + readyCount
    readonly property alias repoModel: repoModel

    // One short line for the footer after an action ("Copied: …", "Hidden …"),
    // shown instead of the key hints for a moment
    property string notice: ""

    readonly property string scriptPath: decodeURIComponent(
        Qt.resolvedUrl("../scripts/sync-repos.sh").toString().replace(/^file:\/\//, ""))
    readonly property url iconSource: Qt.resolvedUrl("../icons/gitway.svg")

    readonly property int recentMax: 50
    readonly property int syncMaxAge: 3600 * 1000 // "Sync repos when opening": at most hourly

    Plasmoid.icon: iconSource
    toolTipMainText: i18n("Gitway")
    toolTipSubText: !account ? ""
        : showBadge && queuesLoadedAt ? i18n("%1 · %2 waiting for review · %3 ready to merge",
                                             Repos.accountLabel(account), reviewItems.length, readyCount)
        : i18n("%1 · %2 repos", Repos.accountLabel(account), repoCount)

    // Extra entries in the widget's own right-click menu, next to
    // "Configure Gitway…". Sync runs at once, so it has no ellipsis.
    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18n("Sync repos")
            icon.name: "view-refresh"
            enabled: root.account !== null && !root.syncing
            onTriggered: root.sync()
        },
        PlasmaCore.Action {
            text: i18n("About Gitway")
            icon.name: "help-about"
            onTriggered: root.showAbout()
        }
    ]

    // The popup has to exist before its About page can be pushed
    function showAbout() {
        root.expanded = true;
        Qt.callLater(() => {
            if (root.fullRepresentationItem) {
                root.fullRepresentationItem.showAbout();
            }
        });
    }

    compactRepresentation: CompactRepresentation { widget: root }
    fullRepresentation: FullRepresentation { widget: root }

    ListModel {
        id: repoModel
    }

    // Runs a shell command and hands stdout, stderr and the exit code to a callback.
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        property var callbacks: ({})

        onNewData: (sourceName, data) => {
            const callback = callbacks[sourceName];
            delete callbacks[sourceName];
            disconnectSource(sourceName);
            if (callback) {
                callback(data["stdout"] || "", data["stderr"] || "", data["exit code"]);
            }
        }
    }

    // For calls the pages make: never deduplicated, since two pages may ask the
    // same thing. The trailing shell comment keeps each data source unique.
    property int runCounter: 0

    function run(command, callback) {
        runCounter++;
        exec(command + " # " + runCounter, callback);
    }

    function exec(command, callback) {
        if (executable.callbacks[command]) {
            return false; // same command already running
        }
        executable.callbacks[command] = callback;
        executable.connectSource(command);
        return true;
    }

    // Last line of stderr without the script's "gitway: " prefix
    function errorLine(stderr) {
        const lines = stderr.trim().split("\n");
        return lines[lines.length - 1].replace(/^gitway: /, "");
    }

    // --- Accounts ------------------------------------------------------------

    // onLoaded(list), optional: called with the fresh account list
    function loadAccounts(onLoaded) {
        run(Repos.accountsCommand(scriptPath), (stdout, stderr, exitCode) => {
            const list = Repos.parseAccounts(stdout);
            accounts = list;
            if (onLoaded) {
                onLoaded(list);
            }
            const next = Repos.pickAccount(list, Plasmoid.configuration.activeAccount);
            if (!next) {
                account = null;
                repoData = null;
                rebuild();
                phase = "noAccounts";
                return;
            }
            const changed = Repos.accountKey(next) !== accountKey;
            account = next;
            phase = "ready";
            if (changed || !repoData) {
                loadRepos();
            }
            // The badge needs the queues even before the popup was ever opened
            if ((root.expanded || showBadge) && (changed || !queuesLoadedAt || Date.now() - queuesLoadedAt > queueMaxAge)) {
                loadQueues();
            }
        });
    }

    // --- My MRs, Reviews, Issues ------------------------------------------------

    function queueItems(kind) {
        return kind === "mine" ? mineItems : kind === "reviews" ? reviewItems : issueItems;
    }

    function loadQueues() {
        if (!account || account.status !== "ok") {
            return;
        }
        queuesLoadedAt = new Date();
        for (const kind of ["mine", "reviews", "issues"]) {
            loadQueue(kind);
        }
    }

    function loadQueue(kind) {
        const forKey = accountKey;
        setQueueState(kind, true, "");
        run(Forge.queueCommand(account, kind), (stdout, stderr, exitCode) => {
            if (forKey !== accountKey) {
                return;
            }
            let items = null;
            let error = "";
            try {
                if (exitCode !== 0) {
                    throw Forge.errorText(stdout, stderr, exitCode);
                }
                items = Forge.parseQueue(account, kind, stdout);
            } catch (e) {
                error = e === "TIMEOUT" ? i18n("No response from gh/glab after 30 s")
                      : e instanceof Error ? e.message : (e || i18n("Unknown error"));
            }
            if (items) {
                if (kind === "mine") {
                    mineItems = items;
                } else if (kind === "reviews") {
                    reviewItems = items;
                } else {
                    issueItems = items;
                }
            }
            setQueueState(kind, false, error);
        });
    }

    // Replaces the objects so bindings on them update
    function setQueueState(kind, loading, error) {
        const nextLoading = Object.assign({}, queueLoading);
        nextLoading[kind] = loading;
        queueLoading = nextLoading;
        const nextErrors = Object.assign({}, queueErrors);
        nextErrors[kind] = error;
        queueErrors = nextErrors;
    }

    function dropQueueItem(kind, item) {
        const rest = queueItems(kind).filter(i => !(i.repoPath === item.repoPath && i.number === item.number));
        if (kind === "mine") {
            mineItems = rest;
        } else if (kind === "reviews") {
            reviewItems = rest;
        } else {
            issueItems = rest;
        }
    }

    // Opens a terminal on the sign-in and, once it is closed, picks the new
    // account. A GitLab host that already has one gets its own glab folder.
    function addAccount(provider, host) {
        if (addingAccount) {
            return;
        }
        const before = accounts.map(Repos.accountKey);
        const sameHost = provider === "gitlab" && accounts.some(a => a.provider === "gitlab" && a.host === host);
        addingAccount = true;
        addFoundNothing = false;
        run(Repos.loginCommand(provider, host, sameHost), () => {
            loadAccounts(list => {
                addingAccount = false;
                const added = list.find(a => before.indexOf(Repos.accountKey(a)) === -1 && a.status === "ok");
                if (!added) {
                    addFoundNothing = true;
                    return;
                }
                switchAccount(Repos.accountKey(added));
                showNotice(i18n("Added %1", Repos.accountLabel(added)));
                if (root.fullRepresentationItem) {
                    root.fullRepresentationItem.accountAdded();
                }
            });
        });
    }

    function switchAccount(key) {
        const next = accounts.find(a => Repos.accountKey(a) === key);
        if (!next || key === accountKey) {
            return;
        }
        Plasmoid.configuration.activeAccount = key;
        account = next;
        repoData = null;
        syncError = "";
        searchText = "";
        mineItems = [];
        reviewItems = [];
        issueItems = [];
        rebuild();
        loadRepos();
        loadQueues();
    }

    // --- Repo list -------------------------------------------------------------

    // Reads the cache; an account that was never synced is synced once.
    function loadRepos() {
        if (!account) {
            return;
        }
        const forKey = accountKey;
        exec(Repos.readCommand(scriptPath, account), (stdout, stderr, exitCode) => {
            if (forKey !== accountKey) {
                return; // the user switched account meanwhile
            }
            const data = exitCode === 0 ? Repos.parseRepoFile(stdout) : null;
            repoData = data;
            rebuild();
            if (!data) {
                sync();
            } else if (Plasmoid.configuration.syncOnOpen && root.expanded) {
                syncIfOld();
            }
        });
    }

    function syncIfOld() {
        const syncedAt = repoData ? Date.parse(repoData.synced_at) : 0;
        if (!syncedAt || Date.now() - syncedAt > syncMaxAge) {
            sync();
        }
    }

    // Never blocks the search: the old list stays until the new one is written.
    function sync() {
        if (!account || syncing) {
            return;
        }
        syncing = true;
        syncError = "";
        const forKey = accountKey;
        exec(Repos.syncCommand(scriptPath, account, Plasmoid.configuration.includeOrgs), (stdout, stderr, exitCode) => {
            syncing = false;
            if (forKey !== accountKey) {
                return;
            }
            if (exitCode === 0) {
                loadRepos();
            } else {
                syncError = errorLine(stderr) || i18n("Sync failed");
            }
        });
    }

    function rebuild() {
        const repos = repoData ? repoData.repos : [];
        const recent = Repos.recentFor(Plasmoid.configuration.recent, accountKey);
        const rows = Repos.buildRows(repos, searchText, recent, Plasmoid.configuration.hideArchived,
                                     Repos.recentFor(Plasmoid.configuration.pinned, accountKey),
                                     Repos.recentFor(Plasmoid.configuration.hidden, accountKey),
                                     { by: Plasmoid.configuration.sortBy, descending: Plasmoid.configuration.sortDescending });
        // Replace in place so the list keeps its scroll position while typing
        while (repoModel.count > rows.length) {
            repoModel.remove(repoModel.count - 1);
        }
        for (let i = 0; i < rows.length; i++) {
            if (i < repoModel.count) {
                repoModel.set(i, rows[i]);
            } else {
                repoModel.append(rows[i]);
            }
        }
    }

    onSearchTextChanged: rebuild()

    Connections {
        target: Plasmoid.configuration
        function onHideArchivedChanged() { root.rebuild(); }
        function onRecentChanged() { root.rebuild(); }
        function onPinnedChanged() { root.rebuild(); }
        function onHiddenChanged() { root.rebuild(); }
        function onSortByChanged() { root.rebuild(); }
        function onSortDescendingChanged() { root.rebuild(); }
        function onShowBadgeChanged() {
            if (root.showBadge) {
                root.loadQueues();
            }
        }
        function onIncludeOrgsChanged() { root.sync(); }
    }

    // --- Actions on a repo -----------------------------------------------------

    function remember(path) {
        Plasmoid.configuration.recent = Repos.addRecent(Plasmoid.configuration.recent, accountKey, path, recentMax);
    }

    function openRepo(index) {
        if (index < 0 || index >= repoModel.count) {
            return;
        }
        const row = repoModel.get(index);
        remember(row.path);
        Qt.openUrlExternally(row.url);
        root.expanded = false;
    }

    // The row as a plain object, for pages that outlive a model rebuild
    function rowAt(index) {
        if (index < 0 || index >= repoModel.count) {
            return null;
        }
        const item = repoModel.get(index);
        const row = {};
        for (const key of ["id", "path", "owner", "name", "url", "ssh", "https", "visibility", "archived", "defaultBranch", "pushedAt", "pinned", "hidden"]) {
            row[key] = item[key];
        }
        return row;
    }

    // --- Pin and hide (per account) ---------------------------------------------

    function togglePin(index) {
        const row = rowAt(index);
        if (row) {
            Plasmoid.configuration.pinned = Repos.toggleEntry(Plasmoid.configuration.pinned, accountKey, row.path);
        }
    }

    // pattern: the repo path, or "owner/group/*" for everything under it
    function hide(pattern) {
        if (Repos.recentFor(Plasmoid.configuration.hidden, accountKey).indexOf(pattern) === -1) {
            Plasmoid.configuration.hidden = Repos.toggleEntry(Plasmoid.configuration.hidden, accountKey, pattern);
        }
        showNotice(i18n("Hidden %1 · search with ! to see it", pattern));
    }

    function unhide(pattern) {
        Plasmoid.configuration.hidden = Repos.removeEntry(Plasmoid.configuration.hidden, accountKey, pattern);
    }

    // Removes every pattern that hides this repo, its own path or "owner/*"
    function unhideRepo(path) {
        const patterns = Repos.recentFor(Plasmoid.configuration.hidden, accountKey).filter(p => Repos.isHidden(path, [p]));
        let entries = Plasmoid.configuration.hidden;
        for (const pattern of patterns) {
            entries = Repos.removeEntry(entries, accountKey, pattern);
        }
        Plasmoid.configuration.hidden = entries;
        showNotice(i18n("Showing %1 again", patterns.join(", ")));
    }

    // Open merge requests of the user in one repo, from the My MRs tab
    function mrCount(path) {
        return mineItems.filter(i => i.repoPath === path).length;
    }

    function lastTarget(path) {
        return Repos.lastTarget(Plasmoid.configuration.lastTargets, accountKey, path);
    }

    function setLastTarget(path, branch) {
        Plasmoid.configuration.lastTargets = Repos.setLastTarget(Plasmoid.configuration.lastTargets, accountKey, path, branch, 200);
    }

    // kind: "url" | "ssh" | "https"
    function copyRepo(index, kind) {
        if (index < 0 || index >= repoModel.count) {
            return;
        }
        const row = repoModel.get(index);
        const text = row[kind];
        if (text) {
            remember(row.path);
            copyText(text);
        }
    }

    // QML has no clipboard API; a hidden TextEdit is the usual workaround.
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function copyText(text) {
        clipboardHelper.text = text;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
        showNotice(i18n("Copied: %1", text));
    }

    function showNotice(text) {
        notice = text;
        noticeReset.restart();
    }

    Timer {
        id: noticeReset
        interval: 2500
        onTriggered: root.notice = ""
    }

    // Sends one desktop notification, optionally with a single action button
    function notify(title, text, actionLabel, onAction) {
        const n = notificationComponent.createObject(root, {
            title: title,
            text: text,
            iconName: "vcs-merge"
        });
        if (actionLabel && onAction) {
            const action = actionComponent.createObject(n, { label: actionLabel });
            action.activated.connect(onAction);
            n.actions = [action];
        }
        n.closed.connect(() => n.destroy());
        n.sendEvent();
    }

    Component {
        id: notificationComponent

        Notification {
            componentName: "plasma_workspace"
            eventId: "notification"
            autoDelete: false // QML owns it; destroyed when closed
        }
    }

    Component {
        id: actionComponent

        NotificationAction {}
    }

    // "3h ago", "yesterday", "4d ago" for the right column of a row
    function ago(iso) {
        const time = Date.parse(iso);
        if (!time) {
            return "";
        }
        const minutes = Math.floor((Date.now() - time) / 60000);
        if (minutes < 60) {
            return i18n("%1m ago", Math.max(minutes, 1));
        }
        const hours = Math.floor(minutes / 60);
        if (hours < 24) {
            return i18n("%1h ago", hours);
        }
        const days = Math.floor(hours / 24);
        if (days === 1) {
            return i18n("yesterday");
        }
        if (days < 30) {
            return i18n("%1d ago", days);
        }
        if (days < 365) {
            return i18n("%1mo ago", Math.floor(days / 30));
        }
        return i18n("%1y ago", Math.floor(days / 365));
    }

    // The only timer, and only while the user asked for the badge with an
    // interval (0 = refresh only when the popup opens). Off by default.
    Timer {
        interval: Math.max(Plasmoid.configuration.badgeInterval, 1) * 60 * 1000
        running: root.showBadge && Plasmoid.configuration.badgeInterval > 0 && root.phase === "ready" && !root.expanded
        repeat: true
        onTriggered: root.loadQueues()
    }

    // Otherwise the account list is checked again each time the popup opens.
    Component.onCompleted: loadAccounts()

    onExpandedChanged: {
        if (root.expanded) {
            loadAccounts();
            if (Plasmoid.configuration.syncOnOpen && repoData) {
                syncIfOld();
            }
        } else {
            searchText = ""; // start fresh next time the popup opens
        }
    }
}
