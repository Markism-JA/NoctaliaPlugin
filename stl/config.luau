--!strict
-- stl/config.luau
local config = {}

--- Reads a string config key with fallback.
function config.getString(key: string, defaultVal: string): string
	local val = noctalia.getConfig(key)
	return if typeof(val) == "string" then val else defaultVal
end

--- Reads a boolean config key with fallback.
function config.getBool(key: string, defaultVal: boolean): boolean
	local val = noctalia.getConfig(key)
	return if typeof(val) == "boolean" then val else defaultVal
end

--- Reads an integer or number config key with fallback.
function config.getNumber(key: string, defaultVal: number): number
	local val = noctalia.getConfig(key)
	return if typeof(val) == "number" then val else defaultVal
end

--- Reads a string_map config key with fallback.
function config.getStringMap(key: string, defaultVal: { [string]: string }): { [string]: string }
	local val = noctalia.getConfig(key)
	return if typeof(val) == "table" then val :: { [string]: string } else defaultVal
end

return config
