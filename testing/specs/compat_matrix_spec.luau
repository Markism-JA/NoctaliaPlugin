--!strict
--- Test specification verifying runtime API feature-gating, capability matrix mapping,
--- safe calls, and versioned fallbacks across Noctalia API tiers (3 to 28).

local testing = require("../testing.luau")
local compat = require("../../stl/compat.luau")
local apiMatrix = require("../../stl/api_matrix.luau")

testing.suite("STL - Compatibility Matrix & Runtime Gating", function(b)
	local mockHost: testing.MockHost

	b.beforeEach(function()
		mockHost = testing.createMockHost()
		compat.__setHost(mockHost :: any)
	end)

	b.afterEach(function()
		compat.__setHost(nil)
	end)

	-- =========================================================================
	-- 1. Static Matrix Schema & Consistency
	-- =========================================================================

	b.test("validates matrix bounds and entry metadata completeness", function()
		testing.assert.equal(apiMatrix.MIN_SUPPORTED_LEVEL, 3)
		testing.assert.equal(apiMatrix.MAX_SUPPORTED_LEVEL, 28)

		for level = apiMatrix.MIN_SUPPORTED_LEVEL, apiMatrix.MAX_SUPPORTED_LEVEL do
			local entry = apiMatrix.ENTRIES[level]
			testing.assert.truthy(entry ~= nil, string.format("Missing API entry for level %d", level))
			testing.assert.equal(entry.level, level)
			testing.assert.truthy(typeof(entry.feature) == "string" and #entry.feature > 0)
			testing.assert.truthy(typeof(entry.description) == "string" and #entry.description > 0)
			testing.assert.truthy(typeof(entry.noctaliaVersion) == "string" and #entry.noctaliaVersion > 0)
		end
	end)

	b.test("verifies BY_FEATURE reverse lookup mapping", function()
		local getSettingEntry = apiMatrix.BY_FEATURE["get_setting"]
		testing.assert.truthy(getSettingEntry ~= nil)
		testing.assert.equal(getSettingEntry.level, 26)
		testing.assert.equal(getSettingEntry.noctaliaVersion, "v5.0.0-beta.9")

		local soundEntry = apiMatrix.BY_FEATURE["sound"]
		testing.assert.truthy(soundEntry ~= nil)
		testing.assert.equal(soundEntry.level, 20)

		local statsEntry = apiMatrix.BY_FEATURE["system_stats"]
		testing.assert.truthy(statsEntry ~= nil)
		testing.assert.equal(statsEntry.level, 12)
	end)

	-- =========================================================================
	-- 2. Dynamic Feature Gating & Version Checks
	-- =========================================================================

	b.test("reports active host API level via getApiLevel", function()
		mockHost.setApiLevel(24)
		testing.assert.equal(compat.getApiLevel(), 24)

		mockHost.setApiLevel(15)
		testing.assert.equal(compat.getApiLevel(), 15)
	end)

	b.test("evaluates compat.supports across cumulative API levels", function()
		-- Simulate an API 19 host (v5.0.0-beta.7)
		mockHost.setApiLevel(19)

		-- Supported in API 19 and below
		testing.assert.truthy(compat.supports("base_api")) -- Level 3
		testing.assert.truthy(compat.supports("http_stream")) -- Level 4
		testing.assert.truthy(compat.supports("system_stats")) -- Level 12
		testing.assert.truthy(compat.supports("timezone_time_format")) -- Level 19

		-- Unsupported in API 19 (Introduced in later releases)
		testing.assert.falsy(compat.supports("sound")) -- Level 20
		testing.assert.falsy(compat.supports("read_file_async")) -- Level 23
		testing.assert.falsy(compat.supports("argv_execution")) -- Level 24
		testing.assert.falsy(compat.supports("get_setting")) -- Level 26
		testing.assert.falsy(compat.supports("context_menu")) -- Level 28
	end)

	b.test("evaluates compat.requireApi and compat.requireFeature", function()
		mockHost.setApiLevel(26)

		testing.assert.truthy(compat.requireApi(26))
		testing.assert.truthy(compat.requireFeature("get_setting"))
		testing.assert.truthy(compat.requireFeature("wallpaper_mask"))

		-- Requires API 28
		testing.assert.falsy(compat.requireApi(28))
		testing.assert.falsy(compat.requireFeature("context_menu"))
	end)

	-- =========================================================================
	-- 3. Dynamic Property Reflection (compat.has)
	-- =========================================================================

	b.test("checks property existence on host root and nested tables", function()
		testing.assert.truthy(compat.has("commandExists"))
		testing.assert.truthy(compat.has("state.get"))
		testing.assert.truthy(compat.has("state.set"))
		testing.assert.truthy(compat.has("json.decode"))

		testing.assert.falsy(compat.has("nonExistentGlobal"))
		testing.assert.falsy(compat.has("state.nonExistentMethod"))
		testing.assert.falsy(compat.has("deeply.nested.invalid.path"))
	end)

	b.test("reflects dynamic method availability when mock API level changes", function()
		mockHost.setApiLevel(26)
		testing.assert.truthy(compat.has("getSetting"))
		testing.assert.truthy(compat.has("sound.play"))

		mockHost.setApiLevel(15)
		testing.assert.falsy(compat.has("getSetting"))
		testing.assert.falsy(compat.has("sound.play"))
	end)

	-- =========================================================================
	-- 4. Protected Execution & Fallbacks
	-- =========================================================================

	b.test("safeCall executes successfully and passes return values", function()
		local ok, sum, diff = compat.safeCall("mathOp", function(a: number, b: number)
			return a + b, a - b
		end, 10, 4)

		testing.assert.truthy(ok)
		testing.assert.equal(sum, 14)
		testing.assert.equal(diff, 6)
	end)

	b.test("safeCall catches thrown exceptions without propagating", function()
		local ok, err = compat.safeCall("crashTest", function()
			error("simulated runtime crash")
		end)

		testing.assert.falsy(ok)
		testing.assert.truthy(string.find(tostring(err), "simulated runtime crash") ~= nil)
	end)

	b.test("withFallback returns primary result on success", function()
		local res = compat.withFallback(function()
			return "primary_success"
		end, function()
			return "fallback_triggered"
		end)

		testing.assert.equal(res, "primary_success")
	end)

	b.test("withFallback routes to fallback closure on error or nil return", function()
		local res = compat.withFallback(function(): string
			error("Missing capability")
		end, function(): string
			return "fallback_triggered"
		end)

		testing.assert.equal(res, "fallback_triggered")
	end)
end)

return true
