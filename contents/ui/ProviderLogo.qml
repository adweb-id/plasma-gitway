import QtQuick
import org.kde.kirigami as Kirigami

// Official GitHub mark or GitLab tanuki in front of accounts and repos.
// The files are used unchanged (see TRADEMARKS.md). The GitHub mark is
// one-colour, so it is tinted with the text colour to read on light and
// dark themes. The tanuki keeps its own colours.
Kirigami.Icon {
    id: logo

    required property string provider

    implicitWidth: Kirigami.Units.iconSizes.small
    implicitHeight: implicitWidth
    source: Qt.resolvedUrl(provider === "gitlab" ? "../icons/gitlab-logo.svg" : "../icons/github-logo.svg")
    isMask: provider !== "gitlab"
    color: Kirigami.Theme.textColor
}
