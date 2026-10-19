import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_hideArchived: archivedCheck.checked
    property alias cfg_includeOrgs: orgsCheck.checked
    property alias cfg_syncOnOpen: syncOnOpenCheck.checked
    property alias cfg_assignToMe: assignCheck.checked
    property alias cfg_deleteSourceBranch: deleteSourceCheck.checked
    property alias cfg_openAfterCreate: openAfterCheck.checked
    property alias cfg_showBadge: badgeCheck.checked
    property alias cfg_badgeInterval: badgeIntervalSpin.value
    // Hidden repos of every account; only the active account's are listed here
    property var cfg_hidden: []
    property string cfg_activeAccount: ""

    readonly property var hiddenHere: cfg_hidden.filter(e => e.startsWith(cfg_activeAccount + "\t"))
                                                .map(e => e.slice(cfg_activeAccount.length + 1))

    function unhide(pattern) {
        cfg_hidden = cfg_hidden.filter(e => e !== cfg_activeAccount + "\t" + pattern);
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: orgsCheck
            Kirigami.FormData.label: i18n("Repositories:")
            text: i18n("Include organization and group repos")
        }

        QQC2.CheckBox {
            id: archivedCheck
            text: i18n("Hide archived repos (search with ! to include them)")
        }

        QQC2.CheckBox {
            id: syncOnOpenCheck
            text: i18n("Sync repos when opening, at most once an hour")
        }

        // Repos hidden with H or the right-click menu, for the account shown in the popup
        ColumnLayout {
            Kirigami.FormData.label: i18n("Hidden repos:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                visible: hiddenHere.length === 0
                text: i18n("None. Press H on a repo, or right-click it, to hide it.")
                opacity: 0.7
            }

            Repeater {
                model: hiddenHere

                RowLayout {
                    required property string modelData

                    QQC2.Label {
                        text: modelData
                        font.family: "monospace"
                    }
                    QQC2.Button {
                        text: i18n("Show")
                        onClicked: unhide(modelData)
                    }
                }
            }

            QQC2.Button {
                visible: hiddenHere.length > 1
                text: i18n("Show all")
                onClicked: cfg_hidden = cfg_hidden.filter(e => !e.startsWith(cfg_activeAccount + "\t"))
            }

            QQC2.Label {
                text: cfg_activeAccount !== "" ? i18n("Account: %1", cfg_activeAccount.split("/").slice(1).reverse().join(" - ")) : ""
                font: Kirigami.Theme.smallFont
                opacity: 0.6
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.Label {
            Kirigami.FormData.label: i18n("Accounts:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.Wrap
            text: i18n("Add GitHub and GitLab accounts from the account list in the popup, with Add account…")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: badgeCheck
            Kirigami.FormData.label: i18n("Panel icon:")
            text: i18n("Show a badge with what waits for me")
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            wrapMode: Text.Wrap
            enabled: badgeCheck.checked
            opacity: 0.7
            text: i18n("Merge requests waiting for my review, plus my merge requests that are ready to merge.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Check every:")
            enabled: badgeCheck.checked

            QQC2.SpinBox {
                id: badgeIntervalSpin
                from: 0
                to: 240
                stepSize: 5
                // 0 checks only when the popup opens: no timer at all
                textFromValue: value => value === 0 ? i18n("never") : i18np("%1 minute", "%1 minutes", value)
                valueFromText: text => parseInt(text) || 0
            }
            QQC2.Label {
                text: badgeIntervalSpin.value === 0 ? i18n("(refreshed when the popup opens)") : ""
                opacity: 0.7
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: openAfterCheck
            Kirigami.FormData.label: i18n("New merge requests:")
            text: i18n("Open in the browser after creating")
        }

        QQC2.CheckBox {
            id: assignCheck
            text: i18n("Assign to me")
        }

        QQC2.CheckBox {
            id: deleteSourceCheck
            text: i18n("Delete the source branch after merge (GitLab)")
        }
    }
}
