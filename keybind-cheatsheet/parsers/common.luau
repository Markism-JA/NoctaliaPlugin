--!strict
-- Pure string transformation & normalization utilities for compositor parsers

local types = require("../types.luau")

type BindingEntry = types.BindingEntry
type ScanRule = types.ScanRule

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

-- O(1) direct keyword table instead of an array of regex iterations
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

--- Fast-path heading parser
function common.parseHeading(rawLine: string): { level: number, title: string }?
	-- Fast exit if the line cannot be a comment heading
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
	table.insert(target, binding :: BindingEntry)
end

--- O(1) keyword tokenizer category fallback (no multiple regex passes)
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

return common
