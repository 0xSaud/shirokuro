# 🍚 Rice Documentation

> A complete reference for this Hyprland setup — components, theming, keybinds, scripts and config layout.
> Generated 2026-11-11. Host: Fedora 43 (kernel 7.2.13).

---

## 1. Overview

| Layer | Choice |
|---|---|
| **OS** | Fedora Linux 43 |
| **Compositor** | Hyprland 0.56.2 (Wayland) |
| **Shell / bar** | Quickshell 0.3.2 (QML) — replaces Waybar + dunst + rofi |
| **Login** | SDDM (gnome-keyring unlocked via PAM) |
| **Terminal** | kitty |
| **File manager** | dolphin |
| **Lock screen** | hyprlock |
| **Idle daemon** | hypridle |
| **Wallpaper** | swww-daemon (hyprpaper.conf kept as fallback) |
| **Notifications** | Quickshell notification server |
| **Polkit agent** | polkit-kde-authentication-agent-1 |
| **Network** | NetworkManager + nm-applet |
| **Clipboard** | cliphist + wl-clipboard (text & image history) |
| **Qt theming** | qt6ct (`QT_QPA_PLATFORMTHEME=qt6ct`) |

**Design language — "Ink" (redesigned 2026-11-14):** built around the
black-and-white katana wallpaper. Black lacquer surfaces, white and steel-grey
text, and ONE accent: seal red `#ce4539`, used sparingly. Selections are
reversed (pale block, black text) rather than coloured. Dark scheme.

- **Seal:** `~/.config/quickshell/assets/seal.png`, a red hanko-style stamp of
  the handle "reouii", drawn by `themes/bin/gen-seal.py`. It is the launcher
  button on the bar and is stamped on the fastfetch picture.
- **Bar:** top, 34px, flush black strip with a hairline under it. Left: seal,
  workspaces numbered in kanji (active one sits on a small red seal), readings.
  Centre: time and date. Right: windows, tray, battery, volume, mic, layout,
  power. No pills. `"kanjiWorkspaces": false` in settings.json gives digits.
- **Launcher (ALT+Space):** a full-width band that drops from under the bar;
  results run left to right as tiles. Left/Right to move, Enter to open.
- **Control Center (SUPER+N):** a centred dashboard of tiles: clock/GIF tile, eight
  icon switches, upright volume and brightness bars (drag or scroll), power
  profile, notifications, and a row of shortcuts to the pickers. Esc closes it.
- **Music (SUPER+O):** a record deck along the bottom of the screen: cover art as
  the sleeve, a record that slides out and turns while playing, seek line,
  transport, and the playing app's own volume. No scrim, takes no focus.
- **Pickers:** black cards with a red stroke and bold title (`Overlay.qml`).
- **Power menu:** five cards headed 一 二 三 四 五; arrows or 1-5, Enter.
- **Notifications:** black cards, top-right.
- **Windows:** rounding 8, gaps 5/12, 1px pale hairline on the focused window,
  soft shadow, blur, slight dim on unfocused.
- **Terminal:** JetBrains Mono (icons via Nerd Font symbol_map), 90% opaque so
  the wallpaper shows faintly, beam cursor.
- **fastfetch:** logo box is 30x12 cells = 300x300px (cell is 10x25px), so the
  square picture is not stretched. Keep width = height x 2.5 if the font changes.
- **Palette:** source `#cf2a27`, vivid 1.25, **mono 1**, deep 1.4, scheme dark.
  Generator knobs in `gen-colors.py` / `settings.json`: `mono` (grey surfaces,
  one accent), `deep` (darker accent), `paper` (sand light scheme, unused now).
- **Shell colours follow the theme:** `apply-colors.sh` also writes the
  starship palette block and `~/.config/themes/shell-theme.zsh`.

**Original design (everforest, pill bar):** snapshot with screenshots at
`~/rice-snapshots/20261114-045237-everforest/`; run its `restore.sh` to go back.

Sections below still describe keybinds, scripts and layout accurately; where
they mention the top bar, rounding, blur or the old palette, the list above wins.

---

## 2. Hardware & Monitors

- **Internal panel:** `eDP-1` — laptop screen, positioned `0x0`, scale 1.
- **External:** `HDMI-A-1` — LG monitor, positioned `1920x0` (right of laptop), scale 1.
- **GPU:** Intel iGPU + NVIDIA hybrid (software cursors forced — see note below).

**Per-monitor workspace pinning**

| Workspace | Monitor |
|---|---|
| 1, 11 | eDP-1 (laptop) |
| 2, 12 | HDMI-A-1 (external) |

> **Software cursors** (`no_hardware_cursors = true`) are forced because the
> hybrid GPU left a frozen "ghost" cursor on the idle screen at login.

---

## 3. Theming System

A custom theming pipeline lives in `~/.config/themes/`.

**Current state** (`~/.config/themes/state.json`):
- Theme: **everforest**
- Wallpaper: `~/Pictures/Wallpapers/thumb-19a20-613357.png`

