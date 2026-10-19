import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../code/forge.js" as Forge

// One merge request or issue in the My MRs, Reviews or Issues tab:
//   ● Fix tax rounding on prorated invoices        [copy] [Merge]
//     invoice-service !412  approved
// Merge and Approve open a confirmation panel right under the row
// (mockup 4.10) instead of a separate dialog.
PlasmaComponents3.ItemDelegate {
    id: row

    required property var page
    required property var item
    required property int index

    readonly property var widget: page.widget
    readonly property var account: widget.account
    readonly property string kind: page.kind
    readonly property bool isIssue: kind === "issues"
    // "merge" | "approve" | "" : which button the row offers
    readonly property string rowAction: kind === "mine" && item.status === "ready" ? "merge"
                                   : kind === "reviews" ? "approve" : ""
    readonly property bool confirming: page.confirmIndex === index

    width: ListView.view ? ListView.view.width : implicitWidth
    // Same gliding highlight as the repo list; it waits while a panel is open
    onHoveredChanged: {
        if (hovered && ListView.view && page.confirmIndex < 0) {
            ListView.view.currentIndex = index;
        }
    }
    leftPadding: Kirigami.Units.largeSpacing
    rightPadding: Kirigami.Units.smallSpacing
    topPadding: Kirigami.Units.smallSpacing * 1.5
    bottomPadding: Kirigami.Units.smallSpacing * 1.5
    onClicked: Qt.openUrlExternally(item.url)

    contentItem: ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            // Colour carries the status, the text under the title says it too
            Rectangle {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: Kirigami.Units.smallSpacing
                implicitWidth: Kirigami.Units.smallSpacing * 2
                implicitHeight: implicitWidth
                radius: width / 2
                color: row.dotColor()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.item.title
                    elide: Text.ElideRight
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: row.item.repoPath.split("/").pop() + " " + (row.isIssue ? "#" : Forge.sigil(row.account)) + row.item.number
                          + "  " + row.statusText()
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    elide: Text.ElideRight
                }
            }

            IconButton {
                iconName: "copy"
                toolTip: i18n("Copy link")
                onClicked: row.widget.copyText(row.item.url)
            }
            PlasmaComponents3.Button {
                visible: row.rowAction !== "" && !row.confirming
                text: row.rowAction === "merge" ? i18n("Merge") : i18n("Approve")
                onClicked: row.page.confirm(row.index)
            }
            IconButton {
                visible: row.rowAction === ""
                iconName: "external"
                toolTip: i18n("Open in browser")
                onClicked: Qt.openUrlExternally(row.item.url)
            }
        }

        // Confirmation panel: repeats the facts, then one button. It grows
        // out of the row and shrinks back instead of popping in.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: row.confirming ? panelBox.implicitHeight : 0
            visible: Layout.preferredHeight > 0
            clip: true
            opacity: row.confirming ? 1 : 0
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: Kirigami.Units.longDuration }
            }

        Rectangle {
            id: panelBox
            width: parent.width
            implicitHeight: panel.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: row.tint(0.12)
            border.color: row.tint(0.5)

            ColumnLayout {
                id: panel
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    font.bold: true
                    wrapMode: Text.Wrap
                    text: row.rowAction === "merge"
                          ? i18n("Merge %1 into %2?", Forge.sigil(row.account) + row.item.number, row.item.target)
                          : i18n("Approve %1?", Forge.sigil(row.account) + row.item.number)
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    font: Kirigami.Theme.smallFont
                    text: row.isIssue ? "" : i18n("%1 → %2 · %3", row.item.source, row.item.target, row.item.repoPath)
                }

                // Defaults follow the repo's own merge settings
                RowLayout {
                    visible: row.rowAction === "merge"
                    PlasmaComponents3.CheckBox {
                        text: i18n("Delete source branch")
                        checked: row.page.mergeOptions.deleteSource
                        enabled: !row.page.acting && row.page.mergeOptions.loaded
                        onToggled: row.page.setOption("deleteSource", checked)
                    }
                    PlasmaComponents3.CheckBox {
                        text: i18n("Squash commits")
                        checked: row.page.mergeOptions.squash
                        enabled: !row.page.acting && row.page.mergeOptions.loaded && !row.page.mergeOptions.squashLocked
                        onToggled: row.page.setOption("squash", checked)
                    }
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: row.page.actionError !== ""
                    type: Kirigami.MessageType.Error
                    text: row.page.actionError
                }

                RowLayout {
                    PlasmaComponents3.Button {
                        text: row.page.acting ? (row.rowAction === "merge" ? i18n("Merging…") : i18n("Approving…"))
                                              : (row.rowAction === "merge" ? i18n("Merge") : i18n("Approve"))
                        enabled: !row.page.acting && (row.rowAction !== "merge" || row.page.mergeOptions.loaded)
                        onClicked: row.page.runAction()
                    }
                    PlasmaComponents3.Button {
                        text: i18n("Cancel")
                        enabled: !row.page.acting
                        onClicked: row.page.cancel()
                    }
                    PlasmaComponents3.BusyIndicator {
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredWidth: Layout.preferredHeight
                        visible: row.page.acting || (row.rowAction === "merge" && !row.page.mergeOptions.loaded)
                        running: visible
                    }
                }
            }
        }
        }
    }

    // Panel colour: green for merge, the accent colour for approve
    function tint(alpha) {
        const c = rowAction === "merge" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.highlightColor;
        return Qt.rgba(c.r, c.g, c.b, alpha);
    }

    function statusText() {
        if (isIssue) {
            return item.labels.join(", ");
        }
        return {
            ready: kind === "reviews" ? i18n("waiting for you") : i18n("ready to merge"),
            running: i18n("pipeline running"),
            review: i18n("awaiting review"),
            failed: i18n("pipeline failed"),
            conflict: i18n("conflicts"),
            draft: i18n("draft")
        }[item.status] || "";
    }

    // Issues: red for high/urgent/critical labels, orange for any other
    // label, green without labels (PRD 4.12)
    function dotColor() {
        if (isIssue) {
            const labels = item.labels.join(" ").toLowerCase();
            return /high|urgent|critical|blocker|p0|p1/.test(labels) ? Kirigami.Theme.negativeTextColor
                 : item.labels.length > 0 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.positiveTextColor;
        }
        switch (item.status) {
        case "ready": return Kirigami.Theme.positiveTextColor;
        case "failed": case "conflict": return Kirigami.Theme.negativeTextColor;
        case "draft": return Kirigami.Theme.disabledTextColor;
        default: return Kirigami.Theme.neutralTextColor;
        }
    }
}
