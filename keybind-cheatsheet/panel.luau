--!strict
-- Snapshot-driven keybind viewer for Mango, Hyprland, and Niri.
--
-- Parsing, durable cache ownership, and refreshes live in service.luau. This
-- panel only reads the shared snapshot and renders it.
-- Hierarchical category presentation.

local stl = require("../stl/stl.luau")
local constants = require("./constants.luau")
local log = stl.log.scope("KeybindsPanel")

type ColorPreference = {
	background: string?,
	text: string?,
}

type Preferences = {
	version: number,
	hidden: { [string]: boolean },
	descriptions: { [string]: string },
	colors: { [string]: ColorPreference },
}

type Binding = {
	id: string,
	key: string,
	modifiers: { string },
	action: string,
	category: string?,
	description: string?,
	compositor: string?,
	displayIndex: number?,
	_lowerMod: string?,
	_keyRaw: string?,
	_formattedKey: string?,
	_lowerFormattedKey: string?,
	_lowerAction: string?,
}

type Snapshot = {
	bindings: { Binding }?,
	warnings: { string }?,
	compositor: string?,
	status: string?,
	error: string?,
}

type CategoryGroup = {
	name: string,
	bindings: { Binding },
	sourceOrder: number,
	order: number,
	weight: number,
}

type ColorBucket = {
	id: string,
	label: string,
	background: string,
	text: string,
	picker: string,
}

-- State channels
local snapshotChannel = stl.state.channel(constants.SNAPSHOT_KEY, nil :: any)
local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)

local bindings: { Binding } = {}
local parseWarnings: { string } = {}
local currentCompositor = ""
local loading = false
local panelOpen = false
local panelError: string? = nil
local refreshError: string? = nil
local snapshot: Snapshot? = nil
local query = ""
local searchRevision = 0
local searchFocused = true
local view: "bindings" | "edit" | "appearance" = "bindings"
local editingId: string? = nil
local editDraft = ""
local preferences: Preferences = { version = 1, hidden = {}, descriptions = {}, colors = {} }

local render: () -> ()
local refresh: () -> ()

local function tr(key: string, values: { [string]: any }?): string
	if noctalia and noctalia.tr then
		return noctalia.tr(key, values)
	end
	return key
end

local function trim(s: string?): string
	if not s or s == "" then
		return ""
	end
	if noctalia and noctalia.string and noctalia.string.trim then
		return noctalia.string.trim(s)
	end
	return s:match("^%s*(.-)%s*$") or ""
end

local function lower(value: string?): string
	return string.lower(value or "")
end