**Active palette** (`~/.config/quickshell/theme.json`):
| Role | Hex |
|---|---|
| bg | `#091610` |
| bg_alt | `#222c27` |
| fg | `#d8e6df` |
| accent | `#36e0a1` |
| accent_fg | `#003824` |
| urgent | `#ffb3b0` |

**Quickshell settings** (`~/.config/quickshell/settings.json`): manual color mode,
source color `#3adfa1`, dark scheme, panel opacity 0.78, motion 0.9, font scale 1.08.

**16 built-in themes** (`~/.config/themes/themes/`):
catppuccin · coffee · cyber · dracula · everforest · gruvbox · kanagawa ·
monokai · nord · onedark · pink · rosepine · sakura · solarized · sunset · tokyonight

**Fonts**
- Display / Body: **Adwaita Sans**
- Mono: **FiraCode Nerd Font Propo**

**Theming scripts** (`~/.config/themes/bin/`):
| Script | Purpose |
|---|---|
| `apply-theme.sh` | Apply a full theme |
| `apply-colors.sh` | Regenerate color config (writes `hypr/theme.conf`) |
| `apply-wallpaper.sh` | Set wallpaper via swww |
| `gen-colors.py` | Material-style palette generation from a source color |
| `theme-picker.sh` / `wallpaper-picker.sh` / `gif-picker.sh` | Pickers |
| `restore-session.sh` | Restores saved theme + wallpaper at login |
| `power-profile.sh` | Cycle Eco → Balanced → Performance |
| `power-menu.sh` | rofi power menu (fallback) |
| `sysinfo.sh` / `wifi-menu.sh` / `restore-brightness.sh` | Helpers |

> Border colors are written to `~/.config/hypr/theme.conf` (sourced last so it
> overrides defaults) and regenerated by the theme picker.

---

## 4. Keybindings

**Modifier:** `$mainMod = SUPER` (Windows key)

### Apps & Window Management
| Keys | Action |
|---|---|
| `SUPER + Q` | Terminal (kitty) |
| `SUPER + E` | File manager (dolphin) |
| `SUPER + C` | Close active window |
| `SUPER + M` | Exit Hyprland |
| `SUPER + V` | Toggle floating |
| `SUPER + F` | Fullscreen |
| `SUPER + S` | Toggle split (dwindle) |
| `SUPER + ALT + P` | Pseudotile |
| `SUPER + SHIFT + R` | Reload config live |
| `SUPER + P` | Cycle power profile |

### Launchers & Panels (Quickshell)
| Keys | Action |
|---|---|
| `ALT + Space` | App launcher |
| `SUPER + /` | Keybind cheatsheet |
| `ALT + Tab` | Window switcher |
| `SUPER + T` | Theme panel |
| `SUPER + W` | Wallpaper panel |
| `SUPER + G` | GIF panel |
| `SUPER + I` | Settings |
| `SUPER + A` | Audio |
| `SUPER + B` | Hide / show the bar |
| `CTRL + B` | Clipboard history |
| `SUPER + D` | Calendar |
| `SUPER + N` | Control center |
| `SUPER + O` | Music |
| `SUPER + Escape` | Power menu |

### Screenshots & Recording
| Keys | Action |
|---|---|
| `Print` / `SUPER + SHIFT + S` | Screenshot region (swappy annotate) |
| `SUPER + Print` | Screenshot active window |
| `SHIFT + Print` | Screenshot whole monitor |
| `CTRL + Print` | Region → clipboard only |
| `SUPER + SHIFT + P` | Color picker (hyprpicker, hex to clipboard) |
| `SUPER + ALT + R` | Record region |
| `SUPER + ALT + S` | Record screen |
| `SUPER + ALT + X` | Stop recording |

> Screenshots land in `~/Pictures/Screenshots`.

### Focus, Movement & Workspaces
| Keys | Action |
|---|---|
| `SUPER + H / L / K / J` | Focus left / right / up / down (vim keys) |
| `SUPER + drag LMB` | Move window |
| `SUPER + drag RMB` | Resize window |
| `SUPER + 1–9, 0` | Switch to workspace |
| `SUPER + SHIFT + 1–9, 0` | Move window to workspace |

### Hardware / Media
| Keys | Action |
|---|---|
| `SUPER + Up / Down` | Brightness (screen under mouse) |
| `SUPER + Right / Left` | Volume up / down |
| `XF86MonBrightness Up/Down` | Laptop brightness ±10 (persists) |
| `ALT + XF86MonBrightness Up/Down` | External LG monitor brightness ±10 |
| `XF86Audio Raise/Lower/Mute` | Volume / mute |
| `SUPER + Space` | Toggle keyboard layout (us ↔ ara) |
| `END` | Dual-screen master toggle |

### Scratchpads
| Keys | Action |
|---|---|
| `SUPER + ` ` (grave) | Dropdown terminal (kitty, respawns on exit) |
| `SUPER + SHIFT + ` ` | Dropdown notes (kwrite on `~/notes.md`) |

