--!strict
-- Snapshot-driven keybind viewer for Mango, Hyprland, and Niri.
--
-- Parsing, durable cache ownership, and refreshes live in service.luau. This
-- panel only reads the shared snapshot and renders it.
-- Hierarchical category presentation.

local stl = require("../stl/stl.luau")
local constants = require("./constants.luau")
local log = stl.log.scope("KeybindsPanel")
local types = require("./types.luau")

type BindingEntry = types.BindingEntry
type SnapshotState = types.SnapshotState
type ModifierPill = types.ModifierPill

type ColorPreference = {
	background: string?,
	text: string?,
}

type Preferences = {
	version: number,
	hidden: { [string]: boolean },
	descriptions: { [string]: string },
	colors: { [string]: ColorPreference },
}

type CategoryGroup = {
	name: string,
	bindings: { BindingEntry },
	sourceOrder: number,
	order: number,
	weight: number,
}

type ColorBucket = {
	id: string,
	label: string,
	background: string,
	text: string,
	picker: string,
}

type ColumnBucket = {
	groups: { CategoryGroup },
	weight: number,
}

-- State channels
local snapshotChannel = stl.state.channel(constants.SNAPSHOT_KEY, nil :: any)
local refreshChannel = stl.state.channel(constants.REFRESH_REQUEST_KEY, 0)

local bindings: { BindingEntry } = {}
local parseWarnings: { string } = {}
local currentCompositor = ""
local loading = false
local panelOpen = false
local panelError: string? = nil
local refreshError: string? = nil
local query = ""
local searchRevision = 0
local searchFocused = true
local view: "bindings" | "edit" | "appearance" = "bindings"
local editingId: string? = nil
local editDraft = ""
local preferences: Preferences = { version = 1, hidden = {}, descriptions = {}, colors = {} }
local cachedColumnCount: number = 3

local categoryPriorityCache: { [string]: number } = {}

local render: () -> ()
local refresh: () -> ()

local function tr(key: string, values: { [string]: any }?): string
	if noctalia and noctalia.tr then
		return noctalia.tr(key, values)
	end
	return key
end

local function trim(s: string?): string
	if not s or s == "" then
		return ""
	end
	if noctalia and noctalia.string and noctalia.string.trim then
		return noctalia.string.trim(s)
	end
	return string.match(s, "^%s*(.-)%s*$") or ""
end

local function normalizePreferences(decoded: any): Preferences
	local result = { version = 1, hidden = {}, descriptions = {}, colors = {} }
	if typeof(decoded) ~= "table" then
		return result
	end

	for id, hidden in pairs(typeof(decoded.hidden) == "table" and decoded.hidden or {}) do
		if typeof(id) == "string" and hidden == true then
			result.hidden[id] = true
		end
	end
	for id, description in pairs(typeof(decoded.descriptions) == "table" and decoded.descriptions or {}) do
		if typeof(id) == "string" and typeof(description) == "string" and trim(description) ~= "" then
			result.descriptions[id] = trim(description)
		end
	end
	for bucket, colors in pairs(typeof(decoded.colors) == "table" and decoded.colors or {}) do
		if typeof(bucket) == "string" and typeof(colors) == "table" then
			result.colors[bucket] = {}
			if typeof(colors.background) == "string" then
				result.colors[bucket].background = colors.background
			end
			if typeof(colors.text) == "string" then
				result.colors[bucket].text = colors.text
			end
		end
	end
	return result
end

local function loadPreferences()
	local decoded, err = stl.filesystem.readPluginData(constants.PREFERENCES_FILE)
	if err then
		log.debug("No custom preferences file found or failed reading", { err = err })
	end
	preferences = normalizePreferences(decoded)
end

local function savePreferences()
	local ok, err = stl.filesystem.writePluginData(constants.PREFERENCES_FILE, preferences, true)
	if not ok then
		log.error("Failed to save preferences", { err = err })
		if noctalia and noctalia.notifyError then
			noctalia.notifyError(tr("title"), err or "Could not save preferences")
		end
	end
end

-- ============================================================================
-- Color Appearance & Theming
-- ============================================================================

