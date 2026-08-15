pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

/**
 * Compositor window/workspace/monitor data, in the shape the shell expects.
 *
 * Originally this shelled out to `hyprctl -j`. On niri it is fed from Niri.qml's
 * event stream instead, but the property and function surface is unchanged so
 * the ~30 call sites across the shell keep working untouched.
 *
 * Field mapping (niri -> Hyprland):
 *   id            -> address ("0x" + hex)
 *   app_id        -> class
 *   workspace_id  -> workspace.id (as the per-output idx)
 *   layout.window_size -> size
 *   is_floating   -> floating
 */
Singleton {
    id: root

    property var windowList: []
    property var addresses: []
    property var windowByAddress: ({})
    property var workspaces: []
    property var workspaceIds: []
    property var workspaceById: ({})
    property var activeWorkspace: null
    property var monitors: []
    property var layers: ({})

    // --- Convenient stuff (unchanged API) -------------------------------

    function toplevelsForWorkspace(workspace) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const win = root.clientForToplevel(toplevel);
            return win?.workspace?.id === workspace;
        });
    }

    function hyprlandClientsForWorkspace(workspace) {
        return root.windowList.filter(win => win.workspace.id === workspace);
    }

    /**
     * Map a Wayland toplevel to a compositor window.
     *
     * Hyprland exposed the window address directly on the toplevel; niri has no
     * such handle, so match on app id + title instead. Titles are unique enough
     * in practice, and ties fall back to the focused window.
     */
    function clientForToplevel(toplevel) {
        if (!toplevel) return null;
        const appId = toplevel.appId ?? "";
        const title = toplevel.title ?? "";

        const exact = root.windowList.filter(w => w.class === appId && w.title === title);
        if (exact.length === 1) return exact[0];
        if (exact.length > 1) {
            return exact.find(w => w.address === Compositor.addressForWindowId(Niri.focusedWindowId)) ?? exact[0];
        }
        return root.windowList.find(w => w.class === appId) ?? null;
    }

    function biggestWindowForWorkspace(workspaceId) {
        const windowsInThisWorkspace = root.windowList.filter(w => w.workspace.id == workspaceId);
        return windowsInThisWorkspace.reduce((maxWin, win) => {
            const maxArea = (maxWin?.size?.[0] ?? 0) * (maxWin?.size?.[1] ?? 0);
            const winArea = (win?.size?.[0] ?? 0) * (win?.size?.[1] ?? 0);
            return winArea > maxArea ? win : maxWin;
        }, null);
    }

    // --- Internals (kept for API compatibility; niri pushes, not polls) --

    function updateWindowList() { root.rebuildWindows(); }
    function updateMonitors() { root.rebuildMonitors(); }
    function updateWorkspaces() { root.rebuildWorkspaces(); }
    function updateLayers() { getLayers.running = true; }

    function updateAll() {
        root.rebuildWindows();
        root.rebuildMonitors();
        root.rebuildWorkspaces();
        root.updateLayers();
    }

    // --- niri -> Hyprland shape -----------------------------------------

    function rebuildWindows() {
        const out = Niri.windows.map(w => {
            const ws = Niri.workspaceById(w.workspace_id);
            const layout = w.layout ?? ({});
            const size = layout.window_size ?? [0, 0];
            const tilePos = layout.tile_pos_in_workspace_view;
            const offset = layout.window_offset_in_tile ?? [0, 0];
            const output = ws ? Niri.outputs[ws.output] : null;
            const originX = output?.logical?.x ?? 0;
            const originY = output?.logical?.y ?? 0;

            return {
                address: Compositor.addressForWindowId(w.id),
                niriId: w.id,
                title: w.title ?? "",
                class: w.app_id ?? "",
                initialClass: w.app_id ?? "",
                pid: w.pid ?? -1,
                workspace: {
                    id: ws?.idx ?? -1,
                    name: ws?.name ?? String(ws?.idx ?? "")
                },
                monitor: ws ? Niri.outputIndex(ws.output) : -1,
                size: [size[0] ?? 0, size[1] ?? 0],
                at: tilePos
                    ? [originX + tilePos[0] + (offset[0] ?? 0), originY + tilePos[1] + (offset[1] ?? 0)]
                    : [originX, originY],
                floating: w.is_floating ?? false,
                fullscreen: false,
                xwayland: false,
                focused: w.is_focused ?? false,
                urgent: w.is_urgent ?? false
            };
        });

        root.windowList = out;
        const byAddress = {};
        out.forEach(w => byAddress[w.address] = w);
        root.windowByAddress = byAddress;
        root.addresses = out.map(w => w.address);
    }

    function rebuildWorkspaces() {
        // Hyprland only ever listed workspaces that exist; niri keeps a trailing
        // empty one per output, so drop empties that aren't currently active.
        const out = Niri.workspaces
            .filter(ws => Niri.windowsForWorkspaceId(ws.id).length > 0 || ws.is_active)
            .map(ws => Compositor.workspaceFromNiri(ws))
            .filter(ws => ws && ws.id >= 1 && ws.id <= 100);

        root.workspaces = out;
        const byId = {};
        out.forEach(ws => byId[ws.id] = ws);
        root.workspaceById = byId;
        root.workspaceIds = out.map(ws => ws.id);
        root.activeWorkspace = Compositor.workspaceFromNiri(Niri.focusedWorkspace);
    }

    function rebuildMonitors() {
        root.monitors = Niri.outputNames
            .map(name => Compositor.monitorFromOutput(name))
            .filter(m => m !== null);
    }

    // Rebuild whenever the compositor state changes.
    Connections {
        target: Niri
        function onWindowsChanged() { root.rebuildWindows(); }
        function onWorkspacesChanged() { root.rebuildWorkspaces(); root.rebuildWindows(); }
        function onOutputsChanged() { root.rebuildMonitors(); root.rebuildWindows(); }
        function onFocusedWorkspaceIdChanged() { root.rebuildWorkspaces(); }
        function onFocusedWindowIdChanged() { root.rebuildWindows(); }
    }

    Component.onCompleted: root.updateAll()

    Process {
        id: getLayers
        command: ["niri", "msg", "-j", "layers"]
        stdout: StdioCollector {
            id: layersCollector
            onStreamFinished: {
                try {
                    root.layers = JSON.parse(layersCollector.text);
                } catch (e) {
                    root.layers = ({});
                }
            }
        }
    }
}
