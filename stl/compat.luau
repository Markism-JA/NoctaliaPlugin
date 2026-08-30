--!strict
--- Runtime feature-gating and capability inspection utilities for Noctalia.
---
--- Provides type-safe host API level verification, dynamic method reflection,
--- protected execution guards, and headless test host injection.
local apiMatrix = require("./api_matrix.luau")

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Known Noctalia host capability identifier from the API matrix.
export type FeatureKey = apiMatrix.FeatureKey

--- Metadata record describing a versioned Noctalia host API tier.
export type ApiEntry = apiMatrix.ApiEntry

--- Expected host runtime bridge for compatibility checking and logging.
export type CompatHost = {
	--- Active plugin API version level reported by the Noctalia host.
	pluginApiLevel: number?,
	--- Host logging bridge function.
	log: ((msg: string) -> ())?,
	[string]: any,
}

local compat = {}

--- Re-exported static API matrix definition containing tiers, versions, and feature mappings.
compat.API = apiMatrix

-- =============================================================================
-- Internal State & Helpers
-- =============================================================================

--- Active mock host override injected during unit tests.
local injectedHost: CompatHost? = nil

--- Resolves the effective host environment bridge, prioritizing active test mocks
--- and checking runtime globals across `_G` and `getfenv()`.
---
--- @return any The active host table.
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

--- Dispatches formatted diagnostic logs to the host console or standard output.
---
--- @param prefix string Diagnostic severity tag (e.g. "STL WARN", "STL ERROR").
--- @param message string Formatted log body.
local function logMessage(prefix: string, message: string)
	local host: any = getHost()
	local formatted = string.format("[%s] %s", prefix, message)
	if host ~= nil and typeof(host.log) == "function" then
		(host.log :: (string) -> ())(formatted)
	else
		print(formatted)
	end
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Returns the active Noctalia Host Plugin API level (returns `0` if unknown or unavailable).
---
--- ### Example:
--- ```luau
--- local level = compat.getApiLevel()
--- if level >= 26 then
---     -- Running on Noctalia v5.0.0-beta.9 or newer
--- end
--- ```
---
--- @return number The integer API level reported by the runtime host.
function compat.getApiLevel(): number
	local host: any = getHost()
	if host == nil then
		return 0
	end
	local rawApi = host.pluginApiLevel
	return if typeof(rawApi) == "number" then rawApi else 0
end

--- Verifies that the host meets a specific API level requirement, logging an error if unsatisfied.
---
--- ### Example:
--- ```luau
--- if not compat.requireApi(24, "Argument-array process execution") then
---     return
--- end
--- ```
---
--- @param apiLevel number Minimum integer API level required.
--- @param featureDescription string? Optional custom description used in failure diagnostics.
--- @return boolean True if the host API level meets or exceeds `apiLevel`.
function compat.requireApi(apiLevel: number, featureDescription: string?): boolean
	local hostApi = compat.getApiLevel()

	if hostApi < apiLevel then
		local entry = apiMatrix.ENTRIES[apiLevel]
		local desc = featureDescription
			or (if entry then entry.description else string.format("Level %d API", apiLevel))
		local minVer = if entry then string.format(" (Introduced in %s)", entry.noctaliaVersion) else ""

		local err = string.format(
			"Feature '%s'%s requires Host Plugin API level %d, but active host only reports level %d.",
			desc,
			minVer,
			apiLevel,
			hostApi
		)
		logMessage("STL ERROR", err)
		return false
	end
	return true
end

--- Verifies support for a typed feature key, logging a detailed error if unsatisfied.
---
--- Sourced from the official API capability matrix.
---
--- ### Example:
--- ```luau
--- if not compat.requireFeature("get_setting") then
---     return
--- end
--- local theme = noctalia.getSetting("theme.name")
--- ```
---
--- @param feature FeatureKey The typed capability identifier.
--- @return boolean True if the host supports the declared capability.
function compat.requireFeature(feature: FeatureKey): boolean
	local entry = apiMatrix.BY_FEATURE[feature]
	if not entry then
		logMessage("STL ERROR", string.format("Unknown feature identifier '%s'", feature))
		return false
	end
	return compat.requireApi(entry.level, entry.description)
