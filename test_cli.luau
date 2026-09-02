--!strict
--- Hermetic Test Runner & CLI Tool for Noctalia Plugin Development.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")

local nativeRequire = require
local moduleCache: { [string]: any } = {}

-- =============================================================================
-- Terminal ANSI Styling Helpers
-- =============================================================================

local function colorize(style: string, color: string, text: string): string
	return stdio.style(style :: any)
		.. stdio.color(color :: any)
		.. text
		.. stdio.style("reset")
		.. stdio.color("reset")
end

local function bold(text: string): string
	return stdio.style("bold") .. text .. stdio.style("reset")
end

local function dim(text: string): string
	return stdio.style("dim") .. text .. stdio.style("reset")
end

local function red(text: string): string
	return stdio.color("red") .. text .. stdio.color("reset")
end

local function yellow(text: string): string
	return stdio.color("yellow") .. text .. stdio.color("reset")
end

local function cyan(text: string): string
	return stdio.color("cyan") .. text .. stdio.color("reset")
end
local function green(text: string): string
	return stdio.color("green") .. text .. stdio.color("reset")
end

local function printHeader(title: string)
	print("\n" .. colorize("bold", "purple", "━━━ ") .. bold(title) .. colorize("bold", "purple", " ━━━"))
end

local function fatal(msg: string, details: string?)
	print("\n" .. colorize("bold", "red", " FATAL ") .. " " .. msg)
	if details then
		print(dim(details))
	end
	process.exit(1)
end

-- Export cache clearing helper for test isolation
local function clearModuleCache(prefix: string?)
	if prefix == nil then
		table.clear(moduleCache)
	else
		for path in pairs(moduleCache) do
			if string.find(path, prefix, 1, true) then
				moduleCache[path] = nil
			end
		end
	end
end

-- Expose cache invalidator globally for specs needing fresh evaluation
(_G :: any).__clearModuleCache = clearModuleCache

-- =============================================================================
-- CLI Option Flags & Parsing
-- =============================================================================

export type CliConfig = {
	targets: { string },
	filter: string?,
	quiet: boolean,
	failFast: boolean,
	help: boolean,
}

local function parseCliArgs(args: { string }): CliConfig
	local config: CliConfig = {
		targets = {},
		filter = nil,
		quiet = false,
		failFast = false,
		help = false,
	}

	local i = 1
	while i <= #args do
		local arg = args[i]
		if arg == "-q" or arg == "--quiet" then
			config.quiet = true
		elseif arg == "-x" or arg == "--fail-fast" then
			config.failFast = true
		elseif arg == "-h" or arg == "--help" then
			config.help = true
		elseif arg == "-f" or arg == "--filter" then
			i += 1
			config.filter = args[i]
		elseif string.match(arg, "^%-%-filter=(.+)") then
			config.filter = string.match(arg, "^%-%-filter=(.+)")
		elseif string.sub(arg, 1, 1) ~= "-" then
			table.insert(config.targets, arg)
		end
		i += 1
	end

	return config
end

local function printHelp()
	print(
		string.format(
			[[
%s

%s
  lune run test_cli [options] [path ...]

%s
  %s                    Optional spec file(s), directory, or partial name filter.
                        Defaults to traversing the entire repository for '*_spec.luau'.

%s
  %s, %s   Filter test suites and test cases by name.
  %s, %s            Silence non-test logging (stdout error traces).
  %s, %s        Abort execution on the first encountered test failure.
  %s, %s           Show this help dialog.
]],
			bold(cyan("Noctalia CLI Test Runner")),
			bold("Usage:"),
			bold("Arguments:"),
			magenta("path"),
			bold("Options:"),
			yellow("-f"),
			yellow("--filter <str>"),
			yellow("-q"),
			yellow("--quiet"),
			yellow("-x"),
			yellow("--fail-fast"),
			yellow("-h"),
			yellow("--help")
		)
	)
end

-- =============================================================================
-- Path Canonicalization & Spec Discovery
-- =============================================================================

local IGNORED_DIRECTORIES: { [string]: boolean } = {
	[".git"] = true,
	[".luau"] = true,
	[".github"] = true,
	["node_modules"] = true,
	["dist"] = true,
	["build"] = true,
	["types"] = true,
}

