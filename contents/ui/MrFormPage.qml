import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../code/forge.js" as Forge

// New merge / pull request (mockups 4.3, 4.9, 4.11). Everything comes from
// the API, so it works for repos never cloned on this machine:
//   source = branch pushed last, target = last target used here or the default
//   branch, title = newest commit of source (click another commit to use it).
FocusScope {
    id: page

    required property var widget
    required property var full
    required property var repoPage
    required property var repo
    property string initialSource: ""

    readonly property var account: widget.account
    readonly property bool gitlab: account && account.provider === "gitlab"
    readonly property string mr: Forge.short(account)
    readonly property bool busy: creating
    readonly property string hints: creating ? i18n("Creating…") : i18n("Enter create · Esc back")
    readonly property string status: repo.path

    readonly property var branchNames: repoPage.branches.map(b => b.name)

    property string source: ""
    property string target: ""
    property bool titleEdited: false

    // compare: {ahead, behind, commits}; compareState: loading | ok | error
    property var compare: null
    property string compareState: "loading"

    property bool creating: false
    property string createError: ""

    readonly property var existing: repoPage.mrs.find(m => m.source === source) || null
    readonly property bool sameBranch: source !== "" && source === target
    readonly property bool nothingToMerge: compareState === "ok" && compare.ahead === 0
    readonly property bool canCreate: !creating && titleField.text.trim() !== "" && source !== "" && target !== ""
        && !sameBranch && !existing && compareState !== "loading" && !nothingToMerge

    // Commits shown before "Show more", and at most after it (PRD 4.11)
    readonly property int shortCommits: 5
    readonly property int maxCommits: 20
    property bool allCommits: false

    Component.onCompleted: {
        const remembered = widget.lastTarget(repo.path);
        target = branchNames.indexOf(remembered) !== -1 ? remembered : repoPage.defaultBranch;
        source = initialSource || (repoPage.lastPushed ? repoPage.lastPushed.name : "");
        titleField.forceActiveFocus();
    }

    onSourceChanged: branchesChanged()
    onTargetChanged: branchesChanged()

    function branchesChanged() {
        if (!titleEdited) {
            const branch = repoPage.branches.find(b => b.name === source);
            titleField.text = branch ? branch.title : "";
        }
        loadCompare();
    }

    function loadCompare() {
        compare = null;
        if (source === "" || target === "" || sameBranch) {
            compareState = "error";
            return;
        }
        compareState = "loading";
        const forPair = source + "\n" + target;
        widget.run(Forge.compareCommand(account, repo, target, source), (stdout, stderr, exitCode) => {
            if (forPair !== source + "\n" + target) {
                return; // a dropdown changed meanwhile
            }
            try {
                if (exitCode !== 0) {
                    throw Forge.errorText(stdout, stderr, exitCode);
                }
                compare = Forge.parseCompare(account, stdout);
                compareState = "ok";
                if (!titleEdited && compare.commits.length > 0) {
                    titleField.text = compare.commits[0].title;
                }
            } catch (e) {
                compareState = "error";
            }
        });
    }

    function create() {
        if (!canCreate) {
            return;
        }
        creating = true;
        createError = "";
        const form = {
            title: titleField.text.trim(),
            source: source,
            target: target,
            description: descriptionField.text,
            draft: draftCheck.checked,
            assignToMe: assignCheck.checked,
            removeSource: removeSourceCheck.checked
        };
        widget.run(Forge.createMrCommand(account, repo, form), (stdout, stderr, exitCode) => {
            creating = false;
            let created;
            try {
                if (exitCode !== 0) {
                    throw Forge.errorText(stdout, stderr, exitCode);
                }
                created = Forge.parseCreatedMr(account, stdout);
            } catch (e) {
                createError = full.describeError(e);
                return;
            }
            widget.setLastTarget(repo.path, form.target);
            // Numbers go in as text: i18n would group them by locale ("!1.383")
            widget.notify(i18n("%1 %2 created", mr, Forge.sigil(account) + created.number),
                          form.title + "\n" + created.url,
                          i18n("Open"), () => Qt.openUrlExternally(created.url));
            if (openCheck.checked) {
                Qt.openUrlExternally(created.url);
            }
            repoPage.reload();
            full.back();
        });
    }

    // Enter in a one-line field or Ctrl+Enter anywhere creates; Escape goes
    // back, but never while the call runs (the popup stays open too).
    Keys.onPressed: event => {
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if (enter && (event.modifiers & Qt.ControlModifier)) {
            create();
        } else if (event.key === Qt.Key_Escape) {
            full.back();
        } else {
            return;
        }
        event.accepted = true;
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
                toolTip: i18n("Back (Esc)")
                enabled: !page.creating
                onClicked: page.full.back()
            }
            PlasmaComponents3.Label {
                text: page.gitlab ? i18n("New merge request") : i18n("New pull request")
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: page.repo.name
                opacity: 0.6
                elide: Text.ElideRight
            }
        }

        PlasmaComponents3.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Kirigami.Units.smallSpacing
                enabled: !page.creating

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: i18n("Source")
                    }
                    PlasmaComponents3.ComboBox {
                        Layout.fillWidth: true
                        model: page.branchNames
                        currentIndex: page.branchNames.indexOf(page.source)
                        onActivated: page.source = currentText
                    }
                    PlasmaComponents3.Label {
                        text: i18n("Target")
                    }
                    PlasmaComponents3.ComboBox {
                        Layout.fillWidth: true
                        model: page.branchNames
                        currentIndex: page.branchNames.indexOf(page.target)
                        onActivated: page.target = currentText
                    }
                }

                // The source branch already has one: offer it instead of a duplicate
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: page.existing !== null
                    type: Kirigami.MessageType.Information
                    text: page.existing ? i18n("This branch already has %1", Forge.sigil(page.account) + page.existing.number) : ""
                    actions: [
                        Kirigami.Action {
                            text: i18n("Open")
                            onTriggered: Qt.openUrlExternally(page.existing.url)
                        }
                    ]
                }

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    visible: page.existing === null
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    text: page.sameBranch ? i18n("Choose two different branches.")
                          : page.compareState === "loading" ? i18n("Comparing %1 with %2…", page.source, page.target)
                          : page.compareState === "error" ? i18n("Couldn't compare the branches.")
                          : page.nothingToMerge ? i18n("Nothing to merge: %1 is up to date with %2", page.source, page.target)
                          : i18np("%1 commit ahead · %2 behind · click a commit to use it as the title",
                                  "%1 commits ahead · %2 behind · click a commit to use it as the title",
                                  page.compare.ahead, page.compare.behind)
                }

                Repeater {
                    model: page.existing === null && page.compare
                           ? page.compare.commits.slice(0, page.allCommits ? page.maxCommits : page.shortCommits) : []

                    PlasmaComponents3.ItemDelegate {
                        id: commitRow
                        required property var modelData

                        Layout.fillWidth: true
                        highlighted: titleField.text === modelData.title
                        onClicked: {
                            titleField.text = modelData.title;
                            page.titleEdited = true;
                        }
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            PlasmaComponents3.Label {
                                text: commitRow.modelData.sha.slice(0, 7)
                                font.family: "monospace"
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                opacity: 0.6
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: commitRow.modelData.title
                                elide: Text.ElideRight
                            }
                            PlasmaComponents3.Label {
                                text: commitRow.modelData.author + " · " + page.widget.ago(commitRow.modelData.date)
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                            }
                        }
                    }
                }

                PlasmaComponents3.ToolButton {
                    visible: page.existing === null && page.compare !== null && !page.allCommits
                             && page.compare.commits.length > page.shortCommits
                    text: page.compare ? i18n("Show %1 more", Math.min(page.compare.commits.length, page.maxCommits) - page.shortCommits) : ""
                    onClicked: page.allCommits = true
                }

                PlasmaComponents3.ToolButton {
                    visible: page.existing === null && page.compare !== null && page.allCommits && page.compare.ahead > page.maxCommits
                    text: page.compare ? i18n("and %1 more…", page.compare.ahead - page.maxCommits) : ""
                    onClicked: Qt.openUrlExternally(Forge.compareUrl(page.account, page.repo, page.target, page.source))
                }

                PlasmaComponents3.Label {
                    visible: page.existing === null
                    text: i18n("Title")
                }
                PlasmaComponents3.TextField {
                    id: titleField
                    Layout.fillWidth: true
                    visible: page.existing === null
                    onTextEdited: page.titleEdited = true
                    Keys.onReturnPressed: page.create()
                    Keys.onEnterPressed: page.create()
                }

                PlasmaComponents3.Label {
                    visible: page.existing === null
                    text: i18n("Description (optional)")
                }
                PlasmaComponents3.TextArea {
                    id: descriptionField
                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 4
                    visible: page.existing === null
                    placeholderText: i18n("Summary of changes…")
                    wrapMode: TextEdit.Wrap
                }

                PlasmaComponents3.CheckBox {
                    id: assignCheck
                    visible: page.existing === null
                    text: i18n("Assign to me")
                    checked: Plasmoid.configuration.assignToMe
                }
                // GitHub has no per-PR setting for this, only a repo-wide one
                PlasmaComponents3.CheckBox {
                    id: removeSourceCheck
                    visible: page.existing === null && page.gitlab
                    text: i18n("Delete source branch after merge")
                    checked: Plasmoid.configuration.deleteSourceBranch
                }
                PlasmaComponents3.CheckBox {
                    id: draftCheck
                    visible: page.existing === null
                    text: i18n("Draft")
                }
                PlasmaComponents3.CheckBox {
                    id: openCheck
                    visible: page.existing === null
                    text: i18n("Open in browser when created")
                    checked: Plasmoid.configuration.openAfterCreate
                }
            }
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.createError !== ""
            type: Kirigami.MessageType.Error
            text: page.createError
            actions: [
                Kirigami.Action {
                    text: i18n("Try again")
                    onTriggered: page.create()
                },
                Kirigami.Action {
                    text: i18n("Open in browser")
                    onTriggered: Qt.openUrlExternally(Forge.newMrUrl(page.account, page.repo, page.source, page.target))
                }
            ]
        }

        RowLayout {
            Layout.fillWidth: true
            visible: page.existing === null

            Item {
                Layout.fillWidth: true
            }
            PlasmaComponents3.Button {
                text: i18n("Cancel")
                enabled: !page.creating
                onClicked: page.full.back()
            }
            PlasmaComponents3.Button {
                enabled: page.canCreate
                text: page.creating ? i18n("Creating…") : i18n("Create %1", page.mr)
                icon.name: "" // the spinner below stands in while creating
                onClicked: page.create()

                PlasmaComponents3.BusyIndicator {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height * 0.8
                    width: height
                    visible: page.creating
                    running: visible
                }
            }
        }
    }
}
