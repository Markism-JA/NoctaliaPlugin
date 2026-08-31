--!strict
--- Typed cross-entry state pub/sub abstraction for Noctalia.
---
--- Provides type-safe shared state channels between isolated Luau VMs
--- (Services, Panels, Bar Widgets) with fallback defaults and CLI test support.
local host = require("./host.luau")

local state = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Accessor interface for a typed state channel.
export type StateChannel<T> = {
	--- Retrieves the current state value, returning defaultVal if unset.
	get: () -> T,
	--- Publishes a new value to this state channel across all VMs.
	set: (val: T) -> (),
	--- Subscribes to updates emitted on this state channel.
	watch: (fn: (val: T) -> ()) -> (),
}

-- =============================================================================
-- Internal Helpers
-- =============================================================================

--- Shallow clone helper to protect default table values from in-place mutation.
local function cloneDefault<T>(val: T): T
	if typeof(val) == "table" then
		return (table.clone(val :: any) :: any) :: T
	end
	return val
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Creates a typed state channel accessor with a guaranteed fallback default.
---
--- ### Example:
--- ```luau
--- local topologyChannel = stl.state.channel("hypr.topology", {
---     focusedOutput = "default",
---     focusedLayout = "dwindle",
---     monitors = {},
--- } :: TopologyState)
---
--- local current = topologyChannel.get()
--- topologyChannel.watch(function(newTopology)
---     render()
--- end)
--- ```
---
--- @param key string The cross-VM state identifier.
--- @param defaultVal T The fallback value returned when host state is nil.
--- @return StateChannel<T> A typed channel object.
function state.channel<T>(key: string, defaultVal: T): StateChannel<T>
	return {
		get = function(): T
			local currentHost = host.get()
			if currentHost == nil or currentHost.state == nil or typeof(currentHost.state.get) ~= "function" then
				return cloneDefault(defaultVal)
			end

			local val = currentHost.state.get(key)
			if val ~= nil then
				return val :: T
			end

			return cloneDefault(defaultVal)
		end,

		set = function(val: T)
			local currentHost = host.get()
			if currentHost == nil or currentHost.state == nil or typeof(currentHost.state.set) ~= "function" then
				return
			end
			currentHost.state.set(key, val)
		end,

		watch = function(fn: (val: T) -> ())
			local currentHost = host.get()
			if currentHost == nil or currentHost.state == nil or typeof(currentHost.state.watch) ~= "function" then
				return
			end

			currentHost.state.watch(key, function(newVal: any)
				if newVal ~= nil then
					fn(newVal :: T)
				else
					fn(cloneDefault(defaultVal))
				end
			end)
		end,
	}
end

--- Reads any state key directly with type casting and optional fallback.
---
--- @param key string The state key to read.
--- @param fallback T? Optional fallback if state is nil.
--- @return T? The state value or fallback.
function state.get<T>(key: string, fallback: T?): T?
	local currentHost = host.get()
	if currentHost == nil or currentHost.state == nil or typeof(currentHost.state.get) ~= "function" then
		return fallback
	end

	local val = currentHost.state.get(key)
	if val ~= nil then
		return val :: T
	end
	return fallback
end

--- Publishes a value directly to a state key without creating a channel.
---
--- @param key string The state key to write.
--- @param val any The payload value.
function state.set(key: string, val: any)
	local currentHost = host.get()
	if currentHost == nil or currentHost.state == nil or typeof(currentHost.state.set) ~= "function" then
		return
	end
	currentHost.state.set(key, val)
end

-- =============================================================================
-- Test Harness Hook
-- =============================================================================

return state
