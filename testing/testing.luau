--!strict
--- Testing Facade Module for Noctalia Plugin Development.
---
--- Serves as the primary entry point for headless unit and integration testing.
--- Re-exports test runners, assertion primitives, mock host generation, and orchestrates
--- host injection across all standard library (STL) service modules.
---
--- ### Example:
--- ```luau
--- local testing = require("./testing/testing.luau")
---
--- testing.suite("Plugin Integration Suite", function(b)
---     local mockHost: testing.MockHost
---
---     b.beforeEach(function()
---         mockHost = testing.bootstrap(28)
---         mockHost.setConfig("theme", "nord")
---     end)
---
---     b.afterEach(function()
---         testing.teardown()
---     end)
---
---     b.test("reads configuration setting via injected host", function()
---         local config = require("../stl/config.luau")
---         testing.assert.equal(config.getString("theme", "default"), "nord")
---     end)
--- end)
---
--- local passed, failed = testing.run()
--- ```

local test = require("./test.luau")
local mock = require("./mock.luau")
local stl = require("../stl/stl.luau")

-- =============================================================================
-- Re-exported Types & Contracts
-- =============================================================================

export type MockHost = mock.MockHost
export type MockState = mock.MockState
export type MockSound = mock.MockSound
export type MockJson = mock.MockJson
export type ExecHandler = mock.ExecHandler
export type ExecResult = mock.ExecResult
export type FileInfo = mock.FileInfo

export type TestCase = test.TestCase
export type TestSuite = test.TestSuite
export type SuiteBuilder = test.SuiteBuilder
export type Assertions = test.Assertions

-- =============================================================================
-- Internal State
-- =============================================================================

local currentHost: mock.MockHost? = nil

-- =============================================================================
-- Public Injection & Lifecycle API
-- =============================================================================

local testing = {}

--- Re-export core test runner & assertion APIs
testing.suite = test.suite
testing.assert = test.assert
testing.clearSuites = test.clearSuites
testing.run = test.run

--- Re-export mock host factory
testing.createMockHost = mock.createMockHost

--- Injects a mock host instance into all core STL modules, globals, and environment tables.
---
--- Propagates the mock host to `proc`, `state`, `log`, `filesystem`, `config`, and `compat`,
--- while binding `_G.noctalia` and `getfenv().noctalia`.
---
--- ### Example:
--- ```luau
--- local host = testing.createMockHost(28)
--- testing.injectHost(host)
--- ```
---
--- @param host mock.MockHost? Active mock host instance to inject, or `nil` to clear.
function testing.injectHost(host: mock.MockHost?)
	currentHost = host

	stl.__setHost(host)

	-- Bind globals for legacy plugins calling `noctalia.*` directly
	local rawG = _G :: any
	rawG.noctalia = host
	local rawEnv = getfenv() :: any
	rawEnv.noctalia = host
end

--- Bootstraps a fresh mock host and injects it across the entire standard library.
---
--- Convenience helper combining `createMockHost` and `injectHost`.
---
--- ### Example:
--- ```luau
--- local host = testing.bootstrap(28)
--- host.setConfig("auto_reload", true)
--- ```
---
--- @param apiLevel number? Optional simulated API tier level (defaults to 28).
--- @return MockHost The newly created and injected mock host.
function testing.bootstrap(apiLevel: number?): mock.MockHost
	local host = mock.createMockHost(apiLevel)
	testing.injectHost(host)
	return host
end

--- Restores real runtime bindings by clearing mock host injection across all modules and environments.
---
--- ### Example:
--- ```luau
--- b.afterEach(function()
---     testing.teardown()
--- end)
--- ```
function testing.teardown()
	if currentHost ~= nil then
		currentHost.reset()
		currentHost = nil
	end

	-- Clear injected host from STL and globals
	testing.injectHost(nil)

	-- Explicitly flush in-memory state that persists across test boundaries
	stl.proc.clearCache()
	stl.log.clearBuffer()
	stl.lifecycle.unbind(getfenv())
end

return testing
