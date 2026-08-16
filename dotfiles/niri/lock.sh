#!/usr/bin/env bash
# Lock the screen showing a blurred snapshot of what was on it.
#
# Fedora ships vanilla swaylock, which has no blur — `effect-blur` belongs to the
# swaylock-effects fork, which isn't packaged. But swaylock does accept an image
# (-i), so we blur a grim capture ourselves.
#
# Locking must NEVER fail open: if the capture or the blur fails for any reason,
# we still lock, just without the image.
set -u
umask 077   # the snapshot is a picture of your desktop — keep it private

# XDG_RUNTIME_DIR is a 0700 tmpfs that's cleared at logout; /tmp is not.
RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
SHOT="$RUNTIME/lock-blur.png"

blur() {
    command -v grim >/dev/null && command -v magick >/dev/null || return 1
    grim "$SHOT" 2>/dev/null || return 1
    # Downscale, blur, upscale: visually the same as a large-radius blur but far
    # cheaper. Speed matters because swayidle -w holds off suspend until we've
    # locked. The colorize dims it slightly so the indicator stays readable.
    magick "$SHOT" -resize 25% -blur 0x5 -resize 400% \
        -fill '#282a36' -colorize 15% "$SHOT.tmp" 2>/dev/null || return 1
    mv -f "$SHOT.tmp" "$SHOT" 2>/dev/null || return 1
    return 0
}

if blur; then
    # -f daemonizes after the image is loaded and the lock is up.
    swaylock -f -i "$SHOT" -s fill
    rc=$?
    # The image is in memory by now; don't leave a desktop snapshot lying around.
    rm -f "$SHOT"
    [ "$rc" -eq 0 ] && exit 0
fi

# Fallback: plain lock, flat Dracula background from ~/.config/swaylock/config.
rm -f "$SHOT"
exec swaylock -f
