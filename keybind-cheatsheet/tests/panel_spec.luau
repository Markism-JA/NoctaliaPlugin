--!strict
--- Test specification for the snapshot-driven Keybind Cheatsheet Panel.

local testing = require("../../testing/testing.luau")
local stl = require("../../stl/stl.luau")
local constants = require("../constants.luau")

testing.suite("Keybinds Panel View", function(b)
	local mockHost: testing.MockHost
	local renderedTrees: { any }
	local panelClosedCount: number
	local toggledPanels: { string }
	local capturedHandlers: {
		onOpen: ((context: string?) -> ())?,
		onClose: (() -> ())?,
		onKey: ((chord: string, pressed: boolean) -> ())?,
		onIpc: ((event: string, payload: string) -> ())?,
	}

	-- Create mock UI helper that constructs inspectable AST node tables
	local function createMockUi()
		local function makeNode(tag: string)
			return function(props: any, children: any?)
				return {
					_tag = tag,
					props = props or {},
					children = children or {},
				}
			end
		end

		return {
			column = makeNode("column"),
			row = makeNode("row"),
			scroll = makeNode("scroll"),
			box = makeNode("box"),
			label = makeNode("label"),
			glyph = makeNode("glyph"),
			input = makeNode("input"),
			button = makeNode("button"),
			separator = makeNode("separator"),
		}
	end

	b.beforeEach(function()
		mockHost = testing.createMockHost()
		testing.injectHost(mockHost)

		renderedTrees = {}
		panelClosedCount = 0
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

		local mockPanel = {
			render = function(tree: any)
				table.insert(renderedTrees, tree)
			end,
			close = function()
				panelClosedCount += 1
			end,
		}

		local mockUi = createMockUi()

		local lifecycleAny = stl.lifecycle :: any
		if lifecycleAny then
			lifecycleAny.panel = function(_env: any, handlers: any)
				capturedHandlers = handlers
			end
		end

		-- Bind mocks to global & environment namespaces
		local rawG = _G :: any
		rawG.noctalia = mockHost
		rawG.panel = mockPanel
		rawG.ui = mockUi

		local rawEnv = getfenv() :: any
		rawEnv.noctalia = mockHost
		rawEnv.panel = mockPanel
		rawEnv.ui = mockUi

		-- Invalidate virtual require module cache
		local clearFn: any = rawG.__clearModuleCache
		if typeof(clearFn) == "function" then
			(clearFn :: (string?) -> ())("keybind-cheatsheet/panel")
		end

		-- Load panel chunk
		require("../panel.luau")
	end)

	b.afterEach(function()
		testing.teardown()

		local rawG = _G :: any
		rawG.panel = nil
		rawG.ui = nil
		rawG.noctalia = nil

		local rawEnv = getfenv() :: any
		rawEnv.panel = nil
		rawEnv.ui = nil
		rawEnv.noctalia = nil
	end)

	-- Sample snapshot helper
	local function getSampleSnapshot()
		return {
			status = "ready",
			compositor = "hyprland",
			bindings = {
				{
					id = "hypr-1",
					modifiers = { "SUPER" },
					key = "Return",
					action = "exec kitty",
					category = "Applications",
					description = "Launch Terminal",
				},
				{
					id = "hypr-2",
					modifiers = { "SUPER", "SHIFT" },
					key = "q",
					action = "killactive",
					category = "Window Management",
					description = "",
				},
				{
					id = "hypr-3",
					modifiers = { "SUPER" },
					key = "d",
					action = "spawn noctalia msg panel-toggle launcher",
					category = "General",
					description = "",
				},
			},
			warnings = {},
			error = nil,
		}
	end

	-- =========================================================================
	-- Lifecycle & State Snapshot Tests
	-- =========================================================================

	b.test("renders loading state when opened without an active snapshot", function()
		local onOpen = capturedHandlers.onOpen
		testing.assert.truthy(onOpen ~= nil, "onOpen was not registered")
		if onOpen then
			onOpen(nil)
		end

		testing.assert.equal(#renderedTrees, 1)
		local rootNode = renderedTrees[1]
		testing.assert.equal(rootNode.props.key, "keybind-cheatsheet-loading")
	end)

	b.test("renders bindings groups and categories when valid snapshot is present", function()
		local snapshotChannel = stl.state.channel(constants.SNAPSHOT_KEY, nil :: any)
		snapshotChannel.set(getSampleSnapshot())

		local onOpen = capturedHandlers.onOpen
		if onOpen then
			onOpen(nil)
		end

		testing.assert.equal(#renderedTrees, 1)
		local rootNode = renderedTrees[1]
		testing.assert.equal(rootNode.props.key, "keybind-cheatsheet-bindings")
	end)

	b.test("displays error screen if snapshot status is 'error'", function()
		local snapshotChannel = stl.state.channel(constants.SNAPSHOT_KEY, nil :: any)
		snapshotChannel.set({
			status = "error",
			compositor = "hyprland",
			bindings = {},
			error = "Hyprland configuration file missing",
		})

		local onOpen = capturedHandlers.onOpen
		if onOpen then
			onOpen(nil)
		end

		testing.assert.equal(#renderedTrees, 1)
		local rootNode = renderedTrees[1]
		testing.assert.equal(rootNode.props.key, "keybind-cheatsheet-error")
	end)

	-- =========================================================================
	-- Keyboard Shortcuts & Interaction
	-- =========================================================================

	b.test("pressing 'Escape' or 'q' closes the panel when search query is empty", function()
		local onOpen = capturedHandlers.onOpen
		if onOpen then
			onOpen(nil)
		end

		local onKey = capturedHandlers.onKey
		testing.assert.truthy(onKey ~= nil, "onKey was not registered")
		if onKey then
			onKey("Escape", true)
			testing.assert.equal(panelClosedCount, 1)

			onKey("q", true)
			testing.assert.equal(panelClosedCount, 2)
		end
	end)

	b.test("pressing 'r' triggers a refresh request via state channel", function()
		local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)
		refreshChannel.set(0)

		local onOpen = capturedHandlers.onOpen
		if onOpen then
			onOpen(nil)
		end

		local onKey = capturedHandlers.onKey
		if onKey then
			onKey("r", true)
			testing.assert.equal(refreshChannel.get(), 1)
		end
	end)

	-- =========================================================================
	-- IPC Events
	-- =========================================================================

	b.test("onIpc 'toggle' closes panel when open or requests toggle from host", function()
		local onOpen = capturedHandlers.onOpen
		if onOpen then
			onOpen(nil)
		end

		local onIpc = capturedHandlers.onIpc
		testing.assert.truthy(onIpc ~= nil, "onIpc was not registered")
		if onIpc then
			-- When already open, toggle closes the panel
			onIpc("toggle", "")
			testing.assert.equal(panelClosedCount, 1)
		end

		-- Close panel
		local onClose = capturedHandlers.onClose
		if onClose then
			onClose()
		end

		if onIpc then
			-- When closed, toggle delegates to host togglePanel
			onIpc("toggle", "")
			testing.assert.equal(#toggledPanels, 1)
			testing.assert.equal(toggledPanels[1], constants.PANEL_ID)
		end
	end)

	b.test("onIpc 'refresh' increments the refresh state channel", function()
		local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)
		refreshChannel.set(0)

		local onIpc = capturedHandlers.onIpc
		if onIpc then
			onIpc("refresh", "")
			testing.assert.equal(refreshChannel.get(), 1)
		end
	end)
end)

return true
