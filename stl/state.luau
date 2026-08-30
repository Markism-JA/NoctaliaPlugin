--!strict
--- Typed cross-entry state pub/sub abstraction for Noctalia.

--- Provides type-safe shared state channels between isolated Luau VMs
--- (Services, Panels, Bar Widgets) with fallback defaults and CLI test support.
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

--- Host interface definition required by state.
export type StateBridge = {
	get: ((key: string) -> any)?,
	set: ((key: string, val: any) -> ())?,
	watch: ((key: string, fn: (newVal: any) -> ()) -> ())?,
}

export type StateHost = {
	state: StateBridge?,
}

-- =============================================================================
-- Internal State & Helpers
-- =============================================================================

--- Optional mock host override injected during tests.
local injectedHost: StateHost? = nil

--- Resolves the effective state host bridge.
local function getStateBridge(): StateBridge?
	if injectedHost ~= nil and injectedHost.state ~= nil then
		return injectedHost.state
	end
	if (noctalia :: any) ~= nil and (noctalia :: any).state ~= nil then
		return (noctalia :: any).state
	end
	return nil
end

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
			local bridge = getStateBridge()
			if bridge == nil or bridge.get == nil then
				return cloneDefault(defaultVal)
			end

			local val = (bridge.get :: any)(key)
			if val ~= nil then
				return (val :: any) :: T
			end

			return cloneDefault(defaultVal)
		end,

		set = function(val: T)
			local bridge = getStateBridge()
			if bridge == nil or bridge.set == nil then
				return
			end
			(bridge.set :: any)(key, val)
		end,

		watch = function(fn: (val: T) -> ())
			local bridge = getStateBridge()
			if bridge == nil or bridge.watch == nil then
				return
			end

			(bridge.watch :: any)(key, function(newVal: any)
				if newVal ~= nil then
					fn((newVal :: any) :: T)
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
	local bridge = getStateBridge()
	if bridge == nil or bridge.get == nil then
		return fallback
	end

	local val = (bridge.get :: any)(key)
	if val ~= nil then
		return (val :: any) :: T
	end
	return fallback
end

--- Publishes a value directly to a state key without creating a channel.
---
--- @param key string The state key to write.
--- @param val any The payload value.
function state.set(key: string, val: any)
	local bridge = getStateBridge()
	if bridge == nil or bridge.set == nil then
		return
	end
	(bridge.set :: any)(key, val)
end

return state
