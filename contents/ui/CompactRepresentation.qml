import QtQuick
import org.kde.kirigami as Kirigami

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
}
