#!/bin/bash
# run-nested.sh [seconds] — start a nested niri, run the island shell inside it,
# and capture the shell's QML errors separately from niri's own log.
SP="${TMPDIR:-/tmp}/openagentisland-nested"
mkdir -p "$SP"
DUR="${1:-20}"
CFG="$(cd "$(dirname "$0")" && pwd)/nested-niri.kdl"
NLOG="$SP/niri.log"
QLOG="$SP/qs.log"

pkill -f "niri -c $CFG" 2>/dev/null
rm -f "$NLOG" "$QLOG"

setsid niri -c "$CFG" >"$NLOG" 2>&1 &
NIRI_PID=$!

# Wait for the compositor to publish its Wayland + IPC sockets.
for _ in $(seq 1 60); do
    SOCK=$(sed -n 's/.*IPC listening on: //p' "$NLOG" | tail -1)
    WD=$(sed -n 's/.*listening on Wayland socket: //p' "$NLOG" | tail -1)
    [ -n "$SOCK" ] && [ -n "$WD" ] && break
    sleep 0.2
done

if [ -z "$SOCK" ] || [ -z "$WD" ]; then
    echo "!! nested niri failed to start; see $NLOG"
    cat "$NLOG"
    kill "$NIRI_PID" 2>/dev/null
    exit 1
fi

echo "nested niri up: WAYLAND_DISPLAY=$WD NIRI_SOCKET=$SOCK"
echo "--- running shell for ${DUR}s ---"

export WAYLAND_DISPLAY="$WD" NIRI_SOCKET="$SOCK" XDG_CURRENT_DESKTOP=niri

# Start the shell in the background so we can screenshot it while it runs.
timeout "$DUR" qs -c openagentisland >"$QLOG" 2>&1 &
QS_PID=$!

# Give the shell time to build its panels, then open a window so the
# workspace pills and window-list have something real to show.
sleep 6
setsid alacritty >/dev/null 2>&1 &
sleep 5

grim "$SP/island.png" 2>/dev/null && echo "screenshot: $SP/island.png" || echo "grim failed"

echo "--- IPC: shortcuts the shell is listening for ---"
qs -c openagentisland ipc call shortcuts list 2>&1 | tee "$SP/shortcuts.txt" | wc -l | sed 's/^/  count: /'

echo "--- agent bridge: sending a fake Claude Code session to the island ---"
ls -la "${XDG_RUNTIME_DIR:-/run/user/1000}/openagentisland.sock" 2>&1 | sed 's/^/  /'
printf '%s' '{"hook_event_name":"SessionStart","session_id":"niri-port-test","cwd":"/home/admin2/Projects/openagentisland","transcript_path":"/tmp/x.jsonl"}' \
    | python3 $(cd "$(dirname "$0")/.." && pwd)/bridge/oai_hook.py status
echo "  status hook exit: $?"
printf '%s' '{"hook_event_name":"UserPromptSubmit","session_id":"niri-port-test","cwd":"/home/admin2/Projects/openagentisland","prompt":"port the island to niri"}' \
    | python3 $(cd "$(dirname "$0")/.." && pwd)/bridge/oai_hook.py status
echo "  prompt hook exit: $?"
sleep 2
grim "$SP/island-agent.png" 2>/dev/null && echo "screenshot: $SP/island-agent.png"

wait $QS_PID 2>/dev/null
echo "shell exited: $?"

kill "$NIRI_PID" 2>/dev/null
pkill -f "niri -c $CFG" 2>/dev/null
echo "--- shell log: $QLOG ($(wc -l <"$QLOG") lines) ---"
