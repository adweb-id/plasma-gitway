import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_hideArchived: archivedCheck.checked
    property alias cfg_includeOrgs: orgsCheck.checked
    property alias cfg_syncOnOpen: syncOnOpenCheck.checked

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
    }
}
