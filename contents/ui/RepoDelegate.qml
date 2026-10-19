import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// One repo:  [GL]  owner/group/name 🔒 [archived]        3d ago
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

    width: ListView.view ? ListView.view.width : implicitWidth
    highlighted: ListView.isCurrentItem

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        ProviderBadge {
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

        Kirigami.Icon {
            visible: row.visibility !== "public"
            source: "object-locked"
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
            // GitLab "internal": visible to every signed-in user of the instance
            opacity: row.visibility === "internal" ? 0.45 : 0.8
        }

        PlasmaComponents3.Label {
            visible: row.archived
            text: i18n("archived")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }

        PlasmaComponents3.Label {
            text: row.widget.ago(row.pushedAt)
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }
    }

    onClicked: widget.openRepo(index)

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
                icon.name: "internet-web-browser"
                onTriggered: row.widget.openRepo(row.index)
            }
            PlasmaComponents3.MenuSeparator {}
            PlasmaComponents3.MenuItem {
                text: i18n("Copy link")
                icon.name: "edit-copy"
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
        }
    }
}
