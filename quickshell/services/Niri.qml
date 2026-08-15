pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live connection to the niri compositor via its IPC event-stream.
 *
 * This is the niri-native layer: it speaks niri's own vocabulary (outputs,
 * windows with integer ids, workspaces with a global `id` and a per-output
 * `idx`). The Hyprland-shaped facade the rest of the shell talks to lives in
 * Compositor.qml, which is built on top of this.
 *
 * niri IPC reference: `niri msg -j <cmd>` and `niri msg -j event-stream`.
 */
Singleton {
    id: root

    // --- niri-native state ---------------------------------------------

    /// All workspaces, niri-native: {id, idx, name, output, is_active, is_focused, active_window_id}
    property var workspaces: []
    /// All windows, niri-native: {id, title, app_id, pid, workspace_id, is_focused, is_floating, layout}
    property var windows: []
    /// Outputs keyed by name: {name, make, model, logical:{x,y,width,height,scale,transform}, ...}
    property var outputs: ({})
    /// Ordered output names, so a stable integer id can be derived per output.
    property var outputNames: []

    property var keyboardLayouts: ({ names: [], current_idx: 0 })
    property bool overviewOpen: false

    property int focusedWindowId: -1
    /// niri's *global* workspace id (not the per-output idx).
    property int focusedWorkspaceId: -1

    readonly property bool connected: eventStream.running

    readonly property var focusedWindow: root.windows.find(w => w.id === root.focusedWindowId) ?? null
    readonly property var focusedWorkspace: root.workspaces.find(w => w.id === root.focusedWorkspaceId) ?? null
    readonly property string focusedOutputName: root.focusedWorkspace?.output ?? ""

    /// Emitted for every compositor event, so services can refresh opportunistically.
    signal event(string name, var data)

    // --- lookups --------------------------------------------------------

    function workspaceById(id) {
        return root.workspaces.find(w => w.id === id) ?? null;
    }

    /// niri global workspace id -> per-output index (what users think of as "workspace 3").
    function idxForWorkspaceId(id) {
        return root.workspaceById(id)?.idx ?? -1;
    }

    /// Per-output index -> niri global workspace id, preferring the given output.
    function workspaceIdForIdx(idx, outputName) {
        const onOutput = root.workspaces.find(w => w.idx === idx && (!outputName || w.output === outputName));
        return (onOutput ?? root.workspaces.find(w => w.idx === idx))?.id ?? -1;
    }

    function windowById(id) {
        return root.windows.find(w => w.id === id) ?? null;
    }

    function windowsForWorkspaceId(id) {
        return root.windows.filter(w => w.workspace_id === id);
    }

    /// Stable integer id for an output, mirroring Hyprland's numeric monitor ids.
    function outputIndex(name) {
        return root.outputNames.indexOf(name);
    }

    // --- actions --------------------------------------------------------

    /// Run `niri msg action <args...>` detached.
    function action(...args) {
        Quickshell.execDetached(["niri", "msg", "action", ...args.map(a => String(a))]);
    }

    function focusWorkspaceIdx(idx) {
        root.action("focus-workspace", idx);
    }

    function focusWorkspaceRelative(delta) {
        root.action(delta > 0 ? "focus-workspace-down" : "focus-workspace-up");
    }

    function focusWindow(id) {
        root.action("focus-window", "--id", id);
    }

    function closeWindow(id) {
        if (id === undefined || id === null) root.action("close-window");
        else root.action("close-window", "--id", id);
    }

    function moveWindowToWorkspaceIdx(windowId, idx, follow) {
        const args = ["move-window-to-workspace"];
        if (windowId !== undefined && windowId !== null) args.push("--window-id", windowId);
        if (follow === false) args.push("--focus", "false");
        args.push(idx);
        root.action(...args);
    }

    function moveFloatingWindow(windowId, x, y) {
        const args = ["move-floating-window"];
        if (windowId !== undefined && windowId !== null) args.push("--id", windowId);
        // niri takes relative ("+10") or absolute ("100") positions; we pass absolute.
        args.push("-x", Math.round(x), "-y", Math.round(y));
        root.action(...args);
    }

    function toggleFloating(windowId) {
        const args = ["toggle-window-floating"];
        if (windowId !== undefined && windowId !== null) args.push("--id", windowId);
        root.action(...args);
    }

    function toggleOverview() {
        root.action("toggle-overview");
    }

    // --- refreshers -----------------------------------------------------

    function refreshOutputs() {
        getOutputs.running = true;
    }

    function refreshAll() {
        getOutputs.running = true;
        getWorkspaces.running = true;
        getWindows.running = true;
    }

    Component.onCompleted: root.refreshAll()

    // --- event stream ---------------------------------------------------

    Process {
        id: eventStream
        running: true
        command: ["niri", "msg", "-j", "event-stream"]

        stdout: SplitParser {
            onRead: line => {
                if (!line || line.length === 0) return;
                let ev;
                try {
                    ev = JSON.parse(line);
                } catch (e) {
                    return; // niri prints non-JSON banners on some versions
                }
                const name = Object.keys(ev)[0];
                if (!name) return;
                root.handleEvent(name, ev[name]);
                root.event(name, ev[name]);
            }
        }

        // If niri restarts (or the stream dies), reconnect rather than going blind.
        onExited: reconnectTimer.restart()
    }

    Timer {
        id: reconnectTimer
        interval: 1000
        repeat: false
        onTriggered: {
            eventStream.running = true;
            root.refreshAll();
        }
    }

    function handleEvent(name, data) {
        switch (name) {
        case "WorkspacesChanged": {
            root.workspaces = data.workspaces ?? [];
            const focused = root.workspaces.find(w => w.is_focused);
            if (focused) root.focusedWorkspaceId = focused.id;
            break;
        }
        case "WorkspaceActivated": {
            // `focused` distinguishes "active on its output" from "keyboard-focused".
            root.workspaces = root.workspaces.map(w => {
                const target = root.workspaceById(data.id);
                if (!target) return w;
                if (w.output !== target.output) return w;
                return Object.assign({}, w, {
                    is_active: w.id === data.id,
                    is_focused: data.focused ? w.id === data.id : w.is_focused
                });
            });
            if (data.focused) root.focusedWorkspaceId = data.id;
            break;
        }
        case "WorkspaceActiveWindowChanged": {
            root.workspaces = root.workspaces.map(w =>
                w.id === data.workspace_id
                    ? Object.assign({}, w, { active_window_id: data.active_window_id })
                    : w);
            break;
        }
        case "WorkspaceUrgencyChanged": {
            root.workspaces = root.workspaces.map(w =>
                w.id === data.id ? Object.assign({}, w, { is_urgent: data.urgent }) : w);
            break;
        }
        case "WindowsChanged": {
            root.windows = data.windows ?? [];
            const focused = root.windows.find(w => w.is_focused);
            root.focusedWindowId = focused?.id ?? -1;
            break;
        }
        case "WindowOpenedOrChanged": {
            const win = data.window;
            if (!win) break;
            const existing = root.windows.findIndex(w => w.id === win.id);
            const next = root.windows.slice();
            if (existing >= 0) next[existing] = win;
            else next.push(win);
            root.windows = next;
            if (win.is_focused) root.focusedWindowId = win.id;
            break;
        }
        case "WindowClosed": {
            root.windows = root.windows.filter(w => w.id !== data.id);
            if (root.focusedWindowId === data.id) root.focusedWindowId = -1;
            break;
        }
        case "WindowFocusChanged": {
            root.focusedWindowId = data.id ?? -1;
            root.windows = root.windows.map(w =>
                Object.assign({}, w, { is_focused: w.id === data.id }));
            break;
        }
        case "WindowUrgencyChanged": {
            root.windows = root.windows.map(w =>
                w.id === data.id ? Object.assign({}, w, { is_urgent: data.urgent }) : w);
            break;
        }
        case "WindowLayoutsChanged": {
            const changes = data.changes ?? [];
            if (changes.length === 0) break;
            const byId = {};
            changes.forEach(([id, layout]) => byId[id] = layout);
            root.windows = root.windows.map(w =>
                byId[w.id] ? Object.assign({}, w, { layout: byId[w.id] }) : w);
            break;
        }
        case "KeyboardLayoutsChanged": {
            root.keyboardLayouts = data.keyboard_layouts ?? ({ names: [], current_idx: 0 });
            break;
        }
        case "KeyboardLayoutSwitched": {
            root.keyboardLayouts = Object.assign({}, root.keyboardLayouts, { current_idx: data.idx ?? 0 });
            break;
        }
        case "OverviewOpenedOrClosed": {
            root.overviewOpen = data.is_open ?? false;
            break;
        }
        case "ConfigLoaded": {
            // Output configuration may have changed with the config.
            root.refreshOutputs();
            break;
        }
        default:
            break;
        }
    }

    // --- one-shot queries (event-stream doesn't carry outputs) -----------

    Process {
        id: getOutputs
        command: ["niri", "msg", "-j", "outputs"]
        stdout: StdioCollector {
            id: outputsCollector
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(outputsCollector.text);
                    root.outputs = parsed;
                    root.outputNames = Object.keys(parsed).sort();
                } catch (e) {
                    console.log("[Niri] failed to parse outputs:", e);
                }
            }
        }
    }

    Process {
        id: getWorkspaces
        command: ["niri", "msg", "-j", "workspaces"]
        stdout: StdioCollector {
            id: workspacesCollector
            onStreamFinished: {
                try {
                    root.workspaces = JSON.parse(workspacesCollector.text);
                    const focused = root.workspaces.find(w => w.is_focused);
                    if (focused) root.focusedWorkspaceId = focused.id;
                } catch (e) {
                    console.log("[Niri] failed to parse workspaces:", e);
                }
            }
        }
    }

    Process {
        id: getWindows
        command: ["niri", "msg", "-j", "windows"]
        stdout: StdioCollector {
            id: windowsCollector
            onStreamFinished: {
                try {
                    root.windows = JSON.parse(windowsCollector.text);
                    const focused = root.windows.find(w => w.is_focused);
                    root.focusedWindowId = focused?.id ?? -1;
                } catch (e) {
                    console.log("[Niri] failed to parse windows:", e);
                }
            }
        }
    }
}
