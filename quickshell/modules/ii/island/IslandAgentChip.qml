pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Agent status, compact, for the island's expanded status row.
 *
 * The notch shows agent status when it owns the display, but hovering swaps the
 * notch to the status row — which used to make the agent vanish exactly as you
 * moved to click it. This carries the same mascot + status word into the row and
 * makes it clickable, opening the agent surface.
 *
 * It is placed on the island's centre line (see IslandStatusRow), so it stays
 * under the pointer that was hovering the compact notch.
 */
Item {
    id: root

    /// Monitor the agent surface should open on.
    property string screenName: ""

    readonly property string mode: AgentService.headlineMode
    readonly property string toast: AgentService.toast

    visible: AgentService.active
    implicitWidth: visible ? chipRow.implicitWidth : 0
    implicitHeight: chipRow.implicitHeight

    RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: 8

        AgentSpinner {
            Layout.alignment: Qt.AlignVCenter
            // Resting presence → the green "running" mascot (alive, no bars).
            mode: root.mode === "idle" ? "running" : (root.mode === "" ? "idle" : root.mode)
            pixel: 2
        }

        AgentStatusText {
            Layout.alignment: Qt.AlignVCenter
            word: root.toast !== "" ? root.toast
                : root.mode === "permission" ? "Needs you"
                : root.mode === "waiting" ? "Waiting"
                : root.mode === "working" ? "Working"
                : root.mode === "done" ? "Done" : "Agent Island"
            animateDots: root.toast === "" && (root.mode === "working" || root.mode === "waiting")
            shimmer: root.toast === "" && (root.mode === "working" || root.mode === "waiting" || root.mode === "permission")
            baseColor: (root.toast !== "" || root.mode === "done") ? "#50FA7B" : IslandStyle.textColor
            pixelSize: Appearance.font.pixelSize.small
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            visible: AgentService.sessionCount > 1
            text: AgentService.sessionCount
            color: IslandStyle.subtextColor
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Island.toggle("agent", root.screenName)
    }
}
