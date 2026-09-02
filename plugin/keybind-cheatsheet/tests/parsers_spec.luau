--!strict
--- Unit tests for isolated format parsers: Common, Mango, Hyprland, Niri.

local testing = require("../../../lib/testing/testing.luau")
local types = require("../../keybind-cheatsheet/types.luau")
local common = require("../../keybind-cheatsheet/parsers/common.luau")
local mango = require("../../keybind-cheatsheet/parsers/mango.luau")
local hyprland = require("../../keybind-cheatsheet/parsers/hyprland.luau")
local niri = require("../../keybind-cheatsheet/parsers/niri.luau")

type ParseContext = types.ParseContext

local function createContext(): ParseContext
	return {
		bindings = {},
		variables = {},
		warnings = {},
		sources = {},
		exactRules = {},
		patternRules = {},
	}
end

testing.suite("Keybind Cheatsheet: Parsers", function(b)
	b.beforeEach(function()
		testing.bootstrap(28)
	end)

	b.afterEach(function()
		testing.teardown()
	end)

	-- =========================================================================
	-- Common Parser & Text Transforms
	-- =========================================================================

	b.test("normalizeModifiers parses string aliases and sorts deterministically", function()
		local mods = common.normalizeModifiers("SUPER+SHIFT+ALT+CTRL")
		testing.assert.equal(#mods, 4)
		testing.assert.equal(mods[1], "SUPER")
		testing.assert.equal(mods[2], "CTRL")
		testing.assert.equal(mods[3], "SHIFT")
		testing.assert.equal(mods[4], "ALT")

		local aliasMods = common.normalizeModifiers("MOD4+CONTROL+MOD1")
		testing.assert.equal(#aliasMods, 3)
		testing.assert.equal(aliasMods[1], "SUPER")
		testing.assert.equal(aliasMods[2], "CTRL")
		testing.assert.equal(aliasMods[3], "ALT")
	end)

	b.test("parseHeading identifies level 1 and level 2 structural sections", function()
		local h1 = common.parseHeading("-- = Applications & Launchers")
		testing.assert.truthy(h1 ~= nil)
		if h1 then
			testing.assert.equal(h1.level, 1)
			testing.assert.equal(h1.title, "Applications & Launchers")
		end

		local h2 = common.parseHeading("-- == Focus Navigation ==")
		testing.assert.truthy(h2 ~= nil)
		if h2 then
			testing.assert.equal(h2.level, 2)
			testing.assert.equal(h2.title, "Focus Navigation")
		end

		local invalid =
			common.parseHeading("-- =============================================================================")
		testing.assert.isNil(invalid)
	end)

	b.test("extractTrailingDescription separates inline comments", function()
		local line1 = 'bind = SUPER, Q, killactive # "Close active window"'
		local clean1, desc1 = common.extractTrailingDescription(line1)
		testing.assert.equal(clean1, "bind = SUPER, Q, killactive")
		testing.assert.equal(desc1, "Close active window")

		local line2 = "bind = SUPER, Return, exec, kitty"
		local clean2, desc2 = common.extractTrailingDescription(line2)
		testing.assert.equal(clean2, "bind = SUPER, Return, exec, kitty")
		testing.assert.equal(desc2, "")
	end)

	-- =========================================================================
	-- Mango Parser
	-- =========================================================================

	b.test("mango.parseContent extracts bindings and generates pre-baked display fields", function()
		local content = [[
-- = Workspace Navigation
bind = SUPER, 1, view, 1 # "Switch to Workspace 1"
bind = SUPER SHIFT, 1, tag, 1
bindm = SUPER, mouse:272, movewindow
]]
		local ctx = createContext()
		mango.parseContent(content, "/fake/mango.conf", ctx)

		testing.assert.equal(#ctx.bindings, 3)

		local b1 = ctx.bindings[1]
		testing.assert.equal(b1.compositor, "mango")
		testing.assert.equal(b1.key, "1")
		testing.assert.equal(b1.action, "view 1")
		testing.assert.equal(b1.description, "Switch to Workspace 1")
		testing.assert.equal(b1.category, "Workspace Navigation")
		testing.assert.equal(b1.formattedKey, "1")
		testing.assert.equal(b1.keyBucket, "number")
		testing.assert.equal(#b1.modPills, 1)
		testing.assert.equal(b1.modPills[1].text, "Super")
		testing.assert.equal(b1.modPills[1].bucket, "super")

		local b3 = ctx.bindings[3]
		testing.assert.equal(b3.bindingType, "bindm")
		testing.assert.equal(b3.key, "mouse:272")
		testing.assert.equal(b3.formattedKey, "Mouse 272")
		testing.assert.equal(b3.keyBucket, "mouse")
	end)

	-- =========================================================================
	-- Hyprland Conf Parser
	-- =========================================================================

	b.test("hyprland.parseConfContent extracts bindings and resolves variables", function()
		local content = [[
$mainMod = SUPER
$term = kitty

-- = Terminal
bind = $mainMod, Return, exec, $term # "Open terminal emulator"
bind = $mainMod SHIFT, Q, killactive
bindm = $mainMod, mouse:272, movewindow
]]
		local ctx = createContext()
		hyprland.parseConfContent(content, "/fake/hyprland.conf", ctx)

		testing.assert.equal(#ctx.bindings, 3)
		testing.assert.equal(ctx.variables["mainMod"], "SUPER")
		testing.assert.equal(ctx.variables["term"], "kitty")

		local b1 = ctx.bindings[1]
		testing.assert.equal(b1.compositor, "hyprland")
		testing.assert.equal(b1.key, "Return")
		testing.assert.equal(b1.formattedKey, "Enter")
		testing.assert.equal(b1.action, "exec $term")
		testing.assert.equal(b1.description, "Open terminal emulator")
		testing.assert.equal(b1.category, "Terminal")
		testing.assert.equal(b1.displayDescription, "Open terminal emulator")
		testing.assert.truthy(string.find(b1.searchIndex, "enter", 1, true) ~= nil)
	end)

	-- =========================================================================
	-- Niri Parser
	-- =========================================================================

	b.test("niri.parseContent extracts bindings from KDL blocks", function()
		local content = [[
// = Window Controls
Mod+Shift+Q { close-window; }
Mod+Return { spawn "kitty"; }
Mod+Left { focus-column-left; }
]]
		local ctx = createContext()
		niri.parseContent(content, "/fake/config.kdl", ctx)

		testing.assert.equal(#ctx.bindings, 3)
		local b1 = ctx.bindings[1]
		testing.assert.equal(b1.compositor, "niri")
		testing.assert.equal(b1.action, "close-window")
		testing.assert.equal(b1.category, "Window Controls")
		testing.assert.equal(b1.displayDescription, "Close Window")
	end)

	-- =========================================================================
	-- Hyprland JSON Decoder
	-- =========================================================================

	b.test("hyprland.parseHyprJson decodes bitmask modifiers, matches needles, and pre-bakes search indices", function()
		local rawJson = [[
        [
            {
                "modmask": 65,
                "key": "Return",
                "dispatcher": "exec",
                "arg": "kitty",
                "description": "Terminal",
                "has_description": true
            },
            {
                "modmask": 64,
                "key": "d",
                "dispatcher": "exec",
                "arg": "rofi -show drun",
                "description": "",
                "has_description": false
            },
            {
                "modmask": 64,
                "key": "1",
                "dispatcher": "workspace",
                "arg": "1",
                "description": "Move Window to Workspace 1 (Follow)",
                "has_description": true
            }
        ]
        ]]

		local scanCtx = createContext()
		scanCtx.exactRules["Terminal"] = {
			section = "Applications & Launchers",
			subsection = "",
			category = "Applications & Launchers",
		}
		table.insert(scanCtx.patternRules, {
			literalNeedles = { "Move Window to Workspace ", " (Follow)" },
			section = "Workspaces & Scratchpads",
			subsection = "Workspaces 1-10",
			category = "Workspaces & Scratchpads • Workspaces 1-10",
		})

		local result, err = hyprland.parseHyprJson(rawJson, scanCtx)
		testing.assert.isNil(err)
		testing.assert.truthy(result ~= nil)

		if result then
			testing.assert.equal(#result, 3)
			testing.assert.equal(result[1].modifiers[1], "SUPER")
			testing.assert.equal(result[1].modifiers[2], "SHIFT")
			testing.assert.equal(result[1].formattedKey, "Enter")
			testing.assert.equal(result[1].description, "Terminal")
			testing.assert.equal(result[1].category, "Applications & Launchers")
			testing.assert.equal(#result[1].modPills, 2)
			testing.assert.equal(result[1].modPills[1].text, "Super")
			testing.assert.equal(result[1].modPills[2].text, "Shift")

			-- Fallback dispatcher / keyword category assignment
			testing.assert.equal(result[2].category, "Applications & Launchers")
			testing.assert.equal(result[2].displayDescription, "Launch Rofi")

			-- Substring needle rule assignment
			testing.assert.equal(result[3].section, "Workspaces & Scratchpads")
			testing.assert.equal(result[3].subsection, "Workspaces 1-10")
			testing.assert.equal(result[3].category, "Workspaces & Scratchpads • Workspaces 1-10")
			testing.assert.truthy(string.find(result[3].searchIndex, "workspace", 1, true) ~= nil)
		end
	end)
end)

return true
