import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

// First page: search the active account's repos (mockup 4.1).
FocusScope {
    id: page

    required property var widget
    required property var full

    readonly property bool hasList: widget.phase === "ready" && widget.repoData !== null
    readonly property string hints: i18n("Enter open · O browser · P pin · H hide")
    readonly property string status: widget.repoData
        ? i18n("%1 repos · synced %2", widget.repoCount, widget.ago(widget.repoData.synced_at)) : ""

    // Order of "All repos", chosen from the button next to the search field
    readonly property var sortChoices: [
        { by: "pushed", descending: true, label: i18n("Last updated, newest first"), short: i18n("newest first") },
        { by: "pushed", descending: false, label: i18n("Last updated, oldest first"), short: i18n("oldest first") },
        { by: "name", descending: false, label: i18n("Name, A to Z"), short: i18n("A→Z") },
        { by: "name", descending: true, label: i18n("Name, Z to A"), short: i18n("Z→A") }
    ]
    readonly property var sortChoice: sortChoices.find(c => c.by === Plasmoid.configuration.sortBy
                                                          && c.descending === Plasmoid.configuration.sortDescending)
                                      || sortChoices[0]

    function setSort(choice) {
        Plasmoid.configuration.sortBy = choice.by;
        Plasmoid.configuration.sortDescending = choice.descending;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            Layout.topMargin: Kirigami.Units.largeSpacing
            Layout.bottomMargin: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing
            visible: page.hasList

        PlasmaExtras.SearchField {
            id: searchField
            objectName: "searchField"
            Layout.fillWidth: true
            focus: true
            placeholderText: i18n("Search repos…  (org:  private:  public:  ! hidden)")
            text: page.widget.searchText
            onTextChanged: {
                page.widget.searchText = text;
                list.currentIndex = 0;
            }
            Keys.onEscapePressed: event => {
                if (text !== "") {
                    page.widget.searchText = "";
                    event.accepted = true;
                } else {
                    event.accepted = false; // let Escape close the popup
                }
            }
            Keys.onDownPressed: page.focusList(list.currentIndex + 1)
            Keys.onUpPressed: list.currentIndex = Math.max(list.currentIndex - 1, 0)
            Keys.onReturnPressed: event => page.enter(event)
            Keys.onEnterPressed: event => page.enter(event)
            // The same actions as the single keys in the list, with Ctrl
            Keys.onPressed: event => page.handleCtrlKey(event)
        }

        IconButton {
            id: sortButton
            iconName: "sort"
            toolTip: i18n("Sort all repos: %1", page.sortChoice.label)
            onClicked: sortMenu.popup(sortButton, 0, sortButton.height)
        }
        }

        PlasmaComponents3.Menu {
            id: sortMenu

            PlasmaComponents3.MenuItem {
                text: page.sortChoices[0].label
                checkable: true
                checked: page.sortChoice === page.sortChoices[0]
                onTriggered: page.setSort(page.sortChoices[0])
            }
            PlasmaComponents3.MenuItem {
                text: page.sortChoices[1].label
                checkable: true
                checked: page.sortChoice === page.sortChoices[1]
                onTriggered: page.setSort(page.sortChoices[1])
            }
            PlasmaComponents3.MenuSeparator {}
            PlasmaComponents3.MenuItem {
                text: page.sortChoices[2].label
                checkable: true
                checked: page.sortChoice === page.sortChoices[2]
                onTriggered: page.setSort(page.sortChoices[2])
            }
            PlasmaComponents3.MenuItem {
                text: page.sortChoices[3].label
                checkable: true
                checked: page.sortChoice === page.sortChoices[3]
                onTriggered: page.setSort(page.sortChoices[3])
            }
        }

        PlasmaComponents3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            visible: page.hasList && list.count > 0

            contentItem: ListView {
                id: list
                objectName: "repoList"
                model: page.widget.repoModel
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                keyNavigationEnabled: true
                highlightMoveDuration: Kirigami.Units.shortDuration
                highlightResizeDuration: 0
                highlight: PlasmaExtras.Highlight {}

                section.property: "section"
                section.delegate: PlasmaExtras.ListSectionHeader {
                    required property string section
                    width: ListView.view.width
                    topPadding: Kirigami.Units.largeSpacing
                    text: section === "pinned" ? i18n("Pinned") : section === "recent" ? i18n("Recent")
                          : i18n("All repos · %1", page.sortChoice.short)
                }

                // Keyboard: Up/Down select, Enter opens the repo page, M (or
                // Ctrl+Enter) a new merge request, O the browser, C copies the
                // link (Shift+C SSH, Alt+C HTTPS), A the account list. Esc or Up
                // on the first row go back to the search, typing goes there too.
                Keys.onUpPressed: event => {
                    if (currentIndex <= 0) {
                        searchField.forceActiveFocus();
                    } else {
                        decrementCurrentIndex();
                    }
                }
                Keys.onReturnPressed: event => page.enter(event)
                Keys.onEnterPressed: event => page.enter(event)
                Keys.onMenuPressed: currentItem && currentItem.openMenu()
                Keys.onEscapePressed: searchField.forceActiveFocus()
                Keys.onPressed: event => {
                    if (page.handleCtrlKey(event)) {
                        return;
                    }
                    const noMods = !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier));
                    if (noMods && event.key === Qt.Key_C) {
                        page.widget.copyRepo(currentIndex, event.modifiers & Qt.ShiftModifier ? "ssh"
                                             : event.modifiers & Qt.AltModifier ? "https" : "url");
                    } else if (noMods && event.key === Qt.Key_O) {
                        page.widget.openRepo(currentIndex);
                    } else if (noMods && event.key === Qt.Key_M) {
                        page.showRepo(currentIndex, true);
                    } else if (noMods && event.key === Qt.Key_A) {
                        page.full.openAccounts();
                    } else if (noMods && event.key === Qt.Key_P) {
                        page.widget.togglePin(currentIndex);
                    } else if (noMods && event.key === Qt.Key_H) {
                        page.hideAt(currentIndex);
                    } else if (noMods && event.text.trim() !== "") {
                        page.widget.searchText += event.text;
                        searchField.forceActiveFocus();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                delegate: RepoDelegate {
                    widget: page.widget
                    onActivated: page.showRepo(index, false)
                }
            }
        }
    }

    // Enter: repo page, Ctrl+Enter: straight to the merge request form
    function enter(event) {
        showRepo(Math.max(list.currentIndex, 0), event.modifiers & Qt.ControlModifier);
        event.accepted = true;
    }

    function showRepo(index, startMr) {
        const row = widget.rowAt(index);
        if (row) {
            widget.remember(row.path);
            full.showRepo(row, startMr);
        }
    }

    // H on a hidden row (only listed when searching with !) shows it again
    function hideAt(index) {
        const row = widget.rowAt(index);
        if (row) {
            if (row.hidden) {
                widget.unhideRepo(row.path);
            } else {
                widget.hide(row.path);
            }
        }
    }

    // Ctrl+O browser, Ctrl+C copy link (only when no text is selected in the
    // search field), Ctrl+P pin, Ctrl+Shift+A account list, F5 check accounts again.
    function handleCtrlKey(event) {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (ctrl && event.key === Qt.Key_P) {
            widget.togglePin(Math.max(list.currentIndex, 0));
        } else if (ctrl && event.key === Qt.Key_O) {
            widget.openRepo(Math.max(list.currentIndex, 0));
        } else if (ctrl && event.key === Qt.Key_C && searchField.selectedText === "") {
            widget.copyRepo(Math.max(list.currentIndex, 0), "url");
        } else if (ctrl && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_A) {
            full.openAccounts();
        } else if (event.key === Qt.Key_F5) {
            widget.loadAccounts();
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

    function focusSearch() {
        list.currentIndex = 0;
        searchField.forceActiveFocus();
    }

    // State: first load, or the first sync of an account
    ColumnLayout {
        anchors.centerIn: parent
        visible: page.widget.phase === "loading" || (page.widget.phase === "ready" && page.widget.repoData === null && page.widget.syncing)
        spacing: Kirigami.Units.largeSpacing

        PlasmaComponents3.BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: parent.visible
        }
        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            text: page.widget.phase === "loading" ? i18n("Checking gh and glab…") : i18n("Syncing repos…")
            opacity: 0.7
        }
    }

    // State: neither gh nor glab is signed in
    EmptyState {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: page.widget.phase === "noAccounts"
        iconName: "merge"
        title: i18n("Connect at least one service")
        explanation: i18n("Gitway works with GitHub, GitLab, or both. Sign in once in a terminal with gh auth login or glab auth login, then open Gitway again.")
        actionText: i18n("Copy gh auth login")
        onActionTriggered: page.widget.copyText("gh auth login")
    }

    // State: the first sync failed, nothing cached to show
    EmptyState {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: page.widget.phase === "ready" && page.widget.repoData === null
                 && !page.widget.syncing && page.widget.syncError !== ""
        iconName: "error"
        title: i18n("Couldn't load repos")
        explanation: page.widget.syncError
        actionText: i18n("Try again")
        onActionTriggered: page.widget.sync()
    }

    // State: list loaded, nothing to show
    EmptyState {
        readonly property bool searching: page.widget.searchText !== ""
        readonly property bool withArchived: page.widget.searchText.startsWith("!")

        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: page.hasList && list.count === 0
        iconName: "search"
        title: searching ? i18n("No repos match \"%1\"", page.widget.searchText)
                         : i18n("No repositories found for this account")
        explanation: searching && !withArchived ? i18n("Hidden and archived repos are left out. Start the search with ! to include them.") : ""
        actionText: !searching ? i18n("Sync repos") : (withArchived ? "" : i18n("Include hidden & archived"))
        onActionTriggered: {
            if (searching) {
                page.widget.searchText = "!" + page.widget.searchText;
            } else {
                page.widget.sync();
            }
        }
    }
}
