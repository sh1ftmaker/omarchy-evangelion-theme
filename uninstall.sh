#!/bin/bash
# Remove the NERV plugins, hooks and CLI. Switch to another theme first so the theme-set hook puts the
# stock bar widgets back. The theme folder, fonts and nerv-wall.json are left in place unless --all is given.
set -uo pipefail
CFG="$HOME/.config/omarchy"

if [[ $(omarchy theme current 2>/dev/null) == Evangelion ]]; then
  echo "Switch to another theme first (e.g. omarchy theme set tokyo-night), then re-run." >&2
  exit 1
fi

for id in $(ls "$CFG/plugins" 2>/dev/null | grep '^zalo\.nerv-'); do
  omarchy plugin disable "$id" >/dev/null 2>&1 || true
  rm -rf "${CFG:?}/plugins/$id"
done
rm -f "$CFG/hooks/theme-set.d/nerv-mode" "$CFG/hooks/theme-set.d/nerv-sync-start" \
      "$CFG/hooks/battery-low.d/nerv-activity-limit" "$HOME/.local/bin/nerv-alert"

if [[ ${1:-} == --all ]]; then
  rm -rf "$CFG/themes/evangelion" "$HOME/.local/share/fonts/nerv" "$CFG/nerv-wall.json"
  fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true
fi
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
echo "NERV extras removed."
