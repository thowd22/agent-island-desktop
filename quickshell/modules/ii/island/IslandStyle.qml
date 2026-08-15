pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// Shared design tokens for all three floating islands, so left / notch / right
// stay visually consistent (geometry, solid space-black surface, accents).
Singleton {
    id: root

    // Geometry
    readonly property int margin: 4            // gap from the screen edge (top/left/right)
    readonly property int pillHeight: 32       // island height
    readonly property int hPadding: 10         // inner horizontal padding
    readonly property real radius: Appearance.rounding.full

    // Surface — Dracula's darkest shade rather than pure black. It still reads as
    // a black notch (rgb 25,26,33) so the Dynamic Island look survives, but it is
    // an actual Dracula colour instead of sitting outside the palette.
    // For the original pitch-black pill, set this back to "#000000".
    readonly property color pillColor: "#191A21"
    readonly property color pillBorder: Appearance.colors.colLayer0Border
    readonly property int borderWidth: 1

    // Content colors — Dracula
    readonly property color textColor: "#F8F8F2"        // Foreground: primary text / used indicators
    readonly property color subtextColor: "#6272A4"     // Comment: secondary text
    readonly property color accent: "#BD93F9"           // Purple: current workspace, highlights
    readonly property real inactiveOpacity: 0.45        // unused / dim elements
}