---

## 5. Look & Feel (Hyprland)

**General:** gaps_in 5, gaps_out 10, border 2px, layout `dwindle`.
Active border follows theme accent; inactive is muted.

**Decoration:** rounding 10, blur enabled (size 3, 1 pass).

**Animations** (centiseconds; decelerating curves for "fast & smooth"):
- Custom beziers: `easeOutQuint`, `easeOutCubic`, `almostLinear`, `quick`
- Windows pop in at 87%, layers fade, workspaces slide — all tuned cheap for the iGPU.

**Misc:** Hyprland logo/splash disabled, software cursors forced.

**Keyboard:** `kb_layout = us,ara` (English + Arabic), toggled with `SUPER + Space`.

### Window Rules
- **pavucontrol** → floating glass sidebar, top-right (400×500, 90% opacity, pinned, slide-in).
- **scratch-term** → floating, centered, 70%×60% of monitor.
- **kwrite notes** → floating, centered, 70%×60% of monitor.

---

## 6. Autostart (`exec-once`)

- dbus activation environment update
- `scripts/start-shell.sh` → launches Quickshell (with retry logic)
- swww-daemon (wallpaper)
- `themes/bin/restore-session.sh` → restore theme + wallpaper
- polkit-kde auth agent
- nm-applet
- cliphist watchers (text + image)
- hypridle

> gnome-keyring is **not** started here — SDDM/PAM already unlocks it
> (starting it again caused a keyring password prompt).

---

## 7. Idle & Lock

**hypridle** (`hypridle.conf`): idle lock / screen-off / auto-suspend are
**all disabled** for long unattended uptime. Lock manually via `SUPER + Escape`.
Still locks before sleep and restores DPMS on resume.

**hyprlock** (`hyprlock.conf`): blurred screenshot background, centered password
field, giant clock (112px), date, and `$USER@hostname` footer.
> Note: header says "tokyonight" but the color palette is custom — auto-generated by the rice refresh.

---

## 8. Scripts (`~/.config/hypr/scripts/`)

| Script | Purpose |
|---|---|
| `start-shell.sh` | Launch Quickshell with retry (survives early compositor crashes) |
| `brightness.sh` | Per-screen brightness (laptop + external DDC), persists to `brightness.json` |
| `screenshot.sh` | region / window / screen / regioncp modes (grim + slurp + swappy) |
| `scratchpad.sh` | Dropdown terminal / notes toggler |
| `dual-screen-toggle.sh` | Toggle external monitor on/off (`END` key) |
| `clipboard-menu.sh` | Clipboard history picker (rofi fallback) |

---

## 9. Quickshell Components (`~/.config/quickshell/`)

`shell.qml` (93k) is the main bar. Panels invoked via `qs ipc call panels <name>`:

`AudioPanel` · `BluetoothPanel` · `CalendarPanel` · `Cheatsheet` ·
`ClipboardPanel` · `ColourPicker` · `GifPicker` · `Launcher` · `Lock` ·
`MediaPanel` · `Overlay` · `PowerMenu` · `Settings` · `WallpaperPicker` ·
`WifiPanel` · `WindowSwitcher`

State/config JSON: `colors.json`, `theme.json`, `settings.json`, `gif.json`.

---

## 10. File Layout

```
~/.config/hypr/
├── hyprland.conf        # main config
├── theme.conf           # auto-generated border colors (sourced last)
├── hypridle.conf        # idle management
├── hyprlock.conf        # lock screen
├── hyprpaper.conf       # wallpaper fallback (swww is primary)
├── SHORTCUTS.md         # keybind notes
├── RICE.md              # this file
└── scripts/             # helper scripts

~/.config/quickshell/    # QML shell (bar, panels, launcher, lock)
~/.config/themes/
├── bin/                 # theme/wallpaper/color/power scripts
├── themes/              # 16 theme JSONs
├── kitty/               # kitty theme files
├── state.json           # active theme + wallpaper
└── brightness.json      # persisted brightness

~/Pictures/
├── Wallpapers/          # wallpaper library
├── Screenshots/         # screenshot output
├── gifs/                # GIF wallpapers/overlays
└── wallpaper.jpg        # hyprpaper fallback target
```

---

## 11. Tooling Cheat Sheet

| Task | Command |
|---|---|
| Reload Hyprland | `SUPER + SHIFT + R` or `hyprctl reload` |
| Active keyboard layout | `hyprctl devices \| grep active_keymap` |
| Restart the bar | `pkill qs; ~/.config/hypr/scripts/start-shell.sh` |
| Call a panel | `qs ipc call panels <name>` |
| Hyprland version | `hyprctl version` |

---

*Rollback configs kept alongside active ones: `hyprland.conf.bak`,
`hyprland.conf.before-rule-conversion`, `hyprland.conf.before-smooth`.*
