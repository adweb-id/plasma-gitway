import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/forge.js" as Forge

// New branch, created on the remote through the API (PRD scenario 2).
// Nothing local is touched: the notification carries the git command
// that brings it into a clone.
FocusScope {
    id: page

    required property var widget
    required property var full
    required property var repoPage
    required property var repo

    readonly property var account: widget.account
    readonly property bool busy: creating
    readonly property string hints: creating ? i18n("Creating…") : i18n("Enter create · Esc back")
    readonly property string status: repo.path

    readonly property var branchNames: repoPage.branches.map(b => b.name)
    readonly property string name: nameField.text.trim()
    property string base: repoPage.defaultBranch

    property bool creating: false
    property string createError: ""

    readonly property bool exists: branchNames.indexOf(name) !== -1
    // git refuses spaces, "..", "~", "^", ":", "?", "*", "[", "\" and a leading or trailing "/"
    readonly property bool validName: name !== "" && !/[\s~^:?*\[\\]|\.\.|^\/|\/$|\.lock$|^-/.test(name)
    readonly property bool canCreate: !creating && validName && !exists && base !== ""

    Component.onCompleted: nameField.forceActiveFocus()

    function create() {
        if (!canCreate) {
            return;
        }
        creating = true;
        createError = "";
        const branch = name;
        widget.run(Forge.createBranchCommand(account, repo, branch, base), (stdout, stderr, exitCode) => {
            creating = false;
            if (exitCode !== 0) {
                createError = full.describeError(Forge.errorText(stdout, stderr, exitCode));
                return;
            }
            const command = "git fetch && git checkout " + branch;
            widget.notify(i18n("Branch %1 created", branch),
                          i18n("In your clone: %1", command),
                          i18n("Copy command"), () => widget.copyText(command));
            repoPage.reload();
            full.back();
        });
    }

    Keys.onPressed: event => {
        const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
        if (enter) {
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
                text: i18n("New branch")
                font.bold: true
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: page.repo.name
                opacity: 0.6
                elide: Text.ElideRight
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.smallSpacing
            enabled: !page.creating

            PlasmaComponents3.Label {
                text: i18n("Name")
            }
            PlasmaComponents3.TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: i18n("feat/export-csv")
            }
            PlasmaComponents3.Label {
                text: i18n("From")
            }
            PlasmaComponents3.ComboBox {
                Layout.fillWidth: true
                model: page.branchNames
                currentIndex: page.branchNames.indexOf(page.base)
                onActivated: page.base = currentText
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: page.name !== "" && !page.validName
            text: i18n("Not a valid branch name.")
            font: Kirigami.Theme.smallFont
            color: Kirigami.Theme.negativeTextColor
        }

        // Already on the remote: the likely next step is a merge request from it
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.exists
            type: Kirigami.MessageType.Information
            text: i18n("%1 already exists on the remote.", page.name)
            actions: [
                Kirigami.Action {
                    text: i18n("New %1 from it", Forge.short(page.account))
                    onTriggered: {
                        const branch = page.name;
                        const repoPage = page.repoPage;
                        page.full.back();
                        page.full.showMrForm(repoPage, branch);
                    }
                }
            ]
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
                }
            ]
        }

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.fillWidth: true

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
                text: page.creating ? i18n("Creating…") : i18n("Create branch")
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
