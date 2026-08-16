# niri port (Fedora 44)

OpenAgentIsland upstream targets **Hyprland** on Arch, on top of the end-4 /
illogical-impulse base. This branch (`niri-port`) runs it on **niri** under
**Fedora 44**, with the Claude Code agent bridge intact.

The distro difference turned out to be the easy half. The real work was that
108 of the 603 QML files reached into `Quickshell.Hyprland` or `hyprctl`, which
cannot work on niri at all.

## The shape of the port

The Hyprland surface area was much smaller than the file count suggested — about
15 distinct call points behind ~180 references. So rather than rewriting call
sites, the port swaps the *implementation* behind the names the shell already uses.

| Layer | File | Role |
|---|---|---|
| niri-native | `quickshell/services/Niri.qml` | Owns `niri msg -j event-stream`; parses every compositor event into live state (workspaces, windows, outputs, keyboard layouts, overview). Reconnects if niri restarts. |
| Hyprland-shaped facade | `quickshell/services/Compositor.qml` | Reproduces the slice of `Quickshell.Hyprland` the shell uses — `dispatch`, `focusedMonitor`, `monitorFor`, `workspaces`, `focusedWorkspace` — on top of `Niri`. |
| Data service | `quickshell/services/HyprlandData.qml` | Same public properties as before (`windowList`, `monitors`, `activeWorkspace`, …), but fed from `Niri` instead of `hyprctl -j`. All ~30 call sites are untouched. |
| Shortcuts | `quickshell/modules/common/NiriShortcut.qml` | Drop-in for `GlobalShortcut` (71 instances), driven by IPC instead of the Hyprland protocol. |

### Key mapping decisions

- **Workspace id** — a Hyprland workspace `id` maps to niri's per-output `idx`,
  because that's the 1..N number the workspace pills and users think in. niri's
  *global* workspace id rides along as `niriId` for issuing actions.
- **Window address** — niri window ids are integers; they're rendered as
  `"0x" + hex` so the shell's existing `address:0x...` string handling works
  unchanged.
- **Dispatch translation** — the shell emits a small closed vocabulary of end-4
  Lua dispatches (`hl.dsp.focus`, `hl.dsp.window.move/close`, `hl.dsp.global`,
  …). `Compositor.dispatch()` pattern-matches these onto `niri msg action`.
  Anything unrecognised is logged, never silently dropped.
- **Toplevel ↔ window** — Hyprland handed the window address straight to the
  Wayland toplevel. niri has no such handle, so `clientForToplevel()` matches on
  app id + title, falling back to the focused window on ties.

### Global shortcuts

niri does not implement `hyprland_global_shortcuts_v1`, so the compositor cannot
push shortcuts into the shell. The direction is inverted: niri keybinds call
back in over Quickshell IPC.

```sh
qs -c openagentisland ipc call shortcuts list                 # 42 names
qs -c openagentisland ipc call shortcuts trigger searchToggle
```

`~/.config/niri/config.kdl` binds the useful ones (Mod+Space launcher, Mod+A /
Mod+N sidebars, Mod+Grave overview, Mod+X session, …).

### Hyprland-only tools replaced

| Upstream | niri / Fedora replacement |
|---|---|
| `hyprsunset` | `gammastep`, via `quickshell/scripts/colors/nightlight.sh`. Wayland resets gamma when the client exits, so gammastep is kept **running** rather than used one-shot. |
| `hyprpicker` | `niri msg -j pick-color`, piped through a hex converter to `wl-copy`. |
| `hyprlock` | `swaylock`. |
| `hyprshot` | niri's built-in `screenshot` / `screenshot-screen` / `screenshot-window`. |

## Fedora 44 notes

`niri` (26.04), `quickshell` (0.2.1) and every helper except two fonts are in
Fedora's official repos — no COPR needed.

- **Not installed:** `power-profiles-daemon` conflicts with the existing **TLP**
  setup, so it was deliberately skipped. The shell's power-profile toggle is
  therefore inert.
