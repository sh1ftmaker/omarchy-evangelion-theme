-- Evangelion / NERV HQ: orange-on-black command terminal for Neovim.
-- Built on aether.nvim (what Omarchy's generated themes use) with the palette
-- remapped so code reads as HUD data: amber functions, red-orange keywords,
-- phosphor-green strings, PATTERN BLUE for preprocessor/special, bone types.
return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      styles = {
        comments = { italic = false },
        keywords = { bold = true },
        sidebars = "dark",
        floats = "dark",
      },
      colors = {
        bg = "#050403",
        dark_bg = "#0b0804",
        darker_bg = "#000000",
        lighter_bg = "#120c06",

        fg = "#ffbf73",
        dark_fg = "#9c6a2e",
        light_fg = "#ffd6a0",
        bright_fg = "#ffe9c8",
        muted = "#7a5528",

        red = "#ff1a1a",
        yellow = "#ffb000",
        orange = "#ff7a00",
        green = "#39ff6a",
        cyan = "#00c8ff",
        -- "blue" drives functions, statements, titles and directories: amber.
        blue = "#ffb000",
        -- "purple" drives keywords and conditionals: hot red-orange.
        purple = "#ff4a1a",
        brown = "#9c6a2e",

        bright_red = "#ff5a4a",
        bright_yellow = "#ffd060",
        bright_green = "#8cffa8",
        bright_cyan = "#ffd6a0", -- identifiers: warm bone
        bright_blue = "#ffd060",
        bright_purple = "#ff6a3a",

        accent = "#ff7a00",
        cursor = "#ff7a00",
        foreground = "#ffbf73",
        background = "#050403",
        selection = "#4a3218",
        selection_foreground = "#ffe9c8",
        selection_background = "#4a3218",
      },
      on_highlights = function(hl, c)
        hl.Type = { fg = "#ffe9c8", bold = true }
        hl.StorageClass = { fg = "#ffe9c8" }
        hl.Structure = { fg = "#ffe9c8" }
        hl.Typedef = { fg = "#ffe9c8" }
        hl["@type"] = { fg = "#ffe9c8", bold = true }
        hl["@type.builtin"] = { fg = "#ffe9c8" }
        hl.Comment = { fg = "#9c6a2e" }
        hl.LineNr = { fg = "#4a3218" }
        hl.LineNrAbove = { fg = "#4a3218" }
        hl.LineNrBelow = { fg = "#4a3218" }
        hl.CursorLineNr = { fg = "#ff7a00", bold = true }
        hl.CursorLine = { bg = "#120c06" }
        hl.Cursor = { fg = "#050403", bg = "#ff7a00" }
        hl.Visual = { bg = "#4a3218" }
        hl.Search = { fg = "#050403", bg = "#ffb000", bold = true }
        hl.IncSearch = { fg = "#050403", bg = "#ff1a1a", bold = true }
        hl.CurSearch = { fg = "#050403", bg = "#ff1a1a", bold = true }
        hl.MatchParen = { fg = "#00c8ff", bold = true, underline = true }
        hl.WinSeparator = { fg = "#ff7a00" }
        hl.VertSplit = { fg = "#ff7a00" }
        hl.FloatBorder = { fg = "#ff7a00", bg = "#0b0804" }
        hl.FloatTitle = { fg = "#050403", bg = "#ff7a00", bold = true }
        hl.TabLineSel = { fg = "#050403", bg = "#ff7a00", bold = true }
        hl.Title = { fg = "#ff7a00", bold = true }
        hl.Directory = { fg = "#ff7a00", bold = true }
        hl.PmenuSel = { fg = "#050403", bg = "#ff7a00", bold = true }
        hl.PmenuMatch = { fg = "#ffb000", bg = "#0b0804" }
        hl.PmenuMatchSel = { fg = "#050403", bg = "#ff7a00", bold = true }
        hl.StatusLine = { fg = "#ff7a00", bg = "#0b0804" }
        hl.ErrorMsg = { fg = "#ff1a1a", bold = true }
        hl.Error = { fg = "#ff1a1a", bold = true }
        hl.DiagnosticError = { fg = "#ff1a1a" }
        hl.DiagnosticWarn = { fg = "#ffb000" }
        hl.DiagnosticInfo = { fg = "#00c8ff" }
        hl.DiagnosticHint = { fg = "#39ff6a" }
        hl.Todo = { fg = "#050403", bg = "#ff1a1a", bold = true }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
