import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// Flat icon-only button with a tooltip. Plasma's own icon property does not
// tint icons loaded from files, so the icon is drawn here.
PlasmaComponents3.ToolButton {
    id: button

    required property string iconName
    required property string toolTip
    // Spins the icon, e.g. while a sync runs
    property bool spinning: false

    Accessible.name: toolTip
    QQC2.ToolTip.text: toolTip
    QQC2.ToolTip.visible: hovered
    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

    contentItem: Item {
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: implicitWidth

        SvgIcon {
            id: icon
            anchors.centerIn: parent
            name: button.iconName

            RotationAnimator on rotation {
                running: button.spinning
                from: 0
                to: 360
                duration: 1000
                loops: Animation.Infinite
                onStopped: icon.rotation = 0
            }
        }
    }
}
