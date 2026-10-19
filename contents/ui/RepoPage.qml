import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../code/forge.js" as Forge

// One repo (mockup 4.2): four actions, the commits of the last pushed
// branch, and the repo's open merge requests. Branches and merge requests
// are read from the API each time the page opens, nothing from local clones.
FocusScope {
    id: page

    required property var widget
    required property var full
    required property var repo
    // Opened with Ctrl+Enter / M from the list: go on to the form once loaded
    property bool startMr: false

    readonly property bool busy: false
    readonly property var account: widget.account
    readonly property string mr: Forge.short(account)
    readonly property string hints: i18n("Ctrl+Enter new %1 · B branch · O browser · C copy · Esc back", mr)
    readonly property string status: loadedAt ? i18n("loaded %1", Qt.formatTime(loadedAt, "hh:mm")) : ""

    property var branches: []
    property var mrs: []
    property bool loadingBranches: false
    property bool loadingMrs: false
    property string loadError: ""
    property var loadedAt: null

    readonly property string defaultBranch: repo.defaultBranch || (branches.length > 0 ? branches[0].name : "")
    // Newest branch other than the default one: what a new merge request is usually for
    readonly property var lastPushed: branches.find(b => b.name !== defaultBranch) || null
    readonly property bool writable: !repo.archived && account && account.status === "ok"

    // Open issues of the repo, folded until asked for
    property bool issuesOpen: false
    property var issues: null
    property bool loadingIssues: false
    readonly property int assignedToMe: issues ? issues.filter(i => i.assignees.indexOf(account.user) !== -1).length : 0

    // Commits of the last pushed branch that are not in the default branch
    property bool commitsOpen: false
    property var compare: null
    property bool loadingCompare: false

    Component.onCompleted: reload()

    function reload() {
        loadError = "";
        loadingBranches = true;
        loadingMrs = true;
        compare = null;
        if (issuesOpen) {
            loadIssues();
        }
        widget.run(Forge.branchesCommand(account, repo), (stdout, stderr, exitCode) => {
            loadingBranches = false;
            try {
                if (exitCode !== 0) {
                    throw Forge.errorText(stdout, stderr, exitCode);
                }
                branches = Forge.parseBranches(account, stdout);
                loadedAt = new Date();
                if (commitsOpen) {
                    loadCompare();
                }
                if (startMr) {
                    startMr = false;
                    newMr();
                }
            } catch (e) {
                loadError = full.describeError(e);
            }
        });
        widget.run(Forge.openMrsCommand(account, repo), (stdout, stderr, exitCode) => {
            loadingMrs = false;
            try {
                if (exitCode !== 0) {
                    throw Forge.errorText(stdout, stderr, exitCode);
                }
                mrs = Forge.parseMrs(account, stdout);
            } catch (e) {
                loadError = full.describeError(e);
            }
        });
    }

    function loadIssues() {
        if (loadingIssues) {
            return;
        }
        loadingIssues = true;
        widget.run(Forge.repoIssuesCommand(account, repo), (stdout, stderr, exitCode) => {
            loadingIssues = false;
            try {
                issues = exitCode === 0 ? Forge.parseRepoIssues(account, stdout) : [];
            } catch (e) {
                issues = [];
            }
        });
    }

    function loadCompare() {
        if (!lastPushed || loadingCompare) {
            return;
        }
        loadingCompare = true;
        widget.run(Forge.compareCommand(account, repo, defaultBranch, lastPushed.name), (stdout, stderr, exitCode) => {
            loadingCompare = false;
            try {
                compare = exitCode === 0 ? Forge.parseCompare(account, stdout) : null;
            } catch (e) {
                compare = null;
            }
        });
    }

    function newMr() {
        if (writable && branches.length > 1) {
            full.showMrForm(page, lastPushed ? lastPushed.name : "");
        }
    }

    function newBranch() {
        if (writable && branches.length > 0) {
            full.showBranchForm(page);
        }
    }

    function copy(kind) {
        const text = repo[kind];
        if (text) {
            widget.copyText(text);
        }
    }

    // Keyboard (PRD 4.13): Ctrl+Enter or M new MR, B branch, O browser,
    // C copy link (Shift+C SSH, Alt+C HTTPS), R or F5 reload, Esc or Backspace back.
    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if ((ctrl && enter) || (!ctrl && event.key === Qt.Key_M)) {
            newMr();
        } else if (!ctrl && event.key === Qt.Key_B) {
            newBranch();
        } else if (event.key === Qt.Key_O) {
            Qt.openUrlExternally(repo.url);
        } else if (event.key === Qt.Key_C) {
            copy(event.modifiers & Qt.ShiftModifier ? "ssh" : event.modifiers & Qt.AltModifier ? "https" : "url");
        } else if (event.key === Qt.Key_R || event.key === Qt.Key_F5) {
            reload();
        } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
            full.back();
        } else if (enter && actions.currentItem) {
            actions.currentItem.clicked();
        } else {
            return;
        }
        event.accepted = true;
    }

    // One action: icon, title, one line of detail, and its key on the right
    component ActionRow: PlasmaComponents3.ItemDelegate {
        id: action

        required property string iconName
        required property string title
        required property string detail
        required property string shortcut

        width: ListView.view ? ListView.view.width : implicitWidth
        highlighted: ListView.isCurrentItem && page.activeFocus

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            SvgIcon {
                name: action.iconName
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                opacity: action.enabled ? 1 : 0.4
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: action.title
                    font.bold: true
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: action.detail
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }
            PlasmaComponents3.Label {
                text: action.shortcut
                font.family: "monospace"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                opacity: 0.6
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            IconButton {
                iconName: "back"
                toolTip: i18n("Back to repos (Esc)")
                onClicked: page.full.back()
            }
            ProviderLogo {
                provider: page.account ? page.account.provider : ""
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: page.repo.path
                font.bold: true
                elide: Text.ElideMiddle
            }
            SvgIcon {
                visible: page.repo.visibility !== "public"
                name: "lock"
                opacity: 0.7
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.repo.archived
            type: Kirigami.MessageType.Information
            text: i18n("Archived: read-only")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.loadError !== ""
            type: Kirigami.MessageType.Error
            text: i18n("Couldn't load: %1", page.loadError)
            actions: [
                Kirigami.Action {
                    text: i18n("Try again")
                    onTriggered: page.reload()
                }
            ]
        }

        ListView {
            id: actions
            Layout.fillWidth: true
            Layout.preferredHeight: contentHeight
            interactive: false
            keyNavigationEnabled: true
            focus: true
            model: 4
            delegate: ActionRow {
                required property int index

                iconName: ["merge", "branch", "external", "copy"][index]
                title: [i18n("New %1", page.account && page.account.provider === "gitlab" ? i18n("merge request") : i18n("pull request")),
                        i18n("New branch"), i18n("Open in browser"), i18n("Copy link")][index]
                detail: [
                    !page.writable ? i18n("Not available for this repo")
                        : page.loadingBranches ? i18n("Loading branches…")
                        : page.lastPushed ? i18n("%1 → %2", page.lastPushed.name, page.defaultBranch)
                        : i18n("No other branches yet"),
                    page.defaultBranch ? i18n("Create on the remote from %1", page.defaultBranch) : i18n("Loading branches…"),
                    page.account && page.account.provider === "gitlab" ? i18n("Repository page on GitLab") : i18n("Repository page on GitHub"),
                    i18n("Web URL · Shift+C SSH · Alt+C HTTPS")
                ][index]
                shortcut: ["Ctrl+Enter", "B", "O", "C"][index]
                enabled: index === 0 ? page.writable && page.branches.length > 1
                         : index === 1 ? page.writable && page.branches.length > 0 : true
                onClicked: {
                    actions.currentIndex = index;
                    [page.newMr, page.newBranch, () => Qt.openUrlExternally(page.repo.url), () => page.copy("url")][index]();
                }
            }
        }

        // Commits of the last pushed branch, folded until asked for (mockup 4.11)
        PlasmaComponents3.ItemDelegate {
            Layout.fillWidth: true
            visible: page.lastPushed !== null
            onClicked: {
                page.commitsOpen = !page.commitsOpen;
                if (page.commitsOpen && !page.compare) {
                    page.loadCompare();
                }
            }
            contentItem: RowLayout {
                SvgIcon {
                    name: page.commitsOpen ? "chevron-down" : "chevron-right"
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: !page.lastPushed ? ""
                          : page.compare ? i18n("Recent commits on %1 · %2 since %3", page.lastPushed.name, page.compare.ahead, page.defaultBranch)
                          : i18n("Recent commits on %1", page.lastPushed.name)
                    elide: Text.ElideRight
                }
            }
        }

        Repeater {
            model: page.commitsOpen && page.compare ? page.compare.commits.slice(0, 5) : []

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit * 1.5
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: modelData.sha.slice(0, 7)
                    font.family: "monospace"
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: 0.6
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: modelData.title
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    text: page.widget.ago(modelData.date)
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                }
            }
        }

        PlasmaComponents3.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            visible: page.commitsOpen && page.loadingCompare
            running: visible
        }

        // Open issues of the repo (PRD 4.2), folded like the commits
        PlasmaComponents3.ItemDelegate {
            Layout.fillWidth: true
            onClicked: {
                page.issuesOpen = !page.issuesOpen;
                if (page.issuesOpen && !page.issues) {
                    page.loadIssues();
                }
            }
            contentItem: RowLayout {
                SvgIcon {
                    name: page.issuesOpen ? "chevron-down" : "chevron-right"
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: !page.issues ? i18n("Open issues")
                          : i18n("Open issues · %1 · %2 assigned to me", page.issues.length, page.assignedToMe)
                    elide: Text.ElideRight
                }
            }
        }

        Repeater {
            model: page.issuesOpen && page.issues ? page.issues.slice(0, 5) : []

            PlasmaComponents3.ItemDelegate {
                id: issueRow
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: Kirigami.Units.gridUnit * 1.5
                onClicked: Qt.openUrlExternally(modelData.url)
                contentItem: RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    PlasmaComponents3.Label {
                        text: "#" + issueRow.modelData.number
                        font.family: "monospace"
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        opacity: 0.6
                    }
                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: issueRow.modelData.title
                        elide: Text.ElideRight
                    }
                    PlasmaComponents3.Label {
                        visible: issueRow.modelData.assignees.indexOf(page.account.user) !== -1
                        text: i18n("you")
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }
                }
            }
        }

        PlasmaComponents3.ToolButton {
            visible: page.issuesOpen && page.issues !== null && page.issues.length > 5
            text: page.issues ? i18n("and %1 more…", page.issues.length - 5) : ""
            onClicked: Qt.openUrlExternally(page.repo.url + (page.account.provider === "gitlab" ? "/-/issues" : "/issues"))
        }

        PlasmaComponents3.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            visible: page.issuesOpen && page.loadingIssues
            running: visible
        }

        PlasmaExtras.ListSectionHeader {
            Layout.fillWidth: true
            text: page.loadingMrs ? i18n("Open %1s in this repo", page.mr)
                                  : i18n("Open %1s in this repo · %2", page.mr, page.mrs.length)
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            contentItem: ListView {
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: page.mrs

                delegate: MrDelegate {
                    widget: page.widget
                    account: page.account
                }
            }
        }

        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: !page.loadingMrs && page.mrs.length === 0 && page.loadError === ""
            text: i18n("No open %1s.", page.mr)
            opacity: 0.6
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            text: page.defaultBranch === "" ? ""
                  : page.lastPushed ? i18n("default: %1 · last pushed: %2 · %3", page.defaultBranch, page.lastPushed.name, page.widget.ago(page.lastPushed.date))
                  : i18n("default: %1", page.defaultBranch)
            font: Kirigami.Theme.smallFont
            opacity: 0.6
            elide: Text.ElideRight
        }
    }
}