local function startsWith(value: string, prefix: string): boolean
	return value:sub(1, #prefix) == prefix
end

local KEY_LABELS: { [string]: string } = {
	xf86audioraisevolume = "Vol Up",
	xf86audiolowervolume = "Vol Down",
	xf86audiomute = "Mute",
	xf86audiomicmute = "Mic Mute",
	xf86monbrightnessup = "Bright Up",
	xf86monbrightnessdown = "Bright Down",
	xf86audioplay = "Play/Pause",
	xf86audiopause = "Pause",
	xf86audionext = "Next",
	xf86audioprev = "Previous",
	print = "PrtSc",
	prtsc = "PrtSc",
	prior = "PgUp",
	page_up = "PgUp",
	pageup = "PgUp",
	next = "PgDn",
	page_down = "PgDn",
	pagedown = "PgDn",
	["return"] = "Enter",
	enter = "Enter",
	escape = "Esc",
	esc = "Esc",
	space = "Space",
	backspace = "Backspace",
	delete = "Del",
	del = "Del",
	insert = "Ins",
	ins = "Ins",
	tab = "Tab",
	home = "Home",
	["end"] = "End",
	caps_lock = "CapsLock",
	capslock = "CapsLock",
	num_lock = "NumLock",
	numlock = "NumLock",
	scroll_lock = "ScrollLock",
	scrolllock = "ScrollLock",
	up = "↑",
	down = "↓",
	left = "←",
	right = "→",
	btn_left = "Mouse Left",
	btn_right = "Mouse Right",
	btn_middle = "Mouse Middle",
	btn_side = "Mouse Side",
	btn_extra = "Mouse Extra",
}

local MODIFIER_DISPLAY = {
	SUPER = "Super",
	CTRL = "Ctrl",
	SHIFT = "Shift",
	ALT = "Alt",
	MOD2 = "Mod2",
	MOD3 = "Mod3",
	MOD5 = "Mod5",
}

local function formatKey(key: string?): string
	if key == nil or key == "" then
		return ""
	end
	local exact = KEY_LABELS[key]
	if exact ~= nil then
		return exact
	end
	local lowered = KEY_LABELS[lower(key)]
	if lowered ~= nil then
		return lowered
	end
	return (key:gsub("^mouse:", "Mouse "))
end

local function normalizePreferences(decoded: any): Preferences
	local result = { version = 1, hidden = {}, descriptions = {}, colors = {} }
	if type(decoded) ~= "table" then
		return result
	end

	for id, hidden in pairs(type(decoded.hidden) == "table" and decoded.hidden or {}) do
		if type(id) == "string" and hidden == true then
			result.hidden[id] = true
		end
	end
	for id, description in pairs(type(decoded.descriptions) == "table" and decoded.descriptions or {}) do
		if type(id) == "string" and type(description) == "string" and trim(description) ~= "" then
			result.descriptions[id] = trim(description)
		end
	end
	for bucket, colors in pairs(type(decoded.colors) == "table" and decoded.colors or {}) do
		if type(bucket) == "string" and type(colors) == "table" then
			result.colors[bucket] = {}
			if type(colors.background) == "string" then
				result.colors[bucket].background = colors.background
			end
			if type(colors.text) == "string" then
				result.colors[bucket].text = colors.text
			end
		end
	end
	return result
end

local function loadPreferences()
	local decoded, err = stl.filesystem.readPluginData(constants.PREFERENCES_FILE)
	if err then
		log.debug("No custom preferences file found or failed reading", { err = err })
	end
	preferences = normalizePreferences(decoded)
end

local function savePreferences()
	local ok, err = stl.filesystem.writePluginData(constants.PREFERENCES_FILE, preferences, true)
	if not ok then
		log.error("Failed to save preferences", { err = err })
		if noctalia.notifyError then
			noctalia.notifyError(tr("title"), err or "Could not save preferences")
		end
	end
end

local function enrichBinding(binding: Binding)
	local mods = binding.modifiers or {}
	binding._lowerMod = lower(table.concat(mods, " "))
	binding._keyRaw = lower(binding.key or "")
	binding._formattedKey = formatKey(binding.key)
	binding._lowerFormattedKey = lower(binding._formattedKey)
	binding._lowerAction = lower(binding.action or "")
end

local function applySnapshot(value: any)
	snapshot = type(value) == "table" and value or nil
	if snapshot == nil then
		bindings = {}
		parseWarnings = {}
		currentCompositor = ""
		loading = true
		panelError = nil
		refreshError = nil
		return
	end

	bindings = type(snapshot.bindings) == "table" and snapshot.bindings or {}
	for _, b in ipairs(bindings) do
		enrichBinding(b)
	end

	parseWarnings = type(snapshot.warnings) == "table" and snapshot.warnings or {}
	currentCompositor = type(snapshot.compositor) == "string" and snapshot.compositor or ""
	loading = (snapshot.status == "loading" or snapshot.status == "idle") and #bindings == 0
	panelError = snapshot.status == "error" and (snapshot.error or tr("missing_config")) or nil
	refreshError = snapshot.status == "ready"
			and type(snapshot.error) == "string"
			and snapshot.error ~= ""
			and snapshot.error
		or nil
end

refresh = function()
	local current = tonumber(refreshChannel.get()) or 0
	refreshChannel.set(current + 1)
	render()
end

-- ============================================================================
-- Color Appearance & Theming Customization
-- ============================================================================

local COLOR_BUCKETS = {
	{ id = "super", label = "Super", background = "primary", text = "on_primary", picker = "#6750A4" },
	{ id = "ctrl", label = "Ctrl", background = "secondary", text = "on_secondary", picker = "#625B71" },
	{ id = "shift", label = "Shift", background = "tertiary", text = "on_tertiary", picker = "#7D5260" },
	{ id = "alt", label = "Alt", background = "error", text = "on_error", picker = "#B3261E" },
	{ id = "xf86", label = "Media", background = "secondary/0.25", text = "secondary", picker = "#E8DEF8" },
	{ id = "number", label = "Numbers", background = "tertiary/0.25", text = "tertiary", picker = "#FFD8E4" },
	{ id = "mouse", label = "Mouse", background = "error/0.2", text = "error", picker = "#F9DEDC" },
	{ id = "print", label = "Print", background = "primary/0.25", text = "primary", picker = "#EADDFF" },
	{
		id = "default",
		label = "Other keys",
		background = "surface_variant",
		text = "on_surface_variant",
		picker = "#E7E0EC",
	},
	{ id = "description", label = "Descriptions", background = "surface", text = "on_surface", picker = "#1D1B20" },
}

local COLOR_BY_ID = {}
for _, bucket in ipairs(COLOR_BUCKETS) do
	COLOR_BY_ID[bucket.id] = bucket
end

local function colorValue(bucketId: string, property: "background" | "text"): string
	local custom = preferences.colors[bucketId]
	if property == "background" then
		if custom and custom.background then
			return custom.background
		end
		local bucket = COLOR_BY_ID[bucketId] or COLOR_BY_ID.default
		return bucket.background
	else
		if custom and custom.text then
			return custom.text
		end
		local bucket = COLOR_BY_ID[bucketId] or COLOR_BY_ID.default
		return bucket.text
	end
end

local function bucketForKey(key: string?): string
	local value = lower(key)
	if startsWith(value, "xf86") then
		return "xf86"
	end
	if value:match("^%d$") then
		return "number"
	end
	if startsWith(value, "mouse") or startsWith(value, "btn_") or value:find("wheel", 1, true) ~= nil then
		return "mouse"
	end
	if value == "print" or value == "prior" or value == "next" then
		return "print"
	end
	return "default"
end

local function bucketForModifier(modifier: string): string
	local value = lower(modifier)
	if value == "super" or value == "mod4" or value == "logo" then
		return "super"
	end
	if value == "ctrl" or value == "control" then
		return "ctrl"
	end
	if value == "shift" then
		return "shift"
	end
	if value == "alt" or value == "mod1" then
		return "alt"
	end
	return "default"
end

local function isHexColor(value)
	if type(value) ~= "string" then
		return false
	end
	return value:match("^#%x%x%x%x%x%x$") ~= nil or value:match("^#%x%x%x%x%x%x%x%x$") ~= nil
end

local function setColor(bucketId: string, property: "background" | "text", value: string)
	local colorObj: ColorPreference = preferences.colors[bucketId] or { background = nil, text = nil }
	if property == "background" then
		colorObj.background = value
	else
		colorObj.text = value
	end
	preferences.colors[bucketId] = colorObj
	savePreferences()
	render()
end

local function chooseColor(bucketId: string, property: "background" | "text")
	local bucket = COLOR_BY_ID[bucketId] or COLOR_BY_ID.default
	local current = colorValue(bucketId, property)
	local initial = isHexColor(current) and current:sub(1, 7) or bucket.picker
	if noctalia.openColorPicker then
		noctalia.openColorPicker(initial, function(color)
			if color ~= nil then
				setColor(bucketId, property, color)
			end
		end)
	end
end

local function pasteColor(bucketId: string, property: "background" | "text")
	local value = trim(noctalia.clipboardText and noctalia.clipboardText() or "")
	if isHexColor(value) then
		setColor(bucketId, property, string.upper(value))
	else
		if noctalia.notifyError then
			noctalia.notifyError(tr("title"), "Clipboard does not contain a #RRGGBB color")
		end
	end
end

local function keyPill(text: string, bucketId: string, key: string): UiNode
	return ui.column({
		key = key,
		minWidth = 20,
		fill = colorValue(bucketId, "background"),
		radius = 4,
		paddingH = 7,
		paddingV = 3,
		align = "center",
	}, {
		ui.label({ text = text, color = colorValue(bucketId, "text"), fontSize = 12, fontWeight = "bold" }),
	})
end

local function authoredDescription(binding: Binding): string
	return preferences.descriptions[binding.id] or binding.description or ""
end

local function titleCase(value: string): string
	local clean = (trim(value):gsub("[_%-]+", " "))
	return (
		clean:gsub("%a[%w']*", function(word: string): string
			return string.upper(word:sub(1, 1)) .. lower(word:sub(2))
		end)
	)
end

local function friendlySpawn(commandLine: string): string
	local value = lower(trim(commandLine))
	if value:find("noctalia msg panel-toggle launcher", 1, true) ~= nil then
		return "Application Launcher"
	end
	if value:find("noctalia msg panel-toggle session", 1, true) ~= nil then
		return "Power Menu"
	end
	if value:find("noctalia msg session lock", 1, true) ~= nil then
		return "Lock Screen"
	end
	if value:find("playerctl play-pause", 1, true) ~= nil then
		return "Play / Pause"
	end
	if value:find("playerctl next", 1, true) ~= nil then
		return "Next Track"
	end
	if value:find("playerctl previous", 1, true) ~= nil then
		return "Previous Track"
	end
	if value:find("playerctl stop", 1, true) ~= nil then
		return "Stop Playback"
	end
	if value:find("wpctl set-volume", 1, true) ~= nil then
		return value:find("+", 1, true) ~= nil and "Volume Up" or "Volume Down"
	end
	if value:find("wpctl set-mute", 1, true) ~= nil then
		return value:find("source", 1, true) ~= nil and "Toggle Microphone Mute" or "Toggle Mute"
	end
	if value:find("brightnessctl", 1, true) ~= nil then
		return value:find("+", 1, true) ~= nil and "Brightness Up" or "Brightness Down"
	end

	local program = trim(commandLine):match("^([^%s]+)") or "Application"
	program = program:match("([^/]+)$") or program
	local programs: { [string]: string } = {
		alacritty = "Terminal",
		chromium = "Browser",
		dolphin = "File Manager",
		firefox = "Browser",
		foot = "Terminal",
		kitty = "Terminal",
		nautilus = "File Manager",
		thunar = "File Manager",
	}
	return programs[lower(program)] or ("Launch " .. titleCase(program))
end

local ACTION_LABELS: { [string]: string } = {
	close_window = "Close Window",
	killactive = "Close Window",
	killclient = "Close Window",
	minimized = "Minimize Window",
	quit = "Exit Compositor",
	reload_config = "Reload Configuration",
	restore_minimized = "Restore Minimized Window",
	switch_proportion_preset = "Cycle Width Preset",
	toggle_named_scratchpad = "Toggle Scratchpad",
	togglefakefullscreen = "Toggle Fake Fullscreen",
	togglefloating = "Toggle Floating",
	togglefullscreen = "Toggle Fullscreen",
	togglegaps = "Toggle Gaps",
	toggleglobal = "Toggle Global Window",
	togglemaximizescreen = "Toggle Maximize",
	toggleoverlay = "Toggle Overlay",
	toggleoverview = "Workspace Overview",
}

local function friendlyAction(binding: Binding): string
	local action = trim(binding.action)
	local command, arguments = action:match("^(%S+)%s*(.*)$")
	command = lower(command or ""):gsub("%-", "_")
	arguments = trim(arguments or "")
	if command == "spawn" or command == "spawn_shell" or command == "exec" then
		return friendlySpawn(arguments)
	end
	if ACTION_LABELS[command] ~= nil then
		return ACTION_LABELS[command]
	end

	local argument = arguments:match("^([^,%s]+)") or ""
	local direction = argument ~= "" and titleCase(argument) or ""
	if command == "focusdir" or command == "movefocus" then
		return "Focus " .. direction
	end
	if command == "exchange_client" or command == "movewindow" then
		return "Move Window " .. direction
	end
	if command == "focusmon" then
		return "Focus Monitor " .. direction
	end
	if command == "tagmon" then
		return "Move to Monitor " .. direction
	end
	if command == "scroller_stack" then
		return "Move Within Stack " .. direction
	end
	if command == "view" or command == "workspace" then
		return "Workspace " .. argument
	end
	if command == "tag" or command == "movetoworkspace" then
		return "Send to Workspace " .. argument
	end
	if command == "viewtoleft" or command == "viewtoleft_have_client" then
		return "Previous Workspace"
	end
	if command == "viewtoright" or command == "viewtoright_have_client" then
		return "Next Workspace"
	end
	if command == "setlayout" then
		return titleCase(argument) .. " Layout"
	end
	if command == "set_proportion" then
		return "Set Window Proportion " .. argument
	end
	if command == "setmfact" then
		return "Set Layout Size " .. argument
	end
	if command == "moveresize" then
		return arguments:find("curresize", 1, true) ~= nil and "Resize Window with Mouse" or "Move Window with Mouse"
	end
	return titleCase(action)
end

local function effectiveDescription(binding: Binding): string
	local description = authoredDescription(binding)
	return description ~= "" and description or friendlyAction(binding)
end

local function effectiveCategory(binding: Binding): string
	if binding.category ~= nil and binding.category ~= "" and binding.category ~= "General" then
		return binding.category
	end
	return tr("other")
end

local SEARCH_MODIFIER_ALIASES: { [string]: string } = {
	win = "super",
	logo = "super",
	mod4 = "super",
	cmd = "super",
	control = "ctrl",
	mod1 = "alt",
}

local function splitQueryTokens(rawQuery: string): { string }
	local clean = lower(rawQuery):gsub("[%+%-%%,_|]+", " ")
	local tokens = {}
	for token in clean:gmatch("%S+") do
		table.insert(tokens, SEARCH_MODIFIER_ALIASES[token] or token)
	end
	return tokens
end

local function bindingMatches(binding: Binding, tokens: { string }): boolean
	if #tokens == 0 then
		return true
	end

	local modStr = binding._lowerMod or ""
	local keyRaw = binding._keyRaw or ""
	local keyFormatted = binding._lowerFormattedKey or ""
	local descStr = lower(effectiveDescription(binding))
	local catStr = lower(effectiveCategory(binding))
	local actionStr = binding._lowerAction or ""

	for _, token in ipairs(tokens) do
		local matched = false
		if modStr:find(token, 1, true) then
			matched = true
		elseif
			keyRaw == token
			or keyFormatted == token
			or startsWith(keyRaw, token)
			or startsWith(keyFormatted, token)
		then
			matched = true
		elseif descStr:find(token, 1, true) then
			matched = true
		elseif catStr:find(token, 1, true) then
			matched = true
		elseif #token >= 3 and actionStr:find(token, 1, true) then
			matched = true
		end

		if not matched then
			return false
		end
	end
	return true
end

type CategoryPriorityEntry = { string | number } -- or struct table

local CATEGORY_PRIORITIES: { { [number]: any } } = {
	{ "applications", 10 },
	{ "system", 20 },
	{ "window management", 30 },
	{ "focus", 40 },
	{ "navigation", 40 },
	{ "moving windows", 45 },
	{ "workspace", 50 },
	{ "tags", 50 },
	{ "monitor", 50 },
	{ "media", 60 },
	{ "brightness", 60 },
	{ "layout", 70 },
	{ "mouse", 80 },
	{ "touchpad", 90 },
	{ "gesture", 90 },
	{ "integration", 100 },
	{ lower(tr("without_description")), 900 },
	{ lower(tr("other")), 950 },
}

local categoryPriorityCache: { [string]: number } = {}
local function categoryPriority(name: string): number
	local cached = categoryPriorityCache[name]
	if cached then
		return cached
	end

	local value = lower(name)
	local score = 500
	for _, entry in ipairs(CATEGORY_PRIORITIES) do
		if value:find(entry[1], 1, true) ~= nil then
			score = entry[2]
			break
		end
	end
	categoryPriorityCache[name] = score
	return score
end

local function bindingAvailableInView(
	hidden: boolean,
	undescribed: boolean,
	managing: boolean,
	showUndescribed: boolean
): boolean
	if managing then
		return true
	end
	return not hidden and (showUndescribed or not undescribed)
end

local function hiddenBindingCount(bindingList: { Binding }, hiddenPreferences: { [string]: boolean }): number
	local currentIds: { [string]: boolean } = {}
	for _, binding in ipairs(bindingList or {}) do
		currentIds[binding.id] = true
	end
	local count = 0
	for id in pairs(currentIds) do
		if hiddenPreferences[id] == true then
			count += 1
		end
	end
	return count
end

local function restoreHiddenBindings(bindingList: { Binding }, hiddenPreferences: { [string]: boolean })
	for _, binding in ipairs(bindingList or {}) do
		hiddenPreferences[binding.id] = nil
	end
end

local function visibleGroups(): { CategoryGroup }
	local showUndescribed = stl.config.getBool("show_undescribed", true)
	local managing = view == "edit"
	local groups: { CategoryGroup } = {}
	local byName: { [string]: CategoryGroup } = {}

	local tokens = splitQueryTokens(query)

	for index, binding in ipairs(bindings) do
		local hidden = preferences.hidden[binding.id] == true
		local undescribed = authoredDescription(binding) == "" and binding.compositor ~= "niri"
		if
			bindingAvailableInView(hidden, undescribed, managing, showUndescribed) and bindingMatches(binding, tokens)
		then
			local category = effectiveCategory(binding)
			local group = byName[category]
			if group == nil then
				group = { name = category, bindings = {}, sourceOrder = #groups + 1, order = 0, weight = 1 }
				byName[category] = group
				table.insert(groups, group)
			end
			binding.displayIndex = index
			table.insert(group.bindings, binding)
			group.weight += 1
		end
	end

	table.sort(groups, function(a: CategoryGroup, b: CategoryGroup): boolean
		local left = categoryPriority(a.name)
		local right = categoryPriority(b.name)
		if left ~= right then
			return left < right
		end
		return a.sourceOrder < b.sourceOrder
	end)

	for index, group in ipairs(groups) do
		group.order = index
	end
	return groups
end

local function columnCount(): number
	local configured = math.clamp(stl.config.getNumber("columns", 3), 1, 4)
	local outputWidth = 1920
	if noctalia.focusedOutputName and noctalia.outputs then
		local focused = noctalia.focusedOutputName()
		for _, output in ipairs(noctalia.outputs()) do
			if output.name == focused or output.focused then
				outputWidth = output.width / math.max(output.scale or 1, 1)
				break
			end
		end
	end
	local responsive = outputWidth < 760 and 1 or (outputWidth < 1100 and 2 or (outputWidth < 1500 and 3 or 4))
	return math.min(configured, responsive)
end

type ColumnBucket = {
	groups: { CategoryGroup },
	weight: number,
}

local function balancedColumns(groups: { CategoryGroup }, count: number): { ColumnBucket }
	local columns: { ColumnBucket } = {}
	for index = 1, count do
		columns[index] = { groups = {}, weight = 0 }
	end
	for _, group in ipairs(groups) do
		local target = 1
		for index = 2, count do
			if columns[index].weight < columns[target].weight then
				target = index
			end
		end
		table.insert(columns[target].groups, group)
		columns[target].weight += group.weight
	end
	for _, column in ipairs(columns) do
		table.sort(column.groups, function(a: CategoryGroup, b: CategoryGroup): boolean
			return a.order < b.order
		end)
	end
	return columns
end

local function saveCustomDescription(binding: Binding, value: string)
	value = trim(value)
	if value == "" or value == binding.description then
		preferences.descriptions[binding.id] = nil
	else
		preferences.descriptions[binding.id] = value
	end
	editingId = nil
	editDraft = ""
	savePreferences()
	render()
end

local function bindingRow(binding: Binding, occurrence: number?): UiNode
	local hidden = preferences.hidden[binding.id] == true
	local contentOpacity = hidden and 0.45 or 1
	local pills: { UiNode } = {}

	for index, modifier in ipairs(binding.modifiers) do
		local modDisplay = MODIFIER_DISPLAY[modifier] or (modifier:sub(1, 1) .. lower(modifier:sub(2)))
		table.insert(pills, keyPill(modDisplay, bucketForModifier(modifier), "mod-" .. index))
	end
	table.insert(pills, keyPill(binding._formattedKey or formatKey(binding.key), bucketForKey(binding.key), "key"))

	local description = effectiveDescription(binding)
	local identity = binding.id .. "#" .. (occurrence or 1)

	if view == "edit" and editingId == identity then
		return ui.row({ key = "edit-" .. identity, gap = 6, align = "center", paddingV = 0 }, {
			ui.row({ minWidth = 188, gap = 3, align = "center", opacity = contentOpacity }, pills),
			ui.input({
				key = "description-" .. identity,
				value = editDraft,
				placeholder = tr("edit_description"),
				focus = true,
				controlSize = "sm",
				flexGrow = 1,
				onChange = function(value: string)
					editDraft = value
				end,
				onSubmit = function(value: string)
					saveCustomDescription(binding, value)
				end,
			}),
			ui.button({
				glyph = "check",
				width = 22,
				height = 22,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				tooltip = tr("save"),
				onClick = function()
					saveCustomDescription(binding, editDraft)
				end,
			}),
			ui.button({
				glyph = "close",
				width = 22,
				height = 22,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				tooltip = tr("cancel"),
				onClick = function()
					editingId = nil
					editDraft = ""
					render()
				end,
			}),
			ui.button({
				glyph = hidden and "eye-off" or "eye",
				width = 22,
				height = 22,
				glyphSize = 13,
				variant = "ghost",
				controlSize = "sm",
				selected = hidden,
				tooltip = hidden and tr("show_binding") or tr("hide_binding"),
				onClick = function()
					preferences.hidden[binding.id] = not hidden and true or nil
					savePreferences()
					render()
				end,
			}),
		})
	end

	local labels: { UiNode } = {
		ui.label({
			text = description,
			color = colorValue("description", "text"),
			fontWeight = "bold",
			fontSize = 13,
			maxLines = 1,
		}),
	}
	if stl.config.getBool("show_actions", true) and description ~= "" and binding.action ~= "" then
		table.insert(
			labels,
			ui.label({ text = binding.action, color = "on_surface_variant", fontSize = 11, maxLines = 1 })
		)
	end

	local rowChildren: { UiNode } = {
		ui.row({ minWidth = 188, gap = 3, align = "center", opacity = contentOpacity }, pills),
		ui.column({ flexGrow = 1, gap = 0, opacity = contentOpacity }, labels),
	}

	if view == "edit" then
		table.insert(
			rowChildren,
			ui.button({
				glyph = "pencil",
				width = 22,
				height = 22,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				tooltip = tr("edit_description"),
				onClick = function()
					editingId = identity
					editDraft = description
					render()
				end,
			})
		)
		table.insert(
			rowChildren,
			ui.button({
				glyph = hidden and "eye-off" or "eye",
				width = 22,
				height = 22,
				glyphSize = 13,
				variant = "ghost",
				controlSize = "sm",
				selected = hidden,
				tooltip = hidden and tr("show_binding") or tr("hide_binding"),
				onClick = function()
					preferences.hidden[binding.id] = not hidden and true or nil
					savePreferences()
					render()
				end,
			})
		)
	end

	return ui.row({ key = identity, gap = 6, align = "center", paddingV = 0 }, rowChildren)
end

local function categoryNode(group: CategoryGroup): UiNode
	local mainSection, subSection = group.name:match("^(.-)%s*•%s*(.+)$")
	local headerNodes: { UiNode } = {}

	if mainSection and subSection then
		table.insert(
			headerNodes,
			ui.row({ gap = 6, align = "center" }, {
				ui.label({
					text = mainSection:upper(),
					color = "on_surface_variant",
					fontSize = 11,
					fontWeight = "bold",
				}),
				ui.glyph({ name = "chevron-right", size = 11, color = "on_surface_variant" }),
				ui.label({ text = subSection, color = "primary", fontSize = 13, fontWeight = "bold" }),
			})
		)
	else
		table.insert(
			headerNodes,
			ui.label({
				text = string.upper(group.name),
				color = "primary",
				fontSize = 13,
				fontWeight = "bold",
			})
		)
	end

	table.insert(headerNodes, ui.separator({ color = "outline/0.25", thickness = 1, spacing = 2 }))

	local children = headerNodes
	local occurrences: { [string]: number } = {}
	for _, binding in ipairs(group.bindings) do
		occurrences[binding.id] = (occurrences[binding.id] or 0) + 1
		table.insert(children, bindingRow(binding, occurrences[binding.id]))
	end

	return ui.column({ key = "category-" .. group.name, gap = 2, paddingV = 4, align = "stretch" }, children)
end

local function bindingsBody(): UiNode
	local groups = visibleGroups()
	if #groups == 0 then
		return ui.column({ flexGrow = 1, align = "center", justify = "center" }, {
			ui.glyph({ name = "search-off", size = 32, color = "on_surface_variant" }),
			ui.label({ text = tr("no_results"), color = "on_surface_variant" }),
		})
	end
	local columns = balancedColumns(groups, columnCount())
	local columnNodes: { UiNode } = {}
	for index, column in ipairs(columns) do
		local categoryNodes: { UiNode } = {}
		for _, group in ipairs(column.groups) do
			table.insert(categoryNodes, categoryNode(group))
		end
		table.insert(
			columnNodes,
			ui.column({ key = "column-" .. index, flexGrow = 1, gap = 8, align = "stretch" }, categoryNodes)
		)
	end
	return ui.scroll({ flexGrow = 1, gap = 0 }, {
		ui.row({ key = "binding-columns", gap = 22, align = "stretch" }, columnNodes),
	})
end

local function colorControl(bucket: ColorBucket, property: "background" | "text"): UiNode
	return ui.row({ gap = 5, align = "center", flexGrow = 1 }, {
		ui.box({
			width = 24,
			height = 24,
			radius = 5,
			fill = colorValue(bucket.id, property),
			border = "outline",
			borderWidth = 1,
		}),
		ui.button({
			text = property == "background" and tr("background") or tr("text"),
			variant = "ghost",
			controlSize = "sm",
			flexGrow = 1,
			onClick = function()
				chooseColor(bucket.id, property)
			end,
		}),
		ui.button({
			glyph = "clipboard",
			variant = "ghost",
			controlSize = "sm",
			tooltip = tr("paste"),
			onClick = function()
				pasteColor(bucket.id, property)
			end,
		}),
		ui.button({
			glyph = "restore",
			variant = "ghost",
			controlSize = "sm",
			tooltip = tr("reset"),
			onClick = function()
				local colorObj = preferences.colors[bucket.id]
				if colorObj ~= nil then
					if property == "background" then
						colorObj.background = nil
					else
						colorObj.text = nil
					end

					if colorObj.background == nil and colorObj.text == nil then
						preferences.colors[bucket.id] = nil
					end

					savePreferences()
					render()
				end
			end,
		}),
	})
end

local function appearanceBody(): UiNode
	local rows: { UiNode } = {
		ui.label({ text = tr("customize_colors"), color = "on_surface_variant" }),
	}
	for _, bucket in ipairs(COLOR_BUCKETS) do
		table.insert(
			rows,
			ui.column({ key = "color-" .. bucket.id, gap = 5, paddingV = 4 }, {
				ui.label({ text = bucket.label, fontWeight = "medium" }),
				ui.row({ gap = 12, align = "center" }, {
					colorControl(bucket, "background"),
					colorControl(bucket, "text"),
				}),
			})
		)
	end

	table.insert(rows, ui.separator({ spacing = 6 }))
	table.insert(
		rows,
		ui.row({ gap = 8, align = "center" }, {
			ui.button({
				glyph = "restore",
				text = tr("reset_colors"),
				onClick = function()
					preferences.colors = {}
					savePreferences()
					render()
				end,
			}),
		})
	)
	return ui.scroll({ flexGrow = 1, gap = 4 }, rows)
end

local function renderHeader(): UiNode
	local title = tr("title")
	if currentCompositor ~= "" then
		title = (currentCompositor == "mango" and "Mango" or (currentCompositor == "niri" and "Niri" or "Hyprland"))
			.. " Keymap"
	end

	local children: { UiNode } = {
		ui.row({ minWidth = 230, gap = 7, align = "center", flexGrow = 1 }, {
			ui.glyph({ name = "keyboard", size = 16, color = "primary" }),
			ui.label({ text = title, fontSize = 15, fontWeight = "bold", color = "on_surface" }),
		}),
	}

	if (view == "bindings" or view == "edit") and not loading and panelError == nil then
		table.insert(
			children,
			ui.input({
				key = "search-" .. searchRevision,
				value = query,
				placeholder = "Search keybinds... (/)",
				focus = (view == "bindings" and editingId == nil and searchFocused),
				controlSize = "sm",
				width = 300,
				onChange = function(value: string)
					query = value
					editingId = nil
					render()
				end,
			})
		)
		table.insert(
			children,
			ui.button({
				glyph = "x",
				width = 26,
				variant = "ghost",
				controlSize = "sm",
				enabled = query ~= "",
				tooltip = tr("clear"),
				onClick = function()
					query = ""
					searchRevision += 1
					searchFocused = true
					render()
				end,
			})
		)
	end

	if not loading or #bindings > 0 then
		table.insert(
			children,
			ui.label({
				text = tr("binding_count", { count = #bindings }),
				color = "on_surface_variant",
				fontSize = 12,
			})
		)
	end

	if view == "edit" then
		local count = hiddenBindingCount(bindings, preferences.hidden)
		table.insert(
			children,
			ui.label({
				text = tr("hidden_count", { count = count }),
				color = "on_surface_variant",
				fontSize = 12,
			})
		)
		table.insert(
			children,
			ui.button({
				glyph = "eye",
				variant = "ghost",
				controlSize = "sm",
				enabled = count > 0,
				tooltip = tr("restore_hidden"),
				onClick = function()
					restoreHiddenBindings(bindings, preferences.hidden)
					savePreferences()
					render()
				end,
			})
		)
	end

	table.insert(
		children,
		ui.button({
			glyph = "refresh",
			variant = "ghost",
			tooltip = tr("refresh"),
			enabled = true,
			onClick = function()
				refresh()
			end,
		})
	)

	table.insert(
		children,
		ui.button({
			glyph = view == "edit" and "check" or "pencil",
			variant = "ghost",
			tooltip = view == "edit" and tr("finish_editing") or tr("edit_bindings"),
			selected = view == "edit",
			onClick = function()
				view = view == "edit" and "bindings" or "edit"
				editingId = nil
				editDraft = ""
				render()
			end,
		})
	)

	table.insert(
		children,
		ui.button({
			glyph = view == "appearance" and "check" or "palette",
			variant = "ghost",
			tooltip = view == "appearance" and tr("back") or tr("appearance"),
			selected = view == "appearance",
			onClick = function()
				view = view == "appearance" and "bindings" or "appearance"
				editingId = nil
				editDraft = ""
				render()
			end,
		})
	)

	return ui.row({ align = "center", justify = "space_between", gap = 7 }, children)
end

render = function()
	if not panelOpen then
		return
	end

	local contentState = "bindings"
	if view == "appearance" then
		contentState = "appearance"
	elseif loading then
		contentState = "loading"
	elseif panelError ~= nil then
		contentState = "error"
	elseif view == "edit" then
		contentState = "edit"
	end

	local children: { UiNode } = { renderHeader() }

	if view == "appearance" then
		table.insert(children, appearanceBody())
	elseif loading then
		table.insert(
			children,
			ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 10 }, {
				ui.glyph({ name = "loader", size = 32, color = "primary" }),
				ui.label({ text = tr("loading"), color = "on_surface_variant" }),
			})
		)
	elseif panelError ~= nil then
		table.insert(
			children,
			ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 10 }, {
				ui.glyph({ name = "alert-triangle", size = 32, color = "error" }),
				ui.label({ text = panelError, color = "error", textAlign = "center", maxWidth = 640 }),
			})
		)
	else
		if refreshError ~= nil then
			table.insert(children, ui.label({ text = refreshError, color = "error", fontSize = 11, maxLines = 2 }))
		end
		if #parseWarnings > 0 then
			table.insert(
				children,
				ui.label({
					text = tr("source_warning") .. " " .. table.concat(parseWarnings, " | "),
					color = "error",
					fontSize = 11,
					maxLines = 2,
				})
			)
		end
		table.insert(children, bindingsBody())
	end

	panel.render(ui.column({
		key = "keybind-cheatsheet-" .. contentState,
		flexGrow = 1,
		gap = 8,
		align = "stretch",
	}, children))