local function resolvePath(baseDir: string, relativePath: string): string
	local fullPath = if baseDir == "" or baseDir == "." then relativePath else baseDir .. "/" .. relativePath
	local parts: { string } = {}

	for segment in string.gmatch(fullPath, "[^/]+") do
		if segment == ".." then
			if #parts > 0 and parts[#parts] ~= ".." then
				table.remove(parts)
			else
				table.insert(parts, "..")
			end
		elseif segment ~= "." then
			table.insert(parts, segment)
		end
	end
	return table.concat(parts, "/")
end

local function getDirName(filePath: string): string
	local dir = string.match(filePath, "^(.*)/[^/]+$")
	return dir or "."
end

--- Recursively scans any directory, ignoring dependency and metadata subtrees.
local function discoverSpecs(rootDir: string): { string }
	local specs: { string } = {}

	local function walk(currentDir: string)
		if not fs.isDir(currentDir) then
			return
		end

		local entries = fs.readDir(currentDir) :: { string }
		for _, entry: string in ipairs(entries) do
			if not IGNORED_DIRECTORIES[entry] and not string.match(entry, "^%.") then
				local fullPath = if currentDir == "." then entry else currentDir .. "/" .. entry

				if fs.isDir(fullPath) then
					walk(fullPath)
				elseif fs.isFile(fullPath) and string.match(entry, "_spec%.luau$") then
					table.insert(specs, fullPath)
				end
			end
		end
	end

	walk(rootDir)
	table.sort(specs)
	return specs
end

--- Matches user-supplied CLI targets against files, directories, or partial substrings.
local function resolveTargets(targets: { string }, allSpecs: { string }): { string }
	if #targets == 0 then
		return allSpecs
	end

	local matchedSpecs: { string } = {}
	local seen: { [string]: boolean } = {}

	local function addMatch(path: string)
		if not seen[path] then
			seen[path] = true
			table.insert(matchedSpecs, path)
		end
	end

	for _, target in ipairs(targets) do
		local directPath = resolvePath(".", target)

		if fs.isFile(directPath) then
			addMatch(directPath)
			continue
		elseif fs.isFile(directPath .. ".luau") then
			addMatch(directPath .. ".luau")
			continue
		end

		if fs.isDir(directPath) then
			for _, spec in ipairs(discoverSpecs(directPath)) do
				addMatch(spec)
			end
			continue
		end

		local pluginCandidate = resolvePath(".", "plugin/" .. target)
		local libCandidate = resolvePath(".", "lib/" .. target)

		if fs.isDir(pluginCandidate) then
			for _, spec in ipairs(discoverSpecs(pluginCandidate)) do
				addMatch(spec)
			end
			continue
		elseif fs.isDir(libCandidate) then
			for _, spec in ipairs(discoverSpecs(libCandidate)) do
				addMatch(spec)
			end
			continue
		end

		local pattern = string.lower(target)
		local foundSubstr = false

		for _, spec in ipairs(allSpecs) do
			if string.find(string.lower(spec), pattern, 1, true) then
				foundSubstr = true
				addMatch(spec)
			end
		end

		if not foundSubstr then
			print(
				string.format(
					"%s Target pattern matched no specs: %s",
					colorize("bold", "yellow", " WARN "),
					cyan(target)
				)
			)
		end
	end

	return matchedSpecs
end

-- =============================================================================
-- Virtual Noctalia Module Loader
-- =============================================================================

