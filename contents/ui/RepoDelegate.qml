import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// One repo:  [logo]  owner/group/name 🔒 [archived] [2 MR]   3d ago  ☆
// The star pins it (shown on hover, always when pinned).
PlasmaComponents3.ItemDelegate {
    id: row

    required property var widget
    required property int index
    // Roles from the ListModel (see repos.js toRow())
    required property string path
    required property string owner
    required property string name
    required property string visibility
    required property bool archived
    required property string pushedAt
    required property bool pinned
    required property bool hidden

    readonly property int mrCount: widget.mrCount(path)

    // Click or Enter: the repo page (the list decides what that means)
    signal activated()

    width: ListView.view ? ListView.view.width : implicitWidth
    highlighted: ListView.isCurrentItem

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        ProviderLogo {
            provider: row.widget.account ? row.widget.account.provider : ""
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            textFormat: Text.StyledText
            elide: Text.ElideMiddle
            // Owner dimmed, name in the normal text colour
            text: "<font color=\"" + Kirigami.Theme.disabledTextColor + "\">" + row.escapeHtml(row.owner)
                  + "</font>" + row.escapeHtml(row.name)
        }

        SvgIcon {
            visible: row.visibility !== "public"
            name: "lock"
            // GitLab "internal": visible to every signed-in user of the instance
            opacity: row.visibility === "internal" ? 0.45 : 0.8
        }

        PlasmaComponents3.Label {
            visible: row.archived || row.hidden
            text: row.archived ? i18n("archived") : i18n("hidden")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        // Open merge requests of the user in this repo (from the My MRs tab)
        Rectangle {
            visible: row.mrCount > 0
            implicitWidth: mrLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
            implicitHeight: mrLabel.implicitHeight
            radius: Kirigami.Units.cornerRadius
            color: Qt.rgba(Kirigami.Theme.positiveTextColor.r, Kirigami.Theme.positiveTextColor.g,
                           Kirigami.Theme.positiveTextColor.b, 0.18)

            PlasmaComponents3.Label {
                id: mrLabel
                anchors.centerIn: parent
                text: i18n("%1 MR", row.mrCount)
                font: Kirigami.Theme.smallFont
                color: Kirigami.Theme.positiveTextColor
            }
        }

        PlasmaComponents3.Label {
            text: row.widget.ago(row.pushedAt)
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }

        IconButton {
            iconName: row.pinned ? "pin-filled" : "pin"
            toolTip: row.pinned ? i18n("Unpin (P)") : i18n("Pin to the top (P)")
            opacity: row.pinned || row.hovered || hovered ? 1 : 0
            onClicked: row.widget.togglePin(row.index)
        }
    }

    onClicked: activated()

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: row.openMenu()
    }

    function escapeHtml(text) {
        return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function openMenu() {
        ListView.view.currentIndex = index;
        const menu = menuComponent.createObject(row);
        menu.closed.connect(() => menu.destroy());
        menu.popup();
    }

    Component {
        id: menuComponent

        PlasmaComponents3.Menu {
            PlasmaComponents3.MenuItem {
                text: i18n("Open in browser")
                onTriggered: row.widget.openRepo(row.index)
            }
            PlasmaComponents3.MenuSeparator {}
            PlasmaComponents3.MenuItem {
                text: i18n("Copy link")
                onTriggered: row.widget.copyRepo(row.index, "url")
            }
            PlasmaComponents3.MenuItem {
                text: i18n("Copy SSH clone URL")
                onTriggered: row.widget.copyRepo(row.index, "ssh")
            }
            PlasmaComponents3.MenuItem {
                text: i18n("Copy HTTPS clone URL")
                onTriggered: row.widget.copyRepo(row.index, "https")
            }
            PlasmaComponents3.MenuSeparator {}
            PlasmaComponents3.MenuItem {
                text: row.pinned ? i18n("Unpin") : i18n("Pin to the top")
                onTriggered: row.widget.togglePin(row.index)
            }
            PlasmaComponents3.MenuItem {
                visible: !row.hidden
                text: i18n("Hide this repo")
                height: visible ? implicitHeight : 0
                onTriggered: row.widget.hide(row.path)
            }
            // Hiding a whole owner or group, e.g. "acme/legacy/*"
            PlasmaComponents3.MenuItem {
                visible: !row.hidden
                text: i18n("Hide everything in %1", row.owner)
                height: visible ? implicitHeight : 0
                onTriggered: row.widget.hide(row.owner + "*")
            }
            PlasmaComponents3.MenuItem {
                visible: row.hidden
                text: i18n("Show again")
                height: visible ? implicitHeight : 0
                onTriggered: row.widget.unhideRepo(row.path)
            }
        }
    }
}
