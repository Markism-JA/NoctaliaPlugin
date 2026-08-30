--!strict
--- Official Noctalia Host Plugin API capability disclosure matrix.
--- Sourced directly from Noctalia plugin runtime documentation (levels 3 through 28).

export type FeatureKey =
	| "base_api"
	| "http_stream"
	| "drag_and_drop"
	| "string_map_setting"
	| "allow_insecure_tls"
	| "dismiss_on_outside_click"
	| "ui_closures"
	| "keyboard_focus"
	| "persistent_panel"
	| "system_stats"
	| "capture_keys"
	| "widget_actions"
	| "open_settings"
	| "disk_mounts"
	| "dynamic_service_lifecycle"
	| "panel_frame_tick"
	| "timezone_time_format"
	| "sound"
	| "ui_markdown_and_scroll"
	| "relative_requires"
	| "read_file_async"
	| "argv_execution"
	| "wallpaper_mask"
	| "get_setting"
	| "input_frame_visible"
	| "context_menu"

export type ApiEntry = {
	level: number,
	feature: FeatureKey,
	description: string,
	noctaliaVersion: string,
	symbol: string?,
}

local matrix: { [number]: ApiEntry } = {
	[3] = {
		level = 3,
		feature = "base_api",
		description = "Mandatory plugin_api compatibility declaration",
		noctaliaVersion = "v5.0.0-beta.3",
		symbol = nil,
	},
	[4] = {
		level = 4,
		feature = "http_stream",
		description = "noctalia.httpStream() for streaming HTTP responses",
		noctaliaVersion = "v5.0.0-beta.4",
		symbol = "httpStream",
	},
	[5] = {
		level = 5,
		feature = "drag_and_drop",
		description = "ui.dragSource() and ui.dropZone() for declarative drag & drop",
		noctaliaVersion = "v5.0.0-beta.4",
		symbol = "ui.dragSource",
	},
	[6] = {
		level = 6,
		feature = "string_map_setting",
		description = "The string_map plugin setting type",
		noctaliaVersion = "v5.0.0-beta.4",
		symbol = nil,
	},
	[7] = {
		level = 7,
		feature = "allow_insecure_tls",
		description = "The allow_insecure_tls HTTP request option",
		noctaliaVersion = "v5.0.0-beta.4",
		symbol = nil,
	},
	[8] = {
		level = 8,
		feature = "dismiss_on_outside_click",
		description = "The dismiss_on_outside_click panel entry option",
		noctaliaVersion = "v5.0.0-beta.4",
		symbol = nil,
	},
	[9] = {
		level = 9,
		feature = "ui_closures",
		description = "Luau closures directly in UI tree callback props",
		noctaliaVersion = "v5.0.0-beta.5",
		symbol = nil,
	},
	[10] = {
		level = 10,
		feature = "keyboard_focus",
		description = "The keyboard_focus panel entry option",
		noctaliaVersion = "v5.0.0-beta.5",
		symbol = nil,
	},
	[11] = {
		level = 11,
		feature = "persistent_panel",
		description = "The persistent panel entry option",
		noctaliaVersion = "v5.0.0-beta.5",
		symbol = nil,
	},
	[12] = {
		level = 12,
		feature = "system_stats",
		description = "noctalia.systemStats(), noctalia.cpuCores(), and noctalia.nowMs()",
		noctaliaVersion = "v5.0.0-beta.5",
		symbol = "systemStats",
	},
	[13] = {
		level = 13,
		feature = "capture_keys",
		description = "The capture_keys panel option and onKey callback",
		noctaliaVersion = "v5.0.0-beta.5",
		symbol = nil,
	},
	[14] = {
		level = 14,
		feature = "widget_actions",
		description = "The [widget.actions] entry table for bar gestures",
		noctaliaVersion = "v5.0.0-beta.5",
		symbol = nil,
	},
	[15] = {
		level = 15,
		feature = "open_settings",
		description = "noctalia.openSettings() bridge to plugin settings page",
		noctaliaVersion = "v5.0.0-beta.6",
		symbol = "openSettings",
	},
	[16] = {
		level = 16,
		feature = "disk_mounts",
		description = "Per-interface network rates and disk mount/stats APIs",
		noctaliaVersion = "v5.0.0-beta.6",
		symbol = "diskMounts",
	},
	[17] = {
		level = 17,
		feature = "dynamic_service_lifecycle",
		description = "Dynamic onEnable and onExit(signal, reason) lifecycle",
		noctaliaVersion = "v5.0.0-beta.7",
		symbol = nil,
	},
	[18] = {
		level = 18,
		feature = "panel_frame_tick",
		description = "panel.setNeedsFrameTick(bool) and onFrameTick(deltaMs)",
		noctaliaVersion = "v5.0.0-beta.7",
		symbol = "panel.setNeedsFrameTick",
	},
	[19] = {
		level = 19,
		feature = "timezone_time_format",
		description = "Timezone formatTime and [shell].time_format/date_format mirrors",
		noctaliaVersion = "v5.0.0-beta.7",
		symbol = "timeFormat",
	},
	[20] = {
		level = 20,
		feature = "sound",
		description = "noctalia.sound.load() and noctalia.sound.play()",
		noctaliaVersion = "v5.0.0-beta.7",
		symbol = "sound.play",
	},
	[21] = {
		level = 21,
		feature = "ui_markdown_and_scroll",
		description = "ui.markdown node, submitOnEnter, and ui.scroll controls",
		noctaliaVersion = "v5.0.0-beta.8",
		symbol = nil,
	},
	[22] = {
		level = 22,
		feature = "relative_requires",
		description = "Relative .luau module requires with entry-local caching",
		noctaliaVersion = "v5.0.0-beta.8",
		symbol = nil,
	},
	[23] = {
		level = 23,
		feature = "read_file_async",
		description = "noctalia.readFileAsync(path, cb) bounded queue",
		noctaliaVersion = "v5.0.0-beta.8",
		symbol = "readFileAsync",
	},
	[24] = {
		level = 24,
		feature = "argv_execution",
		description = "Argument-array form of noctalia.runAsync()",
		noctaliaVersion = "v5.0.0-beta.9",
		symbol = nil,
	},
	[25] = {
		level = 25,
		feature = "wallpaper_mask",
		description = "noctalia.wallpaperPath() and noctalia.setWallpaperMask()",
		noctaliaVersion = "v5.0.0-beta.9",
		symbol = "wallpaperPath",
	},
	[26] = {
		level = 26,
		feature = "get_setting",
		description = "noctalia.getSetting(path) for TOML dotted paths",
		noctaliaVersion = "v5.0.0-beta.9",
		symbol = "getSetting",
	},
	[27] = {
		level = 27,
		feature = "input_frame_visible",
		description = "frameVisible prop on ui.input for border control",
		noctaliaVersion = "v5.0.0-beta.9",
		symbol = nil,
	},
	[28] = {
		level = 28,
		feature = "context_menu",
		description = "panel.openContextMenu(request) native menus",
		noctaliaVersion = "v5.0.0-beta.9",
		symbol = "panel.openContextMenu",
	},
}

-- Fast reverse lookup from FeatureKey string to ApiEntry
local featureMap: { [FeatureKey]: ApiEntry } = {}
for _, entry in pairs(matrix) do
	featureMap[entry.feature] = entry
end

return {
	MIN_SUPPORTED_LEVEL = 3,
	MAX_SUPPORTED_LEVEL = 28,
	ENTRIES = matrix,
	BY_FEATURE = featureMap,
}
