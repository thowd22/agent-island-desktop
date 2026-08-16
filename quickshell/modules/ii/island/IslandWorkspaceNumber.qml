pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import Quickshell

/**
 * The current workspace, as a single number.
 *
 * Replaces the row of dots: at a glance you want "which workspace am I on",
 * not the occupancy of all ten. Keeps the dots' useful gestures — scroll to
 * move between workspaces, click to open the overview.
 */
Item {
    id: root

    /// Monitor to open the overview on. Empty falls back to the global toggle.
    property string screenName: ""
    property color textColor: IslandStyle.accent      // Dracula Purple
    property int pixelSize: Appearance.font.pixelSize.normal

    readonly property var monitor: Compositor.monitorFor(root.QsWindow.window?.screen)
    readonly property int activeWs: monitor?.activeWorkspace?.id ?? 1

    // Reserve the width of a two-digit number so stepping 9 → 10 doesn't shove
    // the rest of the island sideways.
    implicitWidth: Math.max(label.implicitWidth, metrics.implicitWidth)
    implicitHeight: label.implicitHeight

    StyledText {
        id: metrics
        visible: false
        text: "00"
        font.pixelSize: root.pixelSize
        font.weight: Font.DemiBold
    }

    // Scroll → switch workspace (absolute target; the relative form no-ops here).
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y < 0)
                Compositor.dispatch(`hl.dsp.focus({workspace = ${root.activeWs + 1}})`);
            else if (event.angleDelta.y > 0)
                Compositor.dispatch(`hl.dsp.focus({workspace = ${Math.max(1, root.activeWs - 1)}})`);
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: {
            if (root.screenName.length > 0)
                Island.toggle("overview", root.screenName);
            else
                GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }

    StyledText {
        id: label
        anchors.centerIn: parent
        text: String(root.activeWs)
        font.pixelSize: root.pixelSize
        font.weight: Font.DemiBold
        color: root.textColor

        // Brief pop when the workspace changes, so the switch registers even
        // though only one glyph is moving.
        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
        scale: 1
        Connections {
            target: root
            function onActiveWsChanged() { popAnim.restart(); }
        }
        SequentialAnimation {
            id: popAnim
            NumberAnimation { target: label; property: "scale"; to: 1.18; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: label; property: "scale"; to: 1.0; duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2.0 }
        }
    }
}
