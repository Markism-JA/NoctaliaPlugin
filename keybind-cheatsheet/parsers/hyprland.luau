--!strict
-- Parser and AST extractor for Hyprland (.lua / .conf / hyprctl JSON)

local stl = require("../../stl/stl.luau")
local filesystem = stl.filesystem
local types = require("../types.luau")
local common = require("./common.luau")

type BindingEntry = types.BindingEntry
type ParseContext = types.ParseContext
type ScanRule = types.ScanRule
type JsonDecodeFn = types.JsonDecodeFn

local hyprland = {}

local HYPR_MOD_FLAGS: { { mask: number, name: string } } = {
	{ mask = 64, name = "SUPER" },
	{ mask = 4, name = "CTRL" },
	{ mask = 1, name = "SHIFT" },
	{ mask = 8, name = "ALT" },
	{ mask = 16, name = "MOD2" },
	{ mask = 32, name = "MOD3" },
	{ mask = 128, name = "MOD5" },
}

local customJsonDecoder: JsonDecodeFn? = nil

function hyprland.__setJsonDecoder(decoder: JsonDecodeFn?)
	customJsonDecoder = decoder
end

local function getHost(): any
	return (_G :: any).noctalia or (getfenv() :: any).noctalia
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

--- Scans raw .conf line syntax for Hyprland
function hyprland.parseConfContent(content: string, sourceFile: string, context: ParseContext)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in string.gmatch(content, "[^\r\n]+") do
		lineNumber += 1
		local line = common.trim(rawLine)
		if line ~= "" then
			local variable, value = string.match(line, "^%$([%w_]+)%s*=%s*(.-)%s*$")
			local heading = common.parseHeading(line)

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
				local clean, description = common.extractTrailingDescription(line)
				local directive, body = string.match(clean, "^(bind[%a]*)%s*=%s*(.*)$")
				if directive ~= nil and body ~= nil then
					local fields = common.splitCsv(body)
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
						local category = common.buildCategory(currentSection, currentSubsection)
						if category == "General" and description == "" then
							category = common.fallbackCategory(dispatcher, parameters, description)
						end

						local action = if parameters ~= "" then (dispatcher .. " " .. parameters) else dispatcher

						common.addBinding(context.bindings, {
							compositor = "hyprland",
							bindingType = common.lower(directive),
							modifiers = common.normalizeModifiers(fields[1], context.variables),
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

--- Scans Lua configuration AST literals and dynamic patterns
function hyprland.scanLuaContent(content: string, context: ParseContext)
	local currentSection = "General"
	local currentSubsection = ""

	for line in string.gmatch(content, "[^\r\n]+") do
		local heading = common.parseHeading(line)
		if heading then
			if heading.level == 1 then
				currentSection = heading.title
				currentSubsection = ""
			elseif heading.level == 2 then
				currentSubsection = heading.title
			end
		elseif string.find(line, "desc", 1, true) ~= nil then
			local desc = string.match(line, "description%s*=%s*[\"']([^\"']+)[\"']")
				or string.match(line, "desc%s*=%s*[\"']([^\"']+)[\"']")

			if desc and desc ~= "" and not string.find(line, "%.%.", 1, true) then
				context.exactRules[desc] = {
					section = currentSection,
					subsection = currentSubsection,
					category = common.buildCategory(currentSection, currentSubsection),
				}
			else
				local descChunk = string.match(line, "description%s*=%s*(.-)[,}]")
					or string.match(line, "desc%s*=%s*(.-)[,}]")

				if descChunk then
					local parts: { string } = {}
					for strLit in string.gmatch(descChunk, "[\"']([^\"']+)[\"']") do
						local escaped = string.gsub(strLit, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
						table.insert(parts, escaped)
					end

					if #parts > 0 then
						table.insert(context.patternRules, {
							pattern = "^" .. table.concat(parts, ".-") .. "$",
							section = currentSection,
							subsection = currentSubsection,
							category = common.buildCategory(currentSection, currentSubsection),
						})
					end
				end
			end
		end
	end
end

--- Walks Hyprland Lua configuration dependency graph
function hyprland.scanHyprLua(rootPath: string): ParseContext
	local normalizedRoot = filesystem.normalizePath(filesystem.expandEnvironment(rootPath))
	local luaRoot = filesystem.dirName(normalizedRoot)
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
		normalizedRoot,
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
		local normPath = filesystem.normalizePath(path)
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
				hyprland.scanLuaContent(content, context)
			end
		end
	end

	return context
end

--- Synchronously parses hyprctl JSON output with high-performance ScanRule matching
function hyprland.parseHyprJson(raw: string, scanContext: ParseContext): ({ BindingEntry }?, string?)
	local jsonDecoder = resolveJsonDecoder()
	if not jsonDecoder then
		return nil, "No JSON decoder available"
	end

	local decoded: { { [string]: any } }?, err = jsonDecoder(raw)
	if typeof(decoded) ~= "table" or not decoded then
		return nil, err or "Invalid hyprctl JSON"
	end

	local result: { BindingEntry } = {}
	local patternRuleCount = #scanContext.patternRules

	for _, entry in ipairs(decoded) do
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

				for _, flag in ipairs(HYPR_MOD_FLAGS) do
					if bit32.band(mask, flag.mask) ~= 0 then
						table.insert(modifiers, flag.name)
					end
				end

				local rule: ScanRule? = scanContext.exactRules[description]
				if not rule and patternRuleCount > 0 and description ~= "" then
					for i = 1, patternRuleCount do
						local pRule = scanContext.patternRules[i]
						if string.find(description, pRule.pattern) ~= nil then
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
					else common.fallbackCategory(dispatcher, argument, description)

				if section == "" then
					section = category
				end

				local action = if argument ~= "" then (dispatcher .. " " .. argument) else dispatcher

				common.addBinding(result, {
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

return hyprland
