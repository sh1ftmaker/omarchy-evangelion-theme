# NERV / Evangelion Omarchy theme: shared brief for every subagent

Source of the aesthetic: https://github.com/bizarro/evangelion cloned at ~/Work/evangelion
Read: docs/TREATMENT.md (style bible + plate list), app/src/scenes/_eva.ts (UI kit: chamfered panels,
hex grids, 7-seg digits, seg meters, hazard stripes, evaTitle condensed serif, bilingual labels),
app/src/engine/palette.ts, and the individual plates in app/src/scenes/*.ts for ideas.

## Palette (exact)
ink #050403 (terminal black) · ink2 #120C06 (raised panel) · graphite #4A3218 (dim lines) · ash #9C6A2E
bone #FFE9C8 (warm white, biggest type only) · orange #FF7A00 (PRIMARY HUD colour) · amber #FFB000 (highlight)
red #FF1A1A (EMERGENCY) · blood #6A0000 (red panels) · green #39FF6A (scopes, MAGI approve)
cyan #00C8FF (PATTERN BLUE: targets, Angel) · purple #7A3CFF + lime #B6FF00 (Unit-01: sync/berserk only)

## Type (installed in ~/.local/share/fonts/nerv)
- Title card: "Cormorant Garamond" weight 600, horizontally squeezed to ~60 % (QML: font.family + transform Scale xScale 0.6, or font.stretch), bold, bone/orange.
- Data: "IBM Plex Mono" 500–700, TRACKED CAPS (letterSpacing ~2px), orange.
- Japanese: "Noto Sans CJK JP" / "Noto Serif CJK JP". Bilingual labels everywhere:
  警告 warning · 緊急 emergency · 使徒 Angel · 活動限界 activity limit · 内部電源 internal power · 外部電源 external power
  同調率 sync ratio · 暴走 berserk · 承認 approve · 否決 reject · 解析中 analysing · 目標 target · 第3新東京市 Tokyo-3
  神経接続 neural connection · 心理グラフ psychograph · 使徒接近 Angel approaching · 位相空間 phase space

## Shapes & motion
Chamfered 45° corners (never rounded), solid header tabs with title knocked out in black, corner brackets,
hexagons/hex grids, diagonal hazard stripes, tick scales, crosshairs, range rings, 7-segment digits,
segmented meters, scrolling tickers, hex data filler. CRT scanline texture. No soft gradients, no generic blue sci-fi.
Motion: hard, stepped, terminal-like; alarms blink red; data ticks.

## Do NOT
Use the NERV logo / SEELE logo / Evangelion wordmark literally. Genre language (MAGI names, PATTERN BLUE,
SOUND ONLY, bilingual captions, condensed serif cards) is encouraged.

## Layout on disk (each agent owns ONLY its listed paths)
- Theme: ~/.config/omarchy/themes/evangelion/   (slug "evangelion")
- Plugins: ~/.config/omarchy/plugins/zalo.nerv-*/  (manifest id == dir name)
- Shell plugin docs: /usr/share/omarchy/shell/README.md, /usr/share/omarchy/shell/plugins/README.md,
  /usr/share/omarchy/shell/plugins/bar/README.md, services/PluginRegistry.qml; examples in /usr/share/omarchy/shell/plugins/*
  (READ-ONLY: never edit /usr/share/omarchy). Shell theme singleton: /usr/share/omarchy/shell/Commons/{Style,Color}.qml
- Display: single monitor eDP-1 2560x1600 @ scale 2 (1280x800 logical). Keep desktop widgets compact.
- Machine: 16 threads, NVIDIA GPU (nvidia-smi available), lm_sensors, pipewire (pw-cat/parec). No numpy/PIL/cava.

## Rules
- Do not hand-edit ~/.config/omarchy/shell.json and do not run `omarchy theme set` unless your task says so.
  Enabling your own plugin with `omarchy plugin enable <id>` / `omarchy bar move` is fine for testing.
- Keep CPU cost low (poll ≥1s for system stats; Canvas repaints only when data changes; ≤30fps animations).
- Verify: `journalctl --user -n 80 --no-pager | grep -i -E "qml|quickshell|warn|error"` or the shell log, and screenshot with
  `grim /tmp/x.png` (then Read the PNG) to visually check your work. Crop with `grim -g "x,y wxh"`.

## Desktop wall (phase 2)
All desktop HUD panels pack into one wall defined by ~/.config/omarchy/nerv-wall.json (read it). Each desktop
plugin must: read its rect from that file by its plugin id (FileView with watchChanges, fall back to its hard-coded
default rect), scale the 1280x800 reference by the screen's logical size, place a PanelWindow on WlrLayer.Bottom
(wallpaper is Background) that is click-through (mask: Region {}), keyboardFocus None, no exclusive zone,
fill exactly its rect. Panel fill alpha from `fillAlpha`. Visual reference for panel chrome (chamfer, header tab
with knocked-out title, brackets, scanlines): ~/.config/omarchy/plugins/zalo.nerv-tactical/NervPanel.qml and
zalo.nerv-psychograph/NervFrame.qml — match them so the wall reads as ONE interface.
Performance: pause all animation when every screen's active workspace has windows (see how zalo.nerv-tactical
does it), poll data ≥2s, ≤30fps animation, redraw Canvas only on change. Plugin kind: `panel` with
keepLoaded: true (like zalo.nerv-psychograph). Workspace focus uses Lua syntax:
`hyprctl dispatch 'hl.dsp.focus({ workspace = "9" })'`. Shell log: `quickshell log --pid $(pgrep -x quickshell)`.
Hot-reload caches sibling QML files: after editing non-entry files run `omarchy restart shell` (other agents do too —
that's fine). Never leave test processes running (kill any ffplay/tone generators you start — use `-t` AND verify).

## Smooth motion (phase 3)
User wants every wall panel to ANIMATE at the monitor refresh rate (eDP-1 = 60 Hz; Qt 6.11 / Quickshell 0.3.1)
for style, while DATA sampling stays slow (1–3 s). Rules:
- Drive motion with `FrameAnimation` (vsync-locked, gives frameTime/elapsedTime) or Qt property Animations —
  never a fixed-interval Timer for motion. Use time-based motion (position = f(elapsedTime)), not per-tick increments.
- Interpolate between data samples: ease values toward the latest sample every frame (exponential smoothing
  on frameTime), scroll traces continuously by a fractional pixel offset between samples, etc.
- Keep it cheap at 60 fps: animate with GPU-side transforms (rotation, x/y, opacity, scale, clip-scrolling a
  pre-painted Item/Canvas, ShaderEffect) instead of repainting large Canvases every frame. If a Canvas must redraw
  per frame, keep it small, or use renderTarget: Canvas.FramebufferObject + renderStrategy: Canvas.Threaded where it helps.
  Prefer Shape/Rectangle items whose properties change over Canvas repaints.
- Keep the existing pause-when-covered logic: FrameAnimation.running must be false when windows cover the desktop
  (and when hidden) so the covered cost stays ~0.
- Deliberately stepped/blinking "terminal" effects (blinks, 7-seg digits, hard lock-on snaps) may stay stepped — the
  smoothness is for sweeps, scrolling traces, meters, glows, tickers, data packets.
- Measure: shell CPU visible vs covered, per plugin in an isolated test instance
  (`quickshell -n -p <tmpdir with shell.qml loading only your plugin>` as previous agents did) — report numbers.
  Target: each panel ≤ ~6% of one core at 60 fps visible, ~0 covered.
- Verify smoothness: grab a burst of screenshots (e.g. `for i in $(seq 8); do grim -g ... f$i.png; sleep 0.016; done`)
  and confirm motion advances by small consistent steps; also check `hyprctl layers` rect unchanged.