local COLOR_BUCKETS = {
	{ id = "super", label = "Super", background = "primary", text = "on_primary", picker = "#6750A4" },
	{ id = "ctrl", label = "Ctrl", background = "secondary", text = "on_secondary", picker = "#625B71" },
	{ id = "shift", label = "Shift", background = "tertiary", text = "on_tertiary", picker = "#7D5260" },
	{ id = "alt", label = "Alt", background = "error", text = "on_error", picker = "#B3261E" },
	{ id = "xf86", label = "Media", background = "secondary/0.25", text = "secondary", picker = "#E8DEF8" },
	{ id = "number", label = "Numbers", background = "tertiary/0.25", text = "tertiary", picker = "#FFD8E4" },
	{ id = "mouse", label = "Mouse", background = "error/0.2", text = "error", picker = "#F9DEDC" },
	{ id = "print", label = "Print", background = "primary/0.25", text = "primary", picker = "#EADDFF" },
	{
		id = "default",
		label = "Other keys",
		background = "surface_variant",
		text = "on_surface_variant",
		picker = "#E7E0EC",
	},
	{ id = "description", label = "Descriptions", background = "surface", text = "on_surface", picker = "#1D1B20" },
}

local COLOR_BY_ID = {}
for _, bucket in ipairs(COLOR_BUCKETS) do
	COLOR_BY_ID[bucket.id] = bucket
end

local function colorValue(bucketId: string, property: "background" | "text"): string
	local custom = preferences.colors[bucketId]
	if property == "background" then
		if custom and custom.background then
			return custom.background
		end
		local bucket = COLOR_BY_ID[bucketId] or COLOR_BY_ID.default
		return bucket.background
	else
		if custom and custom.text then
			return custom.text
		end
		local bucket = COLOR_BY_ID[bucketId] or COLOR_BY_ID.default
		return bucket.text
	end
end

local function isHexColor(value: any): boolean
	if typeof(value) ~= "string" then
		return false
	end
	return string.match(value, "^#%x%x%x%x%x%x$") ~= nil or string.match(value, "^#%x%x%x%x%x%x%x%x$") ~= nil
end

local function setColor(bucketId: string, property: "background" | "text", value: string)
	local colorObj: ColorPreference = preferences.colors[bucketId] or { background = nil, text = nil }
	if property == "background" then
		colorObj.background = value
	else
		colorObj.text = value
	end
	preferences.colors[bucketId] = colorObj
	savePreferences()
	render()
end

local function chooseColor(bucketId: string, property: "background" | "text")
	local bucket = COLOR_BY_ID[bucketId] or COLOR_BY_ID.default
	local current = colorValue(bucketId, property)
	local initial = isHexColor(current) and string.sub(current, 1, 7) or bucket.picker
	if noctalia and noctalia.openColorPicker then
		noctalia.openColorPicker(initial, function(color)
			if color ~= nil then
				setColor(bucketId, property, color)
			end
		end)
	end
end

local function pasteColor(bucketId: string, property: "background" | "text")
	local value = trim(noctalia and noctalia.clipboardText and noctalia.clipboardText() or "")
	if isHexColor(value) then
		setColor(bucketId, property, string.upper(value))
	else
		if noctalia and noctalia.notifyError then
			noctalia.notifyError(tr("title"), "Clipboard does not contain a #RRGGBB color")
		end
	end
end

local function applySnapshot(value: any)
	local snap = typeof(value) == "table" and (value :: SnapshotState) or nil
	if snap == nil then
		bindings = {}
		parseWarnings = {}
		currentCompositor = ""
		loading = true
		panelError = nil
		refreshError = nil
		return
	end

	bindings = typeof(snap.bindings) == "table" and snap.bindings or {}
	parseWarnings = typeof(snap.warnings) == "table" and snap.warnings or {}
	currentCompositor = typeof(snap.compositor) == "string" and snap.compositor or ""
	loading = (snap.status == "loading" or snap.status == "idle") and #bindings == 0
	panelError = snap.status == "error" and (snap.error or tr("missing_config")) or nil
	refreshError = snap.status == "ready" and typeof(snap.error) == "string" and snap.error ~= "" and snap.error or nil
end

refresh = function()
	local current = tonumber(refreshChannel.get()) or 0
	refreshChannel.set(current + 1)
	render()
end

