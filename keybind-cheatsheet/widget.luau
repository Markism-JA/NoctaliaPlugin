--!strict
-- Static, event-only bar entry.

local stl = require("../stl/stl.luau")
local constants = require("./constants.luau")

local function getBarWidget(): any
	return (_G :: any).barWidget or (getfenv() :: any).barWidget
end

local function getNoctalia(): any
	return (_G :: any).noctalia or (getfenv() :: any).noctalia
end

local function render()
	local bar = getBarWidget()
	local host = getNoctalia()
	if bar and host then
		bar.setGlyph(stl.config.getString("glyph", "keyboard"))
		bar.setTooltip(host.tr("widget_tooltip"))
	end
end

stl.lifecycle.widget(getfenv(), {
	onClick = function()
		local host = getNoctalia()
		if host then
			host.togglePanel(constants.PANEL_ID)
		end
	end,

	onIpc = function(event: string, _payload: string)
		local host = getNoctalia()
		if event == "toggle" and host then
			host.togglePanel(constants.PANEL_ID)
		elseif event == "refresh" then
			local current = stl.state.get(constants.REFRESH_REQUEST_KEY, 0) or 0
			stl.state.set(constants.REFRESH_REQUEST_KEY, current + 1)
		end
	end,
})

render()

return {
	render = render,
}