local function virtualRequire(currentDir: string, importPath: string, runnerConfig: CliConfig): any
	if string.sub(importPath, 1, 1) == "@" then
		return nativeRequire(importPath)
	end

	local targetPath = resolvePath(currentDir, importPath)

	if not string.match(targetPath, "%.luau$") and not string.match(targetPath, "%.lua$") then
		if fs.isFile(targetPath .. ".luau") then
			targetPath = targetPath .. ".luau"
		end
	end

	if moduleCache[targetPath] ~= nil then
		return moduleCache[targetPath]
	end

	if not fs.isFile(targetPath) then
		fatal(
			string.format("Module not found: %s", cyan(importPath)),
			string.format("Resolved to path: %s\nRequired from: %s", targetPath, currentDir)
		)
	end

	local source = fs.readFile(targetPath)

	-- DX: Catch syntax errors during compilation gracefully
	local compileSuccess, bytecode = pcall(luau.compile, source)
	if not compileSuccess then
		fatal(string.format("Syntax Error in %s", cyan(targetPath)), tostring(bytecode))
	end

	local nextDir = getDirName(targetPath)
	local moduleEnv: { [string]: any } = table.clone(getfenv())

	for k, v in pairs(_G) do
		moduleEnv[k] = v
	end

	moduleEnv.require = function(nextPath: string)
		return virtualRequire(nextDir, nextPath, runnerConfig)
	end

	if runnerConfig.quiet then
		moduleEnv.print = function(...: any)
			local firstArg = tostring(select(1, ...))
			if string.find(firstArg, "%[STL ERROR%]") or string.find(firstArg, "%[ERROR%]") then
				return
			end
			print(...)
		end
	end

	local loadSuccess, moduleFn = pcall(luau.load, bytecode :: string, {
		debugName = targetPath,
		environment = moduleEnv,
	})

	if not loadSuccess then
		fatal(string.format("Failed to load module %s", cyan(targetPath)), tostring(moduleFn))
	end

	-- DX: Catch runtime evaluation errors at the file root
	local execSuccess, result = pcall(moduleFn :: any)
	if not execSuccess then
		fatal(string.format("Runtime Error evaluating %s", cyan(targetPath)), tostring(result))
	end

	local exported = if result == nil then true else result
	moduleCache[targetPath] = exported
	return exported
end

-- =============================================================================
-- Execution Engine
-- =============================================================================

local config = parseCliArgs(process.args)

if config.help then
	printHelp()
	process.exit(0)
end

-- Inject CLI config globally so the underlying `testing.luau` framework
-- can respect `--filter` and `--fail-fast` directives.
(_G :: any).__TEST_RUNNER_CONFIG = config

local discoveryStart = os.clock()
local allSpecs = discoverSpecs(".")
local specFiles = resolveTargets(config.targets, allSpecs)
local discoveryTime = os.clock() - discoveryStart

printHeader("Discovery")
if #specFiles == 0 then
	fatal("No matching test specification (*_spec.luau) files found.")
end

print(
	string.format(
		"Found %s test suites in %s",
		bold(tostring(#specFiles)),
		dim(string.format("%.2fms", discoveryTime * 1000))
	)
)

if config.filter then
	print(string.format("%s Active spec filter: %s", colorize("bold", "yellow", " ⚑ "), cyan(config.filter)))
end
if config.failFast then
	print(string.format("%s Fail-fast mode enabled", colorize("bold", "yellow", " ⚑ ")))
end

-- Dynamically resolve testing bootstrap module
local testingPath = "lib/testing/testing.luau"
if not fs.isFile(testingPath) then
	for _, pathCandidate in ipairs({ "testing/testing.luau", "lib/testing.luau" }) do
		if fs.isFile(pathCandidate) then
			testingPath = pathCandidate
			break
		end
	end
end

printHeader("Execution")
local execStart = os.clock()

local testing: any = virtualRequire(".", testingPath, config)

local bootstrapFn: any = testing.bootstrap
if typeof(bootstrapFn) == "function" then
	(bootstrapFn :: () -> ())()
else
	local createHostFn: any = testing.createMockHost
	if typeof(createHostFn) == "function" then
		local host = (createHostFn :: () -> any)()
		local injectHostFn: any = testing.injectHost
		if typeof(injectHostFn) == "function" then
			(injectHostFn :: (any) -> ())(host)
		end
	end
end

-- Evaluate all discovered spec files to register their tests
for _, specPath in ipairs(specFiles) do
	virtualRequire(".", specPath, config)
end

local runFn: any = testing.run
if typeof(runFn) ~= "function" and typeof(testing.test) == "table" then
	runFn = testing.test.run
end

if typeof(runFn) ~= "function" then
	fatal(string.format("Could not find test runner function 'test.run()' in '%s'", testingPath))
end

-- Execute the test suite
local passed: number, failed: number = (runFn :: () -> (number, number))()
local execTime = os.clock() - execStart

local teardownFn: any = testing.teardown
if typeof(teardownFn) == "function" then
	(teardownFn :: () -> ())()
end

-- Final reporting summary
print(string.format("\n%s Executed in %s", dim("⏱"), bold(string.format("%.2fs", execTime))))

if failed > 0 then
	process.exit(1)
end
