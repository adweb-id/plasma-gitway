import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// First page of the popup: the tabs Repos, My MRs, Reviews and Issues
// (mockup 4.4). Ctrl+Tab, Ctrl+Shift+Tab and Ctrl+1…4 switch tabs.
FocusScope {
    id: home

    required property var widget
    required property var full

    readonly property alias listPage: listPage
    readonly property var current: tabs.currentIndex === 0 ? listPage : queues.itemAt(tabs.currentIndex - 1)
    readonly property bool busy: current ? current.busy === true : false
    readonly property string hints: current ? current.hints : ""
    readonly property string status: current ? current.status : ""

    readonly property var kinds: ["mine", "reviews", "issues"]

    function showTab(index) {
        tabs.currentIndex = Math.max(0, Math.min(index, 3));
        if (tabs.currentIndex === 0) {
            listPage.focusSearch();
        } else {
            current.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (busy) {
            return;
        }
        if (ctrl && event.key === Qt.Key_Tab) {
            showTab((tabs.currentIndex + 1) % 4);
        } else if (ctrl && event.key === Qt.Key_Backtab) {
            showTab((tabs.currentIndex + 3) % 4);
        } else if (ctrl && event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
            showTab(event.key - Qt.Key_1);
        } else {
            return;
        }
        event.accepted = true;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PlasmaComponents3.TabBar {
            id: tabs
            Layout.fillWidth: true
            enabled: !home.busy

            PlasmaComponents3.TabButton {
                text: i18n("Repos")
                onClicked: home.showTab(0)
            }
            Repeater {
                model: home.kinds

                PlasmaComponents3.TabButton {
                    required property string modelData
                    required property int index

                    readonly property int count: home.widget.queueItems(modelData).length
                    text: ({ mine: i18n("My MRs"), reviews: i18n("Reviews"), issues: i18n("Issues") })[modelData]
                          + (count > 0 ? " " + count : "")
                    onClicked: home.showTab(index + 1)
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            RepoListPage {
                id: listPage
                widget: home.widget
                full: home.full
            }

            Repeater {
                id: queues
                model: home.kinds

                QueuePage {
                    required property string modelData
                    widget: home.widget
                    full: home.full
                    kind: modelData
                }
            }
        }
    }
}
