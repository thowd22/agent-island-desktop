# AGENT.md — working with this repo

Guide for humans and coding agents. Read this before changing anything.

This is **Agent Island Desktop**: a macOS-style Dynamic Island desktop for
**niri** on **Fedora**, built in Quickshell/QML, with live Claude Code agent
status and permission approval in the notch.

It is a **fork of [patheonsceo/Dynamic-island-for-arch](https://github.com/patheonsceo/Dynamic-island-for-arch)**
(OpenAgentIsland), which targets Hyprland on Arch and is itself a derivative of
[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland). GPL-3.0 — see
[Licence](#licence).

---

## Repo layout

```
quickshell/          the shell itself (QML) — this is the desktop
  shell.qml          entry point; panel families + IPC handlers
  panelFamilies/     which panels are loaded (register/unregister here)
  modules/ii/island/ THE ISLAND — notch, status row, surfaces
  modules/common/    shared widgets, Appearance tokens, Config
  services/          Niri, Compositor, AgentService, Weather, Battery, …
  scripts/           helper shell scripts invoked from QML
bridge/              Claude Code hooks → Unix socket → the island (Python, stdlib only)
tools/               dev harness + theming script
NIRI-PORT.md         how the Hyprland → niri port works, and its known gaps
```

**Runtime symlink:** `~/.config/quickshell/openagentisland` →
`<repo>/quickshell`. Quickshell only loads configs from
`~/.config/quickshell/<name>/`. **Always edit files in the repo**, not through
the symlink.

---

## Running it

```sh
qs -c openagentisland                 # start the shell
Mod+Ctrl+Shift+S                      # restart it from inside niri
tools/run-nested-niri.sh 25           # nested niri + shell, isolated from your session
```

`tools/run-nested-niri.sh` runs a **nested niri in a window** with the shell
inside it, captures QML errors separately from compositor logs, opens a test
window, screenshots the result and exercises the IPC + agent bridge. Use it for
anything risky — it cannot break your live session.

### Reading errors

```sh
qs log -t 60 "$(ls -t /run/user/1000/quickshell/by-id/*/log.qslog | head -1)"
```

QML failures are warnings in that log, not crashes — the shell keeps running
with a broken component, so **absence of a visible problem is not proof**. Grep
for `Binding loop`, `is not a type`, `ReferenceError`, `Cannot read`.

### Hot reload is unreliable here

Quickshell hot-reloads QML on save, but **changes to `panelFamilies/` were not
picked up** during this port — the shell had to be restarted. When a change
seems to do nothing, restart before debugging further.

---

## Architecture: the niri compat layer

Upstream calls `Quickshell.Hyprland` and `hyprctl` from ~108 QML files, neither
of which exists on niri. Rather than rewrite every call site, the implementation
behind the names was swapped:

| Layer | File | Role |
|---|---|---|
| niri-native | `services/Niri.qml` | Owns `niri msg -j event-stream`; parses events into live state. Reconnects if niri restarts. |
| Hyprland-shaped facade | `services/Compositor.qml` | Reproduces the slice of `Quickshell.Hyprland` the shell uses, on top of `Niri`. Translates end-4 `hl.dsp.*` Lua dispatches into `niri msg action`. |
| Data service | `services/HyprlandData.qml` | Same public properties as upstream, fed from `Niri` instead of `hyprctl`. |
| Shortcuts | `modules/common/NiriShortcut.qml` | Drop-in for `GlobalShortcut`; niri has no `hyprland_global_shortcuts_v1`, so niri keybinds call **in** over IPC instead. |

**Do not reintroduce `hyprctl`, `hyprland`, `hyprsunset`, `hyprpicker`,
`hyprlock` or `hyprshot`.** Check before adding a compositor call:

```sh
grep -rn 'hyprctl\|hyprland' --include='*.qml' quickshell/modules/ quickshell/services/
```

`NIRI-PORT.md` documents the full mapping and the known gaps.

### Shortcuts

```sh
qs -c openagentisland ipc call shortcuts list          # every name the shell answers to
qs -c openagentisland ipc call shortcuts trigger NAME  # fire one
```

niri keybinds in `~/.config/niri/config.kdl` call these.

---

## The island

`modules/ii/island/` — one island, centred at the top of every monitor.

State precedence, highest first:

1. `open` — a named surface is up (dashboard, launcher, overview, power, tools, agent)
2. `hover` — pointer on the notch → the full status row (suppressed while a permission is pending)
3. `expanded` — a transient display: volume, brightness, notification, agent, media
4. `idle` — workspace number, clock, caffeine, weather, battery

Key files:

- `IslandNotch.qml` — the panel, state machine, sizing, transient displays
- `IslandStatusRow.qml` — the hover row; `left half │ agent │ right half`, halves padded to equal width so the agent chip stays on the centre line
- `IslandStyle.qml` — shared tokens (pill colour, text, accent). **Change colours here**, not inline
- `Island.qml` — the open-surface bus (`openSurface`, `openScreen`)

### Layout rules learned the hard way

- **Never hardcode a tile width around a label.** Size to content
  (`Math.max(floor, label.implicitWidth + pad)`). Fixed widths clipped
  "Shut down" and "Performance" when the UI font changed.
- **Anchor both sides, or elide.** An `anchors.left`-only row will happily run
  out of its container.
- **`TapHandler` does not consume a press from a `MouseArea` beneath it.** Both
  fire. The notch's background click handler is disabled during `hover` for
  exactly this reason.
- Open surfaces may declare an `implicitWidth`; the notch grows to it, so a
  surface can outgrow its entry in `surfaceSizes`.

---

## The agent bridge

`bridge/` — Python, standard library only, compositor-agnostic.

```
Claude Code hook → oai_hook.py → $XDG_RUNTIME_DIR/openagentisland.sock → AgentService.qml
```

```sh
python3 bridge/install-hooks.py enable|disable|status   # manages ~/.claude/settings.json (backs it up)
python3 bridge/test_safety.py                           # 13 checks — MUST stay green
```

### The safety contract — do not weaken it

On **any** problem — no socket, refused, timeout, malformed data, unexpected
exception — the hook exits 0 with no stdout, and Claude Code falls back to its
normal prompt. It must never hang or auto-approve. `test_safety.py` proves this;
run it after touching anything in `bridge/`.

### What the island interrupts for

Only two things:

- a permission request **outside** auto mode
- Claude waiting on you (the `Notification` hook → `AgentService.waitingCount`)

`permission_mode` values `auto`, `bypassPermissions`, and `acceptEdits` (for
edit tools) are **ungated** — surfaced as status only. The island gates only what
Claude Code would have prompted for itself. Gating `auto` interrupts the
auto-approval classifier on every single tool call.

Inspect live state:

```sh
qs -c openagentisland ipc call agent status
qs -c openagentisland ipc call agent dump
```

Sessions live in memory, so **restarting the shell clears them** until the next
hook fires. An empty agent display right after a restart is expected, not a bug.

---

## Theming

```sh
tools/apply-dracula.sh     # Dracula palette + JetBrainsMono Nerd Font
```

Writes all 53 Material 3 roles to
`~/.local/state/quickshell/user/generated/colors.json`, sets the font roles, and
**disables wallpaper theming** so changing wallpaper no longer regenerates the
palette over the top. Re-run any time to restore.

The islands do **not** use the Material palette — `IslandStyle.qml` holds their
own tokens, and some modules hardcode semantic colours (agent status, battery,
kanban). Change both if you change the theme.

---

## Conventions

- **Verify what you changed, visually.** `grim` a screenshot and look at it; for
  colours and geometry, sample the actual pixels rather than trusting your eye.
- **To inspect a state you can't reach**, temporarily force it (`hovered: true`,
  a fixed `openSurface`, a suppressed agent), screenshot, then **revert**. Mark
  such edits `// TEMP-VERIFY` and grep for that marker before committing.
- **Fake agent events** instead of waiting for real ones:
  ```sh
  printf '%s' '{"hook_event_name":"Notification","session_id":"t","cwd":"/tmp","message":"hi"}' \
    | python3 bridge/oai_hook.py status
  ```
  Clean up afterwards with a `SessionEnd` for the same id, or it lingers as a
  ghost session for ~5 minutes and pins the island's headline.
- **Avoid `pkill -f`** for anything whose pattern appears in your own command
  line — it matches and kills your shell. Use the PID.
- **Backticks in `git commit -m` are shell-interpreted.** Use `-F <file>`.
- User config lives in `~/.config/illogical-impulse/config.json` and
  `~/.config/niri/config.kdl` — **not** in this repo. Back up before editing.

---

## Licence

**GPL-3.0.** This is a derivative of end-4/dots-hyprland via
patheonsceo/Dynamic-island-for-arch. If you distribute it or a modified version
it must stay GPL-3.0, keep the notices, and provide source. See `LICENSE`.
