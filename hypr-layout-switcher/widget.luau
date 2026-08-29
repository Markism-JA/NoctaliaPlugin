--!nonstrict
-- Declarative Bar Widget: Screen-Isolated Topology Subscriber

local NEXT_LAYOUT = {
  dwindle   = "master",
  master    = "monocle",
  monocle   = "scrolling",
  scrolling = "dwindle",
}

local GLYPHS = {
  dwindle   = "layout-grid",
  master    = "layout-sidebar",
  monocle   = "square",
  scrolling = "arrows-horizontal",
}

local LABELS = {
  dwindle   = "DWN",
  master    = "MST",
  monocle   = "MON",
  scrolling = "SCR",
}

local function evaluateVal(val)
  if val == nil then return nil end
  if type(val) == "string" and val ~= "" then return val end
  if type(val) == "function" then
    local ok, res = pcall(val, barWidget)
    if ok and res ~= nil then return evaluateVal(res) end
  end
  if type(val) == "table" or type(val) == "userdata" then
    for _, prop in ipairs({ "name", "screenName", "outputName", "model", "id" }) do
      local ok, sub = pcall(function() return (val :: any)[prop] end)
      if ok and sub ~= nil then
        local res = evaluateVal(sub)
        if res then return res end
      end
      local okM, subM = pcall(function() return (val :: any)[prop](val) end)
      if okM and subM ~= nil then
        local res = evaluateVal(subM)
        if res then return res end
      end
    end
  end
  return nil
end

local function resolveOutputName()
  if barWidget == nil then return "default" end
  local candidateKeys = { "screen", "screenName", "output", "outputName", "monitor", "monitorName", "targetScreen", "bar" }
  for _, key in ipairs(candidateKeys) do
    local ok, prop = pcall(function() return (barWidget :: any)[key] end)
    if ok and prop ~= nil then
      local res = evaluateVal(prop)
      if res then return res end
    end
    local okM, methodRes = pcall(function() return (barWidget :: any)[key](barWidget) end)
    if okM and methodRes ~= nil then
      local res = evaluateVal(methodRes)
      if res then return res end
    end
  end
  return "default"
end

local myOutput = resolveOutputName()
local currentLayout = "dwindle"
local hasResolved = false

local function extractMyLayout(topology)
  if not topology or type(topology) ~= "table" then return currentLayout end
  if myOutput ~= "default" and topology.monitors and topology.monitors[myOutput] then
    hasResolved = true
    return topology.monitors[myOutput].layout or "dwindle"
  end
  if not hasResolved then
    return topology.focusedLayout or "dwindle"
  end
  return currentLayout
end

local initialTopology = noctalia.state.get("hypr.topology")
currentLayout = extractMyLayout(initialTopology)

local function render()
  local container = barWidget.isVertical() and ui.column or ui.row

  barWidget.render(container({
      gap = 5,
      align = "center",
      paddingH = 6,
      paddingV = 2,
  }, {
    ui.glyph({
      name = GLYPHS[currentLayout] or "layout-grid",
      size = 14,
      color = "primary",
    }),
    ui.row({
      fill = "primary/0.18",
      radius = 6,
      minWidth = 36,
      minHeight = 18,
      align = "center",
      justify = "center",
      paddingH = 4,
    }, {
      ui.label({
        text = LABELS[currentLayout] or currentLayout:sub(1, 3):upper(),
        color = "primary",
        fontWeight = "bold",
        fontSize = 11,
        textAlign = "center",
      }),
    }),
  }))
end

noctalia.state.watch("hypr.topology", function(topology)
  local nextLayout = extractMyLayout(topology)
  if nextLayout ~= currentLayout then
    currentLayout = nextLayout
    render()
  end
end)

function onClick()
  currentLayout = NEXT_LAYOUT[currentLayout] or "dwindle"
  render()
  noctalia.runAsync(string.format(
    "noctalia msg plugin maddingo/hypr-layout-switcher:poller all cycle %s",
    myOutput
  ))
end

render()
