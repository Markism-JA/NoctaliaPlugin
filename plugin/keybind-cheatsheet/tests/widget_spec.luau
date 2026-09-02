--!strict
--- Test specification for the bar widget entrypoint.

local testing = require("../../../lib/testing/testing.luau")
local stl = require("../../../lib/stl/stl.luau")
local constants = require("../constants.luau")

testing.suite("Keybind Cheatsheet: Bar Widget", function(b)
	local mockHost: testing.MockHost
	local mockBarWidget: testing.MockBarWidget
	local panelToggled: { string }
	local capturedHandlers: {
		onClick: (() -> ())?,
		onIpc: ((event: string, payload: string) -> ())?,
	}

	b.beforeEach(function()
		mockHost = testing.bootstrap(28)
		mockBarWidget = testing.getBarWidget()
		panelToggled = {}
		capturedHandlers = {}

		local rawHost = mockHost :: any
		rawHost.togglePanel = function(panelId: string)
			table.insert(panelToggled, panelId)
		end
		rawHost.tr = function(key: string)
			if key == "widget_tooltip" then
				return "Keybind Cheatsheet"
			end
			return key
		end

		local lifecycleAny = stl.lifecycle :: any
		if lifecycleAny then
			lifecycleAny.widget = function(_env: any, handlers: any)
				capturedHandlers = handlers
			end
		end

		-- Invalidate widget module cache so every test runs a fresh instance
		local clearFn: any = (_G :: any).__clearModuleCache
		if typeof(clearFn) == "function" then
			(clearFn :: (string?) -> ())("keybind-cheatsheet/widget")
		end

		-- Execute widget entrypoint for this test run
		require("../widget.luau")
	end)

	b.afterEach(function()
		testing.teardown()
	end)

	-- =========================================================================
	-- Tests
	-- =========================================================================

	b.test("renders default glyph and localized tooltip on initialization", function()
		testing.assert.equal(mockBarWidget.glyph, "keyboard")
		testing.assert.equal(mockBarWidget.tooltip, "Keybind Cheatsheet")
	end)

	b.test("onClick handler triggers panel toggle for configured PANEL_ID", function()
		local onClick = capturedHandlers.onClick
		testing.assert.truthy(onClick ~= nil, "onClick handler was not registered")
		if onClick then
			onClick()
		end

		testing.assert.equal(#panelToggled, 1)
		testing.assert.equal(panelToggled[1], constants.PANEL_ID)
	end)

	b.test("onIpc 'toggle' event toggles the panel", function()
		local onIpc = capturedHandlers.onIpc
		testing.assert.truthy(onIpc ~= nil, "onIpc handler was not registered")
		if onIpc then
			onIpc("toggle", "")
		end

		testing.assert.equal(#panelToggled, 1)
		testing.assert.equal(panelToggled[1], constants.PANEL_ID)
	end)

	b.test("onIpc 'refresh' event increments the refresh state channel", function()
		local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)
		refreshChannel.set(0)

		local onIpc = capturedHandlers.onIpc
		testing.assert.truthy(onIpc ~= nil, "onIpc handler was not registered")
		if onIpc then
			onIpc("refresh", "")
			testing.assert.equal(refreshChannel.get(), 1)

			onIpc("refresh", "")
			testing.assert.equal(refreshChannel.get(), 2)
		end
	end)
end)

return true
