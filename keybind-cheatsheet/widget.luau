--!strict
-- Static, event-only bar entry.

local stl = require("../stl/stl.luau")
local constants = require("./constants.luau")

local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)

local function render()
	barWidget.setGlyph(stl.config.getString("glyph", "keyboard"))
	barWidget.setTooltip(noctalia.tr("widget_tooltip"))
end

stl.lifecycle.widget(getfenv(), {
	onClick = function()
		noctalia.togglePanel(constants.PANEL_ID)
	end,

	onIpc = function(event: string, _payload: string)
		if event == "toggle" then
			noctalia.togglePanel(constants.PANEL_ID)
		elseif event == "refresh" then
			refreshChannel.set(refreshChannel.get() + 1)
		end
	end,
})

render()
