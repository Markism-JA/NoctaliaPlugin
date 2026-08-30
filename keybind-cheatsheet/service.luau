--!strict
-- Cache-first keybind data service for Mango, Hyprland, and Niri.

local lifecycle = require("../stl/lifecycle.luau")
local stl = require("../stl/stl.luau")
local config = stl.config
local filesystem = stl.filesystem
local logger = stl.log
local log = stl.log.scope("KeybindService")
local proc = stl.proc
local state = stl.state

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

export type PatternRule = {
	pattern: string,
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
	patternRules: { PatternRule },
}

export type JsonDecodeFn = (string) -> (any, string?)

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

local customJsonDecoder: JsonDecodeFn? = nil

-- =============================================================================
-- Host Environment Resolver
-- =============================================================================

local function getHost(): any
	return (_G :: any).noctalia or (getfenv() :: any).noctalia
end

local function tr(key: string, default: string?): string
	local host: any = getHost()
	if host ~= nil and typeof(host.tr) == "function" then
		return (host.tr :: (string) -> string?)(key) or (default or key)
	end
	return default or key
end

-- =============================================================================
-- Pure Utility & Parser Methods
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
	local first = string.find(s, "%S")
	if not first then
		return ""
	end
	local last = #s
	while last >= first and string.find(string.sub(s, last, last), "%s") do
		last -= 1
	end
	return string.sub(s, first, last)
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
	local host: any = getHost()
	local function getEnvSafe(name: string): string?
		if host ~= nil and typeof(host.getenv) == "function" then
			return (host.getenv :: (string) -> string?)(name)
		elseif (os :: any) ~= nil and typeof((os :: any).getenv) == "function" then
			return ((os :: any).getenv :: (string) -> string?)(name)
		end
		return nil
	end

	local expanded = string.gsub(path, "%${([%w_]+)}", function(name: string)
		return getEnvSafe(name) or ("${" .. name .. "}")
	end)

	local homeVal = getEnvSafe("HOME")
	expanded = string.gsub(expanded, "%$HOME", homeVal or "~")

	if host ~= nil and typeof(host.expandPath) == "function" then
		return (host.expandPath :: (string) -> string)(expanded)
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

