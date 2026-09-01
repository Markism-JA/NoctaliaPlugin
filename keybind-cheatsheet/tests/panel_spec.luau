--!strict
--- Test specification for the snapshot-driven Keybind Cheatsheet Panel.

local testing = require("../../testing/testing.luau")
local stl = require("../../stl/stl.luau")
local constants = require("../constants.luau")
local types = require("../types.luau")

type SnapshotState = types.SnapshotState

testing.suite("Keybind Cheatsheet: Panel View", function(b)
	local mockHost: testing.MockHost
	local mockPanel: testing.MockPanel
	local toggledPanels: { string }
	local capturedHandlers: {
		onOpen: ((context: string?) -> ())?,
		onClose: (() -> ())?,
		onKey: ((chord: string, pressed: boolean) -> ())?,
		onIpc: ((event: string, payload: string) -> ())?,
	}

	local function getSampleSnapshot(): SnapshotState
		return {
			schema = 2,
			status = "ready",
			compositor = "hyprland",
			parser = "hypr-lua",
			source = "/fake/hyprland.lua",
			refreshing = false,
			bindings = {
				{
					id = "hypr-1",
					compositor = "hyprland",
					bindingType = "bind",
					modifiers = { "SUPER" },
					key = "Return",
					action = "exec kitty",
					category = "Applications",
					section = "Applications",
					subsection = "",
					description = "Launch Terminal",
					sourceFile = "keybinds.lua",
					sourceLine = 10,
					formattedKey = "Enter",
					keyBucket = "default",
					modPills = { { text = "Super", bucket = "super" } },
					displayDescription = "Launch Terminal",
					searchIndex = "super enter launch terminal applications exec kitty",
				},
				{
					id = "hypr-2",
					compositor = "hyprland",
					bindingType = "bind",
					modifiers = { "SUPER", "SHIFT" },
					key = "q",
					action = "killactive",
					category = "Window Management",
					section = "Window Management",
					subsection = "",
					description = "",
					sourceFile = "keybinds.lua",
					sourceLine = 12,
					formattedKey = "Q",
					keyBucket = "default",
					modPills = {
						{ text = "Super", bucket = "super" },
						{ text = "Shift", bucket = "shift" },
					},
					displayDescription = "Close Window",
					searchIndex = "super shift q close window window management killactive",
				},
				{
					id = "hypr-3",
					compositor = "hyprland",
					bindingType = "bind",
					modifiers = { "SUPER" },
					key = "d",
					action = "spawn noctalia msg panel-toggle launcher",
					category = "General",
					section = "General",
					subsection = "",
					description = "",
					sourceFile = "keybinds.lua",
					sourceLine = 14,
					formattedKey = "D",
					keyBucket = "default",
					modPills = { { text = "Super", bucket = "super" } },
					displayDescription = "Application Launcher",
					searchIndex = "super d application launcher general spawn",
				},
			},
			warnings = {},
			error = "",
		}
	end

	b.beforeEach(function()
		mockHost = testing.bootstrap(28)
		mockPanel = testing.getPanel()
		toggledPanels = {}
		capturedHandlers = {}

		local rawHost = mockHost :: any
		rawHost.togglePanel = function(id: string)
			table.insert(toggledPanels, id)
		end
		rawHost.tr = function(key: string, values: any?)
			if key == "binding_count" and values then
				return string.format("%d bindings", values.count or 0)
			end
			if key == "hidden_count" and values then
				return string.format("%d hidden", values.count or 0)
			end
			return key
		end
		rawHost.focusedOutputName = function()
			return "DP-1"
		end
		rawHost.outputs = function()
			return {
				{ name = "DP-1", focused = true, width = 1920, scale = 1 },
			}
		end

		local lifecycleAny = stl.lifecycle :: any
		if lifecycleAny then
			lifecycleAny.panel = function(_env: any, handlers: any)
				capturedHandlers = handlers
			end
		end

		-- Invalidate virtual require module cache
		local clearFn: any = (_G :: any).__clearModuleCache
		if typeof(clearFn) == "function" then
			(clearFn :: (string?) -> ())("keybind-cheatsheet/panel")
		end

		-- Load panel chunk
		require("../panel.luau")
	end)

	b.afterEach(function()
		testing.teardown()
	end)

	-- =========================================================================
	-- 1. Lifecycle & UI Tree Rendering Tests
	-- =========================================================================

	b.test("renders loading state when opened without an active snapshot", function()
		if capturedHandlers.onOpen then
			capturedHandlers.onOpen(nil)
		end

		local rootNode = mockPanel.lastRendered
		if not rootNode then
			error("Panel did not render a UI tree", 2)
		end

		testing.assert.equal(rootNode.kind, "column")
		testing.assert.equal(rootNode.props.key, "keybind-cheatsheet-loading")
	end)

	b.test("renders bindings groups and categories when valid snapshot is present", function()
		local snapshotChannel = stl.state.channel(constants.SNAPSHOT_KEY, nil :: any)
		snapshotChannel.set(getSampleSnapshot())

		if capturedHandlers.onOpen then
			capturedHandlers.onOpen(nil)
		end

		local rootNode = mockPanel.lastRendered
		if not rootNode then
			error("Panel did not render a UI tree", 2)
		end

		testing.assert.equal(rootNode.kind, "column")
		testing.assert.equal(rootNode.props.key, "keybind-cheatsheet-bindings")
	end)

	b.test("displays error screen if snapshot status is 'error'", function()
		local snapshotChannel = stl.state.channel(constants.SNAPSHOT_KEY, nil :: any)
		snapshotChannel.set({
			schema = 2,
			status = "error",
			compositor = "hyprland",
			parser = "hypr-lua",
			source = "",
			refreshing = false,
			bindings = {},
			warnings = {},
			error = "Hyprland configuration file missing",
		})

		if capturedHandlers.onOpen then
			capturedHandlers.onOpen(nil)
		end

		local rootNode = mockPanel.lastRendered
		if not rootNode then
			error("Panel did not render a UI tree", 2)
		end

		testing.assert.equal(rootNode.kind, "column")
		testing.assert.equal(rootNode.props.key, "keybind-cheatsheet-error")
	end)

	-- =========================================================================
	-- 2. Keyboard Navigation & Interaction Tests
	-- =========================================================================

	b.test("pressing 'Escape' or 'q' closes the panel when search query is empty", function()
		if capturedHandlers.onOpen then
			capturedHandlers.onOpen(nil)
		end

		testing.assert.truthy(capturedHandlers.onKey ~= nil, "onKey was not registered")
		if capturedHandlers.onKey then
			capturedHandlers.onKey("Escape", true)
			testing.assert.truthy(mockPanel.wasClosed, "Panel was not closed on Escape")

			mockPanel.wasClosed = false
			capturedHandlers.onKey("q", true)
			testing.assert.truthy(mockPanel.wasClosed, "Panel was not closed on 'q'")
		end
	end)

	b.test("pressing 'r' triggers a refresh request via state channel", function()
		local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)
		refreshChannel.set(0)

		if capturedHandlers.onOpen then
			capturedHandlers.onOpen(nil)
		end

		if capturedHandlers.onKey then
			capturedHandlers.onKey("r", true)
			testing.assert.equal(refreshChannel.get(), 1)
		end
	end)

	-- =========================================================================
	-- 3. IPC Message Handling Tests
	-- =========================================================================

	b.test("onIpc 'toggle' closes panel when open or requests toggle from host", function()
		if capturedHandlers.onOpen then
			capturedHandlers.onOpen(nil)
		end

		testing.assert.truthy(capturedHandlers.onIpc ~= nil, "onIpc was not registered")
		if capturedHandlers.onIpc then
			capturedHandlers.onIpc("toggle", "")
			testing.assert.truthy(mockPanel.wasClosed, "Panel did not close when open on toggle IPC")
		end

		if capturedHandlers.onClose then
			capturedHandlers.onClose()
		end

		if capturedHandlers.onIpc then
			capturedHandlers.onIpc("toggle", "")
			testing.assert.equal(#toggledPanels, 1)
			testing.assert.equal(toggledPanels[1], constants.PANEL_ID)
		end
	end)

	b.test("onIpc 'refresh' increments the refresh state channel", function()
		local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)
		refreshChannel.set(0)

		if capturedHandlers.onIpc then
			capturedHandlers.onIpc("refresh", "")
			testing.assert.equal(refreshChannel.get(), 1)
		end
	end)
end)

return true
