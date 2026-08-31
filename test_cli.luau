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

local function magenta(text: string): string
	return stdio.color("purple") .. text .. stdio.color("reset")
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
  %s                   Optional spec file(s) or directories to execute.
                        Defaults to discovering all '*_spec.luau' files.

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

local function discoverSpecs(dir: string): { string }
	local specs: { string } = {}
	local function scan(currentDir: string)
		if not fs.isDir(currentDir) then
			return
		end
		local entries = fs.readDir(currentDir) :: { string }
		for _, entry: string in ipairs(entries) do
			local path = currentDir .. "/" .. entry
			if fs.isDir(path) then
				scan(path)
			elseif fs.isFile(path) and string.match(entry, "_spec%.luau$") then
				table.insert(specs, path)
			end
		end
	end
	scan(dir)
	return specs
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
		error(
			string.format(
				"%s: '%s' %s",
				red("Module not found"),
				importPath,
				dim(string.format("(resolved to '%s')", targetPath))
			),
			2
		)
	end

	local source = fs.readFile(targetPath)
	local bytecode = luau.compile(source)

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

	local moduleFn = luau.load(bytecode, {
		debugName = targetPath,
		environment = moduleEnv,
	})

	local result = moduleFn()
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

local specFiles: { string } = {}

if #config.targets == 0 then
	for _, spec in ipairs(discoverSpecs("testing/specs")) do
		table.insert(specFiles, spec)
	end
	for _, spec in ipairs(discoverSpecs("plugins")) do
		table.insert(specFiles, spec)
	end
	for _, spec in ipairs(discoverSpecs("keybind-cheatsheet/tests")) do
		table.insert(specFiles, spec)
	end
else
	for _, target in ipairs(config.targets) do
		local resolved = resolvePath(".", target)
		if not fs.isFile(resolved) and fs.isFile(resolved .. ".luau") then
			resolved = resolved .. ".luau"
		end

		if fs.isFile(resolved) then
			table.insert(specFiles, resolved)
		elseif fs.isDir(resolved) then
			for _, spec in ipairs(discoverSpecs(resolved)) do
				table.insert(specFiles, spec)
			end
		else
			print(string.format("%s Target not found: %s", colorize("bold", "yellow", " WARN "), cyan(target)))
			process.exit(1)
		end
	end
end

if #specFiles == 0 then
	print(
		string.format(
			"%s No matching test specification (*_spec.luau) files found.",
			colorize("bold", "red", " ERROR ")
		)
	)
	process.exit(1)
end

print(
	string.format("\n%s Discovered %s test suite files", colorize("bold", "cyan", " RUNS "), bold(tostring(#specFiles)))
)

local testing: any = virtualRequire(".", "testing/testing.luau", config)

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

for _, specPath in ipairs(specFiles) do
	virtualRequire(".", specPath, config)
end

local runFn: any = testing.run
if typeof(runFn) ~= "function" and typeof(testing.test) == "table" then
	runFn = testing.test.run
end

if typeof(runFn) ~= "function" then
	print(
		string.format(
			"%s Could not find test runner function 'test.run()' in testing.luau",
			colorize("bold", "red", " ERROR ")
		)
	)
	process.exit(1)
end

local _passed: number, failed: number = (runFn :: () -> (number, number))()

local teardownFn: any = testing.teardown
if typeof(teardownFn) == "function" then
	(teardownFn :: () -> ())()
end

if failed > 0 then
	process.exit(1)
end
