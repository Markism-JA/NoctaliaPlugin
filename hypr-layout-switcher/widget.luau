--!nonstrict

local layouts = { "dwindle", "master", "monocle", "scrolling" }

local glyphs = {
  dwindle   = "layout-grid",
  master    = "layout-sidebar",
  monocle   = "square",
  scrolling = "arrows-horizontal",
}

local labels = {
  dwindle   = "DWN",
  master    = "MST",
  monocle   = "MON",
  scrolling = "SCR",
}

local current = noctalia.state.get("layout") or "dwindle"

local function render()
  barWidget.setGlyph(glyphs[current] or "layout-grid")
barWidget.setText(string.format("%-4s", labels[current] or current:sub(1, 3):upper()))
end

noctalia.state.watch("layout", function(value)
  if value and value ~= current then
    current = value
    render()
  end
end)

function onClick()
  -- 1. Optimistic UI update (0ms instant click response)
  local idx = 1
  for i, l in ipairs(layouts) do
    if l == current then
      idx = (i % #layouts) + 1
      break
    end
  end
  current = layouts[idx]
  render()
  noctalia.state.set("layout", current)

  -- 2. Trigger standard Noctalia IPC
  noctalia.runAsync("noctalia msg plugin maddingo/hypr-layout-switcher:poller all cycle")
end

render()
