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
    // Hidden repos of every account; only the active account's are listed here
    property var cfg_hidden: []
    property string cfg_activeAccount: ""

    readonly property var hiddenHere: cfg_hidden.filter(e => e.startsWith(cfg_activeAccount + "\t"))
                                                .map(e => e.slice(cfg_activeAccount.length + 1))

    // A second GitLab account on the same host: its own glab config folder,
    // which Gitway finds by the glab-cli-* name
    readonly property string glabLogin: "GLAB_CONFIG_DIR=~/.config/glab-cli-work glab auth login --hostname gitlab.com"

    // QML has no clipboard API; a hidden TextEdit is the usual workaround.
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function copy(text) {
        clipboardHelper.text = text;
        clipboardHelper.selectAll();
        clipboardHelper.copy();
    }

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

        ColumnLayout {
            Kirigami.FormData.label: i18n("More GitLab accounts:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 26
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("glab keeps one account per host. For a second account on the same host, sign it in to its own config folder named glab-cli-something. Gitway finds it the next time the popup opens. Another host only needs a normal glab auth login.")
            }

            RowLayout {
                Layout.fillWidth: true

                QQC2.TextField {
                    Layout.fillWidth: true
                    readOnly: true
                    selectByMouse: true
                    font.family: "monospace"
                    text: glabLogin
                }
                QQC2.Button {
                    text: i18n("Copy")
                    onClicked: copy(glabLogin)
                }
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
