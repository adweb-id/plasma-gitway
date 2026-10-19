import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Small round "GH" / "GL" mark in front of accounts and repos.
// Stand-in until the provider logos of PRD §6.2 are added.
Rectangle {
    id: badge

    required property string provider

    implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 1.1)
    implicitHeight: implicitWidth
    radius: width / 2
    color: provider === "gitlab" ? "#e24329" : "#4b5563"

    PlasmaComponents3.Label {
        anchors.centerIn: parent
        text: badge.provider === "gitlab" ? "GL" : "GH"
        color: "white"
        font.pixelSize: Math.round(badge.height * 0.42)
        font.bold: true
        font.family: "monospace"
    }
}
