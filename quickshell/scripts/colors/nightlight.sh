#!/usr/bin/env bash
# Night light for niri, replacing Hyprland's hyprsunset.
#
# Usage: nightlight.sh <temperature_kelvin> [gamma_percent]
#
# Hyprland's hyprsunset is a daemon you poke with `hyprctl hyprsunset ...`.
# niri has no equivalent, so we drive gammastep instead. Note that on Wayland
# the compositor resets the gamma ramps as soon as the controlling client
# disconnects, so gammastep must stay RUNNING — one-shot mode (-O) would apply
# the temperature and immediately lose it. We therefore run it in manual mode
# with the same day/night temperature and restart it on every change.

TEMP="${1:-6000}"
GAMMA_PCT="${2:-100}"

# gammastep wants gamma as a 0.0–1.0 factor; the shell tracks it as a percent.
GAMMA=$(awk "BEGIN { printf \"%.2f\", $GAMMA_PCT / 100 }")

pkill -x gammastep 2>/dev/null

# 6000K at full gamma is the shell's "off" state — leave the ramps reset.
if [ "$TEMP" -ge 6000 ] && [ "$GAMMA_PCT" -ge 100 ]; then
    exit 0
fi

setsid gammastep -m wayland -P -t "${TEMP}:${TEMP}" -g "${GAMMA}" \
    >/dev/null 2>&1 < /dev/null &

exit 0
