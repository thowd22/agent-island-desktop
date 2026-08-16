pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Power profile, backed by TLP.
 *
 * Quickshell's `PowerProfiles` (and `powerprofilesctl`) require
 * power-profiles-daemon, which CONFLICTS with TLP — installing it uninstalls
 * TLP. On a TLP machine those are inert, which is why the profile controls did
 * nothing.
 *
 * `profile` is read from the kernel's platform_profile via
 * scripts/power-profile.sh, so it reflects what is actually applied — including
 * the switches TLP makes by itself when you plug in or unplug, which no
 * UI-side cache would know about.
 */
Singleton {
    id: root

    /// Highest → lowest performance. Matches TLP's own command names.
    readonly property var stops: ["performance", "balanced", "power-saver"]

    property string profile: "balanced"
    readonly property bool available: root.profile !== ""

    readonly property string scriptPath:
        `${Directories.scriptPath}/power-profile.sh`.replace(/file:\/\//, "")

    function refresh() {
        getProc.running = true;
    }

    function setProfile(p) {
        if (root.stops.indexOf(p) < 0)
            return;
        root.profile = p;            // optimistic; reconciled by the re-read below
        setProc.command = ["bash", "-c", `'${root.scriptPath}' set ${p}`];
        setProc.running = true;
    }

    function cycle() {
        const i = root.stops.indexOf(root.profile);
        root.setProfile(root.stops[(i + 1) % root.stops.length]);
    }

    /// Material icon for the current profile.
    function iconFor(p) {
        switch (p) {
        case "performance": return "local_fire_department";
        case "power-saver": return "energy_savings_leaf";
        default: return "balance";
        }
    }

    Process {
        id: setProc
        // Re-read afterwards so the UI snaps back if TLP rejected the change.
        onExited: getProc.running = true
    }

    Process {
        id: getProc
        command: ["bash", "-c", `'${root.scriptPath}' get`]
        stdout: SplitParser {
            onRead: data => {
                const v = data.trim();
                if (v.length > 0)
                    root.profile = v;
            }
        }
    }

    Component.onCompleted: root.refresh()

    // TLP changes the profile itself when the power source changes. Refresh on
    // that event rather than polling — polling a sysfs file forever is exactly
    // the kind of idle work that kept the compositor busy before.
    Connections {
        target: Battery
        function onIsPluggedInChanged() { refreshDelay.restart(); }
        function onChargeStateChanged() { refreshDelay.restart(); }
    }
    Timer {
        id: refreshDelay
        interval: 1500   // let TLP apply its new profile first
        onTriggered: root.refresh()
    }
}
