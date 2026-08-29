--!strict
-- Cache-first keybind data service for Mango, Hyprland, and Niri.

local stl = require("../stl/stl.luau")
local config = stl.config
local filesystem = stl.filesystem
local lifecycle = stl.lifecycle
local logger = stl.log
local log = stl.log.scope("KeybindService")
local proc = stl.proc
local state = stl.state
local test = stl.test

local service = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

export type Compositor = "mango" | "hyprland" | "niri"
export type ParserKind = "mango" | "niri" | "hypr-lua" | "hypr-conf"

export type BindingRequest = {
	compositor: Compositor,
	parser: ParserKind,
	root: string,
}

export type BindingEntry = {
	id: string,
	compositor: Compositor,
	bindingType: string,
	modifiers: { string },
	key: string,
	action: string,
	description: string,
	section: string,
	subsection: string,
	category: string,
	baseCategory: string,
	sourceFile: string,
	sourceLine: number,
	submap: string?,
}

export type SourceSnapshot = {
	path: string,
	size: number,
	mtime: number,
}

export type CachePayload = {
	schema: number,
	request: BindingRequest,
	bindings: { BindingEntry },
	warnings: { string },
	sources: { SourceSnapshot },
}

export type SnapshotState = {
	schema: number,
	status: "ready" | "loading" | "error",
	compositor: string,
	parser: string,
	source: string,
	request: BindingRequest?,
	bindings: { BindingEntry },
	warnings: { string },
	error: string,
	refreshing: boolean,
}

export type ScanRule = {
	section: string,
	subsection: string,
	category: string,
}

export type ParseContext = {
	bindings: { BindingEntry },
	variables: { [string]: string },
	warnings: { string },
	sources: { SourceSnapshot },
	exactRules: { [string]: ScanRule },
}

-- =============================================================================
-- Constants & Static Configurations
-- =============================================================================

local SNAPSHOT_KEY = "keybind-cheatsheet.snapshot"
local REFRESH_REQUEST_KEY = "keybind-cheatsheet.refresh-request"
local BINDINGS_CACHE_FILE = "bindings-cache.json"
local CACHE_SCHEMA = 2
local MAX_SCAN_DEPTH = 3
local MAX_FILE_SIZE_BYTES = 262144 -- 256 KiB ceiling

local IGNORED_DIRECTORIES: { [string]: boolean } = {
	[".git"] = true,
	[".hg"] = true,
	[".svn"] = true,
	["node_modules"] = true,
	["cache"] = true,
	[".cache"] = true,
}

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

-- =============================================================================
-- Pure Utility & Parser Methods (Exported for Testing)
-- =============================================================================

function service.lower(s: string?): string
	return string.lower(s or "")
end

