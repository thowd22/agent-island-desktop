#!/usr/bin/env bash
# Install the desktop's configuration into ~/.config.
#
# The shell itself lives in quickshell/ and is loaded through a symlink; this
# script handles everything AROUND it — the compositor, lock, idle and
# supervision config that makes the desktop a desktop.
#
# Re-runnable. Existing files are backed up to <file>.bak-<timestamp> first.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%s)"
LINK=1   # --copy to install copies instead of symlinks

[ "${1:-}" = "--copy" ] && LINK=0

backup() {
    [ -e "$1" ] && ! [ -L "$1" ] && { cp -a "$1" "$1.bak-$STAMP"; echo "    backed up -> $(basename "$1").bak-$STAMP"; }
    return 0
}

place() { # place <repo-relative src> <dest>
    local src="$REPO/dotfiles/$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    backup "$dest"
    rm -f "$dest"
    if [ "$LINK" -eq 1 ]; then
        ln -s "$src" "$dest"; echo "  linked  $dest"
    else
        cp "$src" "$dest";    echo "  copied  $dest"
    fi
}

echo "Installing desktop config from $REPO"

# Symlinked: hand-edited, and edits should flow back to the repo.
place niri/config.kdl                                  "$CONF/niri/config.kdl"
place niri/lock.sh                                     "$CONF/niri/lock.sh"
place niri/tray-bridge.sh                              "$CONF/niri/tray-bridge.sh"
place swaylock/config                                  "$CONF/swaylock/config"
place systemd/user/agent-island.service                "$CONF/systemd/user/agent-island.service"
place autostart/org.kde.xwaylandvideobridge.desktop    "$CONF/autostart/org.kde.xwaylandvideobridge.desktop"
place autostart/trayscale.desktop                      "$CONF/autostart/trayscale.desktop"

# The shell REWRITES this file whenever you change a setting in its UI, so it is
# copied rather than linked — a symlink would turn every settings tweak into a
# repo diff. __HOME__ is substituted so the paths inside it are portable.
echo "  copying illogical-impulse/config.json (shell rewrites it; not linked)"
mkdir -p "$CONF/illogical-impulse"
backup "$CONF/illogical-impulse/config.json"
sed "s|__HOME__|$HOME|g" "$REPO/dotfiles/illogical-impulse/config.json" \
    > "$CONF/illogical-impulse/config.json"

# The shell is loaded from ~/.config/quickshell/<name>/
mkdir -p "$CONF/quickshell"
if [ ! -e "$CONF/quickshell/openagentisland" ]; then
    ln -s "$REPO/quickshell" "$CONF/quickshell/openagentisland"
    echo "  linked  $CONF/quickshell/openagentisland -> $REPO/quickshell"
fi

chmod +x "$REPO/dotfiles/niri/lock.sh" "$REPO/dotfiles/niri/tray-bridge.sh"

echo
echo "Enabling the shell service..."
systemctl --user daemon-reload
systemctl --user enable agent-island.service
echo
# Power profile control needs root to run tlp. Installed separately because the
# rest of this script needs no privileges — and a malformed sudoers file breaks
# sudo entirely, so it is validated with visudo BEFORE being put in place.
if [ -f /usr/sbin/tlp ] && [ ! -f /etc/sudoers.d/tlp-profile ]; then
    echo
    echo "TLP detected. To let the desktop switch power profiles without a password:"
    echo "  sed 's/__USER__/\$USER/' $REPO/dotfiles/sudoers.d/tlp-profile > /tmp/tlp-profile"
    echo "  sudo visudo -c -f /tmp/tlp-profile && sudo install -m 0440 -o root -g root /tmp/tlp-profile /etc/sudoers.d/tlp-profile"
fi

echo
echo "Done. Next:"
echo "  tools/apply-dracula.sh                  # Dracula + JetBrainsMono Nerd Font"
echo "  python3 bridge/install-hooks.py enable  # Claude Code agent bridge"
echo
echo "  Weather defaults to IP geolocation. To pin a city, set"
echo "  bar.weather.city and bar.weather.enableGPS=false in"
echo "  ~/.config/illogical-impulse/config.json."
echo
echo "  Log out and pick 'niri' at your display manager."
