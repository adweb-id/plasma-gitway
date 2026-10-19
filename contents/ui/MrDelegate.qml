import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/forge.js" as Forge

// One open merge / pull request:
//   Fix tax rounding on prorated invoices          [copy] [open]
//   !412  fix/invoice-tax → develop  draft
PlasmaComponents3.ItemDelegate {
    id: row

    required property var widget
    required property var account
    required property var modelData

    width: ListView.view ? ListView.view.width : implicitWidth
    onClicked: Qt.openUrlExternally(modelData.url)

    contentItem: RowLayout {
        spacing: Kirigami.Units.smallSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: row.modelData.title
                elide: Text.ElideRight
            }
            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: Forge.sigil(row.account) + row.modelData.number + "  "
                          + i18n("%1 → %2", row.modelData.source, row.modelData.target)
                    font.family: "monospace"
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: 0.7
                    elide: Text.ElideMiddle
                }
                PlasmaComponents3.Label {
                    visible: row.modelData.draft
                    text: i18n("draft")
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                }
            }
        }

        IconButton {
            iconName: "copy"
            toolTip: i18n("Copy link")
            onClicked: row.widget.copyText(row.modelData.url)
        }
        IconButton {
            iconName: "external"
            toolTip: i18n("Open in browser")
            onClicked: Qt.openUrlExternally(row.modelData.url)
        }
    }
}
