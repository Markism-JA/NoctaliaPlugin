--!strict
-- Pure string transformation & normalization utilities for compositor parsers

local types = require("../types.luau")

type BindingEntry = types.BindingEntry
type ScanRule = types.ScanRule
type ModifierPill = types.ModifierPill

local common = {}

local MODIFIER_ORDER = { "SUPER", "CTRL", "SHIFT", "ALT", "MOD2", "MOD3", "MOD5" }

local KNOWN_MODIFIERS: { [string]: boolean } = {
	SUPER = true,
	CTRL = true,
	SHIFT = true,
	ALT = true,
	MOD2 = true,
	MOD3 = true,
	MOD5 = true,
}

local MODIFIER_ALIASES: { [string]: string } = {
	LOGO = "SUPER",
	WIN = "SUPER",
	MOD4 = "SUPER",
	CONTROL = "CTRL",
	MOD1 = "ALT",
}

local MODIFIER_DISPLAY: { [string]: string } = {
	SUPER = "Super",
	CTRL = "Ctrl",
	SHIFT = "Shift",
	ALT = "Alt",
	MOD2 = "Mod2",
	MOD3 = "Mod3",
	MOD5 = "Mod5",
}

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

local KEYWORD_CATEGORY_MAP: { [string]: string } = {
	launch = "Applications & Launchers",
	terminal = "Applications & Launchers",
	browser = "Applications & Launchers",
	rofi = "Applications & Launchers",
	wofi = "Applications & Launchers",
	launcher = "Applications & Launchers",
	fsearch = "Applications & Launchers",

	toggle = "Shell & Desktop Controls",
	bar = "Shell & Desktop Controls",
	clipboard = "Shell & Desktop Controls",
	wallpaper = "Shell & Desktop Controls",
	theme = "Shell & Desktop Controls",
	session = "Shell & Desktop Controls",
	cheatsheet = "Shell & Desktop Controls",

	close = "Window Management & Placement",
	zap = "Window Management & Placement",
	float = "Window Management & Placement",
	maximize = "Window Management & Placement",
	fullscreen = "Window Management & Placement",
	pin = "Window Management & Placement",
	align = "Window Management & Placement",
	split = "Window Management & Placement",

	focus = "Focus & Navigation",
	move = "Focus & Navigation",
	cycle = "Focus & Navigation",
	monitor = "Focus & Navigation",

	workspace = "Workspaces & Scratchpads",
	scratchpad = "Workspaces & Scratchpads",

	layout = "Workspace Layouts",
	master = "Workspace Layouts",
	dwindle = "Workspace Layouts",
	scrolling = "Workspace Layouts",
	monocle = "Workspace Layouts",

	brightness = "Media & Hardware",
	volume = "Media & Hardware",
	mute = "Media & Hardware",
	media = "Media & Hardware",
	track = "Media & Hardware",
	zoom = "Media & Hardware",
	audio = "Media & Hardware",
	monbrightness = "Media & Hardware",

	screen = "Screen Toolkit & Capture Utilities",
	annotate = "Screen Toolkit & Capture Utilities",
	ocr = "Screen Toolkit & Capture Utilities",
	lens = "Screen Toolkit & Capture Utilities",
	picker = "Screen Toolkit & Capture Utilities",
	qr = "Screen Toolkit & Capture Utilities",
	measure = "Screen Toolkit & Capture Utilities",
	screenshot = "Screen Toolkit & Capture Utilities",
	recorder = "Screen Toolkit & Capture Utilities",
	gsr = "Screen Toolkit & Capture Utilities",
	grim = "Screen Toolkit & Capture Utilities",
	slurp = "Screen Toolkit & Capture Utilities",

	passthrough = "Submaps & Modes: VM Passthrough",
	submap = "Submaps & Modes: VM Passthrough",
}

local HYPR_DISPATCHER_CATEGORIES: { [string]: string } = {
	killactive = "Window Management & Placement",
	closewindow = "Window Management & Placement",
	togglefloating = "Window Management & Placement",
	fullscreen = "Window Management & Placement",
	movefocus = "Focus & Navigation",
	focuswindow = "Focus & Navigation",
	cyclenext = "Focus & Navigation",
	focusmonitor = "Focus & Navigation",
	workspace = "Workspaces & Scratchpads",
	movetoworkspace = "Workspaces & Scratchpads",
	togglespecialworkspace = "Workspaces & Scratchpads",
	layout = "Workspace Layouts",
	submap = "Submaps & Modes: VM Passthrough",
}

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

local KNOWN_PROGRAMS: { [string]: string } = {
	alacritty = "Terminal",
	chromium = "Browser",
	dolphin = "File Manager",
	firefox = "Browser",
	foot = "Terminal",
	kitty = "Terminal",
	nautilus = "File Manager",
	thunar = "File Manager",
}

function common.lower(s: string?): string
	return string.lower(s or "")
end

function common.startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

function common.trim(s: string?): string
	if not s or s == "" then
		return ""
	end
	return string.match(s, "^%s*(.-)%s*$") or ""
end

