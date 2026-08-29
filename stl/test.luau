--!strict
--- Comprehensive unit testing framework for Luau and Noctalia plugin runtimes.
--- Provides structured suite definitions, lifecycle hooks (beforeEach/afterEach),
--- deep assertion utilities, and safe host API mocking.
local test = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

export type TestCase = {
	name: string,
	fn: () -> (),
}

export type TestSuite = {
	name: string,
	cases: { TestCase },
	beforeEach: (() -> ())?,
	afterEach: (() -> ())?,
}

export type SuiteBuilder = {
	--- Defines an individual unit test case within this suite.
	test: (name: string, fn: () -> ()) -> (),
	--- Defines a setup function to execute before every test in this suite.
	beforeEach: (fn: () -> ()) -> (),
	--- Defines a teardown function to execute after every test in this suite.
	afterEach: (fn: () -> ()) -> (),
}

-- =============================================================================
-- Host Mock Container
-- =============================================================================

--- Mutable host environment container used to intercept calls in CLI tests.
test.host = {} :: { [string]: any }

--- Temporarily shims or mocks Noctalia host functions inside `test.host`.
--- Modules using `stl.proc` or custom parsers will resolve these shims during tests.
---
--- @param shims { [string]: any } Key-value map of functions or tables to inject.
function test.mockHost(shims: { [string]: any })
	for k, v in pairs(shims) do
		test.host[k] = v
	end
end

--- Clears all active shims from `test.host`. Automatically called between test cases.
function test.restoreHost()
	for k in pairs(test.host) do
		test.host[k] = nil
	end
end

-- =============================================================================
-- Test Registration
-- =============================================================================

local suites: { TestSuite } = {}

--- Registers a named test suite with isolated setup/teardown hooks.
---
--- @param name string Human-readable identifier for the test suite.
--- @param define (b: SuiteBuilder) -> () Callback where test cases and hooks are registered.
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

-- =============================================================================
-- Deep Comparison & Serialization Utilities
-- =============================================================================

local function deepCompare(a: any, b: any): boolean
	if typeof(a) ~= typeof(b) then
		return false
	end
	if typeof(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepCompare(v, b[k]) then
			return false
		end
	end
	for k, _ in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function safeSerialize(value: any): string
	if typeof(value) == "table" then
		local parts: { string } = {}
		for k, v in pairs(value) do
			table.insert(parts, string.format("%s: %s", tostring(k), safeSerialize(v)))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	elseif typeof(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

-- =============================================================================
-- Assertions Interface
-- =============================================================================

test.assert = {
	--- Asserts primitive value equality (`actual == expected`).
	equal = function<T>(actual: T, expected: T, msg: string?)
		if actual ~= expected then
			error(
				string.format(
					"%s: expected %s, got %s",
					msg or "Assertion failed",
					safeSerialize(expected),
					safeSerialize(actual)
				),
				2
			)
		end
	end,

	--- Asserts primitive inequality (`actual ~= expected`).
	notEqual = function<T>(actual: T, expected: T, msg: string?)
		if actual == expected then
			error(
				string.format("%s: expected value not to equal %s", msg or "Assertion failed", safeSerialize(expected)),
				2
			)
		end
	end,

	--- Recursively compares two tables or nested structures for structural equality.
	deepEqual = function(actual: any, expected: any, msg: string?)
		if not deepCompare(actual, expected) then
			local actStr = safeSerialize(actual)
			local expStr = safeSerialize(expected)
			error(
				string.format("%s:\n  expected: %s\n  got:      %s", msg or "Deep equality failed", expStr, actStr),
				2
			)
		end
	end,

	--- Asserts that an array contains a specific item matching via deep structural comparison.
	contains = function(array: { any }, item: any, msg: string?)
		for _, v in ipairs(array) do
			if deepCompare(v, item) then
				return
			end
		end
		error(
			string.format("%s: array does not contain item %s", msg or "Contains assertion failed", safeSerialize(item)),
			2
		)
	end,

	--- Asserts that a value is truthy (not `nil` and not `false`).
	truthy = function(value: any, msg: string?)
		if not value then
			error(msg or "Expected truthy value, got falsy", 2)
		end
	end,

	--- Asserts that a value is falsy (`nil` or `false`).
	falsy = function(value: any, msg: string?)
		if value then
			error(msg or string.format("Expected falsy value, got %s", safeSerialize(value)), 2)
		end
	end,

	--- Asserts that invoking `fn` raises a Luau error, optionally matching a substring.
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
}

-- =============================================================================
-- Test Runner Execution
-- =============================================================================

--- Executes all registered test suites in order, reporting pass/fail statuses and execution duration.
---
--- @return (number, number) Returns (passedCount, failedCount).
function test.run(): (number, number)
	local passed = 0
	local failed = 0
	local startTime = os.clock()

	print("========== TEST RUNNER START ==========")
	for _, suite in suites do
		print(string.format("Suite: %s", suite.name))
		for _, tc in suite.cases do
			if suite.beforeEach then
				local bOk, bErr = pcall(suite.beforeEach)
				if not bOk then
					failed += 1
					print(string.format("  [FAIL] %s (beforeEach error: %s)", tc.name, tostring(bErr)))
					test.restoreHost()
					continue
				end
			end

			local ok, err = pcall(tc.fn)
			if ok then
				passed += 1
				print(string.format("  [PASS] %s", tc.name))
			else
				failed += 1
				print(string.format("  [FAIL] %s -> %s", tc.name, tostring(err)))
			end

			if suite.afterEach then
				pcall(suite.afterEach)
			end

			test.restoreHost()
		end
	end

	local durationMs = (os.clock() - startTime) * 1000
	print(string.format("========== RESULTS: %d Passed, %d Failed (%.2f ms) ==========", passed, failed, durationMs))
	return passed, failed
end

return test
