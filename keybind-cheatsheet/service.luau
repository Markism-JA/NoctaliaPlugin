--!strict
-- Orchestration service for Mango, Hyprland, and Niri keybinds

local lifecycle = require("../stl/lifecycle.luau")
local stl = require("../stl/stl.luau")
local config = stl.config
local filesystem = stl.filesystem
local log = stl.log.scope("KeybindService")
local proc = stl.proc
local state = stl.state

local types = require("./types.luau")
local cache = require("./cache.luau")
local hyprlandParser = require("./parsers/hyprland.luau")
local mangoParser = require("./parsers/mango.luau")
local niriParser = require("./parsers/niri.luau")

type Compositor = types.Compositor
type BindingRequest = types.BindingRequest
type BindingEntry = types.BindingEntry
type CachePayload = types.CachePayload
type SnapshotState = types.SnapshotState
type ParseContext = types.ParseContext

local service = {}

-- Export parser methods directly for spec tests & external callers
service.parseHyprJson = hyprlandParser.parseHyprJson
service.scanHyprLua = hyprlandParser.scanHyprLua
service.__setJsonDecoder = hyprlandParser.__setJsonDecoder

-- =============================================================================
-- State & Configuration Channels
-- =============================================================================

local SNAPSHOT_KEY = "keybind-cheatsheet.snapshot"
local REFRESH_REQUEST_KEY = "keybind-cheatsheet.refresh-request"
local MAX_SCAN_DEPTH = 3
local MAX_FILE_SIZE_BYTES = 262144

local IGNORED_DIRECTORIES: { [string]: boolean } = {
	[".git"] = true,
	[".hg"] = true,
	[".svn"] = true,
	["node_modules"] = true,
	["cache"] = true,
	[".cache"] = true,
}

local defaultSnapshot: SnapshotState = {
	schema = 2,
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

-- =============================================================================
-- Helpers & Detection
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
			root = filesystem.normalizePath(
				filesystem.expandEnvironment(config.getString("mango_config", "~/.config/mango/config.conf"))
			),
		}
	elseif comp == "niri" then
		return {
			compositor = comp,
			parser = "niri",
			root = filesystem.normalizePath(
				filesystem.expandEnvironment(config.getString("niri_config", "~/.config/niri/config.kdl"))
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
			root = filesystem.normalizePath(filesystem.expandEnvironment(root)),
		}
	end
end

-- =============================================================================
-- File Tree Scanner
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
			local fullPath = filesystem.normalizePath(filesystem.join(dirPath, name))

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
	local rootDir = filesystem.dirName(filesystem.normalizePath(filesystem.expandEnvironment(rootPath)))
	local files = service.collectSourceFiles(rootDir, extensionPattern)
	local normalizedRoot = filesystem.normalizePath(filesystem.expandEnvironment(rootPath))

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

-- =============================================================================
-- State Pipeline & Refresh
-- =============================================================================

local function publish(
	status: "ready" | "loading" | "error",
	request: BindingRequest?,
	cachePayload: CachePayload?,
	err: string?,
	isRefreshing: boolean
)
	snapshotChannel.set({
		schema = 2,
		status = status,
		compositor = if request then request.compositor else "",
		parser = if request then request.parser else "",
		source = if request then request.root else "",
		request = request,
		bindings = if cachePayload then cachePayload.bindings else {},
		warnings = if cachePayload then cachePayload.warnings else {},
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
		local savedPayload = cache.save(request, result, warnings, sourceSnapshot)
		lastGood = savedPayload
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
			finishRefresh(generation, request, {}, {}, err or tr("hyprctl_failed", "Failed to query hyprctl"), nil)
			return
		end

		-- Yield immediately out of the async command callback
		-- to get a clean VM instruction budget tick
		local host = getHost()
		local defer = if host
				and host.timer
				and typeof(host.timer.defer) == "function"
			then host.timer.defer :: (() -> ()) -> ()
			else nil

		local function executePipeline()
			if generation ~= refreshGeneration then
				return
			end

			-- Scan config files on disk
			local scanOk, scanOrErr = pcall(function()
				return hyprlandParser.scanHyprLua(request.root)
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

			-- Decode and parse JSON bindings
			local parseOk, parsedOrErr = pcall(function()
				return hyprlandParser.parseHyprJson(stdout, scan)
			end)

			if parseOk and parsedOrErr then
				finishRefresh(generation, request, parsedOrErr :: { BindingEntry }, scan.warnings, nil, scan)
			else
				finishRefresh(generation, request, {}, scan.warnings, tostring(parsedOrErr), scan)
			end
		end

		if defer then
			defer(executePipeline)
		else
			executePipeline()
		end
	end, { trimOutput = false })
end

local function performRefresh(generation: number, request: BindingRequest)
	if request.parser == "mango" then
		local context = service.walkConfig(request.root, mangoParser.parseContent, "%.conf$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "niri" then
		local context = service.walkConfig(request.root, niriParser.parseContent, "%.kdl$")
		finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
	elseif request.parser == "hypr-lua" then
		refreshHyprLua(generation, request)
	elseif request.parser == "hypr-conf" then
		local context = service.walkConfig(request.root, hyprlandParser.parseConfContent, "%.conf$")
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
	local request = service.currentRequest()
	local cached = cache.load()

	if cache.isFresh(cached, request) then
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
-- Lifecycle Hooks
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
			pcall(function()
				service.refresh(nil)
			end)
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
		pcall(function()
			service.refresh(nil)
		end)
	end)
end

-- Automatic startup bootstrap when evaluating inside a live host
if host ~= nil then
	service.bootstrap()
end

return service
