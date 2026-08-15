import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Color picker")
    hasStatusText: false
    toggled: false
    icon: "colorize"

    mainAction: () => {
        GlobalStates.sidebarRightOpen = false;
        delayedActionTimer.start();
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            Quickshell.execDetached(["bash", "-c", 'niri msg -j pick-color | python3 -c \'import json,sys;c=json.load(sys.stdin);v=c.get("rgb") or c.get("color") or [0,0,0];print("#%02x%02x%02x" % tuple(int(round(x*255)) if isinstance(x,float) and x<=1 else int(x) for x in v[:3]))\' | tr -d "[:space:]" | wl-copy']);
        }
    }

    tooltipText: Translation.tr("Color picker")
}
