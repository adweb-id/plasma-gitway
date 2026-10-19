import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

// "Add account…": pick GitHub or GitLab and the host, then sign in with
// gh or glab in a terminal. Gitway never sees the token. When the terminal
// closes, the new account shows up and is picked (see main.qml addAccount).
FocusScope {
    id: page

    required property var widget
    required property var full

    objectName: "addAccountPage"

    property string provider: "github"
    property bool hostEdited: false
    readonly property string host: hostField.text.trim()
    readonly property bool sameHost: provider === "gitlab"
        && widget.accounts.some(a => a.provider === "gitlab" && a.host === host)
    readonly property bool validHost: /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:[0-9]+)?$/.test(host)

    readonly property bool busy: false
    readonly property string hints: widget.addingAccount ? i18n("Finish signing in in the terminal, then close it")
                                                         : i18n("Enter sign in · Esc back")
    readonly property string status: ""

    function choose(next) {
        provider = next;
        if (!hostEdited) {
            hostField.text = next === "gitlab" ? "gitlab.com" : "github.com";
        }
    }

    function signIn() {
        if (validHost && !widget.addingAccount) {
            widget.addAccount(provider, host);
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            full.back();
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            signIn();
        } else {
            return;
        }
        event.accepted = true;
    }

    // One of the two services, as a large selectable row
    component ServiceChoice: PlasmaComponents3.ItemDelegate {
        id: choice

        required property string service
        required property string title
        required property string detail

        Layout.fillWidth: true
        highlighted: page.provider === service
        enabled: !page.widget.addingAccount
        onClicked: page.choose(service)

        contentItem: RowLayout {
            spacing: Kirigami.Units.largeSpacing

            ProviderLogo {
                provider: choice.service
                implicitWidth: Kirigami.Units.iconSizes.medium
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                PlasmaComponents3.Label {
                    text: choice.title
                    font.bold: true
                }
                PlasmaComponents3.Label {
                    Layout.fillWidth: true
                    text: choice.detail
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    wrapMode: Text.Wrap
                }
            }
            SvgIcon {
                visible: choice.highlighted
                name: "check"
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            IconButton {
                iconName: "back"
                toolTip: i18n("Back (Esc)")
                onClicked: page.full.back()
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: i18n("Add account")
                font.bold: true
            }
        }

        ServiceChoice {
            service: "github"
            title: i18n("GitHub")
            detail: i18n("github.com or GitHub Enterprise, signed in with gh")
        }
        ServiceChoice {
            service: "gitlab"
            title: i18n("GitLab")
            detail: i18n("gitlab.com or a self-hosted GitLab, signed in with glab")
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.smallSpacing
            enabled: !page.widget.addingAccount

            PlasmaComponents3.Label {
                text: i18n("Host")
            }
            PlasmaComponents3.TextField {
                id: hostField
                Layout.fillWidth: true
                text: "github.com"
                onTextEdited: page.hostEdited = true
                Keys.onReturnPressed: page.signIn()
                Keys.onEnterPressed: page.signIn()
            }
        }

        PlasmaComponents3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: !page.validHost ? i18n("Enter a host name such as gitlab.example.com.")
                : page.sameHost ? i18n("%1 already has an account here. glab keeps one per host, so the new one gets its own glab folder. Nothing else to do.", page.host)
                : page.provider === "github" ? i18n("A terminal opens with gh auth login. Follow it, then close the terminal.")
                : i18n("A terminal opens with glab auth login. Follow it (a token or the browser), then close the terminal.")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: page.widget.addFoundNothing && !page.widget.addingAccount
            type: Kirigami.MessageType.Warning
            text: i18n("No new account showed up. If the sign-in did not finish, try again.")
        }

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents3.BusyIndicator {
                visible: page.widget.addingAccount
                running: visible
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredWidth: Layout.preferredHeight
            }
            PlasmaComponents3.Label {
                visible: page.widget.addingAccount
                text: i18n("Waiting for the terminal…")
                opacity: 0.7
            }
            PlasmaComponents3.Button {
                text: i18n("Sign in in a terminal")
                enabled: page.validHost && !page.widget.addingAccount
                onClicked: page.signIn()
            }
        }
    }
}
