import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

import "../code/repos.js" as Repos

// Popup: a header with the account list, then one page at a time
// (PRD 6.3): RepoListPage -> RepoPage -> MrFormPage / BranchFormPage.
PlasmaExtras.Representation {
    id: full

    required property var widget

    // The page on top, for the footer and for Escape
    readonly property var page: stack.currentItem
    // A create/merge call is running: Escape must not close the popup
    readonly property bool busy: page && page.busy === true

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
                    enabled: !full.busy
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
                    onActivated: {
                        if (currentValue !== full.widget.accountKey) {
                            full.backToList();
                            full.widget.switchAccount(currentValue);
                        }
                    }
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
                            SvgIcon {
                                visible: accountItem.modelData.key === full.widget.accountKey
                                name: "check"
                            }
                        }
                    }
                }

                // Spins while a sync runs; the search keeps working on the old list
                IconButton {
                    visible: full.widget.account !== null
                    iconName: "sync"
                    toolTip: full.widget.syncing ? i18n("Syncing repos…") : i18n("Sync repos")
                    spinning: full.widget.syncing
                    enabled: !full.widget.syncing
                    onClicked: full.widget.sync()
                }

                IconButton {
                    iconName: "settings"
                    toolTip: i18n("Settings")
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
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
                        onTriggered: full.widget.sync()
                    }
                ]
            }
        }
    }

    footer: PlasmaExtras.PlasmoidHeading {
        position: PlasmaComponents3.ToolBar.Footer
        visible: full.widget.phase === "ready"

        contentItem: RowLayout {
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: full.widget.lastCopied !== ""
                      ? i18n("Copied: %1", full.widget.lastCopied)
                      : (full.page && full.page.hints ? full.page.hints : "")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                elide: Text.ElideRight
            }
            PlasmaComponents3.Label {
                text: full.page && full.page.status ? full.page.status : ""
                font: Kirigami.Theme.smallFont
                opacity: 0.5
            }
        }
    }

    QQC2.StackView {
        id: stack
        anchors.fill: parent
        clip: true

        initialItem: RepoListPage {
            id: listPage
            widget: full.widget
            full: full
        }
    }

    Component {
        id: repoPageComponent
        RepoPage {}
    }

    Component {
        id: mrFormComponent
        MrFormPage {}
    }

    Component {
        id: branchFormComponent
        BranchFormPage {}
    }

    // --- Navigation, called by the pages -------------------------------------------

    function showRepo(row, startMr) {
        stack.push(repoPageComponent, { widget: widget, full: full, repo: row, startMr: !!startMr });
        stack.currentItem.forceActiveFocus();
    }

    // repoPage: the RepoPage it was opened from, so it can refresh afterwards
    function showMrForm(repoPage, source) {
        stack.push(mrFormComponent, { widget: widget, full: full, repoPage: repoPage, repo: repoPage.repo, initialSource: source || "" });
        stack.currentItem.forceActiveFocus();
    }

    function showBranchForm(repoPage) {
        stack.push(branchFormComponent, { widget: widget, full: full, repoPage: repoPage, repo: repoPage.repo });
        stack.currentItem.forceActiveFocus();
    }

    function back() {
        if (stack.depth > 1 && !busy) {
            stack.pop();
            stack.currentItem.forceActiveFocus();
        }
    }

    function backToList() {
        stack.pop(null);
        listPage.focusSearch();
    }

    function openAccounts() {
        accountBox.popup.open();
    }

    // A thrown error from a page's callback -> one line for the user
    function describeError(error) {
        if (error === "TIMEOUT") {
            return i18n("No response from gh/glab after 30 s");
        }
        if (error instanceof Error) {
            return i18n("Unexpected answer from the server (%1)", error.message);
        }
        return error || i18n("Unknown error");
    }

    function signInCommand(account) {
        if (!account) {
            return "";
        }
        return account.provider === "gitlab"
            ? "glab auth login --hostname " + account.host
            : "gh auth login --hostname " + account.host;
    }

    // Typing works as soon as the popup opens
    Connections {
        target: full.widget
        function onExpandedChanged() {
            if (full.widget.expanded && stack.depth === 1) {
                listPage.focusSearch();
            }
        }
    }
}
