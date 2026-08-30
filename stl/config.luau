--!strict
--- Type-safe configuration accessor with fallback defaults, table immutability,
--- and headless test host injection.
---
--- Provides typed getters for string, boolean, number, string lists, and string map
--- settings declared in Noctalia plugin configurations.
local config = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Host interface definition required by config.
export type ConfigHost = {
	getConfig: ((key: string) -> any)?,
	[string]: any,
}

-- =============================================================================
-- Internal State & Helpers
-- =============================================================================

--- Active mock host override injected during unit tests.
local injectedHost: ConfigHost? = nil

--- Resolves the effective host environment bridge, prioritizing active test mocks
--- and checking runtime globals across `_G` and `getfenv()`.
local function getHost(): any
	if injectedHost ~= nil then
		return injectedHost
	end

	local gHost = (_G :: any).noctalia
	if gHost ~= nil then
		return gHost
	end

	local fenvHost = (getfenv() :: any).noctalia
	if fenvHost ~= nil then
		return fenvHost
	end

	return nil
end

--- Shallow clone helper to protect table values from in-place mutation.
local function cloneTable<T>(val: T): T
	if typeof(val) == "table" then
		return (table.clone(val :: any) :: any) :: T
	end
	return val
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Reads a string configuration setting with a fallback default.
---
--- ### Example:
--- ```luau
--- local theme = config.getString("theme", "catppuccin")
--- ```
---
--- @param key string Configuration key identifier.
--- @param defaultVal string Value returned if the key is missing or not a string.
--- @return string The resolved string value.
function config.getString(key: string, defaultVal: string): string
	local host: any = getHost()
	if host == nil or typeof(host.getConfig) ~= "function" then
		return defaultVal
	end

	local val = (host.getConfig :: any)(key)
	return if typeof(val) == "string" then val else defaultVal
end

--- Reads a boolean configuration setting with a fallback default.
---
--- ### Example:
--- ```luau
--- local enabled = config.getBool("enable_animations", true)
--- ```
---
--- @param key string Configuration key identifier.
--- @param defaultVal boolean Value returned if the key is missing or not a boolean.
--- @return boolean The resolved boolean value.
function config.getBool(key: string, defaultVal: boolean): boolean
	local host: any = getHost()
	if host == nil or typeof(host.getConfig) ~= "function" then
		return defaultVal
	end

	local val = (host.getConfig :: any)(key)
	return if typeof(val) == "boolean" then val else defaultVal
end

--- Reads a numeric configuration setting with a fallback default.
---
--- ### Example:
--- ```luau
--- local interval = config.getNumber("update_interval_ms", 500)
--- ```
---
--- @param key string Configuration key identifier.
--- @param defaultVal number Value returned if the key is missing or not a number.
--- @return number The resolved numeric value.
function config.getNumber(key: string, defaultVal: number): number
	local host: any = getHost()
	if host == nil or typeof(host.getConfig) ~= "function" then
		return defaultVal
	end

	local val = (host.getConfig :: any)(key)
	return if typeof(val) == "number" then val else defaultVal
end

--- Reads an array of strings configuration setting with a fallback default.
---
--- ### Example:
--- ```luau
--- local keys = config.getStringList("capture_keys", { "Escape", "Tab" })
--- ```
---
--- @param key string Configuration key identifier.
--- @param defaultVal { string } Fallback list returned if key is missing or not a table.
--- @return { string } A list of strings.
function config.getStringList(key: string, defaultVal: { string }): { string }
	local host: any = getHost()
	if host == nil or typeof(host.getConfig) ~= "function" then
		return cloneTable(defaultVal)
	end

	local val = (host.getConfig :: any)(key)
	if typeof(val) == "table" then
		return cloneTable(val :: { string })
	end
	return cloneTable(defaultVal)
end

--- Reads a key-value map of strings with a fallback default.
---
--- ### Example:
--- ```luau
--- local aliases = config.getStringMap("aliases", { term = "kitty" })
--- ```
---
--- @param key string Configuration key identifier.
--- @param defaultVal { [string]: string } Fallback map returned if key is missing or not a table.
--- @return { [string]: string } A key-value map of strings.
function config.getStringMap(key: string, defaultVal: { [string]: string }): { [string]: string }
	local host: any = getHost()
	if host == nil or typeof(host.getConfig) ~= "function" then
		return cloneTable(defaultVal)
	end

	local val = (host.getConfig :: any)(key)
	if typeof(val) == "table" then
		return cloneTable(val :: { [string]: string })
	end
	return cloneTable(defaultVal)
end

-- =============================================================================
-- Test Injection Hook
-- =============================================================================

--- Injects a custom mock host bridge for headless unit tests. Passing nil restores default host.
---
--- @param mockHost ConfigHost? Mock host table implementing `getConfig`.
function config.__setHost(mockHost: ConfigHost?)
	injectedHost = mockHost
end

return config