- **Fonts:** Material Symbols Rounded, JetBrainsMono Nerd Font, Readex Pro and
  Space Grotesk are installed to `~/.local/share/fonts/openagentisland`.
  **Google Sans Flex is not redistributable** and is unavailable in the open
  `google/fonts` repo — `~/.config/illogical-impulse/config.json` substitutes
  **Inter** (Fedora's `rsms-inter-fonts`). The Nerd Font's real family name is
  `JetBrainsMono Nerd Font`, not upstream's `JetBrains Mono NF`.

## Dev workflow

`tools/run-nested-niri.sh` runs a **nested niri in a window** with the shell
inside it, captures QML errors separately from compositor logs, opens a test
window, screenshots the result and exercises the IPC + agent bridge. This
replaces upstream's nested-Hyprland loop and needs no logout.

```sh
tools/run-nested-niri.sh 25
```

Quickshell still hot-reloads on file save.

## Theming: Dracula + JetBrains Mono

`tools/apply-dracula.sh` is the single entry point. It:

1. writes all 53 Material 3 roles as a hand-mapped Dracula palette to
   `~/.local/state/quickshell/user/generated/colors.json`;
2. sets every shell font role to `JetBrainsMono Nerd Font`;
3. sets `appearance.wallpaperTheming.enable*` to **false**, so changing wallpaper
   no longer regenerates the palette over the top of Dracula.

Re-run it any time to restore the theme. Dracula has no Material "container"
tones, so those are darkened/lightened companions of the accent hues, chosen to
keep Material's contrast pairings readable.

The three islands don't use the Material palette — `modules/ii/island/IslandStyle.qml`
holds their own tokens, plus per-module semantic colours (agent status, battery,
kanban). Those were remapped to Dracula in-source. **One deliberate change:** the
pill was pitch black `#000000`; it is now Dracula's darkest `#191A21`, which still
reads as a black notch but is an actual palette colour. Set `pillColor` back to
`#000000` for the original look.

niri itself is themed in `~/.config/niri/config.kdl`: focus ring Purple, border
Pink, urgent Red, inactive "Current Line", overview backdrop `#191A21`.

**niri has no font option at all** (`font` is an unknown config node) — it exposes
no text styling, so "JetBrains everywhere" covers the shell, not the compositor.

## Gotcha: KDE autostart apps black out the desktop

Symptom: a niri session that is **entirely black**, even though `niri` and
`qs -c openagentisland` are both running and the shell logs "Configuration Loaded"
with no errors.

Cause: `niri --session` runs **xdg-desktop-autostart**, and
`/etc/xdg/autostart/org.kde.xwaylandvideobridge.desktop` has no `OnlyShowIn`, so
KDE's `xwaylandvideobridge` starts under niri too. It opens a genuinely
*fullscreen* window, and the shell's `background.hideWhenFullscreen` then
correctly hides the wallpaper, background and screen corners.

Diagnosis without a working screen — this works over SSH or from a TTY, and does
not need the VT to be active:

```sh
export NIRI_SOCKET=$(ls -t /run/user/1000/niri.wayland-*.sock | head -1)
niri msg -j layers   # expect quickshell:background + quickshell:screenCorners
niri msg -j windows  # look for an unexpected fullscreen window
```

If `quickshell:background` is **missing** from the layer list, something is
being treated as fullscreen. Kill the offender and it reappears immediately.

Fix: `~/.config/autostart/org.kde.xwaylandvideobridge.desktop` overrides the
system copy with `NotShowIn=niri;` — out of niri, unchanged under KDE. Any other
KDE autostart that misbehaves can be handled the same way; `ls /etc/xdg/autostart/`
lists the candidates.

Note that a `grim` screenshot taken while the VT is switched away is **always**
pure black, so it is useless as evidence either way — capture while the session
is actually on screen.

## Known gaps

- **`HyprlandFocusGrab`** (7 sites) uses a Hyprland-only protocol. It no-ops on
  niri rather than breaking input, so popups and sidebars must be dismissed
  explicitly instead of by clicking outside. A niri replacement would need a
  transparent layer-shell catcher with careful stacking.
- **Special workspaces** and **window pinning** have no niri equivalent; those
  dispatches log and no-op.
- **The shell's own lock screen is unported.** `modules/ii/lock/Lock.qml` still
  shells out to `hyprctl dispatch` to shuffle windows on lock/unlock, and
  `LockSurface.qml` reads the layout from the inert `HyprlandXkb`. The core
  `WlSessionLock` (ext-session-lock-v1) would work on niri, but nothing is bound
  to it — locking is handled by swayidle + swaylock instead. Wiring a key to an
  untested locker risks a lockout, so it stays unbound until ported.
- **`HyprlandXkb` / `HyprlandKeybinds` / `HyprlandConfig`** parse Hyprland's
  config and are inert. niri exposes `niri msg keyboard-layouts` if the keyboard
  layout indicator is wanted later.
- **`HyprlandAntiFlashbangShader`** is Hyprland-specific and unused here.
- The `waffle` (Windows 11-style) panel family was ported mechanically along with
  everything else but only the `ii` island family has been exercised.
- `ToolbarTabBar.qml:59` emits one benign `Unable to assign [undefined]` warning
  — pre-existing upstream, unrelated to niri.
