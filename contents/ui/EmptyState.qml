import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Centred icon, title, explanation and one optional button: the empty,
// setup and error states of the popup.
ColumnLayout {
    id: emptyState

    required property string iconName
    property string title: ""
    property string explanation: ""
    property string actionText: ""

    signal actionTriggered()

    spacing: Kirigami.Units.largeSpacing

    SvgIcon {
        Layout.alignment: Qt.AlignHCenter
        name: emptyState.iconName
        implicitWidth: Kirigami.Units.iconSizes.huge
        opacity: 0.6
    }

    Kirigami.Heading {
        Layout.fillWidth: true
        level: 3
        text: emptyState.title
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.8
    }

    PlasmaComponents3.Label {
        Layout.fillWidth: true
        visible: text !== ""
        text: emptyState.explanation
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        opacity: 0.7
    }

    PlasmaComponents3.Button {
        Layout.alignment: Qt.AlignHCenter
        visible: emptyState.actionText !== ""
        text: emptyState.actionText
        onClicked: emptyState.actionTriggered()
    }
}
