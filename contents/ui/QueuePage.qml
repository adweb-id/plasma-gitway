import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../code/forge.js" as Forge

// The My MRs, Reviews and Issues tabs (mockups 4.4, 4.10, 4.12): one list
// across every repo of the account, reloaded each time the popup opens or
// with R. Merge and approve are confirmed in a panel under the row.
FocusScope {
    id: queuePage

    required property var widget
    required property var full
    // "mine" | "reviews" | "issues"
    required property string kind

    readonly property var account: widget.account
    readonly property var items: widget.queueItems(kind)
    readonly property bool loading: widget.queueLoading[kind]
    readonly property string error: widget.queueErrors[kind]

    // Row whose confirmation panel is open, -1 when none
    property int confirmIndex: -1
    property bool acting: false
    property string actionError: ""
    // Repo merge defaults, loaded when the merge panel opens
    property var mergeOptions: ({ loaded: false, squash: false, squashLocked: false, deleteSource: false })

    readonly property bool busy: acting
    readonly property string hints: confirmIndex >= 0 ? i18n("Enter confirm · Esc cancel")
        : kind === "issues" ? i18n("Enter open in browser · C copy link · R refresh")
        : kind === "reviews" ? i18n("Enter open · A approve · C copy link · R refresh")
        : i18n("Enter open · M merge · C copy link · R refresh")
    readonly property string status: loading ? i18n("loading…")
        : widget.queuesLoadedAt ? i18n("loaded %1", Qt.formatTime(widget.queuesLoadedAt, "hh:mm")) : ""

    // My MRs: ready to merge first, then the rest; other tabs: newest first
    readonly property var rows: {
        const list = items.slice().sort((a, b) => (b.updatedAt || "").localeCompare(a.updatedAt || ""));
        if (kind !== "mine") {
            return list;
        }
        return list.filter(i => i.status === "ready").concat(list.filter(i => i.status !== "ready"));
    }

    onRowsChanged: {
        model.clear();
        // Only the index goes into the model: a ListModel would turn arrays
        // inside an item (labels) into nested models
        rows.forEach((item, i) => model.append({ idx: i, section: sectionOf(item) }));
        if (confirmIndex >= model.count) {
            cancel();
        }
    }

    function sectionOf(item) {
        if (kind === "mine") {
            return item.status === "ready" ? i18n("Ready to merge") : i18n("Waiting");
        }
        return kind === "reviews" ? i18n("Waiting for your review") : i18n("Assigned to me");
    }

    ListModel {
        id: model
    }

    function confirm(index) {
        const item = rows[index];
        const canMerge = kind === "mine" && item.status === "ready";
        if (!item || acting || (!canMerge && kind !== "reviews")) {
            return;
        }
        confirmIndex = index;
        list.currentIndex = index;
        actionError = "";
        if (canMerge) {
            mergeOptions = { loaded: false, squash: false, squashLocked: false, deleteSource: Plasmoid.configuration.deleteSourceBranch };
            widget.run(Forge.mergeDefaultsCommand(account, item), (stdout, stderr, exitCode) => {
                if (confirmIndex !== index) {
                    return;
                }
                let defaults = { squash: false, squashLocked: false, deleteSource: mergeOptions.deleteSource };
                try {
                    if (exitCode === 0) {
                        defaults = Forge.parseMergeDefaults(account, stdout);
                    }
                } catch (e) {
                    // keep the plain defaults
                }
                mergeOptions = Object.assign(defaults, { loaded: true });
            });
        }
    }

    function setOption(name, value) {
        const next = Object.assign({}, mergeOptions);
        next[name] = value;
        mergeOptions = next;
    }

    function cancel() {
        if (!acting) {
            confirmIndex = -1;
            actionError = "";
            list.forceActiveFocus();
        }
    }

    function runAction() {
        const item = rows[confirmIndex];
        if (!item || acting) {
            return;
        }
        const merging = kind === "mine";
        if (merging && !mergeOptions.loaded) {
            return;
        }
        acting = true;
        actionError = "";
        const command = merging ? Forge.mergeCommand(account, item, mergeOptions) : Forge.approveCommand(account, item);
        const label = Forge.sigil(account) + item.number;
        widget.run(command, (stdout, stderr, exitCode) => {
            acting = false;
            if (exitCode !== 0) {
                actionError = full.describeError(Forge.errorText(stdout, stderr, exitCode)) || i18n("Failed");
                return;
            }
            confirmIndex = -1;
            widget.notify(merging ? i18n("%1 merged into %2", label, item.target) : i18n("%1 approved", label),
                          item.title, i18n("Open"), () => Qt.openUrlExternally(item.url));
            widget.dropQueueItem(kind, item);
            widget.loadQueues();
            list.forceActiveFocus();
        });
    }

    // Keyboard (PRD 4.13): Enter opens in the browser (confirms in the panel),
    // M merge, A approve, C copy link, R or F5 reload, Esc closes the panel.
    Keys.onPressed: event => {
        const item = list.currentIndex >= 0 ? rows[list.currentIndex] : null;
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
        if (confirmIndex >= 0 && enter) {
            runAction();
        } else if (confirmIndex >= 0 && event.key === Qt.Key_Escape) {
            cancel();
        } else if (confirmIndex >= 0) {
            return;
        } else if (enter && item) {
            Qt.openUrlExternally(item.url);
        } else if (plain && event.key === Qt.Key_M && kind === "mine") {
            confirm(list.currentIndex);
        } else if (plain && event.key === Qt.Key_A && kind === "reviews") {
            confirm(list.currentIndex);
        } else if (plain && event.key === Qt.Key_C && item) {
            widget.copyText(item.url);
        } else if ((plain && event.key === Qt.Key_R) || event.key === Qt.Key_F5) {
            widget.loadQueues();
        } else {
            return;
        }
        event.accepted = true;
    }

    PlasmaComponents3.ScrollView {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing
        anchors.rightMargin: Kirigami.Units.smallSpacing
        anchors.topMargin: Kirigami.Units.smallSpacing
        visible: model.count > 0

        contentItem: ListView {
            id: list
            focus: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: queuePage.confirmIndex < 0
            highlightMoveDuration: Kirigami.Units.shortDuration
            model: model

            section.property: "section"
            section.delegate: PlasmaExtras.ListSectionHeader {
                required property string section
                width: ListView.view.width
                topPadding: Kirigami.Units.largeSpacing
                text: section
            }

            delegate: QueueDelegate {
                required property int idx
                page: queuePage
                item: queuePage.rows[idx]
            }
        }
    }

    PlasmaComponents3.BusyIndicator {
        anchors.centerIn: parent
        visible: queuePage.loading && model.count === 0
        running: visible
    }

    EmptyState {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: !queuePage.loading && model.count === 0
        iconName: queuePage.error !== "" ? "error" : queuePage.kind === "issues" ? "issue" : "merge"
        title: queuePage.error !== "" ? i18n("Couldn't load")
             : queuePage.kind === "mine" ? i18n("No open merge requests. Nice.")
             : queuePage.kind === "reviews" ? i18n("Nothing waiting for your review")
             : i18n("No issues assigned to you")
        explanation: queuePage.error
        actionText: queuePage.error !== "" ? i18n("Try again") : ""
        onActionTriggered: queuePage.widget.loadQueues()
    }
}
