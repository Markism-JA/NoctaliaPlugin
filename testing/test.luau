--!strict
--- Standalone unit testing framework for Noctalia plugin development and Luau runtime harnesses.
---
--- Provides structured suite definition, lifecycle hooks (`beforeEach`, `afterEach`),
--- recursive deep equality assertion with cycle and NaN handling, and formatted CLI test reporting.
---
--- ### Example:
--- ```luau
--- local test = require("./testing/test.luau")
---
--- test.suite("Math Operations", function(b)
---     local state: number
---
---     b.beforeEach(function()
---         state = 10
---     end)
---
---     b.test("adds numbers correctly", function()
---         test.assert.equal(state + 5, 15)
---     end)
---
---     b.test("handles nil checks", function()
---         local val: string? = nil
---         test.assert.isNil(val)
---     end)
--- end)
---
--- local passed, failed = test.run()
--- ```
local test = {}

local stdio = require("@lune/stdio")

-- =============================================================================
-- Terminal ANSI Styling Helpers
-- =============================================================================

local function bold(text: string): string
	return stdio.style("bold") .. text .. stdio.style("reset")
end

local function dim(text: string): string
	return stdio.style("dim") .. text .. stdio.style("reset")
end

local function green(text: string): string
	return stdio.color("green") .. text .. stdio.color("reset")
end

local function red(text: string): string
	return stdio.color("red") .. text .. stdio.color("reset")
end

local function cyan(text: string): string
	return stdio.color("cyan") .. text .. stdio.color("reset")
end

local function magenta(text: string): string
	return stdio.color("magenta") .. text .. stdio.color("reset")
end

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Represents a single executable test case within a suite.
export type TestCase = {
	--- Descriptive name of the individual test.
	name: string,
	--- Test body closure.
	fn: () -> (),
}

--- Represents a registered test suite containing test cases and optional lifecycle hooks.
export type TestSuite = {
	--- Name or category title of the test suite.
	name: string,
	--- Ordered list of test cases in this suite.
	cases: { TestCase },
	--- Hook executed immediately prior to each test case.
	beforeEach: (() -> ())?,
	--- Hook executed immediately following each test case (even on failure).
	afterEach: (() -> ())?,
}

--- DSL builder table passed to suite definition closures.
export type SuiteBuilder = {
	--- Registers a new test case into the active suite.
	---
	--- ### Example:
	--- ```luau
	--- b.test("verifies output payload", function()
	---     test.assert.truthy(true)
	--- end)
	--- ```
	---
	--- @param name string Descriptive test name.
	--- @param fn () -> () Closure containing test assertions.
	test: (name: string, fn: () -> ()) -> (),

	--- Registers a pre-test setup hook executed before every test in this suite.
	---
	--- ### Example:
	--- ```luau
	--- b.beforeEach(function()
	---     database.connect()
	--- end)
	--- ```
	---
	--- @param fn () -> () Setup logic closure.
	beforeEach: (fn: () -> ()) -> (),

	--- Registers a post-test cleanup hook executed after every test in this suite.
	---
	--- ### Example:
	--- ```luau
	--- b.afterEach(function()
	---     database.disconnect()
	--- end)
	--- ```
	---
	--- @param fn () -> () Teardown logic closure.
	afterEach: (fn: () -> ()) -> (),
}

