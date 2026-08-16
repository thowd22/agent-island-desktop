pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray

/**
 * The island's expanded status row.
 *
 * Everything the separate left and right islands used to carry, folded into the
 * notch and revealed on hover. Rendered BARE — no pill backgrounds — because the
 * notch itself is already the pill; groups are separated by hairlines instead.
 *
 * Layout:  search · workspace │ weather · network │ CPU RAM SWAP BAT │ tray
 *              │ AGENT │
 *          ⏮ ⏯ ⏭ │ perf · settings · capture │ clock · power
 *
 * The agent chip sits on the island's CENTRE LINE. The two halves live in boxes
 * padded to the width of the wider one, so the centre never drifts as content
 * appears and disappears. That matters because the compact notch shows agent
 * status centred: hovering it expands the island, and the chip stays under the
 * pointer instead of sliding away. The padding only applies while the chip is
 * visible, so the row stays compact when no agent is running.
 *
 * Workspace and clock deliberately also appear in the idle state, so expanding
 * reads as more appearing around what was already there, not a widget swap.
 */
Item {
    id: root

    /// Monitor this row belongs to — surfaces open on the screen you clicked.
    property string screenName: ""

    implicitWidth: row.implicitWidth + 28
    implicitHeight: 40

    // ---- small shared bits -------------------------------------------

    component Sep: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 1
        implicitHeight: 16
        color: Qt.rgba(1, 1, 1, 0.13)
    }

    component IconBtn: MaterialSymbol {
        id: btn
        property color hoverColor: IslandStyle.accent
        /// Resting colour. Overriding `color` directly would break the hover
        /// binding, so state-coloured buttons set this instead.
        property color baseColor: IslandStyle.textColor
        signal activated
        Layout.alignment: Qt.AlignVCenter
        iconSize: 18
        fill: 1
        color: btnHover.hovered ? btn.hoverColor : btn.baseColor
        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutQuad } }
        HoverHandler { id: btnHover }
        TapHandler { onTapped: btn.activated() }
    }

    // Progress ring with a metric icon centred (no numbers) — as the right
    // island drew them.
    component MetricRing: Item {
        id: ring
        property string icon
        property real value
        property color ringColor: IslandStyle.textColor
        property int size: 24
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: size
        implicitHeight: size

        CircularProgress {
            anchors.centerIn: parent
            implicitSize: ring.size
            lineWidth: 3
            value: ring.value
            colPrimary: ring.ringColor
            colSecondary: Qt.rgba(1, 1, 1, 0.13)
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: ring.icon
            iconSize: 12
            fill: 1
            color: ring.ringColor
        }
    }

    // Width each half is padded to so the agent chip lands dead centre.
    readonly property real halfWidth: Math.max(leftRow.implicitWidth, rightRow.implicitWidth)

    // ---- the row ------------------------------------------------------

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 9

        // ===== LEFT HALF — hugs the centre, padded on its outer edge =====
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: agentChip.visible ? root.halfWidth : leftRow.implicitWidth
            implicitHeight: leftRow.implicitHeight

            RowLayout {
                id: leftRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                // search → launcher surface
                IconBtn {
                    text: "search"
                    onActivated: Island.toggle("launcher", root.screenName)
                }

                // current workspace number — scroll to switch, click for the overview
                IslandWorkspaceNumber {
                    Layout.alignment: Qt.AlignVCenter
                    screenName: root.screenName
                }

                Sep {}

                // weather + network, drawn bare inside the island
                IslandWeatherPill { bare: true; Layout.alignment: Qt.AlignVCenter }
                IslandNetworkPill { bare: true; Layout.alignment: Qt.AlignVCenter }

                Sep {}

                // resources — click through to the dashboard for the detail view
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: statsRow.implicitWidth
                    implicitHeight: statsRow.implicitHeight

                    RowLayout {
                        id: statsRow
                        anchors.centerIn: parent
                        spacing: 7

                        MetricRing {
                            icon: "speed"
                            value: ResourceUsage.cpuUsage
                            ringColor: ResourceUsage.cpuUsage > 0.9 ? "#FF5555" : IslandStyle.textColor
                        }
                        MetricRing {
                            icon: "memory"
                            value: ResourceUsage.memoryUsedPercentage
                            ringColor: ResourceUsage.memoryUsedPercentage > 0.9 ? "#FF5555" : IslandStyle.textColor
                        }
                        MetricRing {
                            icon: "swap_horiz"
                            value: ResourceUsage.swapUsedPercentage
                            visible: ResourceUsage.swapUsedPercentage > 0
                        }
                        MetricRing {
                            visible: Battery.available
                            icon: Battery.isCharging ? "bolt" : "battery_full"
                            value: Battery.percentage
                            ringColor: (Battery.isLow && !Battery.isCharging) ? "#FF5555"
                                : Battery.isCharging ? IslandStyle.accent : IslandStyle.textColor
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: Island.toggle("dashboard", root.screenName)
                    }
                }

                // system tray — only when something is in it
                Sep { visible: SystemTray.items.values.length > 0 }
                SysTray {
                    Layout.alignment: Qt.AlignVCenter
                    visible: SystemTray.items.values.length > 0
                    showSeparator: false
                }
            }
        }

        // ===== CENTRE — agent status, clickable, on the centre line =====
        Sep { visible: agentChip.visible }
        IslandAgentChip {
            id: agentChip
            Layout.alignment: Qt.AlignVCenter
            screenName: root.screenName
        }
        Sep { visible: agentChip.visible }

        // ===== RIGHT HALF — hugs the centre, padded on its outer edge =====
        Item {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: agentChip.visible ? root.halfWidth : rightRow.implicitWidth
            implicitHeight: rightRow.implicitHeight

            RowLayout {
                id: rightRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9

                // Media transport. The notch has its own media state, but an active
                // agent outranks it — so with a Claude session running you'd never
                // reach the controls. Here they're always one hover away. Shown
                // whenever a player exists, not just while playing, otherwise the
                // controls would vanish the moment you paused and you could never
                // press play.
                RowLayout {
                    id: mediaGroup
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 5
                    visible: MprisController.activePlayer !== null

                    IconBtn {
                        text: "skip_previous"
                        iconSize: 17
                        // Dimmed when the player can't do it, matching the notch's media state.
                        opacity: MprisController.canGoPrevious ? 1 : 0.35
                        onActivated: MprisController.previous()
                    }
                    IconBtn {
                        text: (MprisController.activePlayer?.isPlaying ?? false) ? "pause" : "play_arrow"
                        iconSize: 20
                        onActivated: MprisController.togglePlaying()
                    }
                    IconBtn {
                        text: "skip_next"
                        iconSize: 17
                        opacity: MprisController.canGoNext ? 1 : 0.35
                        onActivated: MprisController.next()
                    }
                }
                Sep { visible: mediaGroup.visible }

                // night light (gammastep — see scripts/colors/nightlight.sh).
                // Lit in the accent colour while it's on, so the icon doubles as
                // the indicator rather than needing a separate one.
                IconBtn {
                    // One glyph, state shown by colour: the power menu already
                    // renders "nightlight", so there's no risk of a missing-symbol
                    // box, and an on/off pair of glyphs would read as two features.
                    text: "nightlight"
                    iconSize: 18
                    fill: Hyprsunset.temperatureActive ? 1 : 0
                    baseColor: Hyprsunset.temperatureActive ? IslandStyle.accent : IslandStyle.textColor
                    opacity: Hyprsunset.temperatureActive ? 1 : 0.75
                    onActivated: Hyprsunset.toggleTemperature()
                }

                // performance profile toggle
                IconBtn {
                    text: !PowerProfiles.hasPerformanceProfile ? "airwave"
                        : PowerProfiles.profile === PowerProfile.Performance ? "local_fire_department"
                        : PowerProfiles.profile === PowerProfile.PowerSaver ? "energy_savings_leaf"
                        : "airwave"
                    onActivated: {
                        if (PowerProfiles.hasPerformanceProfile) {
                            switch (PowerProfiles.profile) {
                            case PowerProfile.PowerSaver: PowerProfiles.profile = PowerProfile.Balanced; break;
                            case PowerProfile.Balanced: PowerProfiles.profile = PowerProfile.Performance; break;
                            case PowerProfile.Performance: PowerProfiles.profile = PowerProfile.PowerSaver; break;
                            }
                        } else {
                            PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced
                                ? PowerProfile.PowerSaver : PowerProfile.Balanced;
                        }
                    }
                }

                // settings → the Quickshell settings window directly. It used to
                // toggle the right sidebar, which was a detour: the sidebar isn't
                // settings, it just contains a shortcut to them. The sidebar is
                // still on Mod+N.
                IconBtn {
                    text: "settings"
                    iconSize: 19
                    onActivated: Quickshell.execDetached(["bash", "-c",
                        `'${Directories.scriptPath.replace(/file:\/\//, "")}/settings.sh'`])
                }

                // capture / screenshot tools
                IconBtn {
                    text: "ink_pen"
                    iconSize: 17
                    onActivated: Island.toggle("tools", root.screenName)
                }

                Sep {}

                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Qt.locale().toString(DateTime.clock.date, "h:mm AP")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: IslandStyle.textColor
                }

                // Caffeine — same place as in the resting island, and clickable
                // here so it can be turned off without opening the dashboard.
                IconBtn {
                    visible: Idle.inhibit
                    text: "coffee"
                    iconSize: 16
                    baseColor: IslandStyle.accent
                    hoverColor: "#FF5555"
                    onActivated: Idle.toggleInhibit()
                }

                IconBtn {
                    text: "power_settings_new"
                    hoverColor: "#FF5555"
                    onActivated: Island.toggle("power", root.screenName)
                }
            }
        }
    }
}
