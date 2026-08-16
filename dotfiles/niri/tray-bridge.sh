#!/usr/bin/env bash
# Bridge legacy XEmbed tray icons into StatusNotifierItem, which is the only
# thing the island's tray reads.
#
# NoMachine's monitor (nxrunner.bin --monitor) is an X11/XEmbed client — it has
# DISPLAY set and no WAYLAND_DISPLAY. XEmbed clients dock into the owner of the
# X11 tray selection ONCE at startup, and silently show nothing if no owner
# existed at that moment. Because the monitor is started by nxserver (a system
# service), it normally wins the race against anything in the user session, so
# after the proxy is up we nudge it into docking.
set -u
export DISPLAY="${DISPLAY:-:0}"

command -v xembedsniproxy >/dev/null || exit 0

pgrep -x xembedsniproxy >/dev/null 2>&1 || setsid xembedsniproxy >/dev/null 2>&1 &

# Give the proxy time to come up and claim the tray selection.
for _ in $(seq 1 20); do
    pgrep -x xembedsniproxy >/dev/null 2>&1 && break
    sleep 0.5
done
sleep 2

registered_items() {
    busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null |
        awk '{print $2}'
}

# Only nudge if the monitor is running yet nothing registered — i.e. it really
# did dock too early. Matched on the full command line so an active NoMachine
# SESSION runner is never killed, only the tray monitor. nxnode respawns it.
if [ "$(registered_items)" = "0" ] && pgrep -f 'nxrunner\.bin --monitor' >/dev/null 2>&1; then
    pkill -f 'nxrunner\.bin --monitor'
fi

exit 0
