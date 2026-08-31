--!strict
--- In-memory host emulator with dynamic capability gating for Noctalia Plugin APIs.
---
--- Emulates the native Noctalia C/Rust host environment for headless test harnesses
--- (Lune and Luau CLI). Provides state channel pub/sub, process execution hooks, virtual
--- filesystem inspection, configuration bridging, and capability stripping across simulated API tiers (levels 3 to 28).
---
--- ### Example:
--- ```luau
--- local mock = require("./testing/mock.luau")
--- local host = mock.create(28)
---
--- host.setConfig("theme", "catppuccin")
--- host.setExecHandler(function(cmd)
---     if cmd == "hyprctl activewindow -j" then
---         return 0, '{"title":"Terminal","class":"kitty"}', ""
---     end
---     return 1, "", "command not found"
--- end)
---
--- local rawG = _G :: any
--- rawG.noctalia = host
--- ```

local hostBridge = require("../stl/host.luau")
local apiMatrix = require("../stl/api_matrix.luau")

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Interceptor callback for simulating external process execution outcomes.
---
--- @param cmdOrArgv string | { string } Shell command string or argv argument array.
--- @return number exitCode Process exit code (`0` indicates success).
--- @return string stdout Captured standard output stream.
--- @return string stderr Captured standard error stream.
export type ExecHandler = (cmdOrArgv: any) -> (number, string, string)

--- Outcome structure returned by `runAsync` completion callbacks.
export type ExecResult = {
	--- Process exit status code (`0` indicates success).
	exitCode: number,
	--- Standard output stream captured from the process.
	stdout: string,
	--- Standard error stream captured from the process.
	stderr: string,
	--- Indicates whether the process was terminated due to exceeding timeout limits.
	timedOut: boolean,
}

--- Completion callback signature invoked by `runAsync`.
---
--- @param result ExecResult The final execution payload containing output streams and status.
export type MockCallback = (result: ExecResult) -> ()

--- Filesystem metadata entry structure.
export type FileInfo = {
	--- File size in bytes.
	size: number,
	--- Last modification timestamp in POSIX epoch seconds.
	mtime: number,
	--- Indicates whether the target path resolves to a directory.
	isDir: boolean,
}

--- Emulated cross-VM shared state channel namespace.
export type MockState = {
	--- Retrieves the active value for a state key.
	---
	--- @param key string The target state identifier.
	--- @return any The stored value, or `nil` if unset.
	get: (key: string) -> any,

	--- Publishes a value to a state key and notifies registered watchers.
	---
	--- @param key string The target state identifier.
	--- @param val any The payload value to store and broadcast.
	set: (key: string, val: any) -> (),

	--- Registers a subscriber callback invoked whenever a specific key changes.
	---
	--- @param key string The target state identifier.
	--- @param fn (val: any) -> () Listener closure receiving the updated value.
	watch: (key: string, fn: (val: any) -> ()) -> (),

	--- Purges all stored state keys and deregisters all watcher callbacks.
	clear: () -> (),
}

--- Emulated audio runtime interface.
export type MockSound = {
	--- Simulates loading an audio asset into the sound bank.
	---
	--- @param name string Identifier key for the loaded sound.
	--- @param path string File path or asset URI to load.
	--- @param onLoaded (ok: boolean, err: string?) -> () Asynchronous completion callback.
	--- @return boolean True if the load request was queued successfully.
	load: (name: string, path: string, onLoaded: (ok: boolean, err: string?) -> ()) -> boolean,

	--- Triggers playback for a registered audio asset.
	---
	--- @param name string Identifier key of the sound to play.
	play: (name: string) -> (),
}

--- Emulated JSON codec namespace.
export type MockJson = {
	--- Deserializes a JSON string into corresponding Luau primitive types or tables.
	---
	--- @param str string The raw JSON payload to decode.
	--- @return any decoded The parsed Luau value on success.
	--- @return string? err Error message if parsing failed.
	decode: (str: string) -> (any, string?),

	--- Serializes a Luau value or table into a JSON-formatted string.
	---
	--- @param val any The Luau primitive or table to encode.
	--- @return string encoded The generated JSON string.
	--- @return string? err Error message if encoding failed.
	encode: (val: any) -> (string, string?),
}

