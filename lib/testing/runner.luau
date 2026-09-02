--!strict
--- Central Headless Test Runner & Harness Bootstrapper for Noctalia STL.

local testing = require("./testing.luau")

local proc = require("../stl/proc.luau")
local state = require("../stl/state.luau")
local log = require("../stl/log.luau")
local filesystem = require("../stl/filesystem.luau")
local config = require("../stl/config.luau")
local compat = require("../stl/compat.luau")

-- =============================================================================
-- Harness Injection Helper
-- =============================================================================

local function setModuleHost(mod: any, host: any)
	if typeof(mod) == "table" then
		local hook = mod.__setHost
		if typeof(hook) == "function" then
			(hook :: (any) -> ())(host)
		end
	end
end

local function injectHost(host: testing.MockHost?)
	setModuleHost(proc, host)
	setModuleHost(state, host)
	setModuleHost(log, host)
	setModuleHost(filesystem, host)
	setModuleHost(config, host)
	setModuleHost(compat, host)
end

-- Create default mock host and bind across all standard library modules
local mockHost = testing.createMockHost()
injectHost(mockHost)

-- =============================================================================
-- Load STL Base Specs
-- =============================================================================

local _ = require("./specs/compat_matrix_spec.luau")

-- =============================================================================
-- Execute Suites
-- =============================================================================

local _passed, failed = testing.run()

-- Clean up injected harness after completion
injectHost(nil)

-- =============================================================================
-- Process Exit Code (Lune / CLI Test Runner Support)
-- =============================================================================

local processGlobal: any = (_G :: any).process
if failed > 0 and typeof(processGlobal) == "table" then
	local exitFn = processGlobal.exit
	if typeof(exitFn) == "function" then
		(exitFn :: (number) -> ())(1)
	end
end
