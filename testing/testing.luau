--!strict
--- Testing Facade Module for Noctalia Plugin Development.

local test = require("./test.luau")
local mock = require("./mock.luau")

local proc = require("../stl/proc.luau")
local state = require("../stl/state.luau")
local log = require("../stl/log.luau")
local filesystem = require("../stl/filesystem.luau")
local config = require("../stl/config.luau")
local compat = require("../stl/compat.luau")

-- Export Mock types to external consumers
export type MockHost = mock.MockHost
export type MockState = mock.MockState
export type MockSound = mock.MockSound
export type ExecHandler = mock.ExecHandler
export type ExecResult = mock.ExecResult
export type FileInfo = mock.FileInfo

local testing = {}

-- Re-export core test runner & assertion APIs
testing.suite = test.suite
testing.assert = test.assert
testing.clearSuites = test.clearSuites
testing.run = test.run

-- Re-export mock host generator
testing.createMockHost = mock.createMockHost

local function setModuleHost(mod: any, host: any)
	if typeof(mod) == "table" then
		local hook = mod.__setHost
		if typeof(hook) == "function" then
			(hook :: (any) -> ())(host)
		end
	end
end

--- Injects a mock host instance into all core STL modules.
function testing.injectHost(host: mock.MockHost?)
	setModuleHost(proc, host)
	setModuleHost(state, host)
	setModuleHost(log, host)
	setModuleHost(filesystem, host)
	setModuleHost(config, host)
	setModuleHost(compat, host)
end

--- Bootstraps a fresh mock host and injects it across the entire standard library.
function testing.bootstrap(apiLevel: number?): mock.MockHost
	local host = mock.createMockHost(apiLevel)
	testing.injectHost(host)
	return host
end

--- Restores real runtime bindings by removing mock host injection.
function testing.teardown()
	testing.injectHost(nil)
end

return testing
