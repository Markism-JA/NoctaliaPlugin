--!nonstrict
-- Headless Service: Topology Slice Synchronizer & IPC Router

local stl = require("../../lib/stl/stl.luau")
local constants = require("./constants.luau")
local types = require("./types.luau")
local log = stl.log.scope("HyprTopologyService")

type TopologyState = types.TopologyState

local NEXT_LAYOUT = {
	dwindle = "master",
	master = "monocle",
	monocle = "scrolling",
	scrolling = "dwindle",
}

local topologyChannel = stl.state.channel(
	constants.TOPOLOGY_KEY,
	{
		focusedOutput = "default",
		focusedLayout = "dwindle",
		monitors = {},
	} :: TopologyState
)

noctalia.setUpdateInterval(400)

local isPolling = false
local currentTopology: TopologyState = {
	focusedOutput = "default",
	focusedLayout = "dwindle",
	monitors = {},
}

-- Zero-allocation structural equality check
local function isTopologyEqual(a: TopologyState, b: TopologyState): boolean
	if a == b then
		return true
	end
	if a.focusedOutput ~= b.focusedOutput or a.focusedLayout ~= b.focusedLayout then
		return false
	end

	local ma, mb = a.monitors, b.monitors
	if ma == mb then
		return true
	end
	if not ma or not mb then
		return false
	end

	for name, monA in pairs(ma) do
		local monB = mb[name]
		if not monB then
			return false
		end
		if monA.workspaceId ~= monB.workspaceId or monA.layout ~= monB.layout or monA.focused ~= monB.focused then
			return false
		end
	end

	for name in pairs(mb) do
		if not ma[name] then
			return false
		end
	end

	return true
end

local function setLayoutCmd(layout: string, targetWsId: any): string
	local lua
	if targetWsId and tostring(targetWsId) ~= "" then
		lua = string.format("hl.workspace_rule({workspace = %q, layout = %q})", tostring(targetWsId), layout)
	else
		lua = string.format(
			"local w = hl.get_active_special_workspace() or hl.get_active_workspace(); "
				.. "if w then if w.special then hl.workspace_rule({workspace = tostring(w.name), layout = %q}) "
				.. "else hl.workspace_rule({workspace = tostring(w.id), layout = %q}) end end",
			layout,
			layout
		)
	end
	return "hyprctl eval '" .. lua:gsub("'", "'\\''") .. "'"
end

local function poll()
	if isPolling or not stl.proc.exists("hyprctl") then
		return
	end
	isPolling = true

	stl.proc.exec({ "hyprctl", "monitors", "-j" }, function(monErr, monStdout, _monCode)
		if monErr or monStdout == "" then
			isPolling = false
			return
		end

		local monitors, monDecodeErr = noctalia.json.decode(monStdout)
		if monDecodeErr or typeof(monitors) ~= "table" then
			isPolling = false
			return
		end

		stl.proc.exec({ "hyprctl", "workspaces", "-j" }, function(wsErr, wsStdout, _wsCode)
			isPolling = false

			if wsErr or wsStdout == "" then
				return
			end

			local workspaces, wsDecodeErr = noctalia.json.decode(wsStdout)
			if wsDecodeErr or typeof(workspaces) ~= "table" then
				return
			end

			local wsLayoutMap: { [any]: string } = {}
			for _, ws in ipairs(workspaces) do
				if ws.id then
					wsLayoutMap[ws.id] = ws.tiledLayout or ws.layout or "dwindle"
				end
			end

			local newTopology: TopologyState = {
				focusedOutput = "default",
				focusedLayout = "dwindle",
				monitors = {},
			}

			for _, mon in ipairs(monitors) do
				local monName = mon.name or "default"
				local activeWs = mon.activeWorkspace
				local activeWsId = activeWs and activeWs.id
				local layout = (activeWsId and wsLayoutMap[activeWsId]) or "dwindle"

				newTopology.monitors[monName] = {
					workspaceId = activeWsId,
					workspaceName = if activeWs and activeWs.name then activeWs.name else tostring(activeWsId or ""),
					layout = layout,
					focused = mon.focused == true,
				}

				if mon.focused then
					newTopology.focusedOutput = monName
					newTopology.focusedLayout = layout
				end
			end

			if not isTopologyEqual(currentTopology, newTopology) then
				currentTopology = newTopology
				topologyChannel.set(newTopology)
			end
		end)
	end)
end

local function cycle(targetOutput: string?)
	local targetWsId: any = nil
	local currentLayout: string

	if
		targetOutput
		and targetOutput ~= "all"
		and targetOutput ~= "default"
		and currentTopology.monitors[targetOutput]
	then
		local mon = currentTopology.monitors[targetOutput]
		currentLayout = mon.layout or "dwindle"
		targetWsId = mon.workspaceId
	else
		currentLayout = currentTopology.focusedLayout or "dwindle"
		local focusedMon = currentTopology.monitors[currentTopology.focusedOutput]
		targetWsId = if focusedMon then focusedMon.workspaceId else nil
	end

	local nextLayout = NEXT_LAYOUT[currentLayout] or "dwindle"

	if targetOutput and currentTopology.monitors[targetOutput] then
		currentTopology.monitors[targetOutput].layout = nextLayout
	end
	currentTopology.focusedLayout = nextLayout
	topologyChannel.set(currentTopology)

	local cmd = setLayoutCmd(nextLayout, targetWsId)
	stl.proc.exec(cmd, function(err, _stdout, _code)
		if err then
			log.warn("Failed to cycle layout", { err = err })
		end
		poll()
	end)
end

stl.lifecycle.service(getfenv(), {
	onEnable = function()
		poll()
	end,

	update = function()
		poll()
	end,

	onIpc = function(event: string, payload: string)
		if event == "cycle" then
			cycle(payload)
		end
	end,
})

poll()
