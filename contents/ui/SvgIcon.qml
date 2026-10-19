import QtQuick
import org.kde.kirigami as Kirigami

// One of Gitway's own icons from contents/icons/ (PRD §6.2), tinted with
// the theme colour. Theme icons are never used, so a missing name in the
// user's icon theme cannot leave a button blank.
Kirigami.Icon {
    required property string name

    implicitWidth: Kirigami.Units.iconSizes.small
    implicitHeight: implicitWidth
    source: Qt.resolvedUrl("../icons/" + name + ".svg")
    isMask: true
    color: Kirigami.Theme.textColor
}
