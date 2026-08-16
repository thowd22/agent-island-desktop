<h1 align="center">Agent Island Desktop</h1>

<p align="center"><b>A macOS-style Dynamic Island desktop for <a href="https://github.com/YaLTeR/niri">niri</a> on Fedora — with your Claude Code agents living in the notch.</b></p>

<p align="center">Built in <a href="https://quickshell.outfoxxed.me/">Quickshell</a>/QML.</p>

<p align="center"><img src="docs/screenshots/island-hover-niri.png" alt="The island expanded on hover" width="900"></p>

<p align="center"><i>One island. Hovering expands it into the full status row.</i></p>

---

## Credit where it's due

This is a **fork of [patheonsceo/Dynamic-island-for-arch](https://github.com/patheonsceo/Dynamic-island-for-arch)**
(*OpenAgentIsland*) — the original Dynamic Island desktop and, crucially, the
**Claude Code agent bridge**, which is the genuinely novel idea here. That
project targets **Hyprland on Arch**; this fork ports it to **niri on Fedora**
and reworks the layout into a single island.

The desktop chrome underneath both is
**[end-4 / dots-hyprland](https://github.com/end-4/dots-hyprland)** (illogical-impulse).

All of the hard, original design work — the morphing notch, the agent bridge and
its safety model, the surfaces — is theirs. Please star their repos.

- Original project: **[patheonsceo/Dynamic-island-for-arch](https://github.com/patheonsceo/Dynamic-island-for-arch)**
- Framework: **[end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)**
- Toolkit: **[Quickshell](https://quickshell.outfoxxed.me/)**
- Notch interaction techniques studied from **[Hyprfabricated](https://github.com/tr1xem/hyprfabricated)**

GPL-3.0, same as its ancestors.

---

## The headline: Claude Code in your notch

When a Claude Code session needs a decision, the notch morphs open with the
tool, a preview of what it will do, and **Deny · Allow Once · Allow All ·
Bypass** — approved without leaving what you're doing.

The island interrupts for exactly two things:

- a **permission request outside auto mode**
- **Claude waiting on you** — a question, or a session gone idle

In **auto mode it stays out of the way entirely**. Claude Code's own
auto-approval classifier decides, and the island reports status without gating.
It only ever gates what Claude Code would have prompted for itself.

**Safe by design:** the bridge is fire-and-forget. If the island isn't listening,
times out, or anything else goes wrong, the hook exits cleanly and Claude Code
falls back to its normal prompt. It can never hang or break your Claude Code —
13/13 safety checks (`python3 bridge/test_safety.py`).

---

## One island

No bar, no dock, no side panels — a single notch at the top of every monitor.

**Resting:** workspace number · clock · caffeine (when active) · weather ·
battery (always on battery; hidden at 100% when plugged in).

**On hover** it expands into everything else: search · workspace · weather ·
network · CPU/RAM/swap/battery · tray · **agent status, dead centre and
clickable** · media transport · power profile · settings · capture · clock ·
power.

**It also morphs on its own** for volume, brightness, notifications, media (with
a cava visualizer) and agent activity, then returns to resting.

Clicking through opens surfaces in the notch itself: dashboard, app launcher,
workspace overview, power menu, capture tools, and the agent session list.

Multi-monitor throughout — every island renders per-monitor in logical
coordinates, and a surface opens only on the monitor you clicked.

---

## Requirements

- **niri** ≥ 26.04 and **Quickshell** ≥ 0.2.1 — both in Fedora's repos
- **Python 3** (standard library only) for the agent bridge
- **[Claude Code](https://claude.com/claude-code)** — optional; the desktop works fine without it

## Install

```sh
sudo dnf install niri quickshell xwayland-satellite fuzzel swaylock \
                 brightnessctl cliphist matugen cava wl-clipboard grim slurp gammastep

git clone https://github.com/<you>/agent-island-desktop.git ~/Projects/agent-island-desktop
ln -s ~/Projects/agent-island-desktop/quickshell ~/.config/quickshell/openagentisland
```

Fonts (Material Symbols Rounded and a Nerd Font) are required — see
[`NIRI-PORT.md`](NIRI-PORT.md#fedora-44-notes) for exactly which and why one
substitution was needed.

Then apply the theme and enable the agent bridge:

```sh
tools/apply-dracula.sh                        # Dracula + JetBrainsMono Nerd Font
python3 bridge/install-hooks.py enable        # backs up ~/.claude/settings.json first
```

Point niri at the shell in `~/.config/niri/config.kdl`:

```kdl
spawn-at-startup "qs" "-c" "openagentisland"
```

niri has no global-shortcut protocol, so keybinds call the shell over IPC:

```kdl
Mod+Space { spawn "qs" "-c" "openagentisland" "ipc" "call" "shortcuts" "trigger" "searchToggle"; }
```

`qs -c openagentisland ipc call shortcuts list` prints all 42 names.

### Locking

niri has no idle management of its own, so lock and idle are handled by
`swayidle` + `swaylock`:

```kdl
spawn-at-startup "swayidle" "-w" \
  "lock" "swaylock -f" "before-sleep" "swaylock -f" \
  "timeout" "600" "swaylock -f" \
  "timeout" "900" "niri msg action power-off-monitors" \
  "resume" "niri msg action power-on-monitors"
```

The `lock` handler matters: the island's power-menu **Lock** button runs
`loginctl lock-session`, which does nothing unless something is listening for
logind's Lock signal.

Note Fedora ships **vanilla swaylock**, so `screenshots`, `effect-blur` and
`effect-vignette` (swaylock-*effects* options) will stop it starting — which
fails open, leaving the screen unlocked.

For a blurred lock screen without that fork, `~/.config/niri/lock.sh` captures
the screen with `grim`, blurs it with ImageMagick (downscale → blur → upscale,
which is much cheaper than a large-radius blur and matters because `swayidle -w`
holds off suspend until the lock is up), and passes it to `swaylock -i`. The
snapshot goes in `XDG_RUNTIME_DIR` with `umask 077` and is deleted once the lock
is up. If any step fails it still locks, just without the image — locking must
never fail open.

The shell also contains its own themed lock screen (`modules/ii/lock/`), but it
is **not wired up**: `Lock.qml` still shells out to `hyprctl dispatch`, so it is
unported. See [`NIRI-PORT.md`](NIRI-PORT.md#known-gaps).

---

## What's different from upstream

- **niri instead of Hyprland.** ~108 QML files called `Quickshell.Hyprland` or
  `hyprctl`; the implementation behind those names was replaced with a niri IPC
  layer rather than rewriting every call site. See [`NIRI-PORT.md`](NIRI-PORT.md).
- **One island** instead of three — the left and right islands fold into the
  notch's hover row.
- **Hyprland-only tools swapped:** `hyprsunset` → gammastep, `hyprpicker` →
  `niri msg pick-color`, `hyprlock` → swaylock, `hyprshot` → niri's screenshots.
- **Auto mode no longer interrupted** — see above.
- **Dracula + JetBrainsMono Nerd Font**, with the layouts made font-robust.

## Docs

- **[AGENT.md](AGENT.md)** — how to work on this repo: layout, dev harness,
  architecture, conventions, gotchas. Read this first.
- **[NIRI-PORT.md](NIRI-PORT.md)** — the Hyprland → niri mapping and known gaps.
- **[NOTES.md](NOTES.md)** / **[PROGRESS.md](PROGRESS.md)** — upstream's design
  notes and build log, kept for context.

## Licence

**GPL-3.0** — a derivative work of end-4/dots-hyprland via
patheonsceo/Dynamic-island-for-arch. If you distribute it or a modified version,
it must remain GPL-3.0, keep these notices, and provide source. See
[`LICENSE`](LICENSE).