--- Primary mock host interface inheriting native `typeof(noctalia)` capabilities
--- with dedicated test harness control mutators.
export type MockHost = hostBridge.HostBridge & {
	state: MockState,

	--- Resolves configuration settings by key identifier (consumed by `stl.config`).
	---
	--- @param key string Configuration key identifier.
	--- @return any The configured value or `nil` if unset.
	getConfig: (key: string) -> any,

	--- Injects or overrides configuration values in the mock store for unit testing.
	---
	--- @param key string Configuration key identifier.
	--- @param val any Configuration value to assign.
	setConfig: (key: string, val: any) -> (),

	--- Checks whether an executable binary exists on the system `$PATH`.
	---
	--- @param name string Executable binary name to check.
	--- @return boolean True if the binary is accessible on `$PATH`.
	commandExists: (name: string) -> boolean,

	--- Executes a shell command string or argv array asynchronously.
	---
	--- @param cmdOrArgv string | { string } Shell command string or argv argument array.
	--- @param cb MockCallback? Optional completion callback receiving execution metrics.
	--- @return boolean True if the command process was successfully spawned.
	runAsync: (cmdOrArgv: any, cb: MockCallback?) -> boolean,

	--- Spawns a long-lived process and streams standard output line-by-line.
	---
	--- @param cmd string Shell command string to execute.
	--- @param onLine (line: string) -> () Callback invoked on every received stdout line.
	--- @return boolean True if streaming was initiated (requires API level >= 4).
	runStream: (cmd: string, onLine: (line: string) -> ()) -> boolean,

	--- Registers a custom execution trap handler for `runAsync` invocations.
	---
	--- @param handler ExecHandler Callback returning simulated exit codes and outputs.
	setExecHandler: (handler: ExecHandler) -> (),
	setVirtualFile: (path: string, content: string) -> (),
	setApiLevel: (level: number) -> (),

	--- Restores initial API level, clears state channels and configurations, and resets execution handlers.
	reset: () -> (),
}

-- =============================================================================
-- Factory Implementation
-- =============================================================================

local mock = {}

