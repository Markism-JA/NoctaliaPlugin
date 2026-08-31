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
local mockUi = require("./mock_ui.luau")
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

export type MockUiNode = mockUi.MockUiNode
export type MockPanel = mockUi.MockPanel
export type MockBarWidget = mockUi.MockBarWidget
export type MockDesktopWidget = mockUi.MockDesktopWidget
export type MockShortcut = mockUi.MockShortcut
export type MockLauncher = mockUi.MockLauncher

export type TestCase = test.TestCase
export type TestSuite = test.TestSuite
export type SuiteBuilder = test.SuiteBuilder
export type Assertions = test.Assertions

-- =============================================================================
-- Internal State
-- =============================================================================

local currentHost: mock.MockHost? = nil
local currentPanel: mockUi.MockPanel = mockUi.createPanel()
local currentBarWidget: mockUi.MockBarWidget = mockUi.createBarWidget()
local currentDesktopWidget: mockUi.MockDesktopWidget = mockUi.createDesktopWidget()
local currentShortcut: mockUi.MockShortcut = mockUi.createShortcut()
local currentLauncher: mockUi.MockLauncher = mockUi.createLauncher()
local currentUi = mockUi.createUi()

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
testing.createUi = mockUi.createUi()
testing.createPanel = mockUi.createPanel
testing.createBarWidget = mockUi.createBarWidget

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

	local rawG = _G :: any
	local rawEnv = getfenv() :: any

	rawG.noctalia = host
	rawEnv.noctalia = host

	-- Bind UI tree constructors and surface controllers
	rawG.ui = currentUi
	rawEnv.ui = currentUi

	rawG.panel = currentPanel
	rawEnv.panel = currentPanel

	rawG.barWidget = currentBarWidget
	rawEnv.barWidget = currentBarWidget

	rawG.desktopWidget = currentDesktopWidget
	rawEnv.desktopWidget = currentDesktopWidget

	rawG.shortcut = currentShortcut
	rawEnv.shortcut = currentShortcut

	rawG.launcher = currentLauncher
	rawEnv.launcher = currentLauncher
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

--- Surface controller accessors for test assertions
function testing.getPanel(): mockUi.MockPanel
	return currentPanel
end

function testing.getBarWidget(): mockUi.MockBarWidget
	return currentBarWidget
end

function testing.getDesktopWidget(): mockUi.MockDesktopWidget
	return currentDesktopWidget
end

function testing.getShortcut(): mockUi.MockShortcut
	return currentShortcut
end

function testing.getLauncher(): mockUi.MockLauncher
	return currentLauncher
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
