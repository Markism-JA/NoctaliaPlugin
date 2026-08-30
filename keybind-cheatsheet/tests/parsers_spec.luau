--!strict
--- Unit tests for format parsers: Mango, Hyprland, Niri, and hyprctl JSON.

local testing = require("../../testing/testing.luau")
local service = require("../service.luau")

testing.suite("Keybind Service Parsers", function(b)
	-- =========================================================================
	-- Modifier & Pure Utilities
	-- =========================================================================

	b.test("normalizeModifiers parses string aliases and sorts deterministically", function()
		local mods = service.normalizeModifiers("SUPER+SHIFT+ALT+CTRL")
		testing.assert.equal(#mods, 4)
		testing.assert.equal(mods[1], "SUPER")
		testing.assert.equal(mods[2], "CTRL")
		testing.assert.equal(mods[3], "SHIFT")
		testing.assert.equal(mods[4], "ALT")

		local aliasMods = service.normalizeModifiers("MOD4+CONTROL+MOD1")
		testing.assert.equal(#aliasMods, 3)
		testing.assert.equal(aliasMods[1], "SUPER")
		testing.assert.equal(aliasMods[2], "CTRL")
		testing.assert.equal(aliasMods[3], "ALT")
	end)

	b.test("parseHeading identifies level 1 and level 2 structural sections", function()
		-- Typst Level 1 (-- = Section Title)
		local h1 = service.parseHeading("-- = Applications & Launchers")
		testing.assert.truthy(h1 ~= nil)
		if h1 then
			testing.assert.equal(h1.level, 1)
			testing.assert.equal(h1.title, "Applications & Launchers")
		end

		-- Typst Level 2 (-- == Subsection Title)
		local h2 = service.parseHeading("-- == Focus Navigation ==")
		testing.assert.truthy(h2 ~= nil)
		if h2 then
			testing.assert.equal(h2.level, 2)
			testing.assert.equal(h2.title, "Focus Navigation")
		end

		-- Invalid comments / pure decorative dividers
		local invalid =
			service.parseHeading("-- =============================================================================")
		testing.assert.isNil(invalid)
	end)

	b.test("extractTrailingDescription separates inline comments", function()
		local line1 = 'bind = SUPER, Q, killactive # "Close active window"'
		local clean1, desc1 = service.extractTrailingDescription(line1)
		testing.assert.equal(clean1, "bind = SUPER, Q, killactive")
		testing.assert.equal(desc1, "Close active window")

		local line2 = "bind = SUPER, Return, exec, kitty"
		local clean2, desc2 = service.extractTrailingDescription(line2)
		testing.assert.equal(clean2, "bind = SUPER, Return, exec, kitty")
		testing.assert.equal(desc2, "")
	end)

	-- =========================================================================
	-- Mango Conf Parser
	-- =========================================================================

	b.test("parseMangoContent extracts bindings and sections correctly", function()
		local content = [[
-- = Workspace Navigation
bind = SUPER, 1, view, 1 # "Switch to Workspace 1"
bind = SUPER SHIFT, 1, tag, 1
bindm = SUPER, mouse:272, movewindow
]]
		local ctx: service.ParseContext = {
			bindings = {},
			variables = {},
			warnings = {},
			sources = {},
			exactRules = {},
			patternRules = {},
		}

		service.parseMangoContent(content, "/fake/mango.conf", ctx)

		testing.assert.equal(#ctx.bindings, 3)

		local b1 = ctx.bindings[1]
		testing.assert.equal(b1.compositor, "mango")
		testing.assert.equal(b1.key, "1")
		testing.assert.equal(b1.action, "view 1")
		testing.assert.equal(b1.description, "Switch to Workspace 1")
		testing.assert.equal(b1.category, "Workspace Navigation")

		local b3 = ctx.bindings[3]
		testing.assert.equal(b3.bindingType, "bindm")
		testing.assert.equal(b3.key, "mouse:272")
	end)

	-- =========================================================================
	-- Hyprland Conf Parser
	-- =========================================================================

	b.test("parseHyprContent extracts bindings and variable substitutions", function()
		local content = [[
$mainMod = SUPER
$term = kitty

-- = Terminal
bind = $mainMod, Return, exec, $term # "Open terminal emulator"
bind = $mainMod SHIFT, Q, killactive
bindm = $mainMod, mouse:272, movewindow
]]
		local ctx: service.ParseContext = {
			bindings = {},
			variables = {},
			warnings = {},
			sources = {},
			exactRules = {},
			patternRules = {},
		}

		service.parseHyprContent(content, "/fake/hyprland.conf", ctx)

		testing.assert.equal(#ctx.bindings, 3)
		testing.assert.equal(ctx.variables["mainMod"], "SUPER")
		testing.assert.equal(ctx.variables["term"], "kitty")

		local b1 = ctx.bindings[1]
		testing.assert.equal(b1.compositor, "hyprland")
		testing.assert.equal(b1.key, "Return")
		testing.assert.equal(b1.action, "exec $term")
		testing.assert.equal(b1.description, "Open terminal emulator")
		testing.assert.equal(b1.category, "Terminal")
	end)

	-- =========================================================================
	-- Niri KDL Parser
	-- =========================================================================

	b.test("parseNiriContent extracts bindings from KDL blocks", function()
		local content = [[
// = Window Controls
Mod+Shift+Q { close-window; }
Mod+Return { spawn "kitty"; }
Mod+Left { focus-column-left; }
]]
		local ctx: service.ParseContext = {
			bindings = {},
			variables = {},
			warnings = {},
			sources = {},
			exactRules = {},
			patternRules = {},
		}

		service.parseNiriContent(content, "/fake/config.kdl", ctx)

		testing.assert.equal(#ctx.bindings, 3)
		local b1 = ctx.bindings[1]
		testing.assert.equal(b1.compositor, "niri")
		testing.assert.equal(b1.action, "close-window")
		testing.assert.equal(b1.category, "Window Controls")
	end)

	-- =========================================================================
	-- Hyprland JSON Decoder & Template Patterns Parser
	-- =========================================================================

	b.test("parseHyprJson decodes bitmask modifiers and assigns categories", function()
		service.__setJsonDecoder(function(_raw)
			return {
				{
					modmask = 65, -- SUPER (64) + SHIFT (1)
					key = "Return",
					dispatcher = "exec",
					arg = "kitty",
					description = "Terminal",
					has_description = true,
				},
				{
					modmask = 64,
					key = "d",
					dispatcher = "exec",
					arg = "rofi -show drun",
					description = "",
					has_description = false,
				},
				{
					modmask = 64,
					key = "1",
					dispatcher = "workspace",
					arg = "1",
					description = "Move Window to Workspace 1 (Follow)",
					has_description = true,
				},
			},
				nil
		end)

		-- Provide a dynamic pattern rule simulating a loop-generated binding description
		local scanCtx: service.ParseContext = {
			bindings = {},
			variables = {},
			warnings = {},
			sources = {},
			exactRules = {
				["Terminal"] = {
					section = "Applications & Launchers",
					subsection = "",
					category = "Applications & Launchers",
				},
			},
			patternRules = {
				{
					pattern = "^Move Window to Workspace .- %(Follow%)$",
					section = "Workspaces & Scratchpads",
					subsection = "Workspaces 1-10",
					category = "Workspaces & Scratchpads • Workspaces 1-10",
				},
			},
		}

		local result, err = service.parseHyprJson("[]", scanCtx)
		testing.assert.isNil(err)
		testing.assert.truthy(result ~= nil)

		if result then
			testing.assert.equal(#result, 3)

			-- 1. Exact rule matching
			testing.assert.equal(result[1].modifiers[1], "SUPER")
			testing.assert.equal(result[1].modifiers[2], "SHIFT")
			testing.assert.equal(result[1].description, "Terminal")
			testing.assert.equal(result[1].category, "Applications & Launchers")

			-- 2. Heuristic fallback matching
			testing.assert.equal(result[2].category, "Applications & Launchers")

			-- 3. Dynamic template pattern matching
			testing.assert.equal(result[3].section, "Workspaces & Scratchpads")
			testing.assert.equal(result[3].subsection, "Workspaces 1-10")
			testing.assert.equal(result[3].category, "Workspaces & Scratchpads • Workspaces 1-10")
		end

		service.__setJsonDecoder(nil)
	end)
end)

return true
