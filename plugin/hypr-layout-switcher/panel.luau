--!strict
-- Interactive Workspace Layout Selector Panel for Hyprland & Noctalia

local stl = require("../../lib/stl/stl.luau")
local constants = require("./constants.luau")
local types = require("./types.luau")
local log = stl.log.scope("HyprLayoutSwitcher")

type LayoutOption = types.LayoutOption
type TopologyState = types.TopologyState

type MonitorTopology = {
	workspaceId: (number | string)?,
	workspaceName: string?,
	layout: string?,
}

type HyprActiveWorkspace = {
	id: number,
	name: string?,
	monitor: string?,
	layout: string?,
	tiledLayout: string?,
}

local LAYOUT_OPTIONS: { LayoutOption } = {
	{
		id = "dwindle",
		name = "Dwindle",
		badge = "DWN",
		glyph = "layout-grid",
		description = "Binary tree splitting with spiral child placement",
		shortcut = "1",
	},
	{
		id = "master",
		name = "Master & Stack",
		badge = "MST",
		glyph = "layout-sidebar",
		description = "Primary master window with secondary slave column",
		shortcut = "2",
	},
	{
		id = "monocle",
		name = "Monocle",
		badge = "MON",
		glyph = "maximize",
		description = "Single window maximizing the available workspace area",
		shortcut = "3",
	},
	{
		id = "scrolling",
		name = "Scrolling Columns",
		badge = "SCR",
		glyph = "arrows-left-right",
		description = "Infinite horizontal column panning (Niri / PaperWM style)",
		shortcut = "4",
	},
}

-- Cross-VM state channel for topology
local topologyChannel = stl.state.channel(constants.TOPOLOGY_KEY, {} :: any)

local panelOpen = false
local focusedMonitor = "default"
local activeWsId: (number | string)? = nil
local activeWsName = ""
local currentLayout = "dwindle"
local selectedIndex = 1

local render: () -> ()

local function syncSelectedIndex()
	for idx, opt in ipairs(LAYOUT_OPTIONS) do
		if opt.id == currentLayout then
			selectedIndex = idx
			break
		end
	end
end

local function setLayout(layoutId: string)
	local lua: string
	if activeWsId ~= nil then
		lua = string.format("hl.workspace_rule({workspace = %q, layout = %q})", tostring(activeWsId), layoutId)
	else
		lua = string.format(
			"local w = hl.get_active_special_workspace() or hl.get_active_workspace(); "
				.. "if w then if w.special then hl.workspace_rule({workspace = tostring(w.name), layout = %q}) "
				.. "else hl.workspace_rule({workspace = tostring(w.id), layout = %q}) end end",
			layoutId,
			layoutId
		)
	end

	local escapedLua = (lua:gsub("'", "'\\''"))
	local cmd = "hyprctl eval '" .. escapedLua .. "'"
	stl.proc.exec(cmd, function(err, _stdout, _code)
		if err then
			log.warn("Failed to dispatch layout switch via hyprctl", { err = err })
		end

		local topology: TopologyState? = topologyChannel.get()
		if topology and typeof(topology.monitors) == "table" and topology.monitors[focusedMonitor] then
			topology.monitors[focusedMonitor].layout = layoutId
			topology.focusedLayout = layoutId
			topologyChannel.set(topology)
		end
	end)

	panel.close()
end

local function fetchActiveState(cb: (() -> ())?)
	local topology: TopologyState? = topologyChannel.get()
	if topology and typeof(topology.monitors) == "table" then
		focusedMonitor = topology.focusedOutput or "default"
		local monData = topology.monitors[focusedMonitor]
		if monData then
			activeWsId = monData.workspaceId
			activeWsName = monData.workspaceName or tostring(activeWsId or "?")
			currentLayout = monData.layout or "dwindle"
			syncSelectedIndex()
			if cb then
				cb()
			end
			return
		end
	end

	if not stl.proc.exists("hyprctl") then
		syncSelectedIndex()
		if cb then
			cb()
		end
		return
	end

	stl.proc.exec({ "hyprctl", "activeworkspace", "-j" }, function(err, stdout, _code)
		if not err and stdout ~= "" then
			local ws: HyprActiveWorkspace?, decodeErr = noctalia.json.decode(stdout)
			if not decodeErr and typeof(ws) == "table" and ws ~= nil then
				activeWsId = ws.id
				activeWsName = ws.name or tostring(ws.id)
				focusedMonitor = ws.monitor or "default"
				currentLayout = ws.tiledLayout or ws.layout or "dwindle"
			end
		end
		syncSelectedIndex()
		if cb then
			cb()
		end
	end)
end

