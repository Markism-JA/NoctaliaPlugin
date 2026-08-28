--!nonstrict
-- Interactive Workspace Layout Selector Panel for Hyprland & Noctalia

local noctalia = noctalia
local ui = ui
--!nonstrict
-- Interactive Workspace Layout Selector Panel for Hyprland & Noctalia

local noctalia = noctalia
local ui = ui
local panel = panel
if noctalia == nil then
  local host = require("./tests/host_mock")
  noctalia = host.noctalia
  ui = host.ui
  panel = host.panel
end

local PANEL_ID = "maddingo/hypr-layout-switcher:layouts"

local LAYOUT_OPTIONS = {
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

local panelOpen = false
local focusedMonitor = "default"
local activeWsId = nil
local activeWsName = ""
local currentLayout = "dwindle"
local selectedIndex = 1

local render

local function setLayout(layoutId)
  local lua
  if activeWsId then
    lua = string.format("hl.workspace_rule({workspace = %q, layout = %q})", tostring(activeWsId), layoutId)
  else
    lua = string.format(
      "local w = hl.get_active_special_workspace() or hl.get_active_workspace(); "
        .. "if w then if w.special then hl.workspace_rule({workspace = tostring(w.name), layout = %q}) "
        .. "else hl.workspace_rule({workspace = tostring(w.id), layout = %q}) end end",
      layoutId, layoutId
    )
  end

  local cmd = "hyprctl eval '" .. lua:gsub("'", "'\\''") .. "'"
  noctalia.runAsync(cmd, function()
    local topology = noctalia.state.get("hypr.topology")
    if topology and type(topology.monitors) == "table" and topology.monitors[focusedMonitor] then
      topology.monitors[focusedMonitor].layout = layoutId
      topology.focusedLayout = layoutId
      noctalia.state.set("hypr.topology", topology)
    end
  end)

  panel.close()
end

local function syncSelectedIndex()
  for idx, opt in ipairs(LAYOUT_OPTIONS) do
    if opt.id == currentLayout then
      selectedIndex = idx
      break
    end
  end
end

local function fetchActiveState(cb)
  local topology = noctalia.state.get("hypr.topology")
  if topology and type(topology.monitors) == "table" then
    focusedMonitor = topology.focusedOutput or "default"
    local monData = topology.monitors[focusedMonitor]
    if monData then
      activeWsId = monData.workspaceId
      activeWsName = monData.workspaceName or tostring(activeWsId)
      currentLayout = monData.layout or "dwindle"
      syncSelectedIndex()
      if cb then cb() end
      return
    end
  end

  if not noctalia.commandExists("hyprctl") then
    syncSelectedIndex()
    if cb then cb() end
    return
  end

  noctalia.runAsync("hyprctl activeworkspace -j", function(wsRes)
    if wsRes.exitCode == 0 and wsRes.stdout and wsRes.stdout ~= "" then
      local ws = noctalia.json.decode(wsRes.stdout)
      if type(ws) == "table" then
        activeWsId = ws.id
        activeWsName = ws.name or tostring(ws.id)
        focusedMonitor = ws.monitor or "default"
        currentLayout = ws.tiledLayout or ws.layout or "dwindle"
      end
    end
    syncSelectedIndex()
    if cb then cb() end
  end)
end

local function layoutCard(opt, index)
  local isActive = (opt.id == currentLayout)
  local isNavFocused = (index == selectedIndex)

  local cardFill = isNavFocused and (isActive and "primary/0.25" or "surface_variant/0.5")
    or (isActive and "primary/0.12" or "surface_variant/0.2")

  local borderColor = isNavFocused and "primary"
    or (isActive and "primary/0.5" or "outline/0.15")

  local borderWidth = isNavFocused and 2 or 1
  local titleColor = (isNavFocused or isActive) and "primary" or "on_surface"

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
    -- Centered icon container using ui.row
    ui.row({
      width = 40,
      height = 40,
      radius = 8,
      fill = isNavFocused and "primary" or (isActive and "primary/0.7" or "surface_variant/0.4"),
      align = "center",
      justify = "center",
    }, {
      ui.glyph({
        name = opt.glyph,
        size = 20,
        color = (isNavFocused or (isActive and isNavFocused)) and "on_primary" 
          or (isActive and "primary" or "on_surface_variant"),
      }),
    }),

    -- Details
    ui.column({ flexGrow = 1, gap = 2, align = "stretch" }, {
      ui.row({ align = "center", justify = "space_between" }, {
        ui.row({ gap = 6, align = "center" }, {
          ui.label({ text = opt.name, fontWeight = "bold", fontSize = 14, color = titleColor }),
          ui.row({
            fill = isActive and "primary/0.25" or "surface_variant/0.4",
            radius = 4,
            paddingH = 5,
            paddingV = 1,
            align = "center",
          }, {
            ui.label({
              text = opt.badge,
              fontSize = 10,
              fontWeight = "bold",
              color = isActive and "primary" or "on_surface_variant",
            }),
          }),
        }),

        if isActive then
          ui.row({ fill = "primary", radius = 6, paddingH = 6, paddingV = 2, align = "center" }, {
            ui.label({ text = "ACTIVE", fontSize = 10, fontWeight = "bold", color = "on_primary" }),
          })
        else
          ui.label({
            text = isNavFocused and "⏎" or ("[" .. opt.shortcut .. "]"),
            fontSize = 11,
            fontWeight = isNavFocused and "bold" or "medium",
            color = isNavFocused and "primary" or "on_surface_variant",
          })
      }),
      ui.label({
        text = opt.description,
        fontSize = 11,
        color = isNavFocused and "on_surface" or "on_surface_variant",
        maxLines = 1,
      }),
    }),
  })