local function keyPill(text: string, bucketId: string, key: string): UiNode
	return ui.column({
		key = key,
		minWidth = 20,
		fill = colorValue(bucketId, "background"),
		radius = 4,
		paddingH = 7,
		paddingV = 3,
		align = "center",
	}, {
		ui.label({ text = text, color = colorValue(bucketId, "text"), fontSize = 12, fontWeight = "bold" }),
	})
end

local SEARCH_MODIFIER_ALIASES: { [string]: string } = {
	win = "super",
	logo = "super",
	mod4 = "super",
	cmd = "super",
	control = "ctrl",
	mod1 = "alt",
}

local function splitQueryTokens(rawQuery: string): { string }
	local clean = string.gsub(string.lower(rawQuery), "[%+%-%%,_|]+", " ")
	local tokens = {}
	for token in string.gmatch(clean, "%S+") do
		table.insert(tokens, SEARCH_MODIFIER_ALIASES[token] or token)
	end
	return tokens
end

-- Fast single-index raw substring check
local function bindingMatches(binding: BindingEntry, tokens: { string }): boolean
	if #tokens == 0 then
		return true
	end
	local target = binding.searchIndex
	for _, token in ipairs(tokens) do
		if string.find(target, token, 1, true) == nil then
			return false
		end
	end
	return true
end

local CATEGORY_PRIORITIES: { { [number]: any } } = {
	{ "applications", 10 },
	{ "system", 20 },
	{ "window management", 30 },
	{ "focus", 40 },
	{ "navigation", 40 },
	{ "moving windows", 45 },
	{ "workspace", 50 },
	{ "tags", 50 },
	{ "monitor", 50 },
	{ "media", 60 },
	{ "brightness", 60 },
	{ "layout", 70 },
	{ "mouse", 80 },
	{ "touchpad", 90 },
	{ "gesture", 90 },
	{ "integration", 100 },
	{ string.lower(tr("without_description")), 900 },
	{ string.lower(tr("other")), 950 },
}

local function categoryPriority(name: string): number
	local cached = categoryPriorityCache[name]
	if cached then
		return cached
	end

	local value = string.lower(name)
	local score = 500
	for _, entry in ipairs(CATEGORY_PRIORITIES) do
		if string.find(value, entry[1], 1, true) ~= nil then
			score = entry[2]
			break
		end
	end
	categoryPriorityCache[name] = score
	return score
end

local function bindingAvailableInView(
	hidden: boolean,
	undescribed: boolean,
	managing: boolean,
	showUndescribed: boolean
): boolean
	if managing then
		return true
	end
	return not hidden and (showUndescribed or not undescribed)
end

local function hiddenBindingCount(bindingList: { BindingEntry }, hiddenPreferences: { [string]: boolean }): number
	local count = 0
	for _, binding in ipairs(bindingList or {}) do
		if binding.id and hiddenPreferences[binding.id] == true then
			count += 1
		end
	end
	return count
end

local function restoreHiddenBindings(bindingList: { BindingEntry }, hiddenPreferences: { [string]: boolean })
	for _, binding in ipairs(bindingList or {}) do
		hiddenPreferences[binding.id] = nil
	end
end