local function layoutCard(opt: LayoutOption, index: number): UiNode
	local isActive = (opt.id == currentLayout)
	local isNavFocused = (index == selectedIndex)

	local cardFill = if isNavFocused
		then (if isActive then "primary/0.25" else "surface_variant/0.5")
		else (if isActive then "primary/0.12" else "surface_variant/0.2")

	local borderColor = if isNavFocused then "primary" else (if isActive then "primary/0.5" else "outline/0.15")
	local borderWidth = if isNavFocused then 2 else 1
	local titleColor = if isNavFocused or isActive then "primary" else "on_surface"

	return ui.row({
		key = "card-" .. opt.id,
		fill = cardFill,
		border = borderColor,
		borderWidth = borderWidth,
		radius = 10,
		padding = 10,
		gap = 12,
		align = "center",
		onClick = function()
			selectedIndex = index
			setLayout(opt.id)
		end,
	}, {
		-- Leading Icon Container
		ui.row({
			width = 40,
			height = 40,
			radius = 8,
			fill = if isNavFocused then "primary" else (if isActive then "primary/0.7" else "surface_variant/0.4"),
			align = "center",
			justify = "center",
		}, {
			ui.glyph({
				name = opt.glyph,
				size = 20,
				color = if isNavFocused then "on_primary" else (if isActive then "primary" else "on_surface_variant"),
			}),
		}),

		-- Card Details Column
		ui.column({ flexGrow = 1, gap = 2, align = "stretch" }, {
			ui.row({ align = "center", justify = "space_between" }, {
				ui.row({ gap = 6, align = "center" }, {
					ui.label({
						text = opt.name,
						fontWeight = "bold",
						fontSize = 14,
						color = titleColor,
					}),
					ui.row({
						fill = if isActive then "primary/0.25" else "surface_variant/0.4",
						radius = 4,
						paddingH = 5,
						paddingV = 1,
						align = "center",
					}, {
						ui.label({
							text = opt.badge,
							fontSize = 10,
							fontWeight = "bold",
							color = if isActive then "primary" else "on_surface_variant",
						}),
					}),
				}),

				if isActive
					then ui.row({
						fill = "primary",
						radius = 6,
						paddingH = 6,
						paddingV = 2,
						align = "center",
					}, {
						ui.label({
							text = "ACTIVE",
							fontSize = 10,
							fontWeight = "bold",
							color = "on_primary",
						}),
					})
					else ui.label({
						text = if isNavFocused then "⏎" else ("[" .. opt.shortcut .. "]"),
						fontSize = 11,
						fontWeight = if isNavFocused then "bold" else "medium",
						color = if isNavFocused then "primary" else "on_surface_variant",
					}),
			}),
			ui.label({
				text = opt.description,
				fontSize = 11,
				color = if isNavFocused then "on_surface" else "on_surface_variant",
				maxLines = 1,
			}),
		}),
	})
end

render = function()
	if not panelOpen then
		return
	end

	local layoutCards: { UiNode } = table.create(#LAYOUT_OPTIONS)
	for idx, opt in ipairs(LAYOUT_OPTIONS) do
		layoutCards[idx] = layoutCard(opt, idx)
	end

	panel.render(ui.column({
		key = "layout-panel-root",
		flexGrow = 1,
		gap = 12,
		align = "stretch",
	}, {
		-- Header Row
		ui.row({ align = "center", justify = "space_between", gap = 8 }, {
			ui.row({ gap = 8, align = "center" }, {
				ui.glyph({ name = "layout-grid", size = 18, color = "primary" }),
				ui.label({
					text = "Select Workspace Layout",
					fontSize = 15,
					fontWeight = "bold",
					color = "on_surface",
				}),
			}),
			ui.row({ gap = 8, align = "center" }, {
				ui.row({
					fill = "secondary/0.2",
					radius = 6,
					paddingH = 7,
					paddingV = 3,
					align = "center",
				}, {
					ui.label({
						text = string.format(
							"%s • WS %s",
							focusedMonitor,
							if activeWsName ~= "" then activeWsName else "?"
						),
						color = "secondary",
						fontSize = 11,
						fontWeight = "bold",
					}),
				}),
			}),
		}),

		-- Card List
		ui.column({ gap = 8, align = "stretch", flexGrow = 1 }, layoutCards),

		-- Footer Legend
		ui.row({ align = "center", justify = "space_between" }, {
			ui.label({
				text = "[↑/↓, j/k] Navigate  •  [Enter] Apply  •  [1-4] Quick",
				fontSize = 11,
				color = "on_surface_variant",
			}),
			ui.label({
				text = "[Esc] Cancel",
				fontSize = 11,
				color = "on_surface_variant",
			}),
		}),
	}))
end

-- Register panel lifecycle hooks via STL
stl.lifecycle.panel(getfenv(), {
	onOpen = function(_context: string?)
		panelOpen = true
		fetchActiveState(function()
			render()
		end)
	end,

	onClose = function()
		panelOpen = false
		activeWsId = nil
	end,

	onExit = function(_signal: number, _reason: string?)
		panelOpen = false
		activeWsId = nil
	end,

	onKey = function(chord: string, pressed: boolean)
		if not pressed then
			return
		end

		if chord == "down" or chord == "j" then
			selectedIndex = (selectedIndex % #LAYOUT_OPTIONS) + 1
			render()
		elseif chord == "up" or chord == "k" then
			selectedIndex = (selectedIndex - 2 + #LAYOUT_OPTIONS) % #LAYOUT_OPTIONS + 1
			render()
		elseif chord == "Return" or chord == "space" then
			local selected = LAYOUT_OPTIONS[selectedIndex]
			if selected then
				setLayout(selected.id)
			end
		elseif chord == "1" or chord == "2" or chord == "3" or chord == "4" then
			local idx = tonumber(chord)
			if idx and LAYOUT_OPTIONS[idx] then
				selectedIndex = idx
				setLayout(LAYOUT_OPTIONS[idx].id)
			end
		elseif chord == "q" or chord == "Escape" then
			panel.close()
		end
	end,

	onIpc = function(event: string, _payload: string)
		if event == "toggle" then
			if panelOpen then
				panel.close()
			else
				noctalia.togglePanel(constants.PANEL_ID)
			end
		end
	end,
})

return {
	render = render,
}
