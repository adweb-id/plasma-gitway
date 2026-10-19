import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_hideArchived: archivedCheck.checked
    property alias cfg_includeOrgs: orgsCheck.checked
    property alias cfg_syncOnOpen: syncOnOpenCheck.checked
    property alias cfg_assignToMe: assignCheck.checked
    property alias cfg_deleteSourceBranch: deleteSourceCheck.checked
    property alias cfg_openAfterCreate: openAfterCheck.checked

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
