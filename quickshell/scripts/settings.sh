#!/usr/bin/env bash
# Open the Quickshell settings window.
#
# `qs -p settings.qml` spawns a NEW window every time, so clicking the island's
# gear twice would stack up duplicates. If a settings window is already open,
# focus that instead — on niri, focus-window also switches to its workspace.

CONFIG_DIR="$(cd "$(dirname "$0")/.." && pwd)"

existing_id() {
    command -v niri >/dev/null || return
    niri msg -j windows 2>/dev/null | python3 -c "
import json, sys
try:
    wins = json.load(sys.stdin)
except Exception:
    sys.exit()
for w in wins:
    if w.get('app_id') == 'org.quickshell' and 'Settings' in (w.get('title') or ''):
        print(w['id'])
        break
" 2>/dev/null
}

ID="$(existing_id)"
if [ -n "$ID" ]; then
    exec niri msg action focus-window --id "$ID"
fi

exec qs -p "$CONFIG_DIR/settings.qml"
