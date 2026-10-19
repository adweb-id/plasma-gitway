import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.notification

import "../code/repos.js" as Repos

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

    property bool syncing: false
    property string syncError: ""

    property string searchText: ""
    readonly property alias repoModel: repoModel

    // Text copied most recently; the footer shows a short "Copied" confirmation
    property string lastCopied: ""

    readonly property string scriptPath: decodeURIComponent(
        Qt.resolvedUrl("../scripts/sync-repos.sh").toString().replace(/^file:\/\//, ""))
    readonly property url iconSource: Qt.resolvedUrl("../icons/gitway.svg")

    readonly property int recentMax: 50
    readonly property int syncMaxAge: 3600 * 1000 // "Sync repos when opening": at most hourly

    Plasmoid.icon: iconSource
    toolTipMainText: i18n("Gitway")
    toolTipSubText: account ? i18n("%1 · %2 repos", Repos.accountLabel(account), repoCount) : ""

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

    function loadAccounts() {
        exec(Repos.accountsCommand(scriptPath), (stdout, stderr, exitCode) => {
            const list = Repos.parseAccounts(stdout);
            accounts = list;
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
        rebuild();
        loadRepos();
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
        const rows = Repos.buildRows(repos, searchText, recent, Plasmoid.configuration.hideArchived);
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
        for (const key of ["id", "path", "owner", "name", "url", "ssh", "https", "visibility", "archived", "defaultBranch", "pushedAt"]) {
            row[key] = item[key];
        }
        return row;
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
        lastCopied = text;
        copiedReset.restart();
    }

    Timer {
        id: copiedReset
        interval: 1500
        onTriggered: root.lastCopied = ""
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

    // No timer: the account list is checked again each time the popup opens.
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