--- Public assertion library interface.
export type Assertions = {
	--- Asserts that `value` is strictly `nil`.
	---
	--- ### Example:
	--- ```luau
	--- test.assert.isNil(result, "Expected query result to be nil")
	--- ```
	---
	--- @param value any Value to inspect.
	--- @param msg string? Optional custom failure message.
	isNil: (value: any, msg: string?) -> (),

	--- Asserts that `value` is not `nil`.
	---
	--- ### Example:
	--- ```luau
	--- test.assert.isNotNil(session, "Session should be initialized")
	--- ```
	---
	--- @param value any Value to inspect.
	--- @param msg string? Optional custom failure message.
	isNotNil: (value: any, msg: string?) -> (),

	--- Asserts that `actual` and `expected` are strictly equal (`==`).
	--- Handles numeric `NaN == NaN` as a valid equality case.
	---
	--- ### Example:
	--- ```luau
	--- test.assert.equal(response.status, 200, "Status must be OK")
	--- ```
	---
	--- @param actual T Actual resolved value.
	--- @param expected T Expected reference value.
	--- @param msg string? Optional custom failure message prefix.
	equal: <T>(actual: T, expected: T, msg: string?) -> (),

	--- Asserts that `actual` and `expected` are not equal (`~=`).
	---
	--- ### Example:
	--- ```luau
	--- test.assert.notEqual(token, "", "Token must not be empty")
	--- ```
	---
	--- @param actual T Actual resolved value.
	--- @param expected T Unexpected reference value.
	--- @param msg string? Optional custom failure message prefix.
	notEqual: <T>(actual: T, expected: T, msg: string?) -> (),

	--- Performs recursive structural comparison across arbitrary nested tables, arrays, and scalar values.
	---
	--- ### Example:
	--- ```luau
	--- test.assert.deepEqual(userProfile, { id = 1, roles = { "admin" } })
	--- ```
	---
	--- @param actual any Actual structure or value.
	--- @param expected any Expected reference structure.
	--- @param msg string? Optional custom failure message prefix.
	deepEqual: (actual: any, expected: any, msg: string?) -> (),

	--- Asserts that an array contains an item matching `item` (evaluated via recursive deep comparison).
	---
	--- ### Example:
	--- ```luau
	--- test.assert.contains({ "SUPER", "CTRL" }, "SUPER")
	--- ```
	---
	--- @param array { any } Array to inspect.
	--- @param item any Expected element inside `array`.
	--- @param msg string? Optional custom failure message prefix.
	contains: (array: { any }, item: any, msg: string?) -> (),

	--- Asserts that `value` evaluates to a truthy value (neither `nil` nor `false`).
	---
	--- ### Example:
	--- ```luau
	--- test.assert.truthy(isConnected, "Connection flag must be true")
	--- ```
	---
	--- @param value any Value to inspect.
	--- @param msg string? Optional custom failure message.
	truthy: (value: any, msg: string?) -> (),

	--- Asserts that `value` evaluates to a falsy value (`nil` or `false`).
	---
	--- ### Example:
	--- ```luau
	--- test.assert.falsy(hasError, "Error flag should not be active")
	--- ```
	---
	--- @param value any Value to inspect.
	--- @param msg string? Optional custom failure message.
	falsy: (value: any, msg: string?) -> (),

	--- Asserts that invoking `fn` raises a runtime error, optionally matching a substring.
	---
	--- ### Example:
	--- ```luau
	--- test.assert.throws(function()
	---     parseInvalidInput("")
	--- end, "unexpected EOF")
	--- ```
	---
	--- @param fn () -> () Closure expected to throw an exception.
	--- @param expectedSubstring string? Optional substring that must be present in the error message.
	--- @param msg string? Optional custom failure message prefix.
	throws: (fn: () -> (), expectedSubstring: string?, msg: string?) -> (),
}

-- =============================================================================
-- Internal Helpers
-- =============================================================================

--- Internal recursive equality comparator that tracks visited table references to prevent infinite cycles.
---
--- @param a any First value to compare.
--- @param b any Second value to compare.
--- @param visited { [any]: any } Active pointer map of visited table pairs.
--- @return boolean True if both values are structurally equivalent.
local function internalDeepCompare(a: any, b: any, visited: { [any]: any }): boolean
	if a == b then
		return true
	end

	-- Handle NaN equality (0/0 ~= 0/0 in standard IEEE 754)
	if typeof(a) == "number" and typeof(b) == "number" and a ~= a and b ~= b then
		return true
	end

	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) ~= "table" then
		return a == b
	end

	if visited[a] == b then
		return true
	end
	visited[a] = b

	local countA = 0
	for _ in pairs(a) do
		countA += 1
	end
	local countB = 0
	for _ in pairs(b) do
		countB += 1
	end
	if countA ~= countB then
		return false
	end

	for k, v in pairs(a) do
		if b[k] == nil and v ~= nil then
			return false
		end
		if not internalDeepCompare(v, b[k], visited) then
			return false
		end
	end
	return true
