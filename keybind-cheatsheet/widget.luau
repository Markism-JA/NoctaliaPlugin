--!strict
-- Static, event-only bar entry.

local stl = require("../stl/stl.luau")
local constants = require("./constants.luau")

local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)

local function getBarWidget(): any
	return (_G :: any).barWidget or (getfenv() :: any).barWidget
end

local function getHost(): any
	return (_G :: any).noctalia or (getfenv() :: any).noctalia
end

local function render()
	local bar = getBarWidget()
	local host = getHost()
	if bar and host then
		bar.setGlyph(stl.config.getString("glyph", "keyboard"))
		bar.setTooltip(host.tr("widget_tooltip"))
	end
end

stl.lifecycle.widget(nil, {
	onClick = function()
		local host = getHost()
		if host then
			host.togglePanel(constants.PANEL_ID)
		end
	end,

	onIpc = function(event: string, _payload: string)
		local host = getHost()
		if event == "toggle" and host then
			host.togglePanel(constants.PANEL_ID)
		elseif event == "refresh" then
			refreshChannel.set(refreshChannel.get() + 1)
		end
	end,
})

render()

return {
	render = render,
}