function service.startsWith(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

function service.trim(s: string?): string
	if not s or s == "" then
		return ""
	end
	local from = string.match(s, "^%s*()")
	if not from then
		return ""
	end
	return if from > #s then "" else (string.match(s, ".*%S", from) or "")
end

function service.normalizePath(path: string): string
	local absolute = string.sub(path, 1, 1) == "/"
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			if #parts > 0 and parts[#parts] ~= ".." then
				table.remove(parts)
			elseif not absolute then
				table.insert(parts, part)
			end
		elseif part ~= "." and part ~= "" then
			table.insert(parts, part)
		end
	end
	local result = table.concat(parts, "/")
	if absolute then
		result = "/" .. result
	end
	return result == "" and (if absolute then "/" else ".") or result
end

function service.expandEnvironment(path: string): string
	local function getEnvSafe(name: string): string?
		if (noctalia :: any) ~= nil and (noctalia :: any).getenv ~= nil then
			return noctalia.getenv(name)
		elseif (os :: any) ~= nil and typeof((os :: any).getenv) == "function" then
			return (os :: any).getenv(name)
		end
		return nil
	end

	local expanded = string.gsub(path, "%${([%w_]+)}", function(name: string)
		return getEnvSafe(name) or ("${" .. name .. "}")
	end)

	local homeVal = getEnvSafe("HOME")
	expanded = string.gsub(expanded, "%$HOME", homeVal or "~")

	if (noctalia :: any) ~= nil and (noctalia :: any).expandPath ~= nil then
		return noctalia.expandPath(expanded)
	end
	return expanded
end

function service.splitCsv(value: string, maximumParts: number?): { string }
	local parts: { string } = {}
	local count = 0
	for item in string.gmatch(value .. ",", "(.-),") do
		count += 1
		if maximumParts and count >= maximumParts then
			break
		end
		table.insert(parts, service.trim(item))
	end
	if #parts == 0 then
		table.insert(parts, service.trim(value))
	end
	return parts
end

function service.parseHeading(rawLine: string): { level: number, title: string }?
	local body = string.match(rawLine, "^%s*#+%s*(.*)$")
		or string.match(rawLine, "^%s*%-%-+%s*(.*)$")
		or string.match(rawLine, "^%s*//+%s*(.*)$")
	if not body then
		return nil
	end

	local level = 0
	local rawText = ""

	local sub = string.match(body, "^==+%s*(.*)$")
	if sub then
		level = 2
		rawText = sub
	else
		local main = string.match(body, "^=+%s*(.*)$")
		if main then
			level = 1
			rawText = main
		end
	end

	if level == 0 or rawText == "" then
		return nil
	end

	local stripped = string.gsub(rawText, "=+$", "")
	local rawTitle = string.match(stripped, "^%s*(.-)%s*$")
	if not rawTitle or #rawTitle < 2 or #rawTitle > 45 then
		return nil
	end

	local title: string = rawTitle
	local l = service.lower(title)
	if
		string.match(l, "^bind")
		or string.match(l, "^exec")
		or string.match(l, "^local%s")
		or string.match(l, "^return%s")
		or string.match(l, "^note:")
		or string.match(l, "^todo:")
		or string.match(l, "^fixme:")
		or string.find(title, "=", 1, true)
		or string.match(title, "[%.;]$")
		or string.match(title, "^https?://")
	then
		return nil
	end

	return { level = level, title = title }
end

function service.buildCategory(section: string, subsection: string): string
	if subsection ~= "" then
		return section .. " • " .. subsection
	end
	return section
end

function service.normalizeModifiers(value: string?, variables: { [string]: string }?): { string }
	local raw = value or ""
	if variables then
		for varName, varVal in variables do
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

function service.bindingIdentity(binding: { [string]: any }): string
	return table.concat({
		tostring(binding.compositor or ""),
		tostring(binding.bindingType or ""),
		table.concat(binding.modifiers or {}, "+"),
		tostring(binding.key or ""),
		tostring(binding.action or ""),
		tostring(binding.submap or ""),
	}, "|")
end

function service.addBinding(target: { BindingEntry }, binding: any, skipTrim: boolean?)
	if not skipTrim then
		binding.description = service.trim(binding.description or "")
		binding.category = service.trim(binding.category or "")
		binding.section = service.trim(binding.section or "")
		binding.subsection = service.trim(binding.subsection or "")
		binding.action = service.trim(binding.action or "")
		binding.key = service.trim(binding.key or "")
	end
	binding.baseCategory = binding.category
	binding.modifiers = binding.modifiers or {}
	binding.id = service.bindingIdentity(binding)
	table.insert(target, binding :: BindingEntry)
end

function service.fallbackCategory(dispatcher: string?, arg: string?, desc: string?): string
	local d: string = service.lower(dispatcher)
	local a: string = service.lower(arg)
	local s: string = service.lower(desc)
	local combined: string = d .. " " .. a .. " " .. s

	if
		string.find(s, "launch", 1, true)
		or string.find(s, "terminal", 1, true)
		or string.find(s, "browser", 1, true)
		or string.find(s, "file manager", 1, true)
		or string.find(combined, "rofi", 1, true)
		or string.find(combined, "wofi", 1, true)
		or string.find(combined, "launcher", 1, true)
		or string.find(combined, "fsearch", 1, true)
	then
		return "Applications & Launchers"
	end
	if
		string.find(s, "toggle", 1, true)
		or string.find(s, "control center", 1, true)
		or string.find(s, "bar", 1, true)
		or string.find(s, "clipboard", 1, true)
		or string.find(s, "wallpaper", 1, true)
		or string.find(s, "theme", 1, true)
		or string.find(s, "session", 1, true)
		or string.find(s, "cheatsheet", 1, true)
	then
		return "Shell & Desktop Controls"
	end
	if
		string.find(s, "close", 1, true)
		or string.find(s, "zap", 1, true)
		or string.find(s, "float", 1, true)
		or string.find(s, "maximize", 1, true)
		or string.find(s, "fullscreen", 1, true)
		or string.find(s, "pin", 1, true)
		or string.find(s, "align", 1, true)
		or string.find(s, "split", 1, true)
		or d == "killactive"
		or d == "closewindow"
		or d == "togglefloating"
		or d == "fullscreen"
	then
		return "Window Management & Placement"
	end
	if
		string.find(s, "focus window", 1, true)
		or string.find(s, "move window", 1, true)
		or string.find(s, "cycle", 1, true)
		or string.find(s, "monitor", 1, true)
		or d == "movefocus"
		or d == "focuswindow"
		or d == "cyclenext"
		or d == "focusmonitor"
	then
		return "Focus & Navigation"
	end
	if
		string.find(s, "workspace", 1, true)
		or string.find(s, "scratchpad", 1, true)
		or d == "workspace"
		or d == "movetoworkspace"
		or d == "togglespecialworkspace"
	then
		return "Workspaces & Scratchpads"
	end
	if
		string.find(s, "layout", 1, true)
		or string.find(s, "master", 1, true)
		or string.find(s, "dwindle", 1, true)
		or string.find(s, "scrolling", 1, true)
		or string.find(s, "monocle", 1, true)
		or d == "layout"
	then
		return "Workspace Layouts"
	end
	if
		string.find(s, "brightness", 1, true)
		or string.find(s, "volume", 1, true)
		or string.find(s, "mute", 1, true)
		or string.find(s, "media", 1, true)
		or string.find(s, "track", 1, true)
		or string.find(s, "zoom", 1, true)
		or string.find(combined, "audio", 1, true)
		or string.find(combined, "monbrightness", 1, true)
	then
		return "Media & Hardware"
	end
	if
		string.find(s, "screen", 1, true)
		or string.find(s, "annotate", 1, true)
		or string.find(s, "ocr", 1, true)
		or string.find(s, "lens", 1, true)
		or string.find(s, "picker", 1, true)
		or string.find(s, "qr", 1, true)
		or string.find(s, "measure", 1, true)
		or string.find(s, "screenshot", 1, true)
		or string.find(s, "recorder", 1, true)
		or string.find(s, "gsr", 1, true)
		or string.find(combined, "grim", 1, true)
		or string.find(combined, "slurp", 1, true)
		or string.find(combined, "screen-toolkit", 1, true)
	then
		return "Screen Toolkit & Capture Utilities"
	end
	if string.find(s, "passthrough", 1, true) or string.find(s, "submap", 1, true) or d == "submap" then
		return "Submaps & Modes: VM Passthrough"
	end

	return "Other"
end

function service.extractTrailingDescription(line: string): (string, string)
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
	return service.trim(string.sub(line, 1, startIndex - 1)), service.trim(description or "")
end

function service.parseMangoContent(content: string, sourceFile: string, context: ParseContext)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in string.gmatch(content, "[^\r\n]+") do
		lineNumber += 1
		local line = service.trim(rawLine)
		if line ~= "" then
			local heading = service.parseHeading(line)
			if heading then
				if heading.level == 1 then
					currentSection = heading.title
					currentSubsection = ""
				elseif heading.level == 2 then
					currentSubsection = heading.title
				end
			elseif string.find(line, "bind", 1, true) ~= nil then
				local clean, description = service.extractTrailingDescription(line)
				local directive, body = string.match(clean, "^([%a]*bind)%s*=%s*(.*)$")
				if directive ~= nil and body ~= nil then
					local fields = service.splitCsv(body)
					local modifiers = service.normalizeModifiers(fields[1], nil)
					local key = fields[2] or ""
					local command = fields[3] or ""

					local restParts: { string } = {}
					for i = 4, #fields do
						if fields[i] ~= "" then
							table.insert(restParts, fields[i])
						end
					end
					local parameters = table.concat(restParts, " ")

					if key ~= "" and command ~= "" then
						local category = service.buildCategory(currentSection, currentSubsection)
						if category == "General" and description == "" then
							category = service.fallbackCategory(command, parameters, description)
						end

						local action = if parameters ~= "" then (command .. " " .. parameters) else command

						service.addBinding(context.bindings, {
							compositor = "mango",
							bindingType = service.lower(directive),
							modifiers = modifiers,
							key = key,
							action = action,
							description = description,
							section = currentSection,
							subsection = currentSubsection,
							category = category,
							sourceFile = sourceFile,
							sourceLine = lineNumber,
						})
					end
				end
			end
		end
	end
end

function service.parseHyprContent(content: string, sourceFile: string, context: ParseContext)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in string.gmatch(content, "[^\r\n]+") do
		lineNumber += 1
		local line = service.trim(rawLine)
		if line ~= "" then
			local variable, value = string.match(line, "^%$([%w_]+)%s*=%s*(.-)%s*$")
			local heading = service.parseHeading(line)

			if variable ~= nil and value ~= nil then
				context.variables[variable] = value
			elseif heading ~= nil then
				if heading.level == 1 then
					currentSection = heading.title
					currentSubsection = ""
				elseif heading.level == 2 then
					currentSubsection = heading.title
				end
			else
				local clean, description = service.extractTrailingDescription(line)
				local directive, body = string.match(clean, "^(bind[%a]*)%s*=%s*(.*)$")
				if directive ~= nil and body ~= nil then
					local fields = service.splitCsv(body)
					local key = fields[2] or ""
					local dispatcher = fields[3] or ""

					local restParts: { string } = {}
					for i = 4, #fields do
						if fields[i] ~= "" then
							table.insert(restParts, fields[i])
						end
					end
					local parameters = table.concat(restParts, " ")

					if key ~= "" and dispatcher ~= "" then
						local category = service.buildCategory(currentSection, currentSubsection)
						if category == "General" and description == "" then
							category = service.fallbackCategory(dispatcher, parameters, description)
						end

						local action = if parameters ~= "" then (dispatcher .. " " .. parameters) else dispatcher

						service.addBinding(context.bindings, {
							compositor = "hyprland",
							bindingType = service.lower(directive),
							modifiers = service.normalizeModifiers(fields[1], context.variables),
							key = key,
							action = action,
							description = description,
							section = currentSection,
							subsection = currentSubsection,
							category = category,
							sourceFile = sourceFile,
							sourceLine = lineNumber,
						})
					end
				end
			end
		end
	end
end

function service.niriCategoryFor(action: string): string
	local value = service.lower(action)
	if service.startsWith(value, "spawn") then
		return "Applications & Launchers"
	end
	if service.startsWith(value, "focus-column-") or service.startsWith(value, "focus-window-") then
		return "Focus & Navigation"
	end
	if service.startsWith(value, "focus-workspace-") then
		return "Workspaces & Scratchpads"
	end
	if service.startsWith(value, "move-column-") or service.startsWith(value, "move-window-") then
		return "Window Management & Placement"
	end
	if service.startsWith(value, "screenshot") then
		return "Screen Toolkit & Capture Utilities"
	end
	if service.startsWith(value, "close-window") or service.startsWith(value, "fullscreen-window") then
		return "Window Management & Placement"
	end
	if service.startsWith(value, "power-off-monitors") or service.startsWith(value, "quit") then
		return "Shell & Desktop Controls"
	end
	return "Other"
end

function service.parseNiriContent(content: string, sourceFile: string, context: ParseContext)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in string.gmatch(content, "[^\r\n]+") do
		lineNumber += 1
		local line = service.trim(rawLine)

		if line ~= "" then
			local heading = service.parseHeading(line)
			if heading then
				if heading.level == 1 then
					currentSection = heading.title
					currentSubsection = ""
				elseif heading.level == 2 then
					currentSubsection = heading.title
				end
			else
				local bindChord, actionBody = string.match(line, "^([^{]+)%s*{%s*(.-)%s*;?%s*}%s*$")
				if bindChord and actionBody then
					local cleanAction = service.trim((string.gsub(actionBody, ";+$", "")))
					local modifiers = service.normalizeModifiers(bindChord, nil)
					local key = string.match(bindChord, "([^+%s]+)$") or ""

					local category = service.buildCategory(currentSection, currentSubsection)
					if category == "General" then
						category = service.niriCategoryFor(cleanAction)
					end

					service.addBinding(context.bindings, {
						compositor = "niri",
						bindingType = "bind",
						modifiers = modifiers,
						key = key,
						action = cleanAction,
						description = "",
						section = currentSection,
						subsection = currentSubsection,
						category = category,
						sourceFile = sourceFile,
						sourceLine = lineNumber,
					})
				end
			end
		end
	end
end

function service.scanHyprLuaContent(content: string, context: ParseContext)
	local currentSection = "General"
	local currentSubsection = ""

	for line in string.gmatch(content, "[^\r\n]+") do
		local heading = service.parseHeading(line)
		if heading then
			if heading.level == 1 then
				currentSection = heading.title
				currentSubsection = ""
			elseif heading.level == 2 then
				currentSubsection = heading.title
			end
		elseif string.find(line, "desc", 1, true) then
			local desc = string.match(line, "description%s*=%s*[\"']([^\"']+)[\"']")
				or string.match(line, "desc%s*=%s*[\"']([^\"']+)[\"']")
			if desc and desc ~= "" then
				context.exactRules[desc] = {
					section = currentSection,
					subsection = currentSubsection,
					category = service.buildCategory(currentSection, currentSubsection),
				}
			end
		end
	end
end

function service.scanHyprLua(rootPath: string): ParseContext
	local luaRoot = filesystem.dirName(service.normalizePath(service.expandEnvironment(rootPath)))
	local context: ParseContext = {
		bindings = {},
		variables = {},
		warnings = {},
		sources = {},
		exactRules = {},
	}

	local visited: { [string]: boolean } = {}
	local fileList: { string } = {
		service.normalizePath(service.expandEnvironment(rootPath)),
		filesystem.join(luaRoot, "keybinds.lua"),
		filesystem.join(luaRoot, "binds.lua"),
		filesystem.join(luaRoot, "modules/keybinds.lua"),
		filesystem.join(luaRoot, "plugins/gloview.lua"),
	}

	local rootContent, _ = filesystem.readText(fileList[1])
	if rootContent then
		for modName in string.gmatch(rootContent, "name%s*=%s*[\"']([^\"']+)[\"']") do
			if
				string.find(modName, "bind", 1, true)
				or string.find(modName, "workspaces", 1, true)
				or string.find(modName, "gloview", 1, true)
			then
				local relPath: string = (string.gsub(modName, "%.", "/")) .. ".lua"
				local fullModPath: string = filesystem.join(luaRoot, relPath)
				table.insert(fileList, fullModPath)
			end
		end
	end

	for _, path in ipairs(fileList) do
		local normPath = service.normalizePath(path)
		if not visited[normPath] then
			visited[normPath] = true
			local content, _ = filesystem.readText(normPath)
			if
				content
				and (
					string.find(content, "bind", 1, true)
					or string.find(content, "desc", 1, true)
					or string.find(content, "%-%-")
				)
			then
				local info, _ = noctalia.fileInfo(normPath)
				if info then
					table.insert(context.sources, { path = normPath, size = info.size, mtime = info.mtime })
				end
				service.scanHyprLuaContent(content, context)
			end
		end
	end

	return context
end

type JsonDecodeFn = (string) -> (any, string?)

local function resolveJsonDecoder(): JsonDecodeFn?
	local hostTable = test.host :: any
	if
		typeof(hostTable) == "table"
		and typeof(hostTable.json) == "table"
		and typeof(hostTable.json.decode) == "function"
	then
		return hostTable.json.decode :: JsonDecodeFn
	end

	local noctaliaHost = noctalia :: any
	if
		typeof(noctaliaHost) == "table"
		and typeof(noctaliaHost.json) == "table"
		and typeof(noctaliaHost.json.decode) == "function"
	then
		return noctaliaHost.json.decode :: JsonDecodeFn
	end

	return nil
end

function service.parseHyprJson(raw: string, scanContext: ParseContext): ({ BindingEntry }?, string?)
	local jsonDecoder = resolveJsonDecoder()
	if not jsonDecoder then
		return nil, "No JSON decoder available"
	end

	local decoded, err = jsonDecoder(raw)
	if typeof(decoded) ~= "table" then
		return nil, err or "Invalid hyprctl JSON"
	end
	local result: { BindingEntry } = {}

	for _, entry in ipairs(decoded :: { { [string]: any } }) do
		if typeof(entry) == "table" then
			local description: string = if entry.has_description == false then "" else (entry.description or "")
			local key: string = entry.key or ""
			if key == "" and tonumber(entry.keycode) ~= nil and tonumber(entry.keycode) ~= 0 then
				key = "code:" .. tostring(entry.keycode)
			end
			local dispatcher: string = entry.dispatcher or ""
			local argument: string = entry.arg or ""

			if key ~= "" and dispatcher ~= "" then
				local bType = if entry.mouse == true then "bindm" else "bind"
				local submap = entry.submap or ""
				local mask = tonumber(entry.modmask) or 0
				local modifiers: { string } = {}

				if bit32.band(mask, 64) ~= 0 then
					table.insert(modifiers, "SUPER")
				end
				if bit32.band(mask, 4) ~= 0 then
					table.insert(modifiers, "CTRL")
				end
				if bit32.band(mask, 1) ~= 0 then
					table.insert(modifiers, "SHIFT")
				end
				if bit32.band(mask, 8) ~= 0 then
					table.insert(modifiers, "ALT")
				end
				if bit32.band(mask, 16) ~= 0 then
					table.insert(modifiers, "MOD2")
				end
				if bit32.band(mask, 32) ~= 0 then
					table.insert(modifiers, "MOD3")
				end
				if bit32.band(mask, 128) ~= 0 then
					table.insert(modifiers, "MOD5")
				end

				local rule: ScanRule? = scanContext.exactRules[description]
				local section: string = if rule then rule.section else ""
				local subsection: string = if rule then rule.subsection else ""
				local category: string = if rule and rule.category ~= ""
					then rule.category
					else service.fallbackCategory(dispatcher, argument, description)

				if section == "" then
					section = category
				end

				local action = if argument ~= "" then (dispatcher .. " " .. argument) else dispatcher

				service.addBinding(result, {
					compositor = "hyprland",
					bindingType = bType,
					modifiers = modifiers,
					key = key,
					action = action,
					description = description,
					section = section,
					subsection = subsection,
					category = category,
					sourceFile = "hyprctl binds -j",
					sourceLine = 0,
					submap = submap,
				}, true)
			end
		end
	end
	return result, nil
end

-- =============================================================================
-- Orchestration & File Walkers
-- =============================================================================

local function collectSourceFiles(
	dirPath: string,
	extensionPattern: string,
	depth: number?,
	seen: { [string]: boolean }?,
	accum: { string }?
): { string }
	local currentDepth = depth or 1
	local visited = seen or {}
	local results = accum or {}

	if currentDepth > MAX_SCAN_DEPTH then
		return results
	end

	local entries, _ = noctalia.listDir(dirPath)
	if not entries then
		return results
	end

	for _, name in ipairs(entries) do
		if not IGNORED_DIRECTORIES[name] and not (string.sub(name, 1, 1) == "." and name ~= ".") then
			local fullPath = service.normalizePath(filesystem.join(dirPath, name))

			if not visited[fullPath] then
				visited[fullPath] = true
				local info, _ = noctalia.fileInfo(fullPath)
				if info then
					if info.isDir then
						collectSourceFiles(fullPath, extensionPattern, currentDepth + 1, visited, results)
					elseif string.match(name, extensionPattern) and info.size <= MAX_FILE_SIZE_BYTES then
						table.insert(results, fullPath)
					end
				end
			end
		end
	end

	return results
end

local function walkConfig(
	rootPath: string,
	parserFn: (string, string, ParseContext) -> (),
	extensionPattern: string
): ParseContext
	local rootDir = filesystem.dirName(service.normalizePath(service.expandEnvironment(rootPath)))
	local files = collectSourceFiles(rootDir, extensionPattern)
	local normalizedRoot = service.normalizePath(service.expandEnvironment(rootPath))

	local context: ParseContext = {
		bindings = {},
		variables = {},
		warnings = {},
		sources = {},
		exactRules = {},
	}

	local fileSet: { [string]: boolean } = {}
	for _, f in ipairs(files) do
		fileSet[f] = true
	end

	if not fileSet[normalizedRoot] then
		table.insert(files, normalizedRoot)
	end

	for _, path in ipairs(files) do
		local content, _ = filesystem.readText(path)
		if content then
			local info, _ = noctalia.fileInfo(path)
			if info then
				table.insert(context.sources, { path = path, size = info.size, mtime = info.mtime })
			end
			parserFn(content, path, context)
		end
	end

	return context
end

local function detectCompositor(): Compositor
	local forced = config.getString("compositor", "auto")
	if forced == "mango" or forced == "hyprland" or forced == "niri" then
		return forced
	end
	if noctalia.getenv("MANGO_INSTANCE_SIGNATURE") ~= nil then
		return "mango"
	end
	if noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= nil then
		return "hyprland"
	end
	if noctalia.getenv("NIRI_SOCKET") ~= nil then
		return "niri"
	end
	return "hyprland"
end

local function currentRequest(): BindingRequest
	local comp = detectCompositor()
	if comp == "mango" then
		return {
			compositor = comp,
			parser = "mango",
			root = service.normalizePath(
				service.expandEnvironment(config.getString("mango_config", "~/.config/mango/config.conf"))
			),
		}
	elseif comp == "niri" then
		return {
			compositor = comp,
			parser = "niri",
			root = service.normalizePath(
				service.expandEnvironment(config.getString("niri_config", "~/.config/niri/config.kdl"))
			),
		}
	else
		local mode = config.getString("hyprland_parser", "auto")
		local luaPath = config.getString("hyprland_lua_config", "~/.config/hypr/hyprland.lua")
		local useLua = mode == "lua" or (mode == "auto" and noctalia.fileExists(noctalia.expandPath(luaPath)))
		local root = if useLua then luaPath else config.getString("hyprland_config", "~/.config/hypr/hyprland.conf")
		return {
			compositor = "hyprland",
			parser = if useLua then "hypr-lua" else "hypr-conf",
			root = service.normalizePath(service.expandEnvironment(root)),
		}
	end
end

local function isCacheFresh(cached: CachePayload?, request: BindingRequest): boolean
	if not cached or cached.schema ~= CACHE_SCHEMA or typeof(cached.sources) ~= "table" then
		return false
	end
	if not cached.request or cached.request.compositor ~= request.compositor or cached.request.root ~= request.root then
		return false
	end

	for _, src in ipairs(cached.sources) do
		local info, _ = noctalia.fileInfo(src.path)
		if not info or info.mtime ~= src.mtime or info.size ~= src.size then
			return false
		end
	end

	return true
end

-- =============================================================================
-- Runtime State & Refresh Pipeline (Host Bound)
-- =============================================================================

local isInsideNoctalia = (noctalia :: any) ~= nil

local defaultSnapshot: SnapshotState = {
	schema = CACHE_SCHEMA,
	status = "loading",
	compositor = "",
	parser = "",
	source = "",
	request = nil,
	bindings = {},
	warnings = {},
	error = "",
	refreshing = true,
}

local snapshotChannel = if isInsideNoctalia then state.channel(SNAPSHOT_KEY, defaultSnapshot) else nil
local refreshing = false
local refreshQueued = false
local refreshGeneration = 0
local lastGood: CachePayload? = nil

local function publish(
	status: "ready" | "loading" | "error",
	request: BindingRequest?,
	cache: CachePayload?,
	err: string?,
	isRefreshing: boolean
)
	if not snapshotChannel then
		return
	end
	snapshotChannel.set({
		schema = CACHE_SCHEMA,
		status = status,
		compositor = if request then request.compositor else "",
		parser = if request then request.parser else "",
		source = if request then request.root else "",
		request = request,
		bindings = if cache then cache.bindings else {},
		warnings = if cache then cache.warnings else {},
		error = err or "",
		refreshing = isRefreshing == true,
	})
end

-- Forward Declarations
local refresh: (BindingRequest?) -> ()
local performRefresh: (number, BindingRequest) -> ()
local refreshHyprLua: (number, BindingRequest) -> ()
local finishRefresh: (number, BindingRequest, { BindingEntry }, { string }, string?, ParseContext?) -> ()

finishRefresh = function(
	generation: number,
	request: BindingRequest,
	result: { BindingEntry },
	warnings: { string },
	err: string?,
	sourceSnapshot: ParseContext?
)
	if generation ~= refreshGeneration then
		log.warn("finishRefresh aborted: generation mismatch", { gen = generation, expected = refreshGeneration })
		return
	end
	refreshing = false
	if err == nil then
		lastGood = {
			schema = CACHE_SCHEMA,
			request = request,
			bindings = result,
			warnings = warnings,
			sources = if sourceSnapshot then sourceSnapshot.sources else {},
		}

		local writeOk, writeErr = filesystem.writePluginData(BINDINGS_CACHE_FILE, lastGood, false)
		if not writeOk then
			log.error("Failed to write cache file", { error = tostring(writeErr) })
		else
			log.info("Successfully wrote bindings-cache.json", { count = #result })
		end

		publish("ready", request, lastGood, "", false)
		log.info("Keybindings parsed successfully", { count = #result, compositor = request.compositor })
	else
		publish("ready", request, lastGood, err, false)
		log.error("Failed to parse keybindings", { error = err })
	end

	if refreshQueued then
		refreshQueued = false
		refresh(request)
	end
end

refreshHyprLua = function(generation: number, request: BindingRequest)
	if not noctalia.commandExists("hyprctl") then
		finishRefresh(generation, request, {}, {}, noctalia.tr("hyprctl_missing"), nil)
		return
	end

	proc.exec({ "hyprctl", "binds", "-j" }, function(err, stdout, _exitCode)
		if generation ~= refreshGeneration then
			return
		end
		if err then
			finishRefresh(generation, request, {}, {}, service.trim(err) or noctalia.tr("hyprctl_failed"), nil)
			return
		end

		local scanOk, scanOrErr = pcall(function()
			return service.scanHyprLua(request.root)
		end)
		local scan: ParseContext = if scanOk and typeof(scanOrErr) == "table"
			then scanOrErr :: ParseContext
			else {
				warnings = { tostring(scanOrErr) },
				exactRules = {},
				bindings = {},
				variables = {},
				sources = {},
			}

		local parseOk, parsedOrErr = pcall(function()
			return service.parseHyprJson(stdout, scan)
		end)

		if parseOk and parsedOrErr then
			finishRefresh(generation, request, parsedOrErr :: { BindingEntry }, scan.warnings, nil, scan)
		else
			finishRefresh(generation, request, {}, scan.warnings, tostring(parsedOrErr), scan)
		end
	end)
end

performRefresh = function(generation: number, request: BindingRequest)
	if request.parser == "mango" then
		local context = walkConfig(request.root, service.parseMangoContent, "%.conf$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "niri" then
		local context = walkConfig(request.root, service.parseNiriContent, "%.kdl$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "hypr-lua" then
		refreshHyprLua(generation, request)
	elseif request.parser == "hypr-conf" then
		local context = walkConfig(request.root, service.parseHyprContent, "%.conf$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	else
		finishRefresh(generation, request, {}, {}, noctalia.tr("unsupported"), nil)
	end
end

refresh = function(request: BindingRequest?)
	if refreshing then
		refreshQueued = true
		return
	end
	local activeRequest = request or currentRequest()
	refreshGeneration += 1
	refreshing = true
	performRefresh(refreshGeneration, activeRequest)
end

local function bootstrap()
	logger.syncFromConfig("log_level")
	local request = currentRequest()
	local cached: CachePayload?, _ = filesystem.readPluginData(BINDINGS_CACHE_FILE, nil :: CachePayload?)

	if isCacheFresh(cached, request) then
		lastGood = cached
		publish("ready", request, cached, "", false)
		log.debug("Restored keybind cache from disk", { count = #(cached :: CachePayload).bindings })
	else
		if cached ~= nil then
			lastGood = cached
			publish("ready", request, cached, "", true)
		else
			publish("loading", request, nil, "", true)
		end
		refresh(request)
	end
end

-- =============================================================================
-- Lifecycle Registration
-- =============================================================================

if isInsideNoctalia then
	lifecycle.service({
		onEnable = function()
			bootstrap()
		end,
		onConfigChanged = function()
			local request = currentRequest()
			refresh(request)
		end,
		onIpc = function(event: string, _payload: string)
			if event == "refresh" then
				refresh()
			end
		end,
		onExit = function(_signal: number, _reason: string?)
			refreshGeneration += 1
			refreshing = false
			refreshQueued = false
		end,
	})

	noctalia.state.watch(REFRESH_REQUEST_KEY, function(_request: any)
		refresh()
	end)
end

return service
