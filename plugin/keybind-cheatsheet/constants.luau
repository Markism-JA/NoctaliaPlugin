--!strict
-- Shared constants and state keys for keybind-cheatsheet

local constants = {
	PANEL_ID = "kenn/keybind-cheatsheet:cheatsheet",
	SNAPSHOT_KEY = "keybind-cheatsheet.snapshot",
	REFRESH_REQUEST_KEY = "keybind-cheatsheet.refresh-request",
	PREFERENCES_FILE = "preferences.json",
}

return table.freeze(constants)