end

--- Non-failing boolean query checking if a typed feature key is supported by the active host.
---
--- Unlike `requireFeature`, this function does not emit error logs on false checks.
---
--- ### Example:
--- ```luau
--- if compat.supports("sound") then
---     noctalia.sound.play("click")
--- else
---     noctalia.notify("Action Completed")
--- end
--- ```
---
--- @param feature FeatureKey The typed capability identifier.
--- @return boolean True if current host API level meets or exceeds the feature requirement.
function compat.supports(feature: FeatureKey): boolean
	local entry = apiMatrix.BY_FEATURE[feature]
	if not entry then
		return false
	end
	return compat.getApiLevel() >= entry.level
end

--- Resolves the complete metadata descriptor record for a typed feature key.
---
--- @param feature FeatureKey The typed capability identifier.
--- @return ApiEntry? Metadata record containing level, minimum Noctalia version, and symbol name.
function compat.getFeatureInfo(feature: FeatureKey): ApiEntry?
	return apiMatrix.BY_FEATURE[feature]
end

--- Checks whether a specific property, method, or nested path exists on the host.
---
--- Safely traverses table and userdata hierarchies without throwing nil indexing errors.
---
--- ### Example:
--- ```luau
--- if compat.has("sound.play") then
---     noctalia.sound.play("alert")
--- end
--- ```
---
--- @param methodOrPath string Dotted property path on the host object (e.g. `"state.watch"`, `"panel.openContextMenu"`).
--- @return boolean True if the path resolves to a non-nil value on the active host.
function compat.has(methodOrPath: string): boolean
	local host: any = getHost()
	if host == nil then
		return false
	end

	local current: any = host
	for segment in string.gmatch(methodOrPath, "[^.]+") do
		if typeof(current) ~= "table" and typeof(current) ~= "userdata" then
			return false
		end
		current = current[segment]
		if current == nil then
			return false
		end
	end
	return true
end

--- Executes a function safely within a protected call, returning all outputs or logging errors.
---
--- Traps missing functions and runtime exceptions without interrupting caller execution.
---
--- ### Example:
--- ```luau
--- local ok, data, decodeErr = compat.safeCall("jsonDecode", function()
---     return noctalia.json.decode(rawText)
--- end)
--- ```
---
--- @param fnName string Descriptive operation name for diagnostic logging.
--- @param fn (...any) -> ...any Function to execute within a protected call.
--- @param ... any Arguments forwarded to `fn`.
--- @return (boolean, ...any) True and return values on success; false and error message on failure.
function compat.safeCall(fnName: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
	if typeof(fn) ~= "function" then
		local warnMsg = string.format("Function '%s' is not implemented or callable.", fnName)
		logMessage("STL WARN", warnMsg)
		return false, warnMsg
	end

	local results = table.pack(pcall(fn, ...))
	local ok = results[1]

	if not ok then
		local errMsg = string.format("Exception during execution of '%s': %s", fnName, tostring(results[2]))
		logMessage("STL ERROR", errMsg)
		return false, results[2]
	end

	return true, table.unpack(results, 2, results.n)
end

--- Attempts to invoke a preferred primary function, falling back if it throws or returns nil.
---
--- ### Example:
--- ```luau
--- local formatted = compat.withFallback(
---     function() return noctalia.formatTime(noctalia.timeFormat()) end,
---     function() return os.date("%H:%M") end
--- )
--- ```
---
--- @param primary () -> T Preferred closure to attempt.
--- @param fallback () -> T Fallback closure executed when primary fails or yields nil.
--- @return T Output from either the primary or fallback closure.
function compat.withFallback<T>(primary: () -> T, fallback: () -> T): T
	local ok, res = pcall(primary)
	if ok and res ~= nil then
		return res
	end
	return fallback()
end

-- =============================================================================
-- Test Harness Hook
-- =============================================================================

--- Injects or clears the mock host instance for testing.
---
--- Passing `nil` restores default host resolution.
---
--- @param mockHost CompatHost? Mock host table implementing `pluginApiLevel` and logging methods.
function compat.__setHost(mockHost: CompatHost?)
	injectedHost = mockHost
end

return compat