function common.titleCase(value: string): string
	local clean = string.gsub(common.trim(value), "[_%-]+", " ")
	return (
		string.gsub(clean, "%a[%w']*", function(word: string): string
			return string.upper(string.sub(word, 1, 1)) .. common.lower(string.sub(word, 2))
		end)
	)
end

function common.formatKey(key: string?): string
	if key == nil or key == "" then
		return ""
	end
	local exact = KEY_LABELS[key]
	if exact ~= nil then
		return exact
	end
	local lowered = KEY_LABELS[common.lower(key)]
	if lowered ~= nil then
		return lowered
	end
	return (string.gsub(key, "^mouse:", "Mouse "))
end

function common.bucketForKey(key: string?): string
	local value = common.lower(key)
	if common.startsWith(value, "xf86") then
		return "xf86"
	end
	if string.match(value, "^%d$") then
		return "number"
	end
	if
		common.startsWith(value, "mouse")
		or common.startsWith(value, "btn_")
		or string.find(value, "wheel", 1, true) ~= nil
	then
		return "mouse"
	end
	if value == "print" or value == "prior" or value == "next" then
		return "print"
	end
	return "default"
end

function common.bucketForModifier(modifier: string): string
	local value = common.lower(modifier)
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

function common.splitCsv(value: string, maximumParts: number?): { string }
	local parts: { string } = {}
	local count = 0
	for item in string.gmatch(value .. ",", "(.-),") do
		count += 1
		if maximumParts and count >= maximumParts then
			break
		end
		table.insert(parts, common.trim(item))
	end
	if #parts == 0 then
		table.insert(parts, common.trim(value))
	end
	return parts
end

function common.parseHeading(rawLine: string): { level: number, title: string }?
	local firstChar = string.sub(rawLine, 1, 1)
	if firstChar ~= "-" and firstChar ~= "#" and firstChar ~= "/" and firstChar ~= " " and firstChar ~= "\t" then
		return nil
	end

	local commentPrefix, rest = string.match(rawLine, "^%s*([%-#/]+)%s*(.*)$")
	if not commentPrefix or not rest or rest == "" then
		return nil
	end

	local level = 0
	local rawTitle = ""

	if string.sub(rest, 1, 2) == "==" then
		level = 2
		rawTitle = string.match(rest, "^==%s+(.-)%s*==*$") or string.match(rest, "^==%s+(.-)%s*$") or ""
	elseif string.sub(rest, 1, 1) == "=" then
		level = 1
		rawTitle = string.match(rest, "^=%s+(.-)%s*=+$") or string.match(rest, "^=%s+(.-)%s*$") or ""
	end

	if level == 0 or rawTitle == "" then
		return nil
	end

	local title = common.trim(rawTitle)
	if #title < 2 or #title > 55 then
		return nil
	end

	local l = string.lower(title)
	if
		string.sub(l, 1, 4) == "bind"
		or string.sub(l, 1, 4) == "exec"
		or string.sub(l, 1, 5) == "local"
		or string.sub(l, 1, 6) == "return"
		or string.find(title, "=", 1, true) ~= nil
	then
		return nil
	end

	return { level = level, title = title }
end

function common.buildCategory(section: string, subsection: string): string
	if subsection ~= "" and subsection ~= section then
		return section .. " • " .. subsection
	end
	return section
end

function common.normalizeModifiers(value: string?, variables: { [string]: string }?): { string }
	local raw = value or ""
	if variables then
		for varName, varVal in variables do
			raw = string.gsub(raw, "%$" .. varName, varVal)
			raw = string.gsub(raw, varName, varVal)
		end
	end
	raw = string.gsub(string.gsub(string.gsub(raw, "%+", " "), "|", " "), ",", " ")
	local present: { [string]: boolean } = {}
	local unknown: { string } = {}

	for token in string.gmatch(raw, "[^%s]+") do
		local upper = string.upper(token)
		upper = MODIFIER_ALIASES[upper] or upper
		if upper ~= "NONE" and upper ~= "" then
			if KNOWN_MODIFIERS[upper] then
				present[upper] = true
			elseif not present[upper] then
				present[upper] = true
				table.insert(unknown, upper)
			end
		end
	end

	local result: { string } = {}
	for _, name in ipairs(MODIFIER_ORDER) do
		if present[name] then
			table.insert(result, name)
		end
	end
	for _, name in ipairs(unknown) do
		table.insert(result, name)
	end
	return result
end

