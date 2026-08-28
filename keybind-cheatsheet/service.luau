--!nonstrict
-- Cache-first keybind data service for Mango, Hyprland, and Niri.
--
-- The active configuration is parsed once during script startup and only
-- again after a relevant settings change or explicit refresh request. There
-- is no update interval, filesystem watcher, polling loop, or persistent
-- subprocess.

local noctalia = noctalia
if noctalia == nil then
  local host = require("./tests/host_mock")
  noctalia = host.noctalia
end

local SNAPSHOT_KEY = "keybind-cheatsheet.snapshot"
local REFRESH_REQUEST_KEY = "keybind-cheatsheet.refresh-request"
local SELF_TEST_REQUEST_KEY = "keybind-cheatsheet.self-test-request"
local BINDINGS_CACHE_FILE = "bindings-cache.json"
local CACHE_SCHEMA = 1

local refreshing = false
local refreshQueued = false
local refreshGeneration = 0
local lastGood = nil

local function tr(key, values)
  return noctalia.tr(key, values)
end

local function trim(s)
  if not s or s == "" then
      return ""
  end

  local from = s:match("^%s*()")
  return from > #s and "" or s:match(".*%S", from)
end

local function lower(s)
  return string.lower(s or "")
end

local function startsWith(s, prefix)
  return s:sub(1, #prefix) == prefix
end

local function configString(key, fallback)
  local value = noctalia.getConfig(key)
  if type(value) ~= "string" or trim(value) == "" then
    return fallback
  end
  return trim(value)
end

local function pathDirname(path)
  local clean = (path or ""):gsub("/+$", "")
  local parent = clean:match("^(.*)/[^/]*$")
  if parent == nil or parent == "" then
    return clean:sub(1, 1) == "/" and "/" or "."
  end
  return parent
end

local function pathJoin(base, child)
  if not child or child == "" then
      return base
  end
  if child:sub(1, 1) == "/" then
    return child
  end
  if base == "/" then
    return "/" .. child
  end
  return (base:gsub("/+$", "")) .. "/" .. child
end

local function normalizePath(path)
  local absolute = path:sub(1, 1) == "/"
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 and parts[#parts] ~= ".." then
        table.remove(parts)
      elseif not absolute then
        table.insert(parts, part)
      end
    elseif part ~= "." and part ~= "" then
      table.insert(parts, part)
    end
  end
  local result = table.concat(parts, "/")
  if absolute then
      result = "/" .. result
  end
  return result == "" and (absolute and "/" or ".") or result
end

local function expandEnvironment(path)
  local expanded = path:gsub("%${([%w_]+)}", function(name)
    return noctalia.getenv(name) or "${" .. name .. "}"
  end)
  expanded = expanded:gsub("%$HOME", noctalia.getenv("HOME") or "~")
  return noctalia.expandPath(expanded)
end

local function unquote(value)
  local result = trim(value)
  if #result >= 2 then
    local first = result:sub(1, 1)
    local last = result:sub(-1)
    if (first == "\"" and last == "\"") or (first == "'" and last == "'") then
      result = result:sub(2, -2)
    end
  end
  return result
end

local function splitCsv(value, maximumParts)
  local parts = {}
  local count = 0
  for item in (value .. ","):gmatch("(.-),") do
    count = count + 1
    if maximumParts and count >= maximumParts then break end
    table.insert(parts, trim(item))
  end
  if #parts == 0 then table.insert(parts, trim(value)) end
  return parts
end

-- ============================================================================
-- Modifiers & Identity
-- ============================================================================
local MODIFIER_ORDER = { "SUPER", "CTRL", "SHIFT", "ALT", "MOD2", "MOD3", "MOD5" }
local KNOWN_MODIFIERS = { SUPER = true, CTRL = true, SHIFT = true, ALT = true, MOD2 = true, MOD3 = true, MOD5 = true }
local MODIFIER_ALIASES = { LOGO = "SUPER", WIN = "SUPER", MOD4 = "SUPER", CONTROL = "CTRL", MOD1 = "ALT" }

local function normalizeModifiers(value, variables)
  local raw = value or ""
  if variables then
    for varName, varVal in pairs(variables) do
      if type(varVal) == "string" then
        raw = raw:gsub(varName, varVal)
      end
    end
  end
  raw = raw:gsub("%+", " "):gsub("|", " "):gsub(",", " ")
  local present = {}
  local unknown = {}
  for token in raw:gmatch("[^%s]+") do
    local upper = string.upper(token)
    upper = MODIFIER_ALIASES[upper] or upper
    if upper ~= "NONE" and upper ~= "" then
      if KNOWN_MODIFIERS[upper] then
        present[upper] = true
      elseif not present[upper] then
        present[upper] = true
        table.insert(unknown, upper)
      end
    end
  end
  local result = {}
  for _, name in ipairs(MODIFIER_ORDER) do
    if present[name] then table.insert(result, name) end
  end
  for _, name in ipairs(unknown) do table.insert(result, name) end
  return result
end

local function bindingIdentity(binding)
  return table.concat({
    binding.compositor or "",
    binding.bindingType or "",
    table.concat(binding.modifiers or {}, "+"),
    binding.key or "",
    binding.action or "",
    binding.submap or "",
  }, "|")
end

local function addBinding(target, binding, skipTrim)
  if not skipTrim then
    binding.description = trim(binding.description)
    binding.category = trim(binding.category)
    binding.action = trim(binding.action)
    binding.key = trim(binding.key)
  end
  binding.baseCategory = binding.category
  binding.modifiers = binding.modifiers or {}
  binding.id = bindingIdentity(binding)
  table.insert(target, binding)
end

-- ============================================================================
-- Fast Heuristic Category Fallbacks
-- ============================================================================

local DISPATCHER_MAP = {
  killactive = "Window Management & Placement",
  closewindow = "Window Management & Placement",
  togglefloating = "Window Management & Placement",
  fullscreen = "Window Management & Placement",
  movefocus = "Focus & Navigation",
  focuswindow = "Focus & Navigation",
  cyclenext = "Focus & Navigation",
  focusmonitor = "Focus & Navigation",
  workspace = "Workspaces & Scratchpads",
  movetoworkspace = "Workspaces & Scratchpads",
  movetoworkspacesilent = "Workspaces & Scratchpads",
  togglespecialworkspace = "Workspaces & Scratchpads",
  submap = "Submaps & Modes: VM Passthrough",
}

local function fallbackCategory(dispatcher, arg, desc)
  local direct = DISPATCHER_MAP[dispatcher]
  if direct then return direct end

  local s = lower(desc)
  if s == "" then return "Other" end
  if s:find("launch", 1, true) or s:find("terminal", 1, true) or s:find("browser", 1, true) then
    return "Applications & Launchers"
  end
  if s:find("toggle", 1, true) or s:find("control center", 1, true) or s:find("bar", 1, true) then
    return "Shell & Desktop Controls"
  end
  if s:find("layout", 1, true) or s:find("master", 1, true) or s:find("dwindle", 1, true) then
    return "Workspace Layouts"
  end
  if s:find("brightness", 1, true) or s:find("volume", 1, true) or s:find("media", 1, true) then
    return "Media & Hardware"
  end
  if s:find("screen", 1, true) or s:find("ocr", 1, true) or s:find("annotate", 1, true) then
    return "Screen Toolkit & Capture Utilities"
  end
  return "Other"
end

local function fallbackCategory(dispatcher, arg, desc)
  local d = lower(dispatcher or "")
  local a = lower(arg or "")
  local s = lower(desc or "")
  local combined = d .. " " .. a .. " " .. s

  if s:find("launch") or s:find("terminal") or s:find("browser") or s:find("file manager")
    or combined:find("rofi") or combined:find("wofi") or combined:find("launcher") or combined:find("fsearch") then
    return "Applications & Launchers"
  end
  if s:find("toggle") or s:find("control center") or s:find("bar")
    or s:find("clipboard") or s:find("wallpaper") or s:find("theme") or s:find("session") or s:find("cheatsheet") then
    return "Shell & Desktop Controls"
  end
  if s:find("close") or s:find("zap") or s:find("float") or s:find("maximize")
    or s:find("fullscreen") or s:find("pin") or s:find("align") or s:find("split")
    or d == "killactive" or d == "closewindow" or d == "togglefloating" or d == "fullscreen" then
    return "Window Management & Placement"
  end
  if s:find("focus window") or s:find("move window") or s:find("cycle") or s:find("monitor")
    or d == "movefocus" or d == "focuswindow" or d == "cyclenext" or d == "focusmonitor" then
    return "Focus & Navigation"
  end
  if s:find("workspace") or s:find("scratchpad") or d == "workspace" or d == "movetoworkspace" or d == "togglespecialworkspace" then
    return "Workspaces & Scratchpads"
  end
  if s:find("layout") or s:find("master") or s:find("dwindle") or s:find("scrolling") or s:find("monocle") or d == "layout" then
    return "Workspace Layouts"
  end
  if s:find("brightness") or s:find("volume") or s:find("mute") or s:find("media") or s:find("track") or s:find("zoom")
    or combined:find("audio") or combined:find("monbrightness") then
    return "Media & Hardware"
  end
  if s:find("screen") or s:find("annotate") or s:find("ocr") or s:find("lens") or s:find("picker")
    or s:find("qr") or s:find("measure") or s:find("screenshot") or s:find("recorder") or s:find("gsr")
    or combined:find("grim") or combined:find("slurp") or combined:find("screen-toolkit") then
    return "Screen Toolkit & Capture Utilities"
  end
  if s:find("passthrough") or s:find("submap") or d == "submap" then
    return "Submaps & Modes: VM Passthrough"
  end

  return "Other"
end

-- ============================================================================
-- Budget-Safe Ultra Fast Lexer & AST Scanner
-- ============================================================================
local function scanHyprLuaContent(content, context)
  local currentCategory = "General"

  for line in content:gmatch("[^\r\n]+") do
    local b1, b2 = line:byte(1, 2)

    -- Fast branch 1: Line comment (-- ...)
    if b1 == 45 and b2 == 45 then
      local text = line:match("^%-%-+%s*(%w.*)")
      if text then
        local clean = text:match("^%d+[%d%.%-_:)%s]+(.*)") or text
        clean = clean:match("^([%w%s%&%/%,%-%(%)%:%+]+)")
        if clean then
          clean = trim(clean)
          if #clean >= 3 and #clean <= 60 and not clean:find("=", 1, true) then
            local l = lower(clean)
            if not l:match("^local%s") and not l:match("^function%s") and not l:match("^return%s") and not l:match("^hl%.") then
              currentCategory = clean
            end
          end
        end
      end
    -- Fast branch 2: Code line potentially containing description
    elseif line:find("desc", 1, true) then
      local desc = line:match('description%s*=%s*["\']([^"\']+)["\']')
        or line:match('desc%s*=%s*["\']([^"\']+)["\']')
      if desc and desc ~= "" then
        context.exactRules[desc] = currentCategory
      end
    end
  end
end

local function scanHyprLua(rootPath)
  local luaRoot = pathDirname(normalizePath(expandEnvironment(rootPath)))
  local context = {
    exactRules = {},
    warnings = {},
    sources = {},
  }

  local visited = {}
  local fileList = {
    normalizePath(expandEnvironment(rootPath)),
    pathJoin(luaRoot, "keybinds.lua"),
    pathJoin(luaRoot, "binds.lua"),
    pathJoin(luaRoot, "modules/keybinds.lua"),
    pathJoin(luaRoot, "plugins/gloview.lua"),
  }

  local rootContent = noctalia.readFile(fileList[1])
  if rootContent then
    for modName in rootContent:gmatch('name%s*=%s*["\']([^"\']+)["\']') do
      if modName:find("bind", 1, true) or modName:find("workspaces", 1, true) or modName:find("gloview", 1, true) then
        table.insert(fileList, pathJoin(luaRoot, modName:gsub("%.", "/") .. ".lua"))
      end
    end
  end

  for _, path in ipairs(fileList) do
    local normPath = normalizePath(path)
    if not visited[normPath] then
      visited[normPath] = true
      local content = noctalia.readFile(normPath)
      if content and (content:find("bind", 1, true) or content:find("desc", 1, true)) then
        local info = noctalia.fileInfo(normPath)
        if info then
          table.insert(context.sources, { path = normPath, size = info.size, mtime = info.mtime })
        end
        scanHyprLuaContent(content, context)
      end
    end
  end

  return context
end

local function modifiersFromMask(mask)
  mask = tonumber(mask) or 0
  if mask == 0 then return {} end

  local res = {}
  if bit32 and bit32.band then
    if bit32.band(mask, 64) ~= 0 then table.insert(res, "SUPER") end
    if bit32.band(mask, 4)  ~= 0 then table.insert(res, "CTRL") end
    if bit32.band(mask, 1)  ~= 0 then table.insert(res, "SHIFT") end
    if bit32.band(mask, 8)  ~= 0 then table.insert(res, "ALT") end
    if bit32.band(mask, 16) ~= 0 then table.insert(res, "MOD2") end
    if bit32.band(mask, 32) ~= 0 then table.insert(res, "MOD3") end
    if bit32.band(mask, 128) ~= 0 then table.insert(res, "MOD5") end
  else
    if math.floor(mask / 64) % 2 == 1 then table.insert(res, "SUPER") end
    if math.floor(mask / 4)  % 2 == 1 then table.insert(res, "CTRL") end
    if math.floor(mask / 1)  % 2 == 1 then table.insert(res, "SHIFT") end
    if math.floor(mask / 8)  % 2 == 1 then table.insert(res, "ALT") end
    if math.floor(mask / 16) % 2 == 1 then table.insert(res, "MOD2") end
    if math.floor(mask / 32) % 2 == 1 then table.insert(res, "MOD3") end
    if math.floor(mask / 128) % 2 == 1 then table.insert(res, "MOD5") end
  end
  return res
end

local function parseHyprJson(raw, scanContext)
  local decoded, err = noctalia.json.decode(raw)
  if type(decoded) ~= "table" then return nil, err or "Invalid hyprctl JSON" end
  local result = {}
  local exactRules = scanContext.exactRules or {}

  for _, entry in ipairs(decoded) do
    if type(entry) == "table" then
      local description = entry.has_description == false and "" or (entry.description or "")
      local key = entry.key or ""
      if key == "" and tonumber(entry.keycode) ~= nil and tonumber(entry.keycode) ~= 0 then
        key = "code:" .. tostring(entry.keycode)
      end
      local dispatcher = entry.dispatcher or ""
      local argument = entry.arg or ""

      if key ~= "" and dispatcher ~= "" then
        local bType = entry.mouse == true and "bindm" or "bind"
        local submap = entry.submap or ""
        local modifiers = modifiersFromMask(entry.modmask)
        local category = nil

        if description ~= "" then
          category = exactRules[description]
        end
        if not category or category == "" then
          category = fallbackCategory(dispatcher, argument, description)
        end

        -- Direct string construction without regex trim
        local action = argument ~= "" and (dispatcher .. " " .. argument) or dispatcher

        addBinding(result, {
          compositor = "hyprland",
          bindingType = bType,
          modifiers = modifiers,
          key = key,
          action = action,
          description = description,
          category = category,
          sourceFile = "hyprctl binds -j",
          sourceLine = 0,
          submap = submap,
        }, true) -- Pass 'true' to signal pre-sanitized input
      end
    end
  end
  return result, nil
end

-- ============================================================================
-- Mango & Niri Parsers
-- ============================================================================
local function extractTrailingDescription(line)
  local ending = line:sub(-1)
  local startIndex, description
  if ending == "\"" then
    startIndex, _, description = line:find("#%s*\"([^\"]*)\"%s*$")
  elseif ending == "'" then
    startIndex, _, description = line:find("#%s*'([^']*)'%s*$")
  end
  if startIndex == nil then
      return line, ""
  end
  return trim(line:sub(1, startIndex - 1)), trim(description)
end

local function parseMangoContent(content, sourceFile, context)
  local category = ""
  local lineNumber = 0
  for rawLine in content:gmatch("[^\r\n]+") do
    lineNumber = lineNumber + 1
    local line = trim(rawLine)
    if line ~= "" then
      if startsWith(line, "#") then
        local text = line:match("^#+%s*(%w.*)")
        if text then category = trim(text) end
      elseif line:find("bind", 1, true) ~= nil then
        local clean, description = extractTrailingDescription(line)
        local directive, body = clean:match("^([%a]*bind)%s*=%s*(.*)$")
        if directive ~= nil then
          local fields = splitCsv(body, 4)
          local modifiers = normalizeModifiers(fields[1], {})
          local key = fields[2] or ""
          local command = fields[3] or ""
          local parameters = fields[4] or ""
          if key ~= "" and command ~= "" then
            addBinding(context.bindings, {
              compositor = "mango",
              bindingType = lower(directive),
              modifiers = modifiers,
              key = key,
              action = trim(command .. " " .. parameters),
              description = description,
              category = category ~= "" and category or fallbackCategory(command, parameters, description),
              sourceFile = sourceFile,
              sourceLine = lineNumber,
            })
          end
        end
      end
    end
  end
  return {}
end

local function parseHyprContent(content, sourceFile, context)
  local category = ""
  local lineNumber = 0
  for rawLine in content:gmatch("[^\r\n]+") do
    lineNumber = lineNumber + 1
    local line = trim(rawLine)
    if line ~= "" then
      local variable, value = line:match("^%$([%w_]+)%s*=%s*(.-)%s*$")
      local heading = startsWith(line, "#") and line:match("^#+%s*(%w.*)") or nil
      if variable ~= nil then
        context.variables[variable] = value
      elseif heading ~= nil then
        category = trim(heading)
      else
        local clean, description = extractTrailingDescription(line)
        local directive, body = clean:match("^(bind[%a]*)%s*=%s*(.*)$")
        if directive ~= nil then
          local fields = splitCsv(body, 4)
          local key = fields[2] or ""
          local dispatcher = fields[3] or ""
          if key ~= "" and dispatcher ~= "" then
            addBinding(context.bindings, {
              compositor = "hyprland",
              bindingType = lower(directive),
              modifiers = normalizeModifiers(fields[1], context.variables),
              key = key,
              action = trim(dispatcher .. " " .. (fields[4] or "")),
              description = description,
              category = category ~= "" and category or fallbackCategory(dispatcher, fields[4] or "", description),
              sourceFile = sourceFile,
              sourceLine = lineNumber,
            })
          end
        end
      end
    end
  end
  return {}
end

local function parseNiriContent(content, sourceFile, context)
  local category = ""
  for rawLine in content:gmatch("[^\r\n]+") do
    local line = trim(rawLine)
    if startsWith(line, "//") or startsWith(line, "#") then
      local text = line:match("^[/#]+%s*(%w.*)")
      if text then category = trim(text) end
    end
  end
  return {}
end

-- ============================================================================
-- Runtime Orchestration
-- ============================================================================
local function walkConfig(rootPath, parser)
  local context = { bindings = {}, variables = {}, warnings = {}, sources = {} }
  local file = normalizePath(expandEnvironment(rootPath))
  local content = noctalia.readFile(file)
  if content then parser(content, file, context) end
  return context
end

local function detectCompositor()
  local forced = configString("compositor", "auto")
  if forced ~= "auto" then
    return forced
  end
  if noctalia.getenv("MANGO_INSTANCE_SIGNATURE") ~= nil then return "mango" end
  if noctalia.getenv("HYPRLAND_INSTANCE_SIGNATURE") ~= nil then return "hyprland" end
  if noctalia.getenv("NIRI_SOCKET") ~= nil then return "niri" end
  return "hyprland"
end

local function currentRequest()
  local compositor = detectCompositor()
  if compositor == "mango" then
    return { compositor = compositor, parser = "mango", root = normalizePath(expandEnvironment(configString("mango_config", "~/.config/mango/config.conf"))) }
  elseif compositor == "niri" then
    return { compositor = compositor, parser = "niri", root = normalizePath(expandEnvironment(configString("niri_config", "~/.config/niri/config.kdl"))) }
  else
    local mode = configString("hyprland_parser", "auto")
    local luaPath = configString("hyprland_lua_config", "~/.config/hypr/hyprland.lua")
    local useLua = mode == "lua" or (mode == "auto" and noctalia.fileExists(noctalia.expandPath(luaPath)))
    local root = useLua and luaPath or configString("hyprland_config", "~/.config/hypr/hyprland.conf")
    return { compositor = "hyprland", parser = useLua and "hypr-lua" or "hypr-conf", root = normalizePath(expandEnvironment(root)) }
  end
end

local function requestsMatch(left, right)
  return type(left) == "table" and type(right) == "table"
    and left.compositor == right.compositor
    and left.parser == right.parser
    and left.root == right.root
end

local function normalizedCache(decoded)
  if type(decoded) ~= "table" or decoded.schema ~= CACHE_SCHEMA or type(decoded.request) ~= "table"
    or type(decoded.bindings) ~= "table" or type(decoded.sources) ~= "table" then
    return nil
  end
  local cachedBindings = {}
  for _, item in ipairs(decoded.bindings) do
    if type(item) == "table" and type(item.key) == "string" and type(item.action) == "string" and type(item.modifiers) == "table" then
      addBinding(cachedBindings, {
        compositor = type(item.compositor) == "string" and item.compositor or decoded.request.compositor,
        bindingType = type(item.bindingType) == "string" and item.bindingType or "bind",
        modifiers = item.modifiers,
        key = item.key,
        action = item.action,
        description = type(item.description) == "string" and item.description or "",
        category = type(item.category) == "string" and item.category or "Other",
        sourceFile = type(item.sourceFile) == "string" and item.sourceFile or "",
        sourceLine = tonumber(item.sourceLine) or 0,
        submap = type(item.submap) == "string" and item.submap or "",
      })
    end
  end
  return {
    schema = CACHE_SCHEMA,
    request = decoded.request,
    bindings = cachedBindings,
    warnings = type(decoded.warnings) == "table" and decoded.warnings or {},
    sources = decoded.sources,
    globs = decoded.globs or {},
  }
end

local function cachePath()
  local directory = noctalia.pluginDataDir()
  if directory == nil then return nil end
  return directory .. "/" .. BINDINGS_CACHE_FILE
end

local function readBindingCache()
  local path = cachePath()
  if path == nil then return nil end
  local raw = noctalia.readFile(path)
  if raw == nil or raw == "" then return nil end
  local decoded = noctalia.json.decode(raw)
  return normalizedCache(decoded)
end

local function saveBindingCache(cache)
  local path = cachePath()
  if path == nil then return end
  local encoded = noctalia.json.encode(cache, false)
  if encoded == nil then return end
  local temp = path .. ".tmp"
  if noctalia.writeFile(temp, encoded) then
    noctalia.renameFile(temp, path)
  end
end

local refresh

local function publish(status, request, cache, err, isRefreshing)
  noctalia.state.set(SNAPSHOT_KEY, {
    schema = CACHE_SCHEMA,
    status = status,
    compositor = request and request.compositor or "",
    parser = request and request.parser or "",
    source = request and request.root or "",
    request = request,
    bindings = cache and cache.bindings or {},
    warnings = cache and cache.warnings or {},
    error = err or "",
    refreshing = isRefreshing == true,
  })
end

local function finishRefresh(generation, request, result, warnings, err, sourceSnapshot)
  if generation ~= refreshGeneration then return end
  refreshing = false
  if err == nil then
    lastGood = {
      schema = CACHE_SCHEMA,
      request = request,
      bindings = result or {},
      warnings = warnings or {},
      sources = sourceSnapshot and sourceSnapshot.sources or {},
      globs = {},
    }
    saveBindingCache(lastGood)
    publish("ready", request, lastGood, "", false)
  else
    publish("ready", request, lastGood, err, false)
  end
  if refreshQueued then
    refreshQueued = false
    refresh(request)
  end
end

local function refreshHyprLua(generation, request)
  if not noctalia.commandExists("hyprctl") then
    finishRefresh(generation, request, {}, {}, tr("hyprctl_missing"), nil)
    return
  end

  noctalia.runAsync("hyprctl binds -j", function(result)
    if generation ~= refreshGeneration then return end
    if result.exitCode ~= 0 or result.timedOut then
      local message = trim(result.stderr)
      finishRefresh(generation, request, {}, {}, message ~= "" and message or tr("hyprctl_failed"), nil)
      return
    end

    local scanOk, scanOrErr = pcall(function()
      return scanHyprLua(request.root)
    end)
    local scan = (scanOk and type(scanOrErr) == "table") and scanOrErr or { warnings = { tostring(scanOrErr) }, exactRules = {} }

    local parseOk, parsedOrErr = pcall(function()
      return parseHyprJson(result.stdout, scan)
    end)

    if parseOk then
      finishRefresh(generation, request, parsedOrErr or {}, scan.warnings or {}, nil, scan)
    else
      finishRefresh(generation, request, {}, scan.warnings or {}, tostring(parsedOrErr), scan)
    end
  end, 10000)
end

local function performRefresh(generation, request)
  if request == nil then
    finishRefresh(generation, { compositor = "", parser = "", root = "" }, {}, {}, tr("unsupported"), nil)
  elseif request.parser == "mango" then
    local context = walkConfig(request.root, parseMangoContent)
    finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
  elseif request.parser == "niri" then
    local context = walkConfig(request.root, parseNiriContent)
    finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
  elseif request.parser == "hypr-lua" then
    refreshHyprLua(generation, request)
  elseif request.parser == "hypr-conf" then
    local context = walkConfig(request.root, parseHyprContent)
    finishRefresh(generation, request, context.bindings, context.warnings, nil, context)
  else
    finishRefresh(generation, request, {}, {}, tr("unsupported"), nil)
  end
end

refresh = function(request)
  if refreshing then
    refreshQueued = true
    return
  end
  request = request or currentRequest()
  refreshGeneration = refreshGeneration + 1
  refreshing = true
  performRefresh(refreshGeneration, request)
end

local function loadCachedSnapshot(request)
  local cached = readBindingCache()
  if requestsMatch(cached and cached.request, request) then
    lastGood = cached
    publish("ready", request, cached, "", true)
  else
    lastGood = nil
    publish("loading", request, nil, "", true)
  end
end

local function bootstrap()
  local request = currentRequest()
  loadCachedSnapshot(request)
  refresh(request)
end

function onConfigChanged()
  local request = currentRequest()
  loadCachedSnapshot(request)
  refresh(request)
end

function onIpc(event, _payload)
  if event == "refresh" then
    refresh()
  elseif event == "self-test" then
    runSelfTest()
  end
end

function onExit(_signal)
  refreshGeneration += 1
  refreshing = false
  refreshQueued = false
end

noctalia.state.watch(REFRESH_REQUEST_KEY, function(_request)
  refresh()
end)

noctalia.state.watch(SELF_TEST_REQUEST_KEY, function(_request)
  runSelfTest()
end)

bootstrap()

return {
  parseMangoContent = parseMangoContent,
  mangoCategoryFromComment = mangoCategoryFromComment,
  parseHyprContent = parseHyprContent,
  parseNiriContent = parseNiriContent,
  parseHyprJson = parseHyprJson,
  scanHyprLua = scanHyprLua,
  walkConfig = walkConfig,
  configReadError = configReadError,
  currentRequest = currentRequest,
  requestsMatch = requestsMatch,
  normalizedCache = normalizedCache,
  refresh = refresh,
  bootstrap = bootstrap,
  resetForTests = resetForTests,
  lifecycleState = lifecycleState,
  onConfigChanged = onConfigChanged,
  onIpc = onIpc,
  onExit = onExit,
  runSelfTest = runSelfTest,
  snapshotKey = SNAPSHOT_KEY,
  refreshRequestKey = REFRESH_REQUEST_KEY,
}