end

--- Recursively checks structural equality between two arbitrary values without stack overflowing on cyclic references.
---
--- @param a any First value to compare.
--- @param b any Second value to compare.
--- @return boolean True if both values are structurally identical.
local function deepCompare(a: any, b: any): boolean
	return internalDeepCompare(a, b, {})
end

--- Recursively serializes arbitrary Lua values into formatted human-readable diagnostic strings.
---
--- @param value any Value to format.
--- @param depth number Current nesting depth.
--- @param visited { [any]: boolean } Table tracking cycles.
--- @return string Formatted diagnostic representation.
local function internalSerialize(value: any, depth: number, visited: { [any]: boolean }): string
	if depth > 8 then
		return "..."
	end

	local t = typeof(value)
	if t == "table" then
		if visited[value] then
			return "<cycle>"
		end
		visited[value] = true

		local parts: { string } = {}
		for k, v in pairs(value) do
			local keyStr = if typeof(k) == "string" and string.match(k, "^[%a_][%w_]*$")
				then k
				else "[" .. internalSerialize(k, depth + 1, visited) .. "]"
			table.insert(parts, string.format("%s = %s", keyStr, internalSerialize(v, depth + 1, visited)))
		end
		visited[value] = nil
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif t == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

--- Serializes a Lua value safely for assertion error messages.
---
--- @param value any Value to serialize.
--- @return string Formatted diagnostic string.
local function safeSerialize(value: any): string
	return internalSerialize(value, 0, {})
end

-- =============================================================================
-- Assertion Library
-- =============================================================================

test.assert = {
	isNil = function(value: any, msg: string?)
		if value ~= nil then
			error(msg or string.format("Expected nil, got %s", safeSerialize(value)), 2)
		end
	end,

	isNotNil = function(value: any, msg: string?)
		if value == nil then
			error(msg or "Expected value not to be nil", 2)
		end
	end,

	equal = function<T>(actual: T, expected: T, msg: string?)
		if actual ~= expected then
			if
				typeof(actual) == "number"
				and typeof(expected) == "number"
				and actual ~= actual
				and expected ~= expected
			then
				return
			end
			error(
				string.format(
					"%s: expected %s, got %s",
					msg or "Assertion failed (equal)",
					safeSerialize(expected),
					safeSerialize(actual)
				),
				2
			)
		end
	end,

	notEqual = function<T>(actual: T, expected: T, msg: string?)
		if actual == expected then
			error(
				string.format(
					"%s: expected value not to equal %s",
					msg or "Assertion failed (notEqual)",
					safeSerialize(expected)
				),
				2
			)
		end
	end,

	deepEqual = function(actual: any, expected: any, msg: string?)
		if not deepCompare(actual, expected) then
			error(
				string.format(
					"%s:\n  expected: %s\n  got:      %s",
					msg or "Assertion failed (deepEqual)",
					safeSerialize(expected),
					safeSerialize(actual)
				),
				2
			)
		end
	end,

	contains = function(array: { any }, item: any, msg: string?)
		for _, v in ipairs(array) do
			if deepCompare(v, item) then
				return
			end
		end
		error(
			string.format(
				"%s: array does not contain item %s",
				msg or "Assertion failed (contains)",
				safeSerialize(item)
			),
			2
		)
	end,

	truthy = function(value: any, msg: string?)
		if not value then
			error(msg or string.format("Expected truthy value, got %s", safeSerialize(value)), 2)
		end
	end,

	falsy = function(value: any, msg: string?)
		if value then
			error(msg or string.format("Expected falsy value, got %s", safeSerialize(value)), 2)
		end
	end,

	throws = function(fn: () -> (), expectedSubstring: string?, msg: string?)
		local ok, err = pcall(fn)
		if ok then
			error(msg or "Expected function to throw an error, but it succeeded", 2)
		end
		if expectedSubstring and not string.find(tostring(err), expectedSubstring, 1, true) then
			error(
				string.format(
					"%s: expected error containing '%s', got '%s'",
					msg or "Error mismatch",
					expectedSubstring,
					tostring(err)
				),
				2
			)
		end
	end,
} :: Assertions

