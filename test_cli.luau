--!strict
--- Hermetic Test Runner & CLI Tool for Noctalia Plugin Development.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local nativeRequire = require
local moduleCache: { [string]: any } = {}

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
	print([[
Noctalia CLI Test Runner

Usage:
  lune run test_cli [options] [path ...]

Arguments:
  path                  Optional spec file(s) or directories to execute.
                        Defaults to discovering all '*_spec.luau' files.

Options:
  -f, --filter <str>    Filter test suites and test cases by name.
  -q, --quiet           Silence non-test logging (stdout error traces).
  -x, --fail-fast       Abort execution on the first encountered test failure.
  -h, --help            Show this help dialog.
]])
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
		error(string.format("Module not found: '%s' (resolved to '%s')", importPath, targetPath), 2)
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
			print(string.format("[WARN] Target not found: %s", target))
			process.exit(1)
		end
	end
end

if #specFiles == 0 then
	print("[ERROR] No matching test specification (*_spec.luau) files found.")
	process.exit(1)
end

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
	print("[ERROR] Could not find test runner function 'test.run()' in testing.luau")
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