end

-- Watch state snapshot updates
snapshotChannel.watch(function(value)
	applySnapshot(value)
	if panelOpen then
		render()
	end
end)

-- Register panel lifecycle hooks via STL
stl.lifecycle.panel(getfenv(), {
	onOpen = function(_context: string?)
		panelOpen = true
		view = "bindings"
		query = ""
		searchRevision += 1
		searchFocused = true
		editingId = nil
		editDraft = ""
		loadPreferences()
		applySnapshot(snapshotChannel.get())
		render()
	end,

	onClose = function()
		panelOpen = false
		view = "bindings"
		query = ""
		searchFocused = false
		editingId = nil
		editDraft = ""
	end,

	onKey = function(chord: string, pressed: boolean)
		if not pressed then
			return
		end
		if chord == "q" or chord == "Escape" then
			if query ~= "" then
				query = ""
				searchRevision += 1
				searchFocused = true
				render()
			else
				panel.close()
			end
		elseif chord == "r" and view ~= "appearance" and editingId == nil then
			refresh()
		end
	end,

	onIpc = function(event: string, _payload: string)
		if event == "toggle" then
			if panelOpen then
				panel.close()
			else
				noctalia.togglePanel(constants.PANEL_ID)
			end
		elseif event == "refresh" then
			refresh()
		elseif event == "focus-search" then
			searchFocused = true
			searchRevision += 1
			render()
		end
	end,
})

render()

return {
	render = render,
}
