--!strict
--- Headless UI tree generator and surface controller mocks for Noctalia.

export type MockUiNode = {
	kind: string,
	props: { [string]: any },
	children: { MockUiNode }?,
}

export type MockPanel = {
	render: (tree: MockUiNode) -> (),
	close: () -> (),
	openContextMenu: (req: any) -> boolean,
	setWantsSecondTicks: (bool: boolean) -> (),
	setNeedsFrameTick: (bool: boolean) -> (),

	-- Test inspection spies
	wasClosed: boolean,
	lastRendered: MockUiNode?,
	lastContextMenu: any?,
	wantsSecondTicks: boolean,
	needsFrameTick: boolean,
	reset: () -> (),
}

export type MockBarWidget = {
	setText: (text: string) -> (),
	setGlyph: (glyph: string) -> (),
	setImage: (path: string) -> (),
	setTooltip: (tip: string) -> (),
	clearTooltip: () -> (),
	setFont: (family: string, baseline: string?) -> (),
	setColor: (color: string) -> (),
	setGlyphColor: (color: string) -> (),
	setVisible: (visible: boolean) -> (),
	isVertical: () -> boolean,
	outputName: () -> string?,
	render: (tree: MockUiNode) -> (),

	-- Test inspection spies
	text: string,
	glyph: string,
	image: string,
	tooltip: string?,
	color: string?,
	glyphColor: string?,
	visible: boolean,
	vertical: boolean,
	lastRendered: MockUiNode?,
	reset: () -> (),
}

export type MockDesktopWidget = {
	render: (tree: MockUiNode) -> (),
	setWantsSecondTicks: (bool: boolean) -> (),
	setNeedsFrameTick: (bool: boolean) -> (),

	-- Test inspection spies
	lastRendered: MockUiNode?,
	wantsSecondTicks: boolean,
	needsFrameTick: boolean,
	reset: () -> (),
}

export type MockShortcut = {
	setLabel: (text: string) -> (),
	setIcon: (on: string, off: string?) -> (),
	setActive: (bool: boolean) -> (),
	setEnabled: (bool: boolean) -> (),

	-- Test inspection spies
	label: string,
	iconOn: string,
	iconOff: string?,
	active: boolean,
	enabled: boolean,
	reset: () -> (),
}

export type MockLauncher = {
	setResults: (query: string, results: { any }) -> (),
	setQuery: (query: string) -> (),

	-- Test inspection spies
	query: string,
	results: { any },
	reset: () -> (),
}

local mockUi = {}

-- =============================================================================
-- Declarative Virtual UI Constructors (ui.*)
-- =============================================================================

function mockUi.createUi(): typeof(ui)
	local function makeNode(kind: string)
		return function(props: any, children: any): MockUiNode
			return {
				kind = kind,
				props = props or {},
				children = children or {},
			}
		end
	end

	local uiTable = {
		column = makeNode("column"),
		row = makeNode("row"),
		scroll = makeNode("scroll"),
		box = makeNode("box"),
		label = makeNode("label"),
		markdown = makeNode("markdown"),
		glyph = makeNode("glyph"),
		image = makeNode("image"),
		separator = makeNode("separator"),
		spacer = makeNode("spacer"),
		progress = makeNode("progress"),
		button = makeNode("button"),
		graph = makeNode("graph"),
		toggle = makeNode("toggle"),
		slider = makeNode("slider"),
		select = makeNode("select"),
		input = makeNode("input"),
		dragSource = makeNode("dragSource"),
		dropZone = makeNode("dropZone"),
	}

	return (uiTable :: any) :: typeof(ui)
end

-- =============================================================================
-- Imperative Surface Controllers
-- =============================================================================

function mockUi.createPanel(): MockPanel
	local self: MockPanel
	self = {
		wasClosed = false,
		lastRendered = nil :: MockUiNode?,
		lastContextMenu = nil :: any?,
		wantsSecondTicks = false,
		needsFrameTick = false,

		render = function(tree: MockUiNode)
			self.lastRendered = tree
		end,
		close = function()
			self.wasClosed = true
		end,
		openContextMenu = function(req: any): boolean
			self.lastContextMenu = req
			return true
		end,
		setWantsSecondTicks = function(bool: boolean)
			self.wantsSecondTicks = bool
		end,
		setNeedsFrameTick = function(bool: boolean)
			self.needsFrameTick = bool
		end,
		reset = function()
			self.wasClosed = false
			self.lastRendered = nil
			self.lastContextMenu = nil
			self.wantsSecondTicks = false
			self.needsFrameTick = false
		end,
	}
	return self
end

function mockUi.createBarWidget(): MockBarWidget
	local self: MockBarWidget
	self = {
		text = "",
		glyph = "",
		image = "",
		tooltip = nil :: string?,
		color = nil :: string?,
		glyphColor = nil :: string?,
		visible = true,
		vertical = false,
		lastRendered = nil :: MockUiNode?,

		setText = function(text: string)
			self.text = text
		end,
		setGlyph = function(glyph: string)
			self.glyph = glyph
		end,
		setImage = function(path: string)
			self.image = path
		end,
		setTooltip = function(tip: string)
			self.tooltip = tip
		end,
		clearTooltip = function()
			self.tooltip = nil
		end,
		setFont = function(_family: string, _baseline: string?) end,
		setColor = function(color: string)
			self.color = color
		end,
		setGlyphColor = function(color: string)
			self.glyphColor = color
		end,
		setVisible = function(visible: boolean)
			self.visible = visible
		end,
		isVertical = function(): boolean
			return self.vertical
		end,
		outputName = function(): string?
			return "DP-1"
		end,
		render = function(tree: MockUiNode)
			self.lastRendered = tree
		end,

		reset = function()
			self.text = ""
			self.glyph = ""
			self.image = ""
			self.tooltip = nil
			self.color = nil
			self.glyphColor = nil
			self.visible = true
			self.vertical = false
			self.lastRendered = nil
		end,
	}
	return self
end

function mockUi.createDesktopWidget(): MockDesktopWidget
	local self: MockDesktopWidget
	self = {
		lastRendered = nil :: MockUiNode?,
		wantsSecondTicks = false,
		needsFrameTick = false,

		render = function(tree: MockUiNode)
			self.lastRendered = tree
		end,
		setWantsSecondTicks = function(bool: boolean)
			self.wantsSecondTicks = bool
		end,
		setNeedsFrameTick = function(bool: boolean)
			self.needsFrameTick = bool
		end,
		reset = function()
			self.lastRendered = nil
			self.wantsSecondTicks = false
			self.needsFrameTick = false
		end,
	}
	return self
end

function mockUi.createShortcut(): MockShortcut
	local self: MockShortcut
	self = {
		label = "",
		iconOn = "",
		iconOff = nil :: string?,
		active = false,
		enabled = true,

		setLabel = function(text: string)
			self.label = text
		end,
		setIcon = function(on: string, off: string?)
			self.iconOn = on
			self.iconOff = off
		end,
		setActive = function(bool: boolean)
			self.active = bool
		end,
		setEnabled = function(bool: boolean)
			self.enabled = bool
		end,
		reset = function()
			self.label = ""
			self.iconOn = ""
			self.iconOff = nil
			self.active = false
			self.enabled = true
		end,
	}
	return self
end

function mockUi.createLauncher(): MockLauncher
	local self: MockLauncher
	self = {
		query = "",
		results = {},

		setResults = function(query: string, results: { any })
			self.query = query
			self.results = results
		end,
		setQuery = function(query: string)
			self.query = query
		end,
		reset = function()
			self.query = ""
			table.clear(self.results)
		end,
	}
	return self
end

return mockUi
