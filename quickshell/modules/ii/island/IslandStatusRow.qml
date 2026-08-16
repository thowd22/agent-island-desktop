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
 * Layout:  search · workspaces │ weather · network │ CPU RAM SWAP BAT │ tray │
 *          perf · settings · capture │ clock · power
 *
 * Workspaces and the clock deliberately also appear in the idle state, so
 * expanding reads as "more appears around what was already there" rather than a
 * different widget swapping in.
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
        signal activated
        Layout.alignment: Qt.AlignVCenter
        iconSize: 18
        fill: 1
        color: btnHover.hovered ? btn.hoverColor : IslandStyle.textColor
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

    // ---- the row ------------------------------------------------------

    RowLayout {
        id: row
        anchors.centerIn: parent
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

        Sep {}

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

        // settings → right sidebar
        IconBtn {
            text: "settings"
            iconSize: 19
            onActivated: GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
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

        IconBtn {
            text: "power_settings_new"
            hoverColor: "#FF5555"
            onActivated: Island.toggle("power", root.screenName)
        }
    }
}
