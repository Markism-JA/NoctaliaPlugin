--!strict
--- Typed cross-entry state pub/sub abstraction.
local state = {}

--- Accessor interface for a typed state channel.
export type StateChannel<T> = {
	get: () -> T,
	set: (val: T) -> (),
	watch: (fn: (val: T) -> ()) -> (),
}

--- Creates a typed state channel accessor with a guaranteed default value.
function state.channel<T>(key: string, defaultVal: T): StateChannel<T>
	return {
		get = function(): T
			local val = noctalia.state.get(key)
			return if val ~= nil then val :: T else defaultVal
		end,
		set = function(val: T)
			noctalia.state.set(key, val)
		end,
		watch = function(fn: (val: T) -> ())
			noctalia.state.watch(key, function(newVal: any)
				fn(if newVal ~= nil then newVal :: T else defaultVal)
			end)
		end,
	}
end

return state