--- Constructs a new isolated `MockHost` instance initialized to a target API level.
---
--- If `initialApiLevel` is omitted, defaults to `apiMatrix.MAX_SUPPORTED_LEVEL` (28).
--- Dynamic tier methods (`sound`, `getSetting`, `nowMs`) and features (`argv` execution)
--- are bound or stripped dynamically according to the active API level.
---
--- ### Usage:
--- ```luau
--- local mock = require("./testing/mock.luau")
--- local host = mock.create(19) -- Simulate Noctalia v5.0.0-beta.7
---
--- host.setConfig("compositor", "hyprland")
--- host.setExecHandler(function(cmd)
---     if cmd == "hyprctl activewindow -j" then
---         return 0, '{"title":"Terminal","class":"kitty"}', ""
---     end
---     return 1, "", "command not found"
--- end)
--- ```
---
--- @param initialApiLevel number? Optional integer API level to simulate (defaults to 28).
--- @return MockHost Fully configured and isolated mock host bridge.
function mock.create(initialApiLevel: number?): MockHost
	local store: { [string]: any } = {}
	local configStore: { [string]: any } = {}
	local virtualFiles: { [string]: string } = {}
	local watchers: { [string]: { (val: any) -> () } } = {}
	local envVars: { [string]: string } = { HOME = "/home/user" }
	local execHandler: ExecHandler? = nil
	local activeLevel: number = initialApiLevel or apiMatrix.MAX_SUPPORTED_LEVEL

	local defaultSound: MockSound = {
		load = function(_name: string, _path: string, onLoaded: (ok: boolean, err: string?) -> ()): boolean
			onLoaded(true, nil)
			return true
		end,
		play = function(_name: string) end,
	}

	local defaultGetSetting = function(_path: string): any
		return nil
	end

	local defaultNowMs = function(): number
		return os.time() * 1000
	end

	local stateObj: MockState = {
		get = function(key: string): any
			return store[key]
		end,
		set = function(key: string, val: any)
			store[key] = val
			if watchers[key] then
				for _, fn in ipairs(watchers[key]) do
					fn(val)
				end
			end
		end,
		watch = function(key: string, fn: (val: any) -> ())
			watchers[key] = watchers[key] or {}
			table.insert(watchers[key], fn)
		end,
		clear = function()
			table.clear(store)
			table.clear(watchers)
		end,
	}

	local hostTable: { [string]: any }

	local function applyApiLevel(level: number)
		activeLevel = level
		hostTable.pluginApiLevel = level
		hostTable.getSetting = if level >= 26 then defaultGetSetting else nil
		hostTable.sound = if level >= 20 then defaultSound else nil
		hostTable.nowMs = if level >= 12 then defaultNowMs else nil
	end

	local function normalizeVirtualPath(path: string): string
		if string.sub(path, 1, 1) == "~" then
			return (envVars.HOME or "/home/user") .. string.sub(path, 2)
		end
		return path
	end

	hostTable = {
		pluginApiLevel = activeLevel,
		state = stateObj,

		getConfig = function(key: string): any
			return configStore[key]
		end,

		setConfig = function(key: string, val: any)
			configStore[key] = val
		end,

		commandExists = function(_name: string): boolean
			return true
		end,

		runAsync = function(cmdOrArgv: any, cb: MockCallback?)
			if typeof(cmdOrArgv) == "table" and activeLevel < 24 then
				error("Host API level below 24 does not support argv table execution")
			end

			if cb ~= nil then
				local code = 0
				local stdout = ""
				local stderr = ""
				if execHandler ~= nil then
					code, stdout, stderr = execHandler(cmdOrArgv)
				end
				cb({
					exitCode = code,
					stdout = stdout,
					stderr = stderr,
					timedOut = false,
				})
			end
			return true
		end,

		runStream = function(_cmd: string, _onLine: (line: string) -> ()): boolean
			return activeLevel >= 4
		end,

		setExecHandler = function(handler: ExecHandler)
			execHandler = handler
		end,

		getenv = function(name: string): string?
			return envVars[name]
		end,

		expandPath = function(path: string): string
			return normalizeVirtualPath(path)
		end,

		fileExists = function(path: string): boolean
			local resolved = normalizeVirtualPath(path)
			return virtualFiles[resolved] ~= nil
		end,

		fileInfo = function(path: string): (FileInfo?, string?)
			local resolved = normalizeVirtualPath(path)
			local content = virtualFiles[resolved]
			if content ~= nil then
				return {
					size = #content,
					mtime = 1700000000,
					isDir = false,
				}, nil
			end
			return {
				size = 1024,
				mtime = 1700000000,
				isDir = false,
			}, nil
		end,

		listDir = function(_path: string): ({ string }?, string?)
			return {}, nil
		end,

		readFile = function(path: string): (string?, string?)
			local resolved = normalizeVirtualPath(path)
			local content = virtualFiles[resolved]
			if content ~= nil then
				return content, nil
			end
			return nil, "File not found: " .. path
		end,

		writeFile = function(path: string, content: string): (boolean, string?)
			local resolved = normalizeVirtualPath(path)
			virtualFiles[resolved] = content
			return true, nil
		end,

		mkdirAll = function(_path: string): (boolean, string?)
			return true, nil
		end,

		pluginDataDir = function(): (string?, string?)
			return "/home/user/.local/share/noctalia/plugins/mock-plugin", nil
		end,

		setVirtualFile = function(path: string, content: string)
			local resolved = normalizeVirtualPath(path)
			virtualFiles[resolved] = content
		end,

		log = function(_msg: string) end,

		formatTime = function(_fmt: string): string
			return os.date("%Y-%m-%d %H:%M:%S") :: string
		end,

		tr = function(key: string): string
			return key
		end,

		json = {
			decode = function(str: string): (any, string?)
				if str == "" or str == "[]" or str == "{}" then
					return {}, nil
				end
				return {}, nil
			end,
			encode = function(_val: any, _pretty: boolean?): (string, string?)
				return "{}", nil
			end,
		},

		sound = defaultSound,
		getSetting = defaultGetSetting,
		nowMs = defaultNowMs,

		setApiLevel = applyApiLevel,

		reset = function()
			stateObj.clear()
			table.clear(configStore)
			table.clear(virtualFiles)
			execHandler = nil
			applyApiLevel(initialApiLevel or apiMatrix.MAX_SUPPORTED_LEVEL)
		end,
	}

	applyApiLevel(activeLevel)

	return (hostTable :: any) :: MockHost
end

mock.createMockHost = mock.create

return mock