--- Parses Typst-style markdown headings (-- =, -- ==, # =, // =)
function service.parseHeading(rawLine: string): { level: number, title: string }?
	local trimmed = service.trim(rawLine)
	local commentPrefix, rest = string.match(trimmed, "^([%-#/]+)%s*(.*)$")
	if not commentPrefix or not rest or rest == "" then
		return nil
	end

	-- Ignore pure decorative lines like -- ====================
	if string.match(rest, "^=+%s*$") then
		return nil
	end

	local level = 0
	local rawTitle = ""

	-- Level 2: == Title (optionally closed with ==)
	local l2 = string.match(rest, "^==%s+(.-)%s*==*$") or string.match(rest, "^==%s+(.-)%s*$")
	if l2 and l2 ~= "" then
		level = 2
		rawTitle = l2
	else
		-- Level 1: = Title (optionally closed with =)
		local l1 = string.match(rest, "^=%s+(.-)%s*=+$") or string.match(rest, "^=%s+(.-)%s*$")
		if l1 and l1 ~= "" then
			level = 1
			rawTitle = l1
		end
	end

	if level == 0 or rawTitle == "" then
		return nil
	end

	local title = service.trim(rawTitle)
	if #title < 2 or #title > 55 then
		return nil
	end

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
	if subsection ~= "" and subsection ~= section then
		return section .. " • " .. subsection
	end
	return section
end

function service.normalizeModifiers(value: string?, variables: { [string]: string }?): { string }
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
				local directive, body = string.match(clean, "^([%a]*bind[%a]*)%s*=%s*(.*)$")
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

--- Scans a Lua file with isolated section/subsection context and catches dynamic template strings
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
			-- 1. Exact string literals: description = "..."
			local desc = string.match(line, "description%s*=%s*[\"']([^\"']+)[\"']")
				or string.match(line, "desc%s*=%s*[\"']([^\"']+)[\"']")

			if desc and desc ~= "" and not string.find(line, "%.%.") then
				context.exactRules[desc] = {
					section = currentSection,
					subsection = currentSubsection,
					category = service.buildCategory(currentSection, currentSubsection),
				}
			else
				-- 2. Dynamic string concatenation: description = "Prefix " .. i .. " Suffix"
				local descChunk = string.match(line, "description%s*=%s*(.-)[,}]")
					or string.match(line, "desc%s*=%s*(.-)[,}]")

				if descChunk then
					local parts: { string } = {}
					for strLit in string.gmatch(descChunk, "[\"']([^\"']+)[\"']") do
						-- Escape regex magic chars for safe pattern matching
						local escaped = string.gsub(strLit, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
						table.insert(parts, escaped)
					end

					if #parts > 0 then
						local dynamicPattern = "^" .. table.concat(parts, ".-") .. "$"
						table.insert(context.patternRules, {
							pattern = dynamicPattern,
							section = currentSection,
							subsection = currentSubsection,
							category = service.buildCategory(currentSection, currentSubsection),
						})
					end
				end
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
		patternRules = {},
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
				local info, _ = filesystem.fileInfo(normPath)
				if info then
					table.insert(context.sources, { path = normPath, size = info.size, mtime = info.mtime })
				end
				service.scanHyprLuaContent(content, context)
			end
		end
	end

	return context
end

function service.__setJsonDecoder(decoder: JsonDecodeFn?)
	customJsonDecoder = decoder
end

local function resolveJsonDecoder(): JsonDecodeFn?
	if customJsonDecoder ~= nil then
		return customJsonDecoder
	end

	local host = getHost()
	if host and typeof(host.json) == "table" and typeof(host.json.decode) == "function" then
		return host.json.decode :: JsonDecodeFn
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

				-- 1. Exact string match
				local rule: ScanRule? = scanContext.exactRules[description]

				-- 2. Dynamic pattern evaluation
				if not rule and #scanContext.patternRules > 0 and description ~= "" then
					for _, pRule in ipairs(scanContext.patternRules) do
						if string.match(description, pRule.pattern) then
							rule = {
								section = pRule.section,
								subsection = pRule.subsection,
								category = pRule.category,
							}
							break
						end
					end
				end

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

function service.collectSourceFiles(
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

	local entries, _ = filesystem.listDir(dirPath)
	if not entries then
		return results
	end

	for _, name in ipairs(entries) do
		if not IGNORED_DIRECTORIES[name] and not (string.sub(name, 1, 1) == "." and name ~= ".") then
			local fullPath = service.normalizePath(filesystem.join(dirPath, name))

			if not visited[fullPath] then
				visited[fullPath] = true
				local info, _ = filesystem.fileInfo(fullPath)
				if info then
					if info.isDir then
						service.collectSourceFiles(fullPath, extensionPattern, currentDepth + 1, visited, results)
					elseif string.match(name, extensionPattern) and info.size <= MAX_FILE_SIZE_BYTES then
						table.insert(results, fullPath)
					end
				end
			end
		end
	end

	return results
end

function service.walkConfig(
	rootPath: string,
	parserFn: (string, string, ParseContext) -> (),
	extensionPattern: string
): ParseContext
	local rootDir = filesystem.dirName(service.normalizePath(service.expandEnvironment(rootPath)))
	local files = service.collectSourceFiles(rootDir, extensionPattern)
	local normalizedRoot = service.normalizePath(service.expandEnvironment(rootPath))

	local context: ParseContext = {
		bindings = {},
		variables = {},
		warnings = {},
		sources = {},
		exactRules = {},
		patternRules = {},
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
			local info, _ = filesystem.fileInfo(path)
			if info then
				table.insert(context.sources, { path = path, size = info.size, mtime = info.mtime })
			end
			parserFn(content, path, context)
		end
	end

	return context
end

function service.detectCompositor(): Compositor
	local forced = config.getString("compositor", "auto")
	if forced == "mango" or forced == "hyprland" or forced == "niri" then
		return forced
	end

	local host: any = getHost()
	if host ~= nil and typeof(host.getenv) == "function" then
		local getenv = host.getenv :: (string) -> string?
		if getenv("MANGO_INSTANCE_SIGNATURE") ~= nil then
			return "mango"
		end
		if getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= nil then
			return "hyprland"
		end
		if getenv("NIRI_SOCKET") ~= nil then
			return "niri"
		end
	end
	return "hyprland"
end

function service.currentRequest(): BindingRequest
	local comp = service.detectCompositor()
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
		local useLua = mode == "lua" or (mode == "auto" and filesystem.exists(luaPath))
		local root = if useLua then luaPath else config.getString("hyprland_config", "~/.config/hypr/hyprland.conf")
		return {
			compositor = "hyprland",
			parser = if useLua then "hypr-lua" else "hypr-conf",
			root = service.normalizePath(service.expandEnvironment(root)),
		}
	end
end

function service.isCacheFresh(cached: CachePayload?, request: BindingRequest): boolean
	if not cached or cached.schema ~= CACHE_SCHEMA or typeof(cached.sources) ~= "table" then
		return false
	end
	if not cached.request or cached.request.compositor ~= request.compositor or cached.request.root ~= request.root then
		return false
	end

	for _, src in ipairs(cached.sources) do
		local info, _ = filesystem.fileInfo(src.path)
		if not info or info.mtime ~= src.mtime or info.size ~= src.size then
			return false
		end
	end

	return true
end

-- =============================================================================
-- Runtime Pipeline State
-- =============================================================================

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

local snapshotChannel = state.channel(SNAPSHOT_KEY, defaultSnapshot)
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

local function finishRefresh(
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
		end

		publish("ready", request, lastGood, "", false)
		log.info("Keybindings parsed & cached successfully", { count = #result, compositor = request.compositor })
	else
		publish("ready", request, lastGood, err, false)
		log.error("Failed to parse keybindings", { error = err })
	end

	if refreshQueued then
		refreshQueued = false
		service.refresh(request)
	end
end

local function refreshHyprLua(generation: number, request: BindingRequest)
	if not proc.exists("hyprctl") then
		finishRefresh(generation, request, {}, {}, tr("hyprctl_missing", "hyprctl not found"), nil)
		return
	end

	proc.exec({ "hyprctl", "binds", "-j" }, function(err, stdout, _exitCode)
		if generation ~= refreshGeneration then
			return
		end
		if err then
			finishRefresh(
				generation,
				request,
				{},
				{},
				service.trim(err) or tr("hyprctl_failed", "Failed to query hyprctl"),
				nil
			)
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
				patternRules = {},
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

local function performRefresh(generation: number, request: BindingRequest)
	if request.parser == "mango" then
		local context = service.walkConfig(request.root, service.parseMangoContent, "%.conf$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "niri" then
		local context = service.walkConfig(request.root, service.parseNiriContent, "%.kdl$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "hypr-lua" then
		refreshHyprLua(generation, request)
	elseif request.parser == "hypr-conf" then
		local context = service.walkConfig(request.root, service.parseHyprContent, "%.conf$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	else
		finishRefresh(generation, request, {}, {}, tr("unsupported", "Unsupported configuration parser"), nil)
	end
end

function service.refresh(request: BindingRequest?)
	if refreshing then
		refreshQueued = true
		return
	end
	local activeRequest = request or service.currentRequest()
	refreshGeneration += 1
	refreshing = true
	performRefresh(refreshGeneration, activeRequest)
end

function service.bootstrap()
	logger.syncFromConfig("log_level")
	local request = service.currentRequest()
	local cached: CachePayload?, _ = filesystem.readPluginData(BINDINGS_CACHE_FILE)

	if service.isCacheFresh(cached, request) then
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
		service.refresh(request)
	end
end

-- =============================================================================
-- Entrypoint Registration & Startup
-- =============================================================================

lifecycle.service(getfenv(), {
	onEnable = function()
		service.bootstrap()
	end,
	onConfigChanged = function()
		service.bootstrap()
	end,
	onIpc = function(event: string, _payload: string)
		if event == "refresh" or event == "reload" then
			service.refresh()
		end
	end,
	onExit = function(_signal, _reason)
		refreshGeneration += 1
		refreshing = false
		refreshQueued = false
	end,
})

-- Watch state for external refresh requests (e.g. from panel/widget IPC)
local host: any = getHost()
if host ~= nil and host.state ~= nil and typeof(host.state.watch) == "function" then
	(host.state.watch :: (string, (any) -> ()) -> ())(REFRESH_REQUEST_KEY, function(_req: any)
		service.refresh()
	end)
end

-- Automatic startup bootstrap when evaluating inside a live host
if host ~= nil then
	service.bootstrap()
end

return service
