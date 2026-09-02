--!strict
-- Durable disk cache & freshness validation for keybind-cheatsheet

local stl = require("../../lib/stl/stl.luau")
local filesystem = stl.filesystem
local log = stl.log.scope("KeybindCache")
local types = require("./types.luau")

type BindingRequest = types.BindingRequest
type CachePayload = types.CachePayload
type ParseContext = types.ParseContext
type BindingEntry = types.BindingEntry

local cache = {}

local BINDINGS_CACHE_FILE = "bindings-cache.json"
local CACHE_SCHEMA = 2

--- Validates if a cached payload matches current configuration paths and file mtimes
function cache.isFresh(cached: CachePayload?, request: BindingRequest): boolean
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

--- Loads cache from durable plugin storage
function cache.load(): CachePayload?
	local data, err = filesystem.readPluginData(BINDINGS_CACHE_FILE)
	if err then
		log.debug("No valid cache payload found on disk", { err = err })
		return nil
	end
	return data :: CachePayload?
end

--- Saves parsed snapshot and file metadata to durable plugin storage
function cache.save(
	request: BindingRequest,
	bindings: { BindingEntry },
	warnings: { string },
	context: ParseContext?
): (CachePayload, boolean)
	local payload: CachePayload = {
		schema = CACHE_SCHEMA,
		request = request,
		bindings = bindings,
		warnings = warnings,
		sources = if context then context.sources else {},
	}

	local ok, err = filesystem.writePluginData(BINDINGS_CACHE_FILE, payload, false)
	if not ok then
		log.error("Failed to write cache file", { error = tostring(err) })
	end

	return payload, ok
end

return cache