end

render = function()
  if not panelOpen then return end

  local layoutCards = {}
  for idx, opt in ipairs(LAYOUT_OPTIONS) do
    table.insert(layoutCards, layoutCard(opt, idx))
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
        ui.label({ text = "Select Workspace Layout", fontSize = 15, fontWeight = "bold", color = "on_surface" }),
      }),
      ui.row({ gap = 8, align = "center" }, {
        ui.row({ fill = "secondary/0.2", radius = 6, paddingH = 7, paddingV = 3, align = "center" }, {
          ui.label({
            text = string.format("%s • WS %s", focusedMonitor, activeWsName ~= "" and activeWsName or "?"),
            color = "secondary",
            fontSize = 11,
            fontWeight = "bold",
          }),
        }),
        ui.button({
          glyph = "x",
          variant = "ghost",
          controlSize = "sm",
          onClick = function() panel.close() end,
        }),
      }),
    }),

    -- Card List
    ui.column({ gap = 8, align = "stretch", flexGrow = 1 }, layoutCards),

    -- Footer Legend
    ui.row({ align = "center", justify = "space_between" }, {
      ui.label({ text = "[↑/↓, j/k] Navigate  •  [Enter] Apply  •  [1-4] Quick", fontSize = 11, color = "on_surface_variant" }),
      ui.label({ text = "[Esc] Cancel", fontSize = 11, color = "on_surface_variant" }),
    }),
  }))
end

function onKey(chord, pressed)
  if not pressed then return end

  if chord == "down" or chord == "j" then
    selectedIndex = (selectedIndex % #LAYOUT_OPTIONS) + 1
    render()
  elseif chord == "up" or chord == "k" then
    selectedIndex = (selectedIndex - 2 + #LAYOUT_OPTIONS) % #LAYOUT_OPTIONS + 1
    render()
  elseif chord == "Return" or chord == "space" then
    if LAYOUT_OPTIONS[selectedIndex] then
      setLayout(LAYOUT_OPTIONS[selectedIndex].id)
    end
  elseif chord == "1" or chord == "2" or chord == "3" or chord == "4" then
    local idx = tonumber(chord)
    if idx and LAYOUT_OPTIONS[idx] then
      selectedIndex = idx
      setLayout(LAYOUT_OPTIONS[idx].id)
    end
  elseif chord == "q" then
    panel.close()
  end
end

function onOpen(_context)
  panelOpen = true
  fetchActiveState(function()
    render()
  end)
end

function onClose()
  panelOpen = false
  activeWsId = nil
end

function onExit(_signal)
  panelOpen = false
  activeWsId = nil
end

function onIpc(event, _payload)
  if event == "toggle" then
    if panelOpen then panel.close() else noctalia.togglePanel(PANEL_ID) end
  end
end