function common.friendlySpawn(commandLine: string): string
	local value = common.lower(common.trim(commandLine))
	if string.find(value, "panel-toggle launcher", 1, true) ~= nil then
		return "Application Launcher"
	end
	if string.find(value, "panel-toggle session", 1, true) ~= nil then
		return "Power Menu"
	end
	if string.find(value, "session lock", 1, true) ~= nil then
		return "Lock Screen"
	end
	if string.find(value, "playerctl play-pause", 1, true) ~= nil then
		return "Play / Pause"
	end
	if string.find(value, "playerctl next", 1, true) ~= nil then
		return "Next Track"
	end
	if string.find(value, "playerctl previous", 1, true) ~= nil then
		return "Previous Track"
	end
	if string.find(value, "playerctl stop", 1, true) ~= nil then
		return "Stop Playback"
	end
	if string.find(value, "wpctl set-volume", 1, true) ~= nil then
		return string.find(value, "+", 1, true) ~= nil and "Volume Up" or "Volume Down"
	end
	if string.find(value, "wpctl set-mute", 1, true) ~= nil then
		return string.find(value, "source", 1, true) ~= nil and "Toggle Microphone Mute" or "Toggle Mute"
	end
	if string.find(value, "brightnessctl", 1, true) ~= nil then
		return string.find(value, "+", 1, true) ~= nil and "Brightness Up" or "Brightness Down"
	end

	local program = string.match(common.trim(commandLine), "^([^%s]+)") or "Application"
	program = string.match(program, "([^/]+)$") or program
	local match = KNOWN_PROGRAMS[common.lower(program)]
	return match or ("Launch " .. common.titleCase(program))
end

function common.friendlyAction(actionRaw: string): string
	local action = common.trim(actionRaw)
	local command, arguments = string.match(action, "^(%S+)%s*(.*)$")
	command = string.gsub(common.lower(command or ""), "%-", "_")
	arguments = common.trim(arguments or "")
	if command == "spawn" or command == "spawn_shell" or command == "exec" then
		return common.friendlySpawn(arguments)
	end
	if ACTION_LABELS[command] ~= nil then
		return ACTION_LABELS[command]
	end

	local argument = string.match(arguments, "^([^,%s]+)") or ""
	local direction = argument ~= "" and common.titleCase(argument) or ""
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
		return common.titleCase(argument) .. " Layout"
	end
	if command == "set_proportion" then
		return "Set Window Proportion " .. argument
	end
	if command == "setmfact" then
		return "Set Layout Size " .. argument
	end
	if command == "moveresize" then
		return string.find(arguments, "curresize", 1, true) ~= nil and "Resize Window with Mouse"
			or "Move Window with Mouse"
	end
	return common.titleCase(action)
end

function common.bindingIdentity(binding: { [string]: any }): string
	return table.concat({
		tostring(binding.compositor or ""),
		tostring(binding.bindingType or ""),
		table.concat(binding.modifiers or {}, "+"),
		tostring(binding.key or ""),
		tostring(binding.action or ""),
		tostring(binding.submap or ""),
	}, "|")
end

function common.fallbackCategory(dispatcher: string?, arg: string?, desc: string?): string
	local d = common.lower(dispatcher)
	local directMatch = HYPR_DISPATCHER_CATEGORIES[d]
	if directMatch then
		return directMatch
	end

	local a = common.lower(arg)
	local s = common.lower(desc)
	local combined = d .. " " .. a .. " " .. s

	for token in string.gmatch(combined, "[%w_-]+") do
		local matched = KEYWORD_CATEGORY_MAP[token]
		if matched then
			return matched
		end
	end

	return "Other"
end

function common.extractTrailingDescription(line: string): (string, string)
	local ending = string.sub(line, -1)
	local startIndex: number?, description: string?
	if ending == '"' then
		startIndex, _, description = string.find(line, '#%s*"([^"]*)"%s*$')
	elseif ending == "'" then
		startIndex, _, description = string.find(line, "#%s*'([^']*)'%s*$")
	end
	if startIndex == nil then
		return line, ""
	end
	return common.trim(string.sub(line, 1, startIndex - 1)), common.trim(description or "")
end

--- Assembles a fully pre-baked BindingEntry containing display pills and search indexes.
function common.addBinding(target: { BindingEntry }, binding: any, skipTrim: boolean?)
	if not skipTrim then
		binding.description = common.trim(binding.description or "")
		binding.category = common.trim(binding.category or "")
		binding.section = common.trim(binding.section or "")
		binding.subsection = common.trim(binding.subsection or "")
		binding.action = common.trim(binding.action or "")
		binding.key = common.trim(binding.key or "")
	end
	binding.baseCategory = binding.category
	binding.modifiers = binding.modifiers or {}
	binding.id = common.bindingIdentity(binding)

	-- Pre-calculate display representation
	local formattedKey = common.formatKey(binding.key)
	local keyBucket = common.bucketForKey(binding.key)
	local modPills: { ModifierPill } = {}

	for _, mod in ipairs(binding.modifiers) do
		table.insert(modPills, {
			text = MODIFIER_DISPLAY[mod] or (string.sub(mod, 1, 1) .. common.lower(string.sub(mod, 2))),
			bucket = common.bucketForModifier(mod),
		})
	end

	local displayDesc = if binding.description ~= "" then binding.description else common.friendlyAction(binding.action)

	-- Pre-bake single lowercase search index: "super ctrl q close window killactive"
	local searchParts = {
		table.concat(binding.modifiers, " "),
		binding.key,
		formattedKey,
		displayDesc,
		binding.category,
		binding.action,
	}
	local searchIndex = common.lower(table.concat(searchParts, " "))

	binding.formattedKey = formattedKey
	binding.keyBucket = keyBucket
	binding.modPills = modPills
	binding.displayDescription = displayDesc
	binding.searchIndex = searchIndex

	table.insert(target, binding :: BindingEntry)
end

return common
