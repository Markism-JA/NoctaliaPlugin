--!strict
local compat = {}

--- Verifies that a specific host global or function exists before executing.
function compat.requireApi(apiLevel: number, featureName: string): boolean
	local rawApi: any = (noctalia :: any).pluginApiLevel
	local hostApi: number = if typeof(rawApi) == "number" then rawApi else 0

	if hostApi < apiLevel then
		local err: string = string.format(
			"[STL ERROR] Feature '%s' requires Host Plugin API level %d, but active host only supports level %d.",
			featureName,
			apiLevel,
			hostApi
		)
		noctalia.log(err)
		return false
	end
	return true
end

--- Safe function invoker that traps missing host functions.
function compat.safeCall<T...>(fnName: string, fn: (T...) -> (), ...: T...): boolean
	if typeof(fn) ~= "function" then
		local warnMsg: string =
			string.format("[STL WARN] Host function '%s' is not implemented in this Noctalia version.", fnName)
		noctalia.log(warnMsg)
		return false
	end

	local ok, err = pcall(fn, ...)
	if not ok then
		local errMsg: string =
			string.format("[STL ERROR] Exception during execution of '%s': %s", fnName, tostring(err))
		noctalia.log(errMsg)
		return false
	end
	return true
end

return compat
