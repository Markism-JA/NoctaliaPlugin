--!strict
--- Integration and lifecycle tests for Keybind Data Service Orchestration.

local testing = require("../../../lib/testing/testing")
local stl = require("../../../lib/stl/stl.luau")
local constants = require("../../keybind-cheatsheet/constants.luau")
local service = require("../../keybind-cheatsheet/service.luau")

testing.suite("Keybind Cheatsheet: Service Pipeline", function(b)
	local mockHost: testing.MockHost
	local virtualFiles: { [string]: { content: string, size: number, mtime: number } }

	b.beforeEach(function()
		virtualFiles = {}
		mockHost = testing.createMockHost()

		local rawHost = mockHost :: any
		rawHost.readFile = function(path: string): (string?, string?)
			local norm = stl.filesystem.normalizePath(stl.filesystem.expandEnvironment(path))
			local file = virtualFiles[norm]
			if file then
				return file.content, nil
			end
			return nil, "File not found"
		end

		rawHost.writeFile = function(path: string, content: string): (boolean, string?)
			local norm = stl.filesystem.normalizePath(stl.filesystem.expandEnvironment(path))
			virtualFiles[norm] = {
				content = content,
				size = #content,
				mtime = 1700000000,
			}
			return true, nil
		end

		rawHost.fileExists = function(path: string): boolean
			local norm = stl.filesystem.normalizePath(stl.filesystem.expandEnvironment(path))
			return virtualFiles[norm] ~= nil
		end

		rawHost.fileInfo = function(path: string): (testing.FileInfo?, string?)
			local norm = stl.filesystem.normalizePath(stl.filesystem.expandEnvironment(path))
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

		rawHost.listDir = function(dirPath: string): ({ string }?, string?)
			local normDir = stl.filesystem.normalizePath(stl.filesystem.expandEnvironment(dirPath))
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
	-- Bootstrap & State Publishing
	-- =========================================================================

	b.test("bootstrap parses configuration and publishes snapshot to state channel", function()
		local configPath = "/home/user/.config/hypr/hyprland.conf"
		mockHost.setConfig("compositor", "hyprland")
		mockHost.setConfig("hyprland_parser", "conf")
		mockHost.setConfig("hyprland_config", configPath)

		stl.filesystem.writeText(configPath, 'bind = SUPER, Return, exec, kitty # "Terminal"\n')

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

	b.test("bootstrap parses Niri KDL files correctly", function()
		local configPath = "/home/user/.config/niri/config.kdl"
		mockHost.setConfig("compositor", "niri")
		mockHost.setConfig("niri_config", configPath)

		stl.filesystem.writeText(configPath, 'Mod+Return { spawn "foot"; }\n')

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
