import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

MouseArea {
    id: compact

    required property var widget

    hoverEnabled: true
    onClicked: widget.expanded = !widget.expanded

    // One-colour icon, tinted with the panel's text colour
    Kirigami.Icon {
        anchors.fill: parent
        source: compact.widget.iconSource
        isMask: true
        color: Kirigami.Theme.textColor
        active: compact.containsMouse
    }

    // Badge: reviews waiting plus own merge requests ready to merge, only
    // when turned on in the settings
    Rectangle {
        visible: compact.widget.showBadge && compact.widget.badgeCount > 0
        anchors.top: parent.top
        anchors.right: parent.right
        height: Math.max(Math.round(parent.height * 0.45), badgeLabel.implicitHeight)
        width: Math.max(height, badgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2)
        radius: height / 2
        color: Kirigami.Theme.highlightColor

        PlasmaComponents3.Label {
            id: badgeLabel
            anchors.centerIn: parent
            text: compact.widget.badgeCount > 99 ? "99+" : compact.widget.badgeCount
            color: Kirigami.Theme.highlightedTextColor
            font.pixelSize: Math.max(Kirigami.Theme.smallFont.pixelSize, Math.round(compact.height * 0.32))
            font.bold: true
        }
    }
}
