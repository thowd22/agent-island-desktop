pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

/**
 * Hyprland-shaped facade over niri.
 *
 * The shell was written against Quickshell.Hyprland, which cannot work on niri
 * (no $HYPRLAND_INSTANCE_SIGNATURE, no hyprctl). Rather than rewrite ~180 call
 * sites, this singleton reproduces the small slice of that API the shell
 * actually uses — dispatch / focusedMonitor / monitorFor / workspaces /
 * focusedWorkspace — backed by Niri.qml.
 *
 * Deliberate shape choices:
 *  - A Hyprland workspace `id` maps to niri's per-output `idx`, because that's
 *    the 1..N number users and the workspace pills think in. niri's *global*
 *    workspace id is kept alongside as `niriId` for issuing actions.
 *  - A Hyprland window `address` maps to niri's integer window id, rendered as
 *    hex with an "0x" prefix so existing `address:0x...` string handling works.
 */
Singleton {
    id: root

    // --- address <-> niri window id ------------------------------------

    function addressForWindowId(id) {
        return "0x" + Number(id).toString(16);
    }

    function windowIdForAddress(address) {
        if (address === undefined || address === null) return -1;
        const hex = String(address).replace(/^address:/, "").replace(/^0x/, "");
        const parsed = parseInt(hex, 16);
        return isNaN(parsed) ? -1 : parsed;
    }

    // --- monitors -------------------------------------------------------

    /// niri reports transforms as strings; Hyprland (and the overview maths,
    /// which does `transform % 2`) expects the numeric wl_output convention.
    readonly property var transformNumbers: ({
        "Normal": 0, "_90": 1, "_180": 2, "_270": 3,
        "Flipped": 4, "Flipped90": 5, "Flipped180": 6, "Flipped270": 7
    })

    /// Hyprland-shaped monitor built from a niri output.
    function monitorFromOutput(name) {
        const out = Niri.outputs[name];
        if (!out) return null;
        const logical = out.logical ?? ({ x: 0, y: 0, width: 0, height: 0, scale: 1 });
        const activeWs = Niri.workspaces.find(w => w.output === name && w.is_active);
        return {
            id: Niri.outputIndex(name),
            name: name,
            description: `${out.make ?? ""} ${out.model ?? ""}`.trim(),
            x: logical.x ?? 0,
            y: logical.y ?? 0,
            width: logical.width ?? 0,
            height: logical.height ?? 0,
            scale: logical.scale ?? 1,
            transform: root.transformNumbers[logical.transform ?? "Normal"] ?? 0,
            // [left, top, right, bottom] space reserved by layer-shell panels.
            // The islands float rather than reserving space, so nothing is taken.
            reserved: [0, 0, 0, 0],
            focused: name === Niri.focusedOutputName,
            activeWorkspace: activeWs ? root.workspaceFromNiri(activeWs) : null
        };
    }

    readonly property var focusedMonitor: Niri.focusedOutputName
        ? root.monitorFromOutput(Niri.focusedOutputName)
        : null

    /// Accepts a Quickshell screen (ShellScreen) and returns its monitor.
    function monitorFor(screen) {
        if (!screen) return null;
        return root.monitorFromOutput(screen.name);
    }

    // --- workspaces -----------------------------------------------------

    /**
     * Wayland toplevels living on a workspace, shaped like HyprlandWorkspace.toplevels.
     *
     * Hyprland handed out toplevels per workspace directly; niri has no such link,
     * so match ToplevelManager entries against the workspace's windows by app id
     * and title. Each entry is wrapped as {wayland: <Toplevel>} to match the
     * `toplevel.wayland?.x` access pattern the shell uses.
     */
    function toplevelsForWorkspaceId(niriWorkspaceId) {
        const wins = Niri.windowsForWorkspaceId(niriWorkspaceId);
        if (wins.length === 0) return [];
        return ToplevelManager.toplevels.values
            .filter(t => wins.some(w => (w.app_id ?? "") === (t.appId ?? "")
                                     && (w.title ?? "") === (t.title ?? "")))
            .map(t => ({ wayland: t }));
    }

    function workspaceFromNiri(ws) {
        if (!ws) return null;
        return {
            id: ws.idx,               // the 1..N number the UI thinks in
            niriId: ws.id,            // niri's global id, for actions
            name: ws.name ?? String(ws.idx),
            monitor: { name: ws.output, id: Niri.outputIndex(ws.output) },
            urgent: ws.is_urgent ?? false,
            active: ws.is_active ?? false,
            focused: ws.is_focused ?? false,
            // Only workspaces with windows are "occupied"; niri always keeps one
            // empty trailing workspace per output, which shouldn't light up a pill.
            windows: Niri.windowsForWorkspaceId(ws.id).length,
            toplevels: ({ values: root.toplevelsForWorkspaceId(ws.id) })
        };
    }

    /// Mirrors Hyprland.workspaces (an object exposing `.values`), so existing
    /// `Connections { target: Hyprland.workspaces; onValuesChanged }` still fire.
    readonly property QtObject workspaces: QtObject {
        readonly property var values: Niri.workspaces
            .filter(ws => (Niri.windowsForWorkspaceId(ws.id).length > 0) || ws.is_active)
            .map(ws => root.workspaceFromNiri(ws))
    }

    readonly property var focusedWorkspace: root.workspaceFromNiri(Niri.focusedWorkspace)

    // --- global shortcuts ----------------------------------------------

    /**
     * niri has no hyprland_global_shortcuts_v1, so `hl.dsp.global("quickshell:x")`
     * can't round-trip through the compositor. Modules listen to this signal
     * instead, and niri keybinds reach the same handlers via IpcHandler.
     */
    signal globalShortcut(string name)
    signal globalShortcutReleased(string name)

    /// Every shortcut name a live NiriShortcut is listening for. Populated by the
    /// components themselves, so `qs ipc call shortcuts list` always reflects reality.
    property var knownShortcuts: []

    function registerShortcut(name) {
        if (!name || root.knownShortcuts.indexOf(name) >= 0) return;
        root.knownShortcuts = root.knownShortcuts.concat([name]).sort();
    }

    // --- dispatch translation -------------------------------------------

    /**
     * Translate an end-4 Lua dispatch string into niri actions.
     *
     * The shell emits a small, closed vocabulary of `hl.dsp.*` calls; each is
     * matched here and mapped onto `niri msg action`. Anything unrecognised is
     * logged rather than silently dropped, so gaps surface during porting.
     */
    function dispatch(command) {
        const cmd = String(command);

        // hl.config({...}) — Hyprland runtime config (cursor warps, etc). No niri analogue.
        if (cmd.startsWith("hl.config")) return;

        // hl.dsp.global("quickshell:name")
        const globalMatch = cmd.match(/hl\.dsp\.global\(\s*["']([^"']+)["']/);
        if (globalMatch) {
            const name = globalMatch[1].replace(/^quickshell:/, "");
            root.globalShortcut(name);
            return;
        }

        // hl.dsp.workspace.toggle_special(...) — niri has no special workspace.
        if (cmd.includes("toggle_special")) {
            console.log("[Compositor] special workspaces are not supported on niri; ignoring:", cmd);
            return;
        }

        // hl.dsp.window.pin(...) — niri has no pin (window on all workspaces).
        if (cmd.includes("hl.dsp.window.pin")) {
            console.log("[Compositor] window pinning is not supported on niri; ignoring:", cmd);
            return;
        }

        const addressMatch = cmd.match(/window\s*=\s*["']address:([^"']+)["']/);
        const windowId = addressMatch ? root.windowIdForAddress(addressMatch[1]) : -1;

        // hl.dsp.window.close({window = "address:0x..."})
        if (cmd.includes("hl.dsp.window.close")) {
            Niri.closeWindow(windowId >= 0 ? windowId : undefined);
            return;
        }

        // hl.dsp.window.move({...}) — either to a workspace, or a floating move.
        if (cmd.includes("hl.dsp.window.move")) {
            const wsMatch = cmd.match(/workspace\s*=\s*(\d+)/);
            if (wsMatch) {
                const follow = !/follow\s*=\s*false/.test(cmd);
                Niri.moveWindowToWorkspaceIdx(windowId >= 0 ? windowId : undefined,
                                              parseInt(wsMatch[1], 10), follow);
                return;
            }
            const xMatch = cmd.match(/x\s*=\s*["']?(-?[\d.]+)/);
            const yMatch = cmd.match(/y\s*=\s*["']?(-?[\d.]+)/);
            if (xMatch && yMatch) {
                Niri.moveFloatingWindow(windowId >= 0 ? windowId : undefined,
                                        parseFloat(xMatch[1]), parseFloat(yMatch[1]));
                return;
            }
            console.log("[Compositor] unhandled window.move:", cmd);
            return;
        }

        // hl.dsp.focus({...}) — a window, or a workspace (absolute or relative).
        if (cmd.includes("hl.dsp.focus")) {
            if (addressMatch) {
                if (windowId >= 0) Niri.focusWindow(windowId);
                return;
            }
            const relMatch = cmd.match(/workspace\s*=\s*["']r([+-])(\d+)["']/);
            if (relMatch) {
                const delta = (relMatch[1] === "+" ? 1 : -1) * parseInt(relMatch[2], 10);
                Niri.focusWorkspaceRelative(delta);
                return;
            }
            const wsMatch = cmd.match(/workspace\s*=\s*(\d+)/);
            if (wsMatch) {
                Niri.focusWorkspaceIdx(parseInt(wsMatch[1], 10));
                return;
            }
            console.log("[Compositor] unhandled focus:", cmd);
            return;
        }

        console.log("[Compositor] unhandled dispatch:", cmd);
    }
}
