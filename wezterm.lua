local wezterm = require("wezterm")
local config = wezterm.config_builder()
local act = wezterm.action -- Shortcut for actions

-- Event: Run fastfetch only in the first window
wezterm.on("gui-startup", function(cmd)
	local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
	pane:send_text("fastfetch\n")
end)

-- Appearance & Performance
config.enable_wayland = false
config.window_background_opacity = 0.6
config.macos_window_background_blur = 5
config.initial_cols = 120
config.initial_rows = 36
config.max_fps = 120
config.animation_fps = 120
config.front_end = "WebGpu"
config.webgpu_power_preference = "LowPower"

-- Fonts
config.font_dirs = { "~/.local/share/fonts/NerdFonts" }
config.font = wezterm.font("Roboto Mono Nerd Font")
config.font_size = 12
config.warn_about_missing_glyphs = false

-- Layout
-- config.window_decorations = "RESIZE"
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
config.color_scheme = "Flat (base16)"
config.cursor_blink_ease_in = "Constant"
config.cursor_blink_ease_out = "Constant"

-- Fixed Key Mappings
config.keys = {
	{ key = "c", mods = "CTRL|SHIFT", action = act.CopyTo("Clipboard") },
	{ key = "v", mods = "CTRL|SHIFT", action = act.PasteFrom("Clipboard") },
	{ key = "t", mods = "CTRL|SHIFT", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "t", mods = "ALT", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "CTRL|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },
	{ key = "w", mods = "ALT", action = act.CloseCurrentTab({ confirm = true }) },
	{ key = "n", mods = "ALT", action = act.SpawnWindow },
	{ key = "h", mods = "ALT", action = act.ActivatePaneDirection("Left") },
	{ key = "l", mods = "ALT", action = act.ActivatePaneDirection("Right") },
	{ key = "j", mods = "ALT", action = act.ActivatePaneDirection("Down") },
	{ key = "k", mods = "ALT", action = act.ActivatePaneDirection("Up") },
	-- Splitting
	{ key = "LeftArrow", mods = "ALT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "RightArrow", mods = "ALT", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "DownArrow", mods = "ALT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "UpArrow", mods = "ALT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	{ key = "q", mods = "ALT", action = act.CloseCurrentPane({ confirm = true }) },
	-- Tab Navigation
	{ key = "1", mods = "ALT", action = act.ActivateTab(0) },
	{ key = "2", mods = "ALT", action = act.ActivateTab(1) },
	{ key = "3", mods = "ALT", action = act.ActivateTab(2) },
	{ key = "4", mods = "ALT", action = act.ActivateTab(3) },
	{ key = "5", mods = "ALT", action = act.ActivateTab(4) },
	{ key = "6", mods = "ALT", action = act.ActivateTab(5) },
	{ key = "7", mods = "ALT", action = act.ActivateTab(6) },
	{ key = "8", mods = "ALT", action = act.ActivateTab(7) },
	{ key = "9", mods = "ALT", action = act.ActivateTab(8) },
	-- Corrected Font Size Actions
	{ key = "+", mods = "CTRL|SHIFT", action = act.IncreaseFontSize },
	{ key = "-", mods = "CTRL|SHIFT", action = act.DecreaseFontSize },
	{ key = "0", mods = "CTRL|SHIFT", action = act.ResetFontSize },
}

return config
