--!nonstrict
-- Cache-first keybind data service for Mango, Hyprland, and Niri.
--
-- The active configuration is parsed once during script startup and only
-- again after a relevant settings change or explicit refresh request. There
-- is no update interval, filesystem watcher, polling loop, or persistent
-- subprocess.
-- Hierarchical section parser (= Section, == Subsection).

local SNAPSHOT_KEY = "keybind-cheatsheet.snapshot"
local REFRESH_REQUEST_KEY = "keybind-cheatsheet.refresh-request"
local BINDINGS_CACHE_FILE = "bindings-cache.json"
local CACHE_SCHEMA = 2

local refreshing = false
local refreshQueued = false
local refreshGeneration = 0
local lastGood = nil

local function tr(key, values)
	return noctalia.tr(key, values)
end

local function trim(s)
	if not s or s == "" then
		return ""
	end

	local from = s:match("^%s*()")
	return from > #s and "" or s:match(".*%S", from)
end

local function lower(s)
	return string.lower(s or "")
end

local function startsWith(s: string, prefix: string): boolean
	return s:sub(1, #prefix) == prefix
end

local function configString(key: string, fallback: string): string
	local value = noctalia.getConfig(key)
	if type(value) ~= "string" or trim(value) == "" then
		return fallback
	end
	return trim(value)
end

local function pathDirname(path): string
	local clean = (path or ""):gsub("/+$", "")
	local parent = clean:match("^(.*)/[^/]*$")
	if parent == nil or parent == "" then
		return clean:sub(1, 1) == "/" and "/" or "."
	end
	return parent
end

local function pathJoin(base: string, child: string): string
	if not child or child == "" then
		return base
	end
	if child:sub(1, 1) == "/" then
		return child
	end
	if base == "/" then
		return "/" .. child
	end
	return (base:gsub("/+$", "")) .. "/" .. child
end

local function normalizePath(path: string): string
	local absolute = path:sub(1, 1) == "/"
	local parts = {}
	for part in path:gmatch("[^/]+") do
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
	return result == "" and (absolute and "/" or ".") or result
end

local function expandEnvironment(path: string): string
	local expanded = path:gsub("%${([%w_]+)}", function(name)
		return noctalia.getenv(name) or "${" .. name .. "}"
	end)
	expanded = expanded:gsub("%$HOME", noctalia.getenv("HOME") or "~")
	return noctalia.expandPath(expanded)
end

local function splitCsv(value: string, maximumParts: number?): { [number]: string }
	local parts = {}
	local count = 0
	for item in (value .. ","):gmatch("(.-),") do
		count = count + 1
		if maximumParts and count >= maximumParts then
			break
		end
		table.insert(parts, trim(item))
	end
	if #parts == 0 then
		table.insert(parts, trim(value))
	end
	return parts
end

-- Bounded Synchronous Recursive File Collector

local MAX_SCAN_DEPTH = 3

local IGNORED_DIRECTORIES = {
	[".git"] = true,
	[".hg"] = true,
	[".svn"] = true,
	["node_modules"] = true,
	["cache"] = true,
	[".cache"] = true,
}

local MAX_FILE_SIZE_BYTES = 262144 -- 256 KiB ceiling per file

local function collectSourceFiles(
	dirPath: string,
	extensionPattern: string,
	depth: number?,
	seen: { [string]: boolean }?,
	accum: { [number]: string }?
): { [number]: string }
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
		if not IGNORED_DIRECTORIES[name] and not (name:sub(1, 1) == "." and name ~= ".") then
			local fullPath = normalizePath(pathJoin(dirPath, name))

			if not visited[fullPath] then
				visited[fullPath] = true
				local info = noctalia.fileInfo(fullPath)
				if info then
					if info.isDir then
						collectSourceFiles(fullPath, extensionPattern, currentDepth + 1, visited, results)
					elseif name:match(extensionPattern) and info.size <= MAX_FILE_SIZE_BYTES then
						table.insert(results, fullPath)
					end
				end
			end
		end
	end

	return results
end

-- Section & Heading Parser (= L1, == L2)

local function parseHeading(rawLine: string): { level: number, title: string }?
	local body = rawLine:match("^%s*#+%s*(.*)$")
		or rawLine:match("^%s*%-%-+%s*(.*)$")
		or rawLine:match("^%s*//+%s*(.*)$")
	if not body then
		return nil
	end

	local level = nil
	local content = nil

	local sub = body:match("^==+%s*(.*)$")
	if sub then
		level = 2
		content = sub
	else
		local main = body:match("^=+%s*(.*)$")
		if main then
			level = 1
			content = main
		end
	end

	if not level or not content then
		return nil
	end

	local title = content:gsub("=+$", ""):match("^%s*(.-)%s*$")
	if not title or #title < 2 or #title > 45 then
		return nil
	end

	local l = lower(title)
	if
		l:match("^bind")
		or l:match("^exec")
		or l:match("^local%s")
		or l:match("^return%s")
		or l:match("^note:")
		or l:match("^todo:")
		or l:match("^fixme:")
		or title:find("=")
		or title:match("[%.;]$")
		or title:match("^https?://")
	then
		return nil
	end

	return { level = level, title = title }
end

local function buildCategory(section: string, subsection: string): string
	if subsection ~= "" then
		return section .. " • " .. subsection
	end
	return section
end

-- Modifiers & Identity

local MODIFIER_ORDER = { "SUPER", "CTRL", "SHIFT", "ALT", "MOD2", "MOD3", "MOD5" }
local KNOWN_MODIFIERS = { SUPER = true, CTRL = true, SHIFT = true, ALT = true, MOD2 = true, MOD3 = true, MOD5 = true }
local MODIFIER_ALIASES = { LOGO = "SUPER", WIN = "SUPER", MOD4 = "SUPER", CONTROL = "CTRL", MOD1 = "ALT" }

local function normalizeModifiers(value, variables)
	local raw = value or ""
	if variables then
		for varName, varVal in pairs(variables) do
			if type(varVal) == "string" then
				raw = raw:gsub(varName, varVal)
			end
		end
	end
	raw = raw:gsub("%+", " "):gsub("|", " "):gsub(",", " ")
	local present = {}
	local unknown = {}
	for token in raw:gmatch("[^%s]+") do
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
	local result = {}
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

local function bindingIdentity(binding)
	return table.concat({
		binding.compositor or "",
		binding.bindingType or "",
		table.concat(binding.modifiers or {}, "+"),
		binding.key or "",
		binding.action or "",
		binding.submap or "",
	}, "|")
end

local function addBinding(target, binding, skipTrim)
	if not skipTrim then
		binding.description = trim(binding.description)
		binding.category = trim(binding.category)
		binding.section = trim(binding.section)
		binding.subsection = trim(binding.subsection)
		binding.action = trim(binding.action)
		binding.key = trim(binding.key)
	end
	binding.baseCategory = binding.category
	binding.modifiers = binding.modifiers or {}
	binding.id = bindingIdentity(binding)
	table.insert(target, binding)
end

-- Fast Heuristic Category Fallbacks

local function fallbackCategory(dispatcher, arg, desc)
	local d = lower(dispatcher or "")
	local a = lower(arg or "")
	local s = lower(desc or "")
	local combined = d .. " " .. a .. " " .. s

	if
		s:find("launch")
		or s:find("terminal")
		or s:find("browser")
		or s:find("file manager")
		or combined:find("rofi")
		or combined:find("wofi")
		or combined:find("launcher")
		or combined:find("fsearch")
	then
		return "Applications & Launchers"
	end
	if
		s:find("toggle")
		or s:find("control center")
		or s:find("bar")
		or s:find("clipboard")
		or s:find("wallpaper")
		or s:find("theme")
		or s:find("session")
		or s:find("cheatsheet")
	then
		return "Shell & Desktop Controls"
	end
	if
		s:find("close")
		or s:find("zap")
		or s:find("float")
		or s:find("maximize")
		or s:find("fullscreen")
		or s:find("pin")
		or s:find("align")
		or s:find("split")
		or d == "killactive"
		or d == "closewindow"
		or d == "togglefloating"
		or d == "fullscreen"
	then
		return "Window Management & Placement"
	end
	if
		s:find("focus window")
		or s:find("move window")
		or s:find("cycle")
		or s:find("monitor")
		or d == "movefocus"
		or d == "focuswindow"
		or d == "cyclenext"
		or d == "focusmonitor"
	then
		return "Focus & Navigation"
	end
	if
		s:find("workspace")
		or s:find("scratchpad")
		or d == "workspace"
		or d == "movetoworkspace"
		or d == "togglespecialworkspace"
	then
		return "Workspaces & Scratchpads"
	end
	if
		s:find("layout")
		or s:find("master")
		or s:find("dwindle")
		or s:find("scrolling")
		or s:find("monocle")
		or d == "layout"
	then
		return "Workspace Layouts"
	end
	if
		s:find("brightness")
		or s:find("volume")
		or s:find("mute")
		or s:find("media")
		or s:find("track")
		or s:find("zoom")
		or combined:find("audio")
		or combined:find("monbrightness")
	then
		return "Media & Hardware"
	end
	if
		s:find("screen")
		or s:find("annotate")
		or s:find("ocr")
		or s:find("lens")
		or s:find("picker")
		or s:find("qr")
		or s:find("measure")
		or s:find("screenshot")
		or s:find("recorder")
		or s:find("gsr")
		or combined:find("grim")
		or combined:find("slurp")
		or combined:find("screen-toolkit")
	then
		return "Screen Toolkit & Capture Utilities"
	end
	if s:find("passthrough") or s:find("submap") or d == "submap" then
		return "Submaps & Modes: VM Passthrough"
	end

	return "Other"
end

-- AST / Lexer Scanner for Hyprland Lua

local function scanHyprLuaContent(content, context)
	local currentSection = "General"
	local currentSubsection = ""

	for line in content:gmatch("[^\r\n]+") do
		local heading = parseHeading(line)
		if heading then
			if heading.level == 1 then
				currentSection = heading.title
				currentSubsection = ""
			elseif heading.level == 2 then
				currentSubsection = heading.title
			end
		elseif line:find("desc", 1, true) then
			local desc = line:match("description%s*=%s*[\"']([^\"']+)[\"']")
				or line:match("desc%s*=%s*[\"']([^\"']+)[\"']")
			if desc and desc ~= "" then
				context.exactRules[desc] = {
					section = currentSection,
					subsection = currentSubsection,
					category = buildCategory(currentSection, currentSubsection),
				}
			end
		end
	end
end

local function scanHyprLua(rootPath)
	local luaRoot = pathDirname(normalizePath(expandEnvironment(rootPath)))
	local context = {
		exactRules = {},
		warnings = {},
		sources = {},
	}

	local visited = {}
	local fileList = {
		normalizePath(expandEnvironment(rootPath)),
		pathJoin(luaRoot, "keybinds.lua"),
		pathJoin(luaRoot, "binds.lua"),
		pathJoin(luaRoot, "modules/keybinds.lua"),
		pathJoin(luaRoot, "plugins/gloview.lua"),
	}

	local rootContent = noctalia.readFile(fileList[1])
	if rootContent then
		for modName in rootContent:gmatch("name%s*=%s*[\"']([^\"']+)[\"']") do
			if
				modName:find("bind", 1, true)
				or modName:find("workspaces", 1, true)
				or modName:find("gloview", 1, true)
			then
				table.insert(fileList, pathJoin(luaRoot, modName:gsub("%.", "/") .. ".lua"))
			end
		end
	end

	for _, path in ipairs(fileList) do
		local normPath = normalizePath(path)
		if not visited[normPath] then
			visited[normPath] = true
			local content = noctalia.readFile(normPath)
			if content and (content:find("bind", 1, true) or content:find("desc", 1, true) or content:find("%-%-")) then
				local info = noctalia.fileInfo(normPath)
				if info then
					table.insert(context.sources, { path = normPath, size = info.size, mtime = info.mtime })
				end
				scanHyprLuaContent(content, context)
			end
		end
	end

	return context
end

local function modifiersFromMask(mask)
	mask = tonumber(mask) or 0
	if mask == 0 then
		return {}
	end

	local res = {}
	if bit32 and bit32.band then
		if bit32.band(mask, 64) ~= 0 then
			table.insert(res, "SUPER")
		end
		if bit32.band(mask, 4) ~= 0 then
			table.insert(res, "CTRL")
		end
		if bit32.band(mask, 1) ~= 0 then
			table.insert(res, "SHIFT")
		end
		if bit32.band(mask, 8) ~= 0 then
			table.insert(res, "ALT")
		end
		if bit32.band(mask, 16) ~= 0 then
			table.insert(res, "MOD2")
		end
		if bit32.band(mask, 32) ~= 0 then
			table.insert(res, "MOD3")
		end
		if bit32.band(mask, 128) ~= 0 then
			table.insert(res, "MOD5")
		end
	else
		if math.floor(mask / 64) % 2 == 1 then
			table.insert(res, "SUPER")
		end
		if math.floor(mask / 4) % 2 == 1 then
			table.insert(res, "CTRL")
		end
		if math.floor(mask / 1) % 2 == 1 then
			table.insert(res, "SHIFT")
		end
		if math.floor(mask / 8) % 2 == 1 then
			table.insert(res, "ALT")
		end
		if math.floor(mask / 16) % 2 == 1 then
			table.insert(res, "MOD2")
		end
		if math.floor(mask / 32) % 2 == 1 then
			table.insert(res, "MOD3")
		end
		if math.floor(mask / 128) % 2 == 1 then
			table.insert(res, "MOD5")
		end
	end
	return res
end

local function parseHyprJson(raw, scanContext)
	local decoded, err = noctalia.json.decode(raw)
	if type(decoded) ~= "table" then
		return nil, err or "Invalid hyprctl JSON"
	end
	local result = {}
	local exactRules = scanContext.exactRules or {}

	for _, entry in ipairs(decoded) do
		if type(entry) == "table" then
			local description = entry.has_description == false and "" or (entry.description or "")
			local key = entry.key or ""
			if key == "" and tonumber(entry.keycode) ~= nil and tonumber(entry.keycode) ~= 0 then
				key = "code:" .. tostring(entry.keycode)
			end
			local dispatcher = entry.dispatcher or ""
			local argument = entry.arg or ""

			if key ~= "" and dispatcher ~= "" then
				local bType = entry.mouse == true and "bindm" or "bind"
				local submap = entry.submap or ""
				local modifiers = modifiersFromMask(entry.modmask)
				local rule = exactRules[description]

				local section = rule and rule.section or ""
				local subsection = rule and rule.subsection or ""
				local category = rule and rule.category or nil

				if not category or category == "" then
					category = fallbackCategory(dispatcher, argument, description)
					section = category
				end

				local action = argument ~= "" and (dispatcher .. " " .. argument) or dispatcher

				addBinding(result, {
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

-- Mango, Hyprland Conf, and Niri Parsers

local function extractTrailingDescription(line)
	local ending = line:sub(-1)
	local startIndex, description
	if ending == '"' then
		startIndex, _, description = line:find('#%s*"([^"]*)"%s*$')
	elseif ending == "'" then
		startIndex, _, description = line:find("#%s*'([^']*)'%s*$")
	end
	if startIndex == nil then
		return line, ""
	end
	return trim(line:sub(1, startIndex - 1)), trim(description)
end

local function parseMangoContent(content, sourceFile, context)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in content:gmatch("[^\r\n]+") do
		lineNumber = lineNumber + 1
		local line = trim(rawLine)
		if line ~= "" then
			local heading = parseHeading(line)
			if heading then
				if heading.level == 1 then
					currentSection = heading.title
					currentSubsection = ""
				elseif heading.level == 2 then
					currentSubsection = heading.title
				end
			elseif line:find("bind", 1, true) ~= nil then
				local clean, description = extractTrailingDescription(line)
				local directive, body = clean:match("^([%a]*bind)%s*=%s*(.*)$")
				if directive ~= nil then
					local fields = splitCsv(body, 4)
					local modifiers = normalizeModifiers(fields[1], {})
					local key = fields[2] or ""
					local command = fields[3] or ""
					local parameters = fields[4] or ""
					if key ~= "" and command ~= "" then
						local category = buildCategory(currentSection, currentSubsection)
						if category == "General" and description == "" then
							category = fallbackCategory(command, parameters, description)
						end
						addBinding(context.bindings, {
							compositor = "mango",
							bindingType = lower(directive),
							modifiers = modifiers,
							key = key,
							action = trim(command .. " " .. parameters),
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
	return {}
end

local function parseHyprContent(content, sourceFile, context)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in content:gmatch("[^\r\n]+") do
		lineNumber = lineNumber + 1
		local line = trim(rawLine)
		if line ~= "" then
			local variable, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
			local heading = parseHeading(line)

			if variable ~= nil then
				context.variables[variable] = value
			elseif heading ~= nil then
				if heading.level == 1 then
					currentSection = heading.title
					currentSubsection = ""
				elseif heading.level == 2 then
					currentSubsection = heading.title
				end
			else
				local clean, description = extractTrailingDescription(line)
				local directive, body = clean:match("^(bind[%a]*)%s*=%s*(.*)$")
				if directive ~= nil then
					local fields = splitCsv(body, 4)
					local key = fields[2] or ""
					local dispatcher = fields[3] or ""
					if key ~= "" and dispatcher ~= "" then
						local category = buildCategory(currentSection, currentSubsection)
						if category == "General" and description == "" then
							category = fallbackCategory(dispatcher, fields[4] or "", description)
						end
						addBinding(context.bindings, {
							compositor = "hyprland",
							bindingType = lower(directive),
							modifiers = normalizeModifiers(fields[1], context.variables),
							key = key,
							action = trim(dispatcher .. " " .. (fields[4] or "")),
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
	return {}
end

local function niriCategoryFor(action: string): string
	local value = lower(action)
	if startsWith(value, "spawn") then
		return "Applications & Launchers"
	end
	if startsWith(value, "focus-column-") or startsWith(value, "focus-window-") then
		return "Focus & Navigation"
	end
	if startsWith(value, "focus-workspace-") then
		return "Workspaces & Scratchpads"
	end
	if startsWith(value, "move-column-") or startsWith(value, "move-window-") then
		return "Window Management & Placement"
	end
	if startsWith(value, "screenshot") then
		return "Screen Toolkit & Capture Utilities"
	end
	if startsWith(value, "close-window") or startsWith(value, "fullscreen-window") then
		return "Window Management & Placement"
	end
	if startsWith(value, "power-off-monitors") or startsWith(value, "quit") then
		return "Shell & Desktop Controls"
	end
	return "Other"
end

local function parseNiriContent(content, sourceFile, context)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in content:gmatch("[^\r\n]+") do
		lineNumber = lineNumber + 1
		local line = trim(rawLine)

		if line ~= "" then
			local heading = parseHeading(line)
			if heading then
				if heading.level == 1 then
					currentSection = heading.title
					currentSubsection = ""
				elseif heading.level == 2 then
					currentSubsection = heading.title
				end
			else
				-- Match single-line KDL binds: "Mod+Shift+S { screenshot-screen; }"
				local bindChord, actionBody = line:match("^([^%{]+)%s*%{%s*(.-)%s*;?%s*%}%s*$")
				if bindChord and actionBody then
					local cleanAction = trim(actionBody:gsub(";+$", ""))
					local modifiers = normalizeModifiers(bindChord, {})
					local key = bindChord:match("([^+%s]+)$") or ""

					local category = buildCategory(currentSection, currentSubsection)
					if category == "General" then
						category = niriCategoryFor(cleanAction)
					end

					addBinding(context.bindings, {
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

	return {}
end

-- Runtime Orchestration

local function walkConfig(rootPath: string, parser: (string, string, any) -> (), extensionPattern: string)
	local rootDir = pathDirname(normalizePath(expandEnvironment(rootPath)))
	local files = collectSourceFiles(rootDir, extensionPattern)
	local normalizedRoot = normalizePath(expandEnvironment(rootPath))

	local context = {
		bindings = {} :: { [number]: any },
		variables = {} :: { [string]: any },
		warnings = {} :: { [number]: string },
		sources = {} :: { [number]: any },
	}

	local fileSet: { [string]: boolean } = {}

	for _, f in ipairs(files) do
		fileSet[f] = true
	end

	if not fileSet[normalizedRoot] then
		table.insert(files, normalizedRoot)
	end

	for _, path in ipairs(files) do
		local content = noctalia.readFile(path)
		if content then
			local info = noctalia.fileInfo(path)
			if info then
				table.insert(context.sources, { path = path, size = info.size, mtime = info.mtime })
			end
			parser(content, path, context)
		end
	end

	return context
end

-- Cache Validation & State Publishing

local function detectCompositor(): string
	local forced = configString("compositor", "auto")
	if forced ~= "auto" then
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

local function currentRequest()
	local compositor = detectCompositor()
	if compositor == "mango" then
		return {
			compositor = compositor,
			parser = "mango",
			root = normalizePath(expandEnvironment(configString("mango_config", "~/.config/mango/config.conf"))),
		}
	elseif compositor == "niri" then
		return {
			compositor = compositor,
			parser = "niri",
			root = normalizePath(expandEnvironment(configString("niri_config", "~/.config/niri/config.kdl"))),
		}
	else
		local mode = configString("hyprland_parser", "auto")
		local luaPath = configString("hyprland_lua_config", "~/.config/hypr/hyprland.lua")
		local useLua = mode == "lua" or (mode == "auto" and noctalia.fileExists(noctalia.expandPath(luaPath)))
		local root = useLua and luaPath or configString("hyprland_config", "~/.config/hypr/hyprland.conf")
		return {
			compositor = "hyprland",
			parser = useLua and "hypr-lua" or "hypr-conf",
			root = normalizePath(expandEnvironment(root)),
		}
	end
end

local function isCacheFresh(cached: any, request: any): boolean
	if type(cached) ~= "table" or cached.schema ~= CACHE_SCHEMA or type(cached.sources) ~= "table" then
		return false
	end
	if
		cached.request == nil
		or cached.request.compositor ~= request.compositor
		or cached.request.root ~= request.root
	then
		return false
	end

	for _, src in ipairs(cached.sources) do
		local info = noctalia.fileInfo(src.path)
		if not info or info.mtime ~= src.mtime or info.size ~= src.size then
			return false
		end
	end

	return true
end

local function cachePath()
	local directory = noctalia.pluginDataDir()
	if directory == nil then
		return nil
	end
	return directory .. "/" .. BINDINGS_CACHE_FILE
end

local function readBindingCache()
	local path = cachePath()
	if path == nil then
		return nil
	end
	local raw = noctalia.readFile(path)
	if raw == nil or raw == "" then
		return nil
	end
	return noctalia.json.decode(raw)
end

local function saveBindingCache(cache: any)
	local path = cachePath()
	if path == nil then
		return
	end
	local encoded = noctalia.json.encode(cache, false)
	if encoded == nil then
		return
	end
	local temp = path .. ".tmp"
	if noctalia.writeFile(temp, encoded) then
		noctalia.renameFile(temp, path)
	end
end

local function publish(status: string, request: any, cache: any, err: string?, isRefreshing: boolean)
	noctalia.state.set(SNAPSHOT_KEY, {
		schema = CACHE_SCHEMA,
		status = status,
		compositor = request and request.compositor or "",
		parser = request and request.parser or "",
		source = request and request.root or "",
		request = request,
		bindings = cache and cache.bindings or {},
		warnings = cache and cache.warnings or {},
		error = err or "",
		refreshing = isRefreshing == true,
	})
end

local refresh: (any?) -> ()

local function finishRefresh(
	generation: number,
	request: any,
	result: any,
	warnings: any,
	err: string?,
	sourceSnapshot: any
)
	if generation ~= refreshGeneration then
		return
	end
	refreshing = false
	if err == nil then
		lastGood = {
			schema = CACHE_SCHEMA,
			request = request,
			bindings = result or {},
			warnings = warnings or {},
			sources = sourceSnapshot and sourceSnapshot.sources or {},
			globs = {},
		}
		saveBindingCache(lastGood)
		publish("ready", request, lastGood, "", false)
	else
		publish("ready", request, lastGood, err, false)
	end
	if refreshQueued then
		refreshQueued = false
		refresh(request)
	end
end

local function refreshHyprLua(generation: number, request: any)
	if not noctalia.commandExists("hyprctl") then
		finishRefresh(generation, request, {}, {}, tr("hyprctl_missing"), nil)
		return
	end

	noctalia.runAsync("hyprctl binds -j", function(result)
		if generation ~= refreshGeneration then
			return
		end
		if result.exitCode ~= 0 or result.timedOut then
			local message = trim(result.stderr)
			finishRefresh(generation, request, {}, {}, message ~= "" and message or tr("hyprctl_failed"), nil)
			return
		end

		local scanOk, scanOrErr = pcall(function()
			return scanHyprLua(request.root)
		end)
		local scan = (scanOk and type(scanOrErr) == "table") and scanOrErr
			or { warnings = { tostring(scanOrErr) }, exactRules = {} }

		local parseOk, parsedOrErr = pcall(function()
			return parseHyprJson(result.stdout, scan)
		end)

		if parseOk then
			finishRefresh(generation, request, parsedOrErr or {}, scan.warnings or {}, nil, scan)
		else
			finishRefresh(generation, request, {}, scan.warnings or {}, tostring(parsedOrErr), scan)
		end
	end)
end

local function performRefresh(generation: number, request: any)
	if request == nil then
		finishRefresh(generation, { compositor = "", parser = "", root = "" }, {}, {}, tr("unsupported"), nil)
	elseif request.parser == "mango" then
		local context = walkConfig(request.root, parseMangoContent, "%.conf$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "niri" then
		local context = walkConfig(request.root, parseNiriContent, "%.kdl$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "hypr-lua" then
		refreshHyprLua(generation, request)
	elseif request.parser == "hypr-conf" then
		local context = walkConfig(request.root, parseHyprContent, "%.conf$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	else
		finishRefresh(generation, request, {}, {}, tr("unsupported"), nil)
	end
end

refresh = function(request: any?)
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
	local request = currentRequest()
	local cached = readBindingCache()

	if isCacheFresh(cached, request) then
		lastGood = cached
		publish("ready", request, cached, "", false)
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

-- Lifecycle Exports

function _onConfigChanged()
	local request = currentRequest()
	refresh(request)
end

function _onIpc(event: string, _payload: string)
	if event == "refresh" then
		refresh()
	end
end

function _onExit(_signal: number, _reason: string?)
	refreshGeneration += 1
	refreshing = false
	refreshQueued = false
end

noctalia.state.watch(REFRESH_REQUEST_KEY, function(_request)
	refresh()
end)

bootstrap()
