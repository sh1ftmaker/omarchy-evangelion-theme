-- Evangelion / NERV HQ: angular command-terminal panels. Zero rounding,
-- command-orange frame raking into amber, graphite for idle panels, a faint
-- orange phosphor glow on the active window, and hard, terminal-fast motion.

local active_border_color = {
  colors = { "rgba(ff7a00ff)", "rgba(ff7a00ff)", "rgba(ffb000ff)" },
  angle = 45,
}
local inactive_border_color = "rgba(4a3218cc)"

hl.config({
  general = {
    border_size = 2,

    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },

    -- Header tabs: solid orange with the title knocked out in black.
    groupbar = {
      font_family = "IBM Plex Mono",
      font_weight_active = "bold",
      font_weight_inactive = "medium",
      text_color = "rgb(050403)",
      text_color_inactive = "rgb(ff7a00)",
      gradients = true,
      gradient_rounding = 0,
      col = {
        active = "rgba(ff7a00ff)",
        inactive = "rgba(120c06ff)",
      },
    },
  },

  decoration = {
    -- NERV panels are cut, never rounded.
    rounding = 0,

    -- Idle terminals fall back into the dark.
    dim_inactive = true,
    dim_strength = 0.12,

    blur = {
      enabled = false,
    },

    -- Faint CRT bloom around the live panel.
    shadow = {
      enabled = true,
      range = 10,
      render_power = 3,
      color = "rgba(ff7a0040)",
      color_inactive = "rgba(00000000)",
    },
  },
})

-- Hard, terminal-fast motion: everything lands almost instantly, no float.
hl.curve("nervSnap", { type = "bezier", points = { { 0.05, 0.95 }, { 0.1, 1 } } })
hl.curve("nervCut", { type = "bezier", points = { { 0.9, 0 }, { 1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 4, bezier = "nervSnap" })
hl.animation({ leaf = "border", enabled = true, speed = 2, bezier = "nervSnap" })
hl.animation({ leaf = "windows", enabled = true, speed = 2, bezier = "nervSnap" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 1.8, bezier = "nervSnap", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.2, bezier = "nervCut", style = "popin 92%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.2, bezier = "nervSnap" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1, bezier = "nervCut" })
hl.animation({ leaf = "fade", enabled = true, speed = 1.5, bezier = "nervSnap" })
hl.animation({ leaf = "layers", enabled = true, speed = 1.8, bezier = "nervSnap" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.8, bezier = "nervSnap", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1, bezier = "nervCut", style = "fade" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 2, bezier = "nervSnap", style = "slidevert" })
