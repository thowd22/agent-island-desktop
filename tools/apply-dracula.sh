#!/usr/bin/env bash
# Apply the Dracula palette and the JetBrains font to the island shell.
#
# The shell normally derives its Material 3 palette from the wallpaper via
# matugen, writing ~/.local/state/quickshell/user/generated/colors.json. This
# script writes that file directly with a hand-mapped Dracula palette and turns
# wallpaper theming OFF, so changing wallpaper no longer overwrites the theme.
#
# Re-run it any time to restore Dracula (e.g. after toggling theming back on).
set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated"
CONFIG_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json"
FONT="${OAI_FONT:-JetBrainsMono Nerd Font}"

mkdir -p "$STATE_DIR"

python3 - "$STATE_DIR/colors.json" "$CONFIG_JSON" "$FONT" <<'PY'
import json, os, shutil, sys

colors_path, config_path, font = sys.argv[1], sys.argv[2], sys.argv[3]

# --- Dracula (https://draculatheme.com/contribute) -----------------------
bg          = "#282a36"  # Background
bg_dark     = "#21222c"
bg_darker   = "#191a21"
line        = "#44475a"  # Current Line / Selection
line_high   = "#343746"
line_higher = "#424450"
fg          = "#f8f8f2"  # Foreground
comment     = "#6272a4"
cyan        = "#8be9fd"
green       = "#50fa7b"
pink        = "#ff79c6"
purple      = "#bd93f9"
red         = "#ff5555"

# Dracula has no "container" tones, so those are darkened/lightened companions
# of the accent hues, chosen to keep Material's contrast pairings readable.
# Keys map to Appearance.m3colors via snake_case -> m3camelCase, so every key
# here must have a matching property (no "source_color" — there is no m3sourceColor).
M3 = {
    "background": bg,
    "on_background": fg,
    "surface": bg,
    "surface_dim": bg_dark,
    "surface_bright": line,
    "surface_container_lowest": bg_darker,
    "surface_container_low": bg_dark,
    "surface_container": bg,
    "surface_container_high": line_high,
    "surface_container_highest": line_higher,
    "on_surface": fg,
    "surface_variant": line,
    "on_surface_variant": "#c3cae0",
    "inverse_surface": fg,
    "inverse_on_surface": bg,
    "outline": comment,
    "outline_variant": line,
    "shadow": "#000000",
    "scrim": "#000000",
    "surface_tint": purple,

    # Purple is Dracula's signature -> primary
    "primary": purple,
    "on_primary": bg_dark,
    "primary_container": "#4a3374",
    "on_primary_container": "#ece0ff",
    "inverse_primary": "#6a4bab",

    "secondary": pink,
    "on_secondary": bg_dark,
    "secondary_container": "#7d2f5c",
    "on_secondary_container": "#ffdcef",

    "tertiary": cyan,
    "on_tertiary": bg_dark,
    "tertiary_container": "#14555f",
    "on_tertiary_container": "#c9f4ff",

    "error": red,
    "on_error": bg_dark,
    "error_container": "#7a1f1f",
    "on_error_container": "#ffdad6",

    "success": green,
    "on_success": bg_dark,
    "success_container": "#1c5c2e",
    "on_success_container": "#c9ffd6",

    "primary_fixed": "#ece0ff",
    "primary_fixed_dim": purple,
    "on_primary_fixed": "#22005d",
    "on_primary_fixed_variant": "#4a3374",

    "secondary_fixed": "#ffdcef",
    "secondary_fixed_dim": pink,
    "on_secondary_fixed": "#3b0025",
    "on_secondary_fixed_variant": "#7d2f5c",

    "tertiary_fixed": "#c9f4ff",
    "tertiary_fixed_dim": cyan,
    "on_tertiary_fixed": "#002f36",
    "on_tertiary_fixed_variant": "#14555f",
}

with open(colors_path, "w") as f:
    json.dump(M3, f, indent=2)
print(f"wrote {len(M3)} colour roles -> {colors_path}")

# --- shell config: fonts + stop wallpaper theming overwriting us ---------
if os.path.exists(config_path):
    shutil.copy(config_path, config_path + ".bak-dracula")
    cfg = json.load(open(config_path))
else:
    cfg = {}

appearance = cfg.setdefault("appearance", {})

fonts = appearance.setdefault("fonts", {})
for role in ("main", "numbers", "title", "monospace", "iconNerd", "reading", "expressive"):
    fonts[role] = font

theming = appearance.setdefault("wallpaperTheming", {})
theming["enableAppsAndShell"] = False   # keep our colors.json authoritative
theming["enableQtApps"] = False
theming["enableTerminal"] = False

json.dump(cfg, open(config_path, "w"), indent=2)
print(f"fonts -> {font}")
print("wallpaper theming disabled (Dracula stays put across wallpaper changes)")
PY

echo
echo "Restart the shell to see it:  qs -c openagentisland  (or Mod+Ctrl+Shift+S in niri)"
