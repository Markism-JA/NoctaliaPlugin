--!strict
--- Host Bridge Resolver for Noctalia STL.

-- Aliased directly to ambient global declared in types/noctalia.d.luau
export type NoctaliaHost = typeof(noctalia)

-- Open host bridge accommodating runtime host and testing mocks
export type HostBridge = NoctaliaHost

local hostModule = {}

--- Injected test mock instance
local injectedHost: HostBridge? = nil

--- Injects or clears a custom test host instance.
function hostModule.setInjectedHost(mockHost: any?)
	injectedHost = if mockHost ~= nil then mockHost :: HostBridge else nil
end

--- Resolves the effective host environment bridge.
--- Returns the typed ambient host when in live runtime, or the injected mock during tests.
function hostModule.get(): HostBridge?
	if injectedHost ~= nil then
		return injectedHost
	end

	local gHost = (_G :: any).noctalia
	if gHost ~= nil then
		return gHost :: HostBridge
	end

	local fenvHost = (getfenv() :: any).noctalia
	if fenvHost ~= nil then
		return fenvHost :: HostBridge
	end

	return nil
end

return hostModule