local function visibleGroups(): { CategoryGroup }
	local showUndescribed = stl.config.getBool("show_undescribed", true)
	local managing = view == "edit"
	local groups: { CategoryGroup } = {}
	local byName: { [string]: CategoryGroup } = {}

	local tokens = if query ~= "" then splitQueryTokens(query) else {}

	for index, binding in ipairs(bindings) do
		local hidden = preferences.hidden[binding.id] == true
		local undescribed = (binding.description == "" and preferences.descriptions[binding.id] == nil)
			and binding.compositor ~= "niri"

		if
			bindingAvailableInView(hidden, undescribed, managing, showUndescribed)
			and bindingMatches(binding, tokens)
		then
			local category = if binding.category ~= "" and binding.category ~= "General"
				then binding.category
				else tr("other")

			local group = byName[category]
			if group == nil then
				group = { name = category, bindings = {}, sourceOrder = #groups + 1, order = 0, weight = 1 }
				byName[category] = group
				table.insert(groups, group)
			end
			binding.displayIndex = index
			table.insert(group.bindings, binding)
			group.weight += 1
		end
	end

	table.sort(groups, function(a: CategoryGroup, b: CategoryGroup): boolean
		local left = categoryPriority(a.name)
		local right = categoryPriority(b.name)
		if left ~= right then
			return left < right
		end
		return a.sourceOrder < b.sourceOrder
	end)

	for index, group in ipairs(groups) do
		group.order = index
	end
	return groups
end

local function updateColumnCountCache()
	local configured = math.clamp(stl.config.getNumber("columns", 3), 1, 4)

	-- The panel width defined in plugin.toml
	local panelWidth = 1500

	-- Only drop below panelWidth if the physical monitor is narrower than the panel
	if noctalia and noctalia.focusedOutputName and noctalia.outputs then
		local focused = noctalia.focusedOutputName()
		for _, output in ipairs(noctalia.outputs()) do
			if output.name == focused or output.focused then
				local logicalMonitorWidth = output.width / math.max(output.scale or 1, 1)
				-- Avoid tiny fallback heads (< 800) overriding the real display
				if logicalMonitorWidth >= 800 then
					panelWidth = math.min(panelWidth, logicalMonitorWidth)
				end
				break
			end
		end
	end

	local responsive = if panelWidth < 760 then 1 elseif panelWidth < 1100 then 2 elseif panelWidth < 1400 then 3 else 4

	cachedColumnCount = math.min(configured, responsive)
end

local function balancedColumns(groups: { CategoryGroup }, count: number): { ColumnBucket }
	local columns: { ColumnBucket } = {}
	for index = 1, count do
		columns[index] = { groups = {}, weight = 0 }
	end
	for _, group in ipairs(groups) do
		local target = 1
		for index = 2, count do
			if columns[index].weight < columns[target].weight then
				target = index
			end
		end
		table.insert(columns[target].groups, group)
		columns[target].weight += group.weight
	end
	for _, column in ipairs(columns) do
		table.sort(column.groups, function(a: CategoryGroup, b: CategoryGroup): boolean
			return a.order < b.order
		end)
	end
	return columns
end

local function saveCustomDescription(binding: BindingEntry, value: string)
	value = trim(value)
	if value == "" or value == binding.description then
		preferences.descriptions[binding.id] = nil
	else
		preferences.descriptions[binding.id] = value
	end
	editingId = nil
	editDraft = ""
	savePreferences()
	render()
end

local function bindingRow(binding: BindingEntry, occurrence: number?): UiNode
	local bindId = binding.id or "unknown"
	local hidden = preferences.hidden[bindId] == true
	local contentOpacity = hidden and 0.45 or 1
	local pills: { UiNode } = {}

	for index, pill in ipairs(binding.modPills) do
		table.insert(pills, keyPill(pill.text, pill.bucket, "mod-" .. index))
	end
	table.insert(pills, keyPill(binding.formattedKey, binding.keyBucket, "key"))

	local description = preferences.descriptions[binding.id] or binding.displayDescription
	local identity = binding.id .. "#" .. (occurrence or 1)

	if view == "edit" and editingId == identity then
		return ui.row({ key = "edit-" .. identity, gap = 6, align = "center", paddingV = 0 }, {
			ui.row({ minWidth = 188, gap = 3, align = "center", opacity = contentOpacity }, pills),
			ui.input({
				key = "description-" .. identity,
				value = editDraft,
				placeholder = tr("edit_description"),
				focus = true,
				controlSize = "sm",
				flexGrow = 1,
				onChange = function(value: string)
					editDraft = value
				end,
				onSubmit = function(value: string)
					saveCustomDescription(binding, value)
				end,
			}),
			ui.button({
				glyph = "check",
				width = 22,
				height = 22,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				tooltip = tr("save"),
				onClick = function()
					saveCustomDescription(binding, editDraft)
				end,
			}),
			ui.button({
				glyph = "close",
				width = 22,
				height = 22,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				tooltip = tr("cancel"),
				onClick = function()
					editingId = nil
					editDraft = ""
					render()
				end,
			}),
			ui.button({
				glyph = hidden and "eye-off" or "eye",
				width = 22,
				height = 22,
				glyphSize = 13,
				variant = "ghost",
				controlSize = "sm",
				selected = hidden,
				tooltip = hidden and tr("show_binding") or tr("hide_binding"),
				onClick = function()
					preferences.hidden[binding.id] = not hidden and true or nil
					savePreferences()
					render()
				end,
			}),
		})
	end

	local labels: { UiNode } = {
		ui.label({
			text = description,
			color = colorValue("description", "text"),
			fontWeight = "bold",
			fontSize = 13,
			maxLines = 1,
		}),
	}
	if stl.config.getBool("show_actions", true) and description ~= "" and binding.action ~= "" then
		table.insert(
			labels,
			ui.label({ text = binding.action, color = "on_surface_variant", fontSize = 11, maxLines = 1 })
		)
	end

	local rowChildren: { UiNode } = {
		ui.row({ minWidth = 188, gap = 3, align = "center", opacity = contentOpacity }, pills),
		ui.column({ flexGrow = 1, gap = 0, opacity = contentOpacity }, labels),
	}

	if view == "edit" then
		table.insert(
			rowChildren,
			ui.button({
				glyph = "pencil",
				width = 22,
				height = 22,
				glyphSize = 12,
				variant = "ghost",
				controlSize = "sm",
				tooltip = tr("edit_description"),
				onClick = function()
					editingId = identity
					editDraft = description
					render()
				end,
			})
		)
		table.insert(
			rowChildren,
			ui.button({
				glyph = hidden and "eye-off" or "eye",
				width = 22,
				height = 22,
				glyphSize = 13,
				variant = "ghost",
				controlSize = "sm",
				selected = hidden,
				tooltip = hidden and tr("show_binding") or tr("hide_binding"),
				onClick = function()
					preferences.hidden[binding.id] = not hidden and true or nil
					savePreferences()
					render()
				end,
			})
		)
	end

	return ui.row({ key = identity, gap = 6, align = "center", paddingV = 0 }, rowChildren)
end

local function categoryNode(group: CategoryGroup): UiNode
	local mainSection, subSection = string.match(group.name, "^(.-)%s*•%s*(.+)$")
	local headerNodes: { UiNode } = {}

	if mainSection and subSection then
		table.insert(
			headerNodes,
			ui.row({ gap = 6, align = "center" }, {
				ui.label({
					text = string.upper(mainSection),
					color = "on_surface_variant",
					fontSize = 11,
					fontWeight = "bold",
				}),
				ui.glyph({ name = "chevron-right", size = 11, color = "on_surface_variant" }),
				ui.label({ text = subSection, color = "primary", fontSize = 13, fontWeight = "bold" }),
			})
		)
	else
		table.insert(
			headerNodes,
			ui.label({
				text = string.upper(group.name),
				color = "primary",
				fontSize = 13,
				fontWeight = "bold",
			})
		)
	end

	table.insert(headerNodes, ui.separator({ color = "outline/0.25", thickness = 1, spacing = 2 }))

	local children = headerNodes
	local occurrences: { [string]: number } = {}
	for _, binding in ipairs(group.bindings) do
		occurrences[binding.id] = (occurrences[binding.id] or 0) + 1
		table.insert(children, bindingRow(binding, occurrences[binding.id]))
	end

	return ui.column({ key = "category-" .. group.name, gap = 2, paddingV = 4, align = "stretch" }, children)
end

local function bindingsBody(): UiNode
	local groups = visibleGroups()
	if #groups == 0 then
		return ui.column({ flexGrow = 1, align = "center", justify = "center" }, {
			ui.glyph({ name = "search-off", size = 32, color = "on_surface_variant" }),
			ui.label({ text = tr("no_results"), color = "on_surface_variant" }),
		})
	end
	local columns = balancedColumns(groups, cachedColumnCount)
	local columnNodes: { UiNode } = {}
	for index, column in ipairs(columns) do
		local categoryNodes: { UiNode } = {}
		for _, group in ipairs(column.groups) do
			table.insert(categoryNodes, categoryNode(group))
		end
		table.insert(
			columnNodes,
			ui.column({ key = "column-" .. index, flexGrow = 1, gap = 8, align = "stretch" }, categoryNodes)
		)
	end
	return ui.scroll({ flexGrow = 1, gap = 0 }, {
		ui.row({ key = "binding-columns", gap = 22, align = "stretch" }, columnNodes),
	})
end

local function colorControl(bucket: ColorBucket, property: "background" | "text"): UiNode
	return ui.row({ gap = 5, align = "center", flexGrow = 1 }, {
		ui.box({
			width = 24,
			height = 24,
			radius = 5,
			fill = colorValue(bucket.id, property),
			border = "outline",
			borderWidth = 1,
		}),
		ui.button({
			text = property == "background" and tr("background") or tr("text"),
			variant = "ghost",
			controlSize = "sm",
			flexGrow = 1,
			onClick = function()
				chooseColor(bucket.id, property)
			end,
		}),
		ui.button({
			glyph = "clipboard",
			variant = "ghost",
			controlSize = "sm",
			tooltip = tr("paste"),
			onClick = function()
				pasteColor(bucket.id, property)
			end,
		}),
		ui.button({
			glyph = "restore",
			variant = "ghost",
			controlSize = "sm",
			tooltip = tr("reset"),
			onClick = function()
				local colorObj = preferences.colors[bucket.id]
				if colorObj ~= nil then
					if property == "background" then
						colorObj.background = nil
					else
						colorObj.text = nil
					end

					if colorObj.background == nil and colorObj.text == nil then
						preferences.colors[bucket.id] = nil
					end

					savePreferences()
					render()
				end
			end,
		}),
	})
end

local function appearanceBody(): UiNode
	local rows: { UiNode } = {
		ui.label({ text = tr("customize_colors"), color = "on_surface_variant" }),
	}
	for _, bucket in ipairs(COLOR_BUCKETS) do
		table.insert(
			rows,
			ui.column({ key = "color-" .. bucket.id, gap = 5, paddingV = 4 }, {
				ui.label({ text = bucket.label, fontWeight = "medium" }),
				ui.row({ gap = 12, align = "center" }, {
					colorControl(bucket, "background"),
					colorControl(bucket, "text"),
				}),
			})
		)
	end

	table.insert(rows, ui.separator({ spacing = 6 }))
	table.insert(
		rows,
		ui.row({ gap = 8, align = "center" }, {
			ui.button({
				glyph = "restore",
				text = tr("reset_colors"),
				onClick = function()
					preferences.colors = {}
					savePreferences()
					render()
				end,
			}),
		})
	)
	return ui.scroll({ flexGrow = 1, gap = 4 }, rows)
end

local function renderHeader(): UiNode
	local title = tr("title")
	if currentCompositor ~= "" then
		title = (currentCompositor == "mango" and "Mango" or (currentCompositor == "niri" and "Niri" or "Hyprland"))
			.. " Keymap"
	end

	local children: { UiNode } = {
		ui.row({ minWidth = 230, gap = 7, align = "center", flexGrow = 1 }, {
			ui.glyph({ name = "keyboard", size = 16, color = "primary" }),
			ui.label({ text = title, fontSize = 15, fontWeight = "bold", color = "on_surface" }),
		}),
	}

	if (view == "bindings" or view == "edit") and not loading and panelError == nil then
		table.insert(
			children,
			ui.input({
				key = "search-" .. searchRevision,
				value = query,
				placeholder = "Search keybinds... (/)",
				focus = (view == "bindings" and editingId == nil and searchFocused),
				controlSize = "sm",
				width = 300,
				onChange = function(value: string)
					query = value
					editingId = nil
					render()
				end,
			})
		)
		table.insert(
			children,
			ui.button({
				glyph = "x",
				width = 26,
				variant = "ghost",
				controlSize = "sm",
				enabled = query ~= "",
				tooltip = tr("clear"),
				onClick = function()
					query = ""
					searchRevision += 1
					searchFocused = true
					render()
				end,
			})
		)
	end

	if not loading or #bindings > 0 then
		table.insert(
			children,
			ui.label({
				text = tr("binding_count", { count = #bindings }),
				color = "on_surface_variant",
				fontSize = 12,
			})
		)
	end

	if view == "edit" then
		local count = hiddenBindingCount(bindings, preferences.hidden)
		table.insert(
			children,
			ui.label({
				text = tr("hidden_count", { count = count }),
				color = "on_surface_variant",
				fontSize = 12,
			})
		)
		table.insert(
			children,
			ui.button({
				glyph = "eye",
				variant = "ghost",
				controlSize = "sm",
				enabled = count > 0,
				tooltip = tr("restore_hidden"),
				onClick = function()
					restoreHiddenBindings(bindings, preferences.hidden)
					savePreferences()
					render()
				end,
			})
		)
	end

	table.insert(
		children,
		ui.button({
			glyph = "refresh",
			variant = "ghost",
			tooltip = tr("refresh"),
			enabled = true,
			onClick = function()
				refresh()
			end,
		})
	)

	table.insert(
		children,
		ui.button({
			glyph = view == "edit" and "check" or "pencil",
			variant = "ghost",
			tooltip = view == "edit" and tr("finish_editing") or tr("edit_bindings"),
			selected = view == "edit",
			onClick = function()
				view = view == "edit" and "bindings" or "edit"
				editingId = nil
				editDraft = ""
				render()
			end,
		})
	)

	table.insert(
		children,
		ui.button({
			glyph = view == "appearance" and "check" or "palette",
			variant = "ghost",
			tooltip = view == "appearance" and tr("back") or tr("appearance"),
			selected = view == "appearance",
			onClick = function()
				view = view == "appearance" and "bindings" or "appearance"
				editingId = nil
				editDraft = ""
				render()
			end,
		})
	)

	return ui.row({ align = "center", justify = "space_between", gap = 7 }, children)
end

render = function()
	if not panelOpen then
		return
	end

	local contentState = "bindings"
	if view == "appearance" then
		contentState = "appearance"
	elseif loading then
		contentState = "loading"
	elseif panelError ~= nil then
		contentState = "error"
	elseif view == "edit" then
		contentState = "edit"
	end

	local children: { UiNode } = { renderHeader() }

	if view == "appearance" then
		table.insert(children, appearanceBody())
	elseif loading then
		table.insert(
			children,
			ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 10 }, {
				ui.glyph({ name = "loader", size = 32, color = "primary" }),
				ui.label({ text = tr("loading"), color = "on_surface_variant" }),
			})
		)
	elseif panelError ~= nil then
		table.insert(
			children,
			ui.column({ flexGrow = 1, align = "center", justify = "center", gap = 10 }, {
				ui.glyph({ name = "alert-triangle", size = 32, color = "error" }),
				ui.label({ text = panelError, color = "error", textAlign = "center", maxWidth = 640 }),
			})
		)
	else
		if refreshError ~= nil then
			table.insert(children, ui.label({ text = refreshError, color = "error", fontSize = 11, maxLines = 2 }))
		end
		if #parseWarnings > 0 then
			table.insert(
				children,
				ui.label({
					text = tr("source_warning") .. " " .. table.concat(parseWarnings, " | "),
					color = "error",
					fontSize = 11,
					maxLines = 2,
				})
			)
		end
		table.insert(children, bindingsBody())
	end

	local node = ui.column({
		key = "keybind-cheatsheet-" .. contentState,
		flexGrow = 1,
		gap = 8,
		align = "stretch",
	}, children)

	panel.render(node)
end

-- Watch state snapshot updates
snapshotChannel.watch(function(value)
	applySnapshot(value)
	if panelOpen then
		render()
	end
end)

-- Register panel lifecycle hooks via STL
stl.lifecycle.panel(getfenv(), {
	onOpen = function(_context: string?)
		panelOpen = true
		view = "bindings"
		query = ""
		searchRevision += 1
		searchFocused = true
		editingId = nil
		editDraft = ""
		loadPreferences()
		updateColumnCountCache()
		applySnapshot(snapshotChannel.get())
		render()
	end,

	onClose = function()
		panelOpen = false
		view = "bindings"
		query = ""
		searchFocused = false
		editingId = nil
		editDraft = ""
	end,

	onKey = function(chord: string, pressed: boolean)
		if not pressed then
			return
		end
		if chord == "q" or chord == "Escape" then
			if query ~= "" then
				query = ""
				searchRevision += 1
				searchFocused = true
				render()
			else
				panel.close()
			end
		elseif chord == "r" and view ~= "appearance" and editingId == nil then
			refresh()
		end
	end,

	onIpc = function(event: string, _payload: string)
		if event == "toggle" then
			if panelOpen then
				panel.close()
			else
				noctalia.togglePanel(constants.PANEL_ID)
			end
		elseif event == "refresh" then
			refresh()
		elseif event == "focus-search" then
			searchFocused = true
			searchRevision += 1
			render()
		end
	end,
})

render()

return {
	render = render,
}
