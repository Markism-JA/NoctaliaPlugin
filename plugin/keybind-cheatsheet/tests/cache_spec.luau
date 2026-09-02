--!strict
--- Unit tests for durable cache serialization and freshness tracking.

local testing = require("../../../lib/testing/testing.luau")
local types = require("../../keybind-cheatsheet/types.luau")
local cache = require("../../keybind-cheatsheet/cache.luau")

type BindingRequest = types.BindingRequest
type CachePayload = types.CachePayload
type FileInfo = testing.FileInfo

testing.suite("Keybind Cheatsheet: Cache Validation", function(b)
	local mockHost: testing.MockHost
	local virtualFiles: { [string]: { content: string, size: number, mtime: number } }

	b.beforeEach(function()
		virtualFiles = {}
		mockHost = testing.createMockHost()

		local rawHost = mockHost :: any
		rawHost.fileInfo = function(path: string): (FileInfo?, string?)
			local file = virtualFiles[path]
			if file then
				return { size = file.size, mtime = file.mtime, isDir = false }, nil
			end
			return nil, "File not found"
		end

		testing.injectHost(mockHost)
	end)

	b.afterEach(function()
		testing.teardown()
	end)

	b.test("isFresh returns true when source files match size and mtime", function()
		local req: BindingRequest = {
			compositor = "hyprland",
			parser = "hypr-conf",
			root = "/home/user/.config/hypr/hyprland.conf",
		}

		virtualFiles[req.root] = { content = "bind = SUPER, Q, killactive", size = 27, mtime = 1700000000 }

		local payload: CachePayload = {
			schema = 2,
			request = req,
			bindings = {},
			warnings = {},
			sources = {
				{ path = req.root, size = 27, mtime = 1700000000 },
			},
		}

		testing.assert.truthy(cache.isFresh(payload, req))
	end)

	b.test("isFresh returns false if file mtime or size was modified", function()
		local req: BindingRequest = {
			compositor = "hyprland",
			parser = "hypr-conf",
			root = "/home/user/.config/hypr/hyprland.conf",
		}

		virtualFiles[req.root] = { content = "bind = SUPER, Q, killactive", size = 27, mtime = 1700000050 }

		local payload: CachePayload = {
			schema = 2,
			request = req,
			bindings = {},
			warnings = {},
			sources = {
				{ path = req.root, size = 27, mtime = 1700000000 },
			},
		}

		testing.assert.falsy(cache.isFresh(payload, req))
	end)
end)

return true