-- =============================================================================
-- Suite Registration & Execution API
-- =============================================================================

--- Internal list of registered test suites awaiting execution.
local suites: { TestSuite } = {}

--- Registers a new test suite and its test cases into the runner.
---
--- ### Example:
--- ```luau
--- test.suite("Keybind Parser Suite", function(b)
---     b.beforeEach(function()
---         resetState()
---     end)
---
---     b.test("parses single key chord", function()
---         local result = parse("SUPER, Q")
---         test.assert.equal(result.key, "Q")
---     end)
--- end)
--- ```
---
--- @param name string Descriptive title of the suite.
--- @param define (b: SuiteBuilder) -> () Callback receiving the DSL builder.
function test.suite(name: string, define: (b: SuiteBuilder) -> ())
	local cases: { TestCase } = {}
	local hooks: { beforeEach: (() -> ())?, afterEach: (() -> ())? } = {}

	define({
		test = function(testName: string, fn: () -> ())
			table.insert(cases, { name = testName, fn = fn })
		end,
		beforeEach = function(fn: () -> ())
			hooks.beforeEach = fn
		end,
		afterEach = function(fn: () -> ())
			hooks.afterEach = fn
		end,
	})

	table.insert(suites, {
		name = name,
		cases = cases,
		beforeEach = hooks.beforeEach,
		afterEach = hooks.afterEach,
	})
end

--- Purges all currently queued test suites from memory.
function test.clearSuites()
	table.clear(suites)
end

--- Executes all registered test suites sequentially, printing formatted results to standard output.
---
--- ### Example:
--- ```luau
--- local passed, failed = test.run()
--- if failed > 0 then
---     process.exit(1)
--- end
--- ```
---
--- @return (number, number) Returns a `(passedCount, failedCount)` tuple.
function test.run(): (number, number)
	local passed = 0
	local failed = 0
	local startTime = os.clock()

	print(cyan("\n============================================================"))
	print(bold(cyan(" NOCTALIA TEST RUNNER")))
	print(cyan("============================================================"))

	for _, suite in ipairs(suites) do
		print(string.format("\n%s %s", bold(magenta("[Suite]")), bold(suite.name)))
		for _, tc in ipairs(suite.cases) do
			local testFailed = false
			local failureReason = ""

			if suite.beforeEach then
				local bOk, bErr = pcall(suite.beforeEach)
				if not bOk then
					testFailed = true
					failureReason = string.format("beforeEach failed: %s", tostring(bErr))
				end
			end

			if not testFailed then
				local ok, err = pcall(tc.fn)
				if not ok then
					testFailed = true
					failureReason = tostring(err)
				end
			end

			if suite.afterEach then
				local aOk, aErr = pcall(suite.afterEach)
				if not aOk and not testFailed then
					testFailed = true
					failureReason = string.format("afterEach failed: %s", tostring(aErr))
				end
			end

			if testFailed then
				failed += 1
				print(
					string.format("  %s %s\n    └─ %s", bold(red("✗ [FAIL]")), bold(tc.name), red(failureReason))
				)
			else
				passed += 1
				print(string.format("  %s %s", bold(green("✓ [PASS]")), dim(tc.name)))
			end
		end
	end

	local durationMs = (os.clock() - startTime) * 1000
	print(dim("\n------------------------------------------------------------"))
	if failed == 0 then
		print(bold(green(string.format(" RESULTS: %d Passed, %d Failed (%.2f ms)", passed, failed, durationMs))))
	else
		print(bold(red(string.format(" RESULTS: %d Passed, %d Failed (%.2f ms)", passed, failed, durationMs))))
	end
	print(cyan("============================================================\n"))

	return passed, failed
end

return test
