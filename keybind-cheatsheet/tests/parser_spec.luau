--!strict
-- tests/parser_spec.luau

local stl = require("../../stl/stl")
local service = require("../service")
local test = stl.test
local assert = test.assert

-- =============================================================================
-- Test Suite: Heading Hierarchy & Categories
-- =============================================================================
test.suite("Heading Hierarchy & Categories", function(t)
	t.test("parses Level 1 sections correctly", function()
		local h = service.parseHeading("# = Applications & Launchers =")
		assert.truthy(h ~= nil, "Expected L1 heading to parse")
		if h then
			assert.equal(h.level, 1, "Expected level 1")
			assert.equal(h.title, "Applications & Launchers", "Title mismatch")
		end
	end)

	t.test("parses Level 2 subsections correctly", function()
		local h = service.parseHeading("# == State Toggles ==")
		assert.truthy(h ~= nil, "Expected L2 heading to parse")
		if h then
			assert.equal(h.level, 2, "Expected level 2")
			assert.equal(h.title, "State Toggles", "Title mismatch")
		end
	end)

	t.test("handles different comment prefix styles", function()
		local hBash = service.parseHeading("# = Section One")
		local hLua = service.parseHeading("-- = Section Two")
		local hC = service.parseHeading("// = Section Three")

		assert.truthy(hBash ~= nil, "Failed to parse # heading")
		assert.truthy(hLua ~= nil, "Failed to parse -- heading")
		assert.truthy(hC ~= nil, "Failed to parse // heading")
	end)

	t.test("builds composite hierarchical category strings", function()
		local catComposite = service.buildCategory("Window Management", "State Toggles")
		assert.equal(catComposite, "Window Management • State Toggles", "Composite delimiter mismatch")

		local catPlain = service.buildCategory("General", "")
		assert.equal(catPlain, "General", "Empty subsection should return plain section")
	end)
end)

-- =============================================================================
-- Test Suite: Modifier Normalizer & Identity
-- =============================================================================
test.suite("Modifier Normalizer & Identity", function(t)
	t.test("normalizes aliased and unordered modifiers deterministically", function()
		local res1 = service.normalizeModifiers("MOD4+SHIFT+CONTROL", nil)
		assert.deepEqual(res1, { "SUPER", "CTRL", "SHIFT" }, "Failed to resolve MOD4/CONTROL aliases")

		local res2 = service.normalizeModifiers("ALT+WIN", nil)
		assert.deepEqual(res2, { "SUPER", "ALT" }, "Failed to resolve WIN alias")
	end)

	t.test("replaces configured variables in modifier chords", function()
		local vars = { ["$mainMod"] = "SUPER" }
		local res = service.normalizeModifiers("$mainMod+SHIFT", vars)
		assert.deepEqual(res, { "SUPER", "SHIFT" }, "Failed variable interpolation")
	end)

	t.test("generates deterministic binding identities", function()
		local id = service.bindingIdentity({
			compositor = "mango",
			bindingType = "bind",
			modifiers = { "SUPER", "SHIFT" },
			key = "Return",
			action = "alacritty",
			submap = "",
		})
		assert.equal(id, "mango|bind|SUPER+SHIFT|Return|alacritty|", "Identity format mismatch")
	end)
end)

