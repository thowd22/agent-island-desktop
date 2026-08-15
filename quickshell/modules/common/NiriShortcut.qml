import QtQuick
import qs.services

/**
 * Drop-in replacement for Quickshell.Hyprland's GlobalShortcut, for niri.
 *
 * niri does not implement hyprland_global_shortcuts_v1, so GlobalShortcut is
 * inert there ("The active compositor does not support hyprland_global_shortcuts_v1").
 * This keeps the exact same shape — `name`, `description`, `onPressed`,
 * `onReleased` — but is driven by Compositor.globalShortcut instead.
 *
 * Two things fire these:
 *   - niri keybinds, via `qs -c openagentisland ipc call shortcuts trigger <name>`
 *     (see the `shortcuts` IpcHandler in shell.qml, and binds in ~/.config/niri/config.kdl)
 *   - in-shell `Compositor.dispatch('hl.dsp.global("quickshell:<name>")')` calls
 *
 * Non-visual: sits at the top level of a Scope/PanelWindow like the original did.
 */
Item {
    id: root

    property string name: ""
    property string description: ""

    signal pressed
    signal released

    visible: false
    width: 0
    height: 0

    Component.onCompleted: Compositor.registerShortcut(root.name)

    Connections {
        target: Compositor

        function onGlobalShortcut(shortcutName) {
            if (shortcutName === root.name)
                root.pressed();
        }

        function onGlobalShortcutReleased(shortcutName) {
            if (shortcutName === root.name)
                root.released();
        }
    }
}
