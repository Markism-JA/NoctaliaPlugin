--!strict
-- Static, event-only bar entry.

local stl = require("../../lib/stl/stl.luau")
local constants = require("./constants.luau")

local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)

local function getBarWidget(): any
	return (_G :: any).barWidget or (getfenv() :: any).barWidget
end

local function getHost(): any
	return (_G :: any).noctalia or (getfenv() :: any).noctalia
end

local function togglePanel()
	local host = getHost()
	if host then
		host.togglePanel(constants.PANEL_ID)
	end
end

local function render()
	local bar = getBarWidget()
	local host = getHost()
	if bar and host then
		bar.setGlyph(stl.config.getString("glyph", "keyboard"))
		bar.setTooltip(host.tr("widget_tooltip"))

		-- Fallback: bind directly if barWidget provides setter
		if typeof(bar.onClick) == "function" then
			bar.onClick(togglePanel)
		end
	end
end

-- Pass getfenv() explicitly so hooks are placed into widget.luau's environment table
stl.lifecycle.widget(getfenv(), {
	onClick = togglePanel,

	onIpc = function(event: string, _payload: string)
		if event == "toggle" then
			togglePanel()
		elseif event == "refresh" then
			refreshChannel.set(refreshChannel.get() + 1)
		end
	end,
})

render()

return {
	render = render,
}
