#!/bin/bash
# Install the Evangelion / NERV Omarchy theme with its fonts, shell plugins, hooks and the nerv-alert CLI.
#
#   ./install.sh            install everything and switch to the theme
#   ./install.sh --no-apply install, but don't run `omarchy theme set evangelion`
#
# The theme is copied (not cloned) into ~/.config/omarchy/themes/evangelion so Omarchy treats it as a
# user theme and keeps its hyprland.lua / neovim.lua (themes cloned by `omarchy theme install` lose those).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config/omarchy"
THEME_DIR="$CFG/themes/evangelion"
APPLY=1
[[ ${1:-} == --no-apply ]] && APPLY=0

command -v omarchy >/dev/null || { echo "omarchy not found: this theme is for Omarchy (https://omarchy.org)" >&2; exit 1; }

say() { printf '\033[38;2;255;122;0m::\033[0m %s\n' "$*"; }

say "Theme -> $THEME_DIR"
mkdir -p "$THEME_DIR"
for f in "$REPO"/*.toml "$REPO"/*.lua "$REPO"/btop.theme "$REPO"/chromium.theme "$REPO"/icons.theme \
         "$REPO"/keyboard.rgb "$REPO"/unlock.png "$REPO"/preview.png; do
  [[ -e $f ]] && cp "$f" "$THEME_DIR/"
done
rm -rf "$THEME_DIR/backgrounds"
cp -r "$REPO/backgrounds" "$THEME_DIR/backgrounds"

say "Fonts (Cormorant Garamond, IBM Plex Mono) -> ~/.local/share/fonts/nerv"
mkdir -p "$HOME/.local/share/fonts/nerv"
cp "$REPO"/extras/fonts/*.ttf "$REPO/extras/fonts/OFL.txt" "$HOME/.local/share/fonts/nerv/"
fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true

say "Shell plugins -> $CFG/plugins"
mkdir -p "$CFG/plugins"
for p in "$REPO"/extras/plugins/*/; do
  id="$(basename "$p")"
  rm -rf "$CFG/plugins/$id"
  cp -r "$p" "$CFG/plugins/$id"
done
find "$CFG/plugins" -path '*zalo.nerv-*' \( -name '*.py' -o -name '*.sh' \) -exec chmod +x {} +

say "Wall layout -> $CFG/nerv-wall.json"
if [[ -e $CFG/nerv-wall.json ]]; then
  echo "   (kept your existing nerv-wall.json; the default is in extras/config/nerv-wall.json)"
else
  cp "$REPO/extras/config/nerv-wall.json" "$CFG/nerv-wall.json"
fi

say "nerv-alert -> ~/.local/bin"
mkdir -p "$HOME/.local/bin"
install -m 755 "$REPO/extras/bin/nerv-alert" "$HOME/.local/bin/nerv-alert"

say "Hooks"
omarchy hook install theme-set "$REPO/extras/hooks/theme-set.d/nerv-mode" >/dev/null
omarchy hook install theme-set "$REPO/extras/hooks/theme-set.d/nerv-sync-start" >/dev/null
omarchy hook install battery-low "$REPO/extras/hooks/battery-low.d/nerv-activity-limit" >/dev/null

say "Rescanning shell plugins"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

if (( APPLY )); then
  say "Applying theme (the theme-set hook enables the NERV widgets and desktop wall)"
  omarchy theme set evangelion
  # hot reload caches sibling QML files; a restart loads every plugin file fresh
  omarchy restart shell >/dev/null 2>&1 || true
fi

say "Done. 起動完了 — try: nerv-alert pattern-blue \"Angel approaching\""
