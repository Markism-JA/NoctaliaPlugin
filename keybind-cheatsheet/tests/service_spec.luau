--!strict
--- Integration and lifecycle tests for Keybind Data Service.

local testing = require("../../testing/testing.luau")
local stl = require("../../stl/stl.luau")
local constants = require("../constants.luau")
local service = require("../service.luau")

testing.suite("Keybind Service Pipeline", function(b)
	local mockHost: testing.MockHost
	local virtualFiles: { [string]: { content: string, size: number, mtime: number } }

	b.beforeEach(function()
		virtualFiles = {}
		mockHost = testing.createMockHost()

		-- Provide in-memory virtual filesystem hooks directly on the mock host
		local rawHost = mockHost :: any
		rawHost.readText = function(path: string): (string?, string?)
			local norm = service.normalizePath(service.expandEnvironment(path))
			local file = virtualFiles[norm]
			if file then
				return file.content, nil
			end
			return nil, "File not found"
		end

		rawHost.writeText = function(path: string, content: string): (boolean, string?)
			local norm = service.normalizePath(service.expandEnvironment(path))
			virtualFiles[norm] = {
				content = content,
				size = #content,
				mtime = 1700000000,
			}
			return true, nil
		end

		rawHost.fileExists = function(path: string): boolean
			local norm = service.normalizePath(service.expandEnvironment(path))
			return virtualFiles[norm] ~= nil
		end

		rawHost.fileInfo = function(path: string): (testing.FileInfo?, string?)
			local norm = service.normalizePath(service.expandEnvironment(path))
			local file = virtualFiles[norm]
			if file then
				return {
					size = file.size,
					mtime = file.mtime,
					isDir = false,
				}, nil
			end
			return nil, "File not found"
		end

		-- Mock listDir so walkConfig discovers directory contents
		rawHost.listDir = function(dirPath: string): ({ string }?, string?)
			local normDir = service.normalizePath(service.expandEnvironment(dirPath))
			local results: { string } = {}
			for path in pairs(virtualFiles) do
				if string.sub(path, 1, #normDir) == normDir then
					local rest = string.sub(path, #normDir + 2)
					if not string.find(rest, "/") then
						table.insert(results, rest)
					end
				end
			end
			return results, nil
		end

		testing.injectHost(mockHost)

		-- Direct STL bridge fallback sync
		local rawFs = stl.filesystem :: any
		if rawFs and rawFs.writeText then
			rawFs.writeText = rawHost.writeText
			rawFs.readText = rawHost.readText
			rawFs.fileInfo = rawHost.fileInfo
			rawFs.exists = rawHost.fileExists
			rawFs.listDir = rawHost.listDir
		end

		local rawG = _G :: any
		local clearFn: any = rawG.__clearModuleCache
		if typeof(clearFn) == "function" then
			(clearFn :: (string?) -> ())("keybind-cheatsheet/service")
		end
	end)

	b.afterEach(function()
		testing.teardown()
	end)

	-- =========================================================================
	-- Compositor Detection
	-- =========================================================================

	b.test("detectCompositor prioritizes configuration override", function()
		mockHost.setConfig("compositor", "mango")
		testing.assert.equal(service.detectCompositor(), "mango")

		mockHost.setConfig("compositor", "niri")
		testing.assert.equal(service.detectCompositor(), "niri")
	end)

	b.test("detectCompositor detects environment instance signatures", function()
		mockHost.setConfig("compositor", "auto")

		mockHost.getenv = function(name: string): string?
			if name == "HYPRLAND_INSTANCE_SIGNATURE" then
				return "hypr-1234"
			end
			return nil
		end

		testing.assert.equal(service.detectCompositor(), "hyprland")
	end)

	-- =========================================================================
	-- Cache Validity
	-- =========================================================================

	b.test("isCacheFresh returns true when source files match size and mtime", function()
		local req: service.BindingRequest = {
			compositor = "hyprland",
			parser = "hypr-conf",
			root = "/home/user/.config/hypr/hyprland.conf",
		}

		local content = "bind = SUPER, Q, killactive"
		stl.filesystem.writeText(req.root, content)

		local cachePayload: service.CachePayload = {
			schema = 2,
			request = req,
			bindings = {},
			warnings = {},
			sources = {
				{ path = req.root, size = #content, mtime = 1700000000 },
			},
		}

		testing.assert.truthy(service.isCacheFresh(cachePayload, req))
	end)

	-- =========================================================================
	-- Bootstrap & State Publishing
	-- =========================================================================

	b.test("bootstrap parses configuration and publishes snapshot to state channel", function()
		local req: service.BindingRequest = {
			compositor = "hyprland",
			parser = "hypr-conf",
			root = "/home/user/.config/hypr/hyprland.conf",
		}

		mockHost.setConfig("compositor", "hyprland")
		mockHost.setConfig("hyprland_parser", "conf")
		mockHost.setConfig("hyprland_config", req.root)

		stl.filesystem.writeText(req.root, 'bind = SUPER, Return, exec, kitty # "Terminal"\n')

		service.bootstrap()

		local snapshot: any = stl.state.get(constants.SNAPSHOT_KEY, nil)
		testing.assert.truthy(snapshot ~= nil)
		if snapshot then
			testing.assert.equal(snapshot.status, "ready")
			testing.assert.equal(#snapshot.bindings, 1)
			testing.assert.equal(snapshot.bindings[1].key, "Return")
			testing.assert.equal(snapshot.bindings[1].description, "Terminal")
		end
	end)

	-- =========================================================================
	-- Lifecycle Hooks
	-- =========================================================================

	b.test("bootstrap re-runs and publishes updated configurations", function()
		local req: service.BindingRequest = {
			compositor = "niri",
			parser = "niri",
			root = "/home/user/.config/niri/config.kdl",
		}

		mockHost.setConfig("compositor", "niri")
		mockHost.setConfig("niri_config", req.root)

		stl.filesystem.writeText(req.root, 'Mod+Return { spawn "foot"; }\n')

		service.bootstrap()

		local snapshot: any = stl.state.get(constants.SNAPSHOT_KEY, nil)
		testing.assert.truthy(snapshot ~= nil)
		if snapshot then
			testing.assert.equal(snapshot.compositor, "niri")
			testing.assert.equal(#snapshot.bindings, 1)
			testing.assert.equal(snapshot.bindings[1].action, 'spawn "foot"')
		end
	end)
end)

return true
