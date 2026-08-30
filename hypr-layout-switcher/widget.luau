--!nonstrict
-- Declarative Bar Widget: Screen-Isolated Topology Subscriber

local stl = require("../stl/stl.luau")
local constants = require("./constants.luau")
local types = require("./types.luau")

type TopologyState = types.TopologyState
type MonitorSlice = types.MonitorSlice

local NEXT_LAYOUT: { [string]: string } = {
	dwindle = "master",
	master = "monocle",
	monocle = "scrolling",
	scrolling = "dwindle",
}

local GLYPHS: { [string]: string } = {
	dwindle = "layout-grid",
	master = "layout-sidebar",
	monocle = "square",
	scrolling = "arrows-horizontal",
}

local LABELS: { [string]: string } = {
	dwindle = "DWN",
	master = "MST",
	monocle = "MON",
	scrolling = "SCR",
}

local uiNode: any = ui
local topologyChannel = stl.state.channel(
	constants.TOPOLOGY_KEY,
	{
		focusedOutput = "default",
		focusedLayout = "dwindle",
	} :: TopologyState
)

local myOutput = if barWidget and barWidget.outputName then (barWidget.outputName() or "default") else "default"
local currentLayout = "dwindle"
local hasResolved = false

local function extractMyLayout(topology: TopologyState?): string
	if not topology or typeof(topology) ~= "table" then
		return currentLayout
	end

	if myOutput ~= "default" and topology.monitors and topology.monitors[myOutput] then
		hasResolved = true
		return topology.monitors[myOutput].layout or "dwindle"
	end

	if not hasResolved then
		return topology.focusedLayout or "dwindle"
	end

	return currentLayout
end

currentLayout = extractMyLayout(topologyChannel.get())

local function render()
	local isVert = barWidget.isVertical and barWidget.isVertical() or false
	local container = if isVert then uiNode.column else uiNode.row

	barWidget.render(container({
		gap = 5,
		align = "center",
		paddingH = 6,
		paddingV = 2,
	}, {
		uiNode.glyph({
			name = GLYPHS[currentLayout] or "layout-grid",
			size = 14,
			color = "primary",
		}),
		uiNode.row({
			fill = "primary/0.18",
			radius = 6,
			minWidth = 36,
			minHeight = 18,
			align = "center",
			justify = "center",
			paddingH = 4,
		}, {
			uiNode.label({
				text = LABELS[currentLayout] or currentLayout:sub(1, 3):upper(),
				color = "primary",
				fontWeight = "bold",
				fontSize = 11,
				textAlign = "center",
			}),
		}),
	}))
end

topologyChannel.watch(function(topology)
	local nextLayout = extractMyLayout(topology)
	if nextLayout ~= currentLayout then
		currentLayout = nextLayout
		render()
	end
end)

stl.lifecycle.widget(getfenv(), {
	onClick = function()
		currentLayout = NEXT_LAYOUT[currentLayout] or "dwindle"
		render()
		stl.proc.spawn(string.format("noctalia msg plugin %s all cycle %s", constants.SERVICE_TARGET, myOutput))
	end,
})

render()
