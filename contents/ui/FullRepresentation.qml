import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../code/repos.js" as Repos

PlasmaExtras.Representation {
    id: full

    required property var widget

    readonly property bool hasList: widget.phase === "ready" && widget.repoData !== null

    Layout.minimumWidth: Kirigami.Units.gridUnit * 18
    Layout.minimumHeight: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 23
    Layout.preferredHeight: Kirigami.Units.gridUnit * 28

    collapseMarginsHint: true

    header: PlasmaExtras.PlasmoidHeading {
        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    level: 4
                    text: i18n("Gitway")
                }

                Item {
                    Layout.fillWidth: true
                }

                // One list of every account, "user - host"; the popup shows only the chosen one
                ProviderLogo {
                    visible: full.widget.account !== null
                    provider: full.widget.account ? full.widget.account.provider : ""
                }

                PlasmaComponents3.ComboBox {
                    id: accountBox
                    objectName: "accountBox"
                    visible: full.widget.accounts.length > 0
                    Layout.maximumWidth: Kirigami.Units.gridUnit * 12
                    model: full.widget.accounts.map(a => ({
                        key: Repos.accountKey(a),
                        label: Repos.accountLabel(a),
                        provider: a.provider,
                        ok: a.status === "ok"
                    }))
                    textRole: "label"
                    valueRole: "key"
                    currentIndex: model.findIndex(a => a.key === full.widget.accountKey)
                    onActivated: full.widget.switchAccount(currentValue)
                    Accessible.name: i18n("Account")

                    delegate: PlasmaComponents3.ItemDelegate {
                        id: accountItem
                        required property var modelData
                        required property int index

                        width: accountBox.popup.width
                        highlighted: accountBox.highlightedIndex === accountItem.index
                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            ProviderLogo {
                                provider: accountItem.modelData.provider
                            }
                            PlasmaComponents3.Label {
                                Layout.fillWidth: true
                                text: accountItem.modelData.label
                                elide: Text.ElideRight
                            }
                            PlasmaComponents3.Label {
                                visible: !accountItem.modelData.ok
                                text: i18n("signed out")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                            }
                            Kirigami.Icon {
                                visible: accountItem.modelData.key === full.widget.accountKey
                                source: "checkmark"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: implicitWidth
                            }
                        }
                    }
                }

                PlasmaComponents3.ToolButton {
                    visible: full.widget.account !== null && !full.widget.syncing
                    icon.name: "view-refresh"
                    onClicked: full.widget.sync()
                    Accessible.name: i18n("Sync repos")
                    QQC2.ToolTip.text: i18n("Sync repos")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }

                PlasmaComponents3.BusyIndicator {
                    visible: full.widget.syncing
                    running: visible
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "configure"
                    onClicked: Plasmoid.internalAction("configure").trigger()
                    Accessible.name: i18n("Settings")
                    QQC2.ToolTip.text: i18n("Settings")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                }
            }

            PlasmaExtras.SearchField {
                id: searchField
                objectName: "searchField"
                Layout.fillWidth: true
                visible: full.hasList
                placeholderText: i18n("Search repos…  (org:  private:  public:  !archived)")
                text: full.widget.searchText
                onTextChanged: {
                    full.widget.searchText = text;
                    list.currentIndex = 0;
                }
                Keys.onEscapePressed: event => {
                    if (text !== "") {
                        full.widget.searchText = "";
                        event.accepted = true;
                    } else {
                        event.accepted = false; // let Escape close the popup
                    }
                }
                Keys.onDownPressed: full.focusList(list.currentIndex + 1)
                Keys.onUpPressed: list.currentIndex = Math.max(list.currentIndex - 1, 0)
                Keys.onReturnPressed: full.widget.openRepo(Math.max(list.currentIndex, 0))
                Keys.onEnterPressed: full.widget.openRepo(Math.max(list.currentIndex, 0))
                // The same actions as the single keys in the list, with Ctrl
                Keys.onPressed: event => full.handleCtrlKey(event)
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: full.widget.accountBroken
                type: Kirigami.MessageType.Warning
                text: full.widget.account
                      ? i18n("%1 is signed out. Showing the last synced list.", Repos.accountLabel(full.widget.account))
                      : ""
                actions: [
                    Kirigami.Action {
                        text: i18n("Copy sign-in command")
                        icon.name: "edit-copy"
                        onTriggered: full.widget.copyText(full.signInCommand(full.widget.account))
                    }
                ]
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: full.widget.syncError !== "" && full.widget.repoData !== null
                type: Kirigami.MessageType.Error
                text: i18n("Couldn't sync: %1", full.widget.syncError)
                actions: [
                    Kirigami.Action {
                        text: i18n("Try again")
                        icon.name: "view-refresh"
                        onTriggered: full.widget.sync()
                    }
                ]
            }
        }
    }

    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaComponents3.ToolBar.Footer
        visible: full.hasList

        contentItem: RowLayout {
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: full.widget.lastCopied !== ""
                      ? i18n("Copied: %1", full.widget.lastCopied)
                      : i18n("Enter open · Ctrl+C copy link · Ctrl+Shift+A account")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                text: full.widget.repoData
                      ? i18n("%1 repos · synced %2", full.widget.repoCount, full.widget.ago(full.widget.repoData.synced_at))
                      : ""
                font: Kirigami.Theme.smallFont
                opacity: 0.5
            }
        }
    }

    PlasmaComponents3.ScrollView {
        anchors.fill: parent
        visible: full.hasList && list.count > 0

        contentItem: ListView {
            id: list
            objectName: "repoList"
            model: full.widget.repoModel
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            highlightMoveDuration: 0
            highlight: PlasmaExtras.Highlight {}

            section.property: "section"
            section.delegate: PlasmaExtras.ListSectionHeader {
                required property string section
                width: ListView.view.width
                text: section === "recent" ? i18n("Recent") : i18n("All repos")
            }

            // Keyboard: Up/Down select, Enter or O opens, C copies the link
            // (Shift+C SSH, Alt+C HTTPS), A opens the account list, Esc or Up on
            // the first row go back to the search, and typing goes to the search.
            Keys.onUpPressed: event => {
                if (currentIndex <= 0) {
                    searchField.forceActiveFocus();
                } else {
                    decrementCurrentIndex();
                }
            }
            Keys.onReturnPressed: full.widget.openRepo(currentIndex)
            Keys.onEnterPressed: full.widget.openRepo(currentIndex)
            Keys.onMenuPressed: currentItem && currentItem.openMenu()
            Keys.onEscapePressed: searchField.forceActiveFocus()
            Keys.onPressed: event => {
                if (full.handleCtrlKey(event)) {
                    return;
                }
                const noMods = !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier));
                if (noMods && event.key === Qt.Key_C) {
                    full.widget.copyRepo(currentIndex, event.modifiers & Qt.ShiftModifier ? "ssh"
                                         : event.modifiers & Qt.AltModifier ? "https" : "url");
                } else if (noMods && event.key === Qt.Key_O) {
                    full.widget.openRepo(currentIndex);
                } else if (noMods && event.key === Qt.Key_A) {
                    accountBox.popup.open();
                } else if (noMods && event.text.trim() !== "") {
                    full.widget.searchText += event.text;
                    searchField.forceActiveFocus();
                } else {
                    return;
                }
                event.accepted = true;
            }

            delegate: RepoDelegate {
                widget: full.widget
            }
        }
    }

    // Ctrl+O open, Ctrl+C copy link (only when no text is selected in the
    // search field), Ctrl+Shift+A account list, F5 check accounts again.
    function handleCtrlKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key === Qt.Key_O) {
            full.widget.openRepo(Math.max(list.currentIndex, 0));
        } else if (ctrl && event.key === Qt.Key_C && searchField.selectedText === "") {
            full.widget.copyRepo(Math.max(list.currentIndex, 0), "url");
        } else if (ctrl && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_A) {
            accountBox.popup.open();
        } else if (event.key === Qt.Key_F5) {
            full.widget.loadAccounts();
        } else {
            return false;
        }
        event.accepted = true;
        return true;
    }

    function focusList(index) {
        if (list.count > 0) {
            list.currentIndex = Math.min(Math.max(index, 0), list.count - 1);
            list.forceActiveFocus();
        }
    }

    function signInCommand(account) {
        if (!account) {
            return "";
        }
        return account.provider === "gitlab"
            ? "glab auth login --hostname " + account.host
            : "gh auth login --hostname " + account.host;
    }

    // State: first load, or the first sync of an account
    ColumnLayout {
        anchors.centerIn: parent
        visible: full.widget.phase === "loading" || (full.widget.phase === "ready" && full.widget.repoData === null && full.widget.syncing)
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents3.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: parent.visible
        }
        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            text: full.widget.phase === "loading" ? i18n("Checking gh and glab…") : i18n("Syncing repos…")
            opacity: 0.7
        }
    }

    // State: neither gh nor glab is signed in
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: full.widget.phase === "noAccounts"
        iconName: "network-connect"
        text: i18n("Connect at least one service")
        explanation: i18n("Gitway works with GitHub, GitLab, or both. Sign in once in a terminal with gh auth login or glab auth login, then open Gitway again.")
        helpfulAction: Kirigami.Action {
            text: i18n("Copy gh auth login")
            icon.name: "edit-copy"
            onTriggered: full.widget.copyText("gh auth login")
        }
    }

    // State: the first sync failed, nothing cached to show
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: full.widget.phase === "ready" && full.widget.repoData === null
                 && !full.widget.syncing && full.widget.syncError !== ""
        iconName: "dialog-error"
        text: i18n("Couldn't load repos")
        explanation: full.widget.syncError
        helpfulAction: Kirigami.Action {
            text: i18n("Try again")
            icon.name: "view-refresh"
            onTriggered: full.widget.sync()
        }
    }

    // State: list loaded, nothing to show
    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: full.hasList && list.count === 0
        iconName: "edit-find"
        text: full.widget.searchText !== ""
              ? i18n("No repos match \"%1\"", full.widget.searchText)
              : i18n("No repositories found for this account")
        explanation: full.widget.searchText !== "" && !full.widget.searchText.startsWith("!")
                     ? i18n("Archived repos are hidden. Start the search with ! to include them.")
                     : ""
        helpfulAction: Kirigami.Action {
            enabled: full.widget.searchText === "" || !full.widget.searchText.startsWith("!")
            text: full.widget.searchText !== "" ? i18n("Include archived") : i18n("Sync repos")
            icon.name: full.widget.searchText !== "" ? "edit-find" : "view-refresh"
            onTriggered: {
                if (full.widget.searchText !== "") {
                    full.widget.searchText = "!" + full.widget.searchText;
                } else {
                    full.widget.sync();
                }
            }
        }
    }

    // Typing works as soon as the popup opens
    Connections {
        target: full.widget
        function onExpandedChanged() {
            if (full.widget.expanded) {
                list.currentIndex = 0;
                searchField.forceActiveFocus();
            }
        }
    }
}