-- =============================================================================
-- Test Suite: Mango Config Parser
-- =============================================================================
test.suite("Mango Parser", function(t)
	local sampleMango = [[
# = Applications & Launchers
bind = SUPER, Return, alacritty # "Launch Terminal"
bind = SUPER, E, nemo # "Launch File Manager"

# = Window Management
# == State Toggles
bind = SUPER, Q, killactive # "Close Active Window"
bind = SUPER+SHIFT, F, togglefloating # "Toggle Float"

# == Split Scaling
bind = SUPER, Semicolon, splitratio, -0.05 # "Decrease Split"
]]

	t.test("parses hierarchical categories and trailing descriptions", function()
		local ctx: service.ParseContext = {
			bindings = {},
			variables = {},
			warnings = {},
			sources = {},
			exactRules = {},
		}

		service.parseMangoContent(sampleMango, "config.conf", ctx)

		assert.equal(#ctx.bindings, 5, "Expected 5 parsed bindings")
		assert.equal(ctx.bindings[1].section, "Applications & Launchers")
		assert.equal(ctx.bindings[1].description, "Launch Terminal")
		assert.equal(ctx.bindings[3].category, "Window Management • State Toggles")
		assert.equal(ctx.bindings[3].description, "Close Active Window")
		assert.equal(ctx.bindings[5].category, "Window Management • Split Scaling")
		assert.equal(ctx.bindings[5].action, "splitratio -0.05")
	end)
end)

-- =============================================================================
-- Test Suite: Niri KDL Parser
-- =============================================================================
test.suite("Niri Parser", function(t)
	local sampleNiri = [[
// = Navigation
Mod+Left  { focus-column-left; }
Mod+Right { focus-column-right; }

// = Screen Toolkit
Mod+Shift+S { screenshot-screen; }
]]

	t.test("extracts single-line KDL chord blocks and resolves categories", function()
		local ctx: service.ParseContext = {
			bindings = {},
			variables = {},
			warnings = {},
			sources = {},
			exactRules = {},
		}

		service.parseNiriContent(sampleNiri, "config.kdl", ctx)

		assert.equal(#ctx.bindings, 3, "Expected 3 bindings")
		assert.equal(ctx.bindings[1].action, "focus-column-left")
		assert.equal(ctx.bindings[1].category, "Navigation")
		assert.equal(ctx.bindings[3].action, "screenshot-screen")
		assert.equal(ctx.bindings[3].category, "Screen Toolkit")
	end)
end)

-- =============================================================================
-- Test Suite: Hyprland Subprocess & AST Merge Pipeline (Mocked Host)
-- =============================================================================
test.suite("Hyprland Subprocess & AST Pipeline", function(t)
	local sampleLuaAST = [[
-- = Window Management
-- == State Toggles
bind({
    mods = { "SUPER" },
    key = "Q",
    action = "killactive",
    desc = "Close Active Window"
})

bind({
    mods = { "SUPER", "SHIFT" },
    key = "F",
    action = "togglefloating",
    desc = "Toggle Window Float"
})

-- = Virtualization
bind({
    mods = { "SUPER", "CTRL" },
    key = "Backslash",
    action = "submap passthrough",
    desc = "Toggle VM Passthrough"
})
]]

	local sampleHyprctlJSON = [[
[
    {
        "modmask": 64,
        "key": "Q",
        "keycode": 0,
        "dispatcher": "killactive",
        "arg": "",
        "description": "Close Active Window",
        "has_description": true,
        "mouse": false,
        "submap": ""
    },
    {
        "modmask": 65,
        "key": "F",
        "keycode": 0,
        "dispatcher": "togglefloating",
        "arg": "",
        "description": "Toggle Window Float",
        "has_description": true,
        "mouse": false,
        "submap": ""
    },
    {
        "modmask": 68,
        "key": "Backslash",
        "keycode": 0,
        "dispatcher": "submap",
        "arg": "passthrough",
        "description": "Toggle VM Passthrough",
        "has_description": true,
        "mouse": false,
        "submap": "passthrough"
    }
]
]]

	t.test("executes mock hyprctl and merges AST headings with modmask bit decoding", function()
		-- 1. Shim host APIs via test.mockHost
		test.mockHost({
			commandExists = function(cmd: string)
				return cmd == "hyprctl"
			end,
			runAsync = function(cmdOrArgv: any, cb: (res: any) -> ())
				assert.deepEqual(cmdOrArgv, { "hyprctl", "binds", "-j" }, "Subprocess arguments mismatch")
				cb({
					exitCode = 0,
					stdout = sampleHyprctlJSON,
					stderr = "",
					timedOut = false,
				})
				return true
			end,
			json = {
				decode = function(str: string)
					-- Parse raw sampleHyprctlJSON into Luau objects
					return {
						{
							modmask = 64, -- SUPER (bit 6)
							key = "Q",
							dispatcher = "killactive",
							arg = "",
							description = "Close Active Window",
							has_description = true,
							mouse = false,
							submap = "",
						},
						{
							modmask = 65, -- SUPER (bit 6) + SHIFT (bit 0)
							key = "F",
							dispatcher = "togglefloating",
							arg = "",
							description = "Toggle Window Float",
							has_description = true,
							mouse = false,
							submap = "",
						},
						{
							modmask = 68, -- SUPER (bit 6) + CTRL (bit 2)
							key = "Backslash",
							dispatcher = "submap",
							arg = "passthrough",
							description = "Toggle VM Passthrough",
							has_description = true,
							mouse = false,
							submap = "passthrough",
						},
					},
						nil
				end,
			},
			string = {
				trim = function(s: string)
					return service.trim(s)
				end,
			},
		})

		-- 2. Build AST Scan Context from the Lua config
		local scanContext: service.ParseContext = {
			bindings = {},
			variables = {},
			warnings = {},
			sources = {},
			exactRules = {},
		}
		service.scanHyprLuaContent(sampleLuaAST, scanContext)

		assert.truthy(scanContext.exactRules["Close Active Window"] ~= nil, "AST rule missing for Close Window")
		assert.equal(scanContext.exactRules["Close Active Window"].category, "Window Management • State Toggles")

		-- 3. Execute process runner via stl.proc
		local resultBindings: { service.BindingEntry }? = nil
		local procOk = stl.proc.exec({ "hyprctl", "binds", "-j" }, function(err, stdout, _code)
			assert.truthy(err == nil, "Expected process exec to succeed without error")
			local parsed, parseErr = service.parseHyprJson(stdout, scanContext)
			assert.truthy(parseErr == nil, "Failed to parse Hyprctl JSON")
			resultBindings = parsed
		end)

		assert.truthy(procOk, "Expected proc.exec to be accepted")
		assert.truthy(resultBindings ~= nil, "Expected parsed bindings result")

		local bindings = resultBindings :: { service.BindingEntry }
		assert.equal(#bindings, 3, "Expected 3 parsed bindings from JSON")

		-- Verify Entry 1: Modmask 64 (SUPER), category from AST
		assert.deepEqual(bindings[1].modifiers, { "SUPER" }, "Modifiers mismatch on entry 1")
		assert.equal(bindings[1].key, "Q")
		assert.equal(bindings[1].category, "Window Management • State Toggles")
		assert.equal(bindings[1].description, "Close Active Window")

		-- Verify Entry 2: Modmask 65 (SUPER + SHIFT)
		assert.deepEqual(bindings[2].modifiers, { "SUPER", "SHIFT" }, "Modifiers mismatch on entry 2")
		assert.equal(bindings[2].key, "F")
		assert.equal(bindings[2].category, "Window Management • State Toggles")

		-- Verify Entry 3: Modmask 68 (SUPER + CTRL) with Submap
		assert.deepEqual(bindings[3].modifiers, { "SUPER", "CTRL" }, "Modifiers mismatch on entry 3")
		assert.equal(bindings[3].key, "Backslash")
		assert.equal(bindings[3].submap, "passthrough")
		assert.equal(bindings[3].action, "submap passthrough")
	end)
end)

-- Execute all test suites
local passed, failed = test.run()
