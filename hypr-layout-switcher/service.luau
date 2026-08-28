--!nonstrict
-- Headless Service: Topology Slice Synchronizer & IPC Router

local NEXT_LAYOUT = {
  dwindle   = "master",
  master    = "monocle",
  monocle   = "scrolling",
  scrolling = "dwindle",
}

noctalia.setUpdateInterval(400)

local isPolling = false
local currentTopology = {
  focusedOutput = "default",
  focusedLayout = "dwindle",
  monitors = {},
}

-- Zero-allocation structural equality check
local function isTopologyEqual(a, b)
  if a == b then return true end
  if not a or not b then return false end
  if a.focusedOutput ~= b.focusedOutput or a.focusedLayout ~= b.focusedLayout then
    return false
  end

  local ma, mb = a.monitors, b.monitors
  if ma == mb then return true end
  if not ma or not mb then return false end

  for name, monA in pairs(ma) do
    local monB = mb[name]
    if not monB then return false end
    if monA.workspaceId ~= monB.workspaceId
      or monA.layout ~= monB.layout
      or monA.focused ~= monB.focused then
      return false
    end
  end

  for name in pairs(mb) do
    if not ma[name] then return false end
  end

  return true
end

local function setLayoutCmd(layout, targetWsId)
  local lua
  if targetWsId and tostring(targetWsId) ~= "" then
    lua = string.format("hl.workspace_rule({workspace = %q, layout = %q})", tostring(targetWsId), layout)
  else
    lua = string.format(
      "local w = hl.get_active_special_workspace() or hl.get_active_workspace(); "
        .. "if w then if w.special then hl.workspace_rule({workspace = tostring(w.name), layout = %q}) "
        .. "else hl.workspace_rule({workspace = tostring(w.id), layout = %q}) end end",
      layout, layout
    )
  end
  return "hyprctl eval '" .. lua:gsub("'", "'\\''") .. "'"
end

local function poll()
  if isPolling or not noctalia.commandExists("hyprctl") then return end
  isPolling = true

  noctalia.runAsync("hyprctl monitors -j", function(monResult)
    if monResult.exitCode ~= 0 or not monResult.stdout or monResult.stdout == "" then
      isPolling = false
      return
    end

    local monitors = noctalia.json.decode(monResult.stdout)
    if type(monitors) ~= "table" then
      isPolling = false
      return
    end

    noctalia.runAsync("hyprctl workspaces -j", function(wsResult)
      isPolling = false

      if wsResult.exitCode ~= 0 or not wsResult.stdout or wsResult.stdout == "" then
        return
      end

      local workspaces = noctalia.json.decode(wsResult.stdout)
      if type(workspaces) ~= "table" then return end

      local wsLayoutMap = {}
      for _, ws in ipairs(workspaces) do
        if ws.id then
          wsLayoutMap[ws.id] = ws.tiledLayout or ws.layout or "dwindle"
        end
      end

      local newTopology = {
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
          workspaceName = activeWs and activeWs.name or tostring(activeWsId),
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
        noctalia.state.set("hypr.topology", newTopology)
      end
    end)
  end)
end

local function cycle(targetOutput)
  local targetWsId = nil
  local currentLayout = "dwindle"

  if targetOutput and targetOutput ~= "all" and targetOutput ~= "default" and currentTopology.monitors[targetOutput] then
    local mon = currentTopology.monitors[targetOutput]
    currentLayout = mon.layout or "dwindle"
    targetWsId = mon.workspaceId
  else
    currentLayout = currentTopology.focusedLayout or "dwindle"
    local focusedMon = currentTopology.monitors[currentTopology.focusedOutput]
    targetWsId = focusedMon and focusedMon.workspaceId or nil
  end

  local nextLayout = NEXT_LAYOUT[currentLayout] or "dwindle"

  if targetOutput and currentTopology.monitors[targetOutput] then
    currentTopology.monitors[targetOutput].layout = nextLayout
  end
  currentTopology.focusedLayout = nextLayout
  noctalia.state.set("hypr.topology", currentTopology)

  noctalia.runAsync(setLayoutCmd(nextLayout, targetWsId), function()
    poll()
  end)
end

function onIpc(event, payload)
  if event == "cycle" then
    cycle(payload)
  end
end

function update()
  poll()
end

poll()
