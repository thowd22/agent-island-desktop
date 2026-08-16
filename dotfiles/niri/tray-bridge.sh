#!/usr/bin/env bash
# Bridge legacy XEmbed tray icons into StatusNotifierItem, which is the only
# thing the island's tray reads.
#
# Two ordering traps this has to survive:
#
#  1. niri starts XWayland ON DEMAND — there is no X server at login until some
#     X client connects. Starting xembedsniproxy before that just fails, so we
#     wait for the display to answer first.
#  2. XEmbed clients dock into the owner of the X11 tray selection ONCE at
#     startup and silently show nothing if no owner existed then. NoMachine's
#     monitor is started by nxserver (a system service) and normally wins that
#     race, so once the proxy is up we nudge it into docking.
#
# Also re-runnable by hand: if XWayland is ever restarted, every X client dies
# with it, including the proxy — just run this again.
set -u
export DISPLAY="${DISPLAY:-:0}"

command -v xembedsniproxy >/dev/null || exit 0

# 1. Wait for an X server to exist (up to ~60s), rather than failing instantly.
x_ready() { timeout 2 xprop -root >/dev/null 2>&1; }
for _ in $(seq 1 120); do
    x_ready && break
    sleep 0.5
done
x_ready || exit 0   # no XWayland this session; nothing to bridge

# 2. Start the proxy if it isn't already up.
if ! pgrep -x xembedsniproxy >/dev/null 2>&1; then
    setsid xembedsniproxy >/dev/null 2>&1 &
    sleep 2
fi

registered_items() {
    busctl --user get-property org.kde.StatusNotifierWatcher /StatusNotifierWatcher \
        org.kde.StatusNotifierWatcher RegisteredStatusNotifierItems 2>/dev/null |
        awk '{print $2}'
}

# 3. Nudge XEmbed clients that docked before the proxy existed. Matched on the
#    full command line so an active NoMachine SESSION runner is never killed,
#    only the tray monitor — which nxnode respawns by itself.
if [ "$(registered_items)" = "0" ] && pgrep -f 'nxrunner\.bin --monitor' >/dev/null 2>&1; then
    pkill -f 'nxrunner\.bin --monitor'
fi

exit 0
