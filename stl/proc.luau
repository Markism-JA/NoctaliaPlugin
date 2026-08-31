--!strict
--- Subprocess execution and persistent stream handling helpers for Noctalia.
---
--- Provides safe asynchronous execution, detached process spawning, stream management,
--- path caching, and host fallback for both live shell runtimes and CLI test harnesses.
local proc = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Optional configuration flags for subprocess execution.
export type ExecOptions = {
	--- When true, automatically strips leading and trailing whitespace from stdout and stderr.
	--- Set to false when capturing large binary or structured JSON payloads to conserve CPU budget.
	--- Defaults to true for small outputs.
	trimOutput: boolean?,

	--- Maximum stdout length in bytes to automatically apply trimming to.
	--- Defaults to 65536 (64 KiB). Outputs larger than this bypass auto-trimming unless forced.
	maxTrimBytes: number?,
}

--- Raw process outcome emitted by the underlying host runtime.
export type ProcessResult = {
	--- Process exit status code (0 indicates success).
	exitCode: number,
	--- Standard output stream captured from the process.
	stdout: string,
	--- Standard error stream captured from the process.
	stderr: string,
	--- True if the execution duration exceeded the host timeout threshold.
	timedOut: boolean,
	--- True if stdout exceeded buffer limits and was truncated by the host.
	stdoutTruncated: boolean?,
	--- True if stderr exceeded buffer limits and was truncated by the host.
	stderrTruncated: boolean?,
}

--- Standard completion callback for asynchronous subprocess execution.
export type ExecCallback = (err: string?, stdout: string, exitCode: number) -> ()

--- Host interface definition required by proc.
export type ProcHost = {
	runAsync: ((cmdOrArgv: string | { string }, cb: ((res: ProcessResult) -> ())?) -> boolean)?,
	runStream: ((cmd: string, onLine: (line: string) -> ()) -> boolean)?,
	commandExists: ((name: string) -> boolean)?,
	[string]: any,
}

-- =============================================================================
-- Internal State & Constants
-- =============================================================================

local DEFAULT_MAX_TRIM_BYTES = 64 * 1024 -- 64 KiB threshold

--- Memoization cache for `commandExists` lookups across poll cycles.
local PATH_CACHE: { [string]: boolean } = {}

--- Optional mock host override injected during tests.
local injectedHost: ProcHost? = nil

--- Fast C-level pattern trim (zero Lua loops, zero Luau instruction budget consumption).
local function nativeTrim(str: string): string
	if #str == 0 then
		return ""
	end
	-- Native C regex matcher consumes negligible VM instructions
	return str:match("^%s*(.-)%s*$") or ""
end

--- Resolves the effective host environment bridge, prioritizing active test mocks
--- and checking runtime globals across `_G` and `getfenv()`.
local function getHost(): any
	if injectedHost ~= nil then
		return injectedHost
	end

	local gHost = (_G :: any).noctalia
	if gHost ~= nil then
		return gHost
	end

	local fenvHost = (getfenv() :: any).noctalia
	if fenvHost ~= nil then
		return fenvHost
	end

	return nil
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Runs a command string or argv table asynchronously and captures its output.
---
--- If the host runner is unavailable or rejects the task queue (exhaustion limit),
--- the callback is invoked synchronously with an error rather than hanging.
---
--- ### Example:
--- ```luau
--- proc.exec({ "hyprctl", "activeworkspace", "-j" }, function(err, stdout, code)
---     if err then
---         log.error("Failed to query workspace", { err = err, code = code })
---         return
---     end
---     local ws = noctalia.json.decode(stdout)
--- end)
--- ```
---
--- @param cmdOrArgv string | { string } Shell command string or argument array.
--- @param cb ExecCallback Callback invoked upon process completion or immediate failure.
--- @param options ExecOptions? Optional execution controls (e.g. `trimOutput`, `maxTrimBytes`).
--- @return boolean True if the execution request was accepted and queued by the host.
function proc.exec(cmdOrArgv: string | { string }, cb: ExecCallback, options: ExecOptions?): boolean
	local runner: any = getHost()

	if runner == nil or typeof(runner.runAsync) ~= "function" then
		cb("Host process runner unavailable", "", -1)
		return false
	end

	local maxTrim = (options and options.maxTrimBytes) or DEFAULT_MAX_TRIM_BYTES
	local shouldTrim = if options and options.trimOutput ~= nil then options.trimOutput else true
	local didComplete = false

	local accepted = (runner.runAsync :: any)(cmdOrArgv, function(res: ProcessResult)
		if didComplete then
			return
		end
		didComplete = true

		if res.timedOut then
			cb("Process timed out", "", res.exitCode)
			return
		end

		local stdout = res.stdout or ""
		local stderr = res.stderr or ""

		-- Safeguard: Do not perform pattern operations if output exceeds byte threshold
		local allowTrim = shouldTrim and #stdout <= maxTrim

		if res.exitCode ~= 0 then
			local err = if stderr ~= "" then stderr else string.format("Process exited with code %d", res.exitCode)

			if shouldTrim and #err <= maxTrim then
				err = nativeTrim(err)
			end
			if allowTrim and stdout ~= "" then
				stdout = nativeTrim(stdout)
			end

			cb(err, stdout, res.exitCode)
			return
		end

		if allowTrim and stdout ~= "" then
			stdout = nativeTrim(stdout)
		end

		cb(nil, stdout, res.exitCode)
	end)

	if not accepted then
		if not didComplete then
			didComplete = true
			cb("Failed to queue subprocess (host task queue full or invalid command)", "", -1)
		end
		return false
	end

	return true
end

--- Starts a detached process without output capture (fire-and-forget).
---
--- Useful for triggering external applications or dispatching CLI IPC messages.
---
--- ### Example:
--- ```luau
--- proc.spawn("noctalia msg panel-toggle launcher")
--- ```
---
--- @param cmdOrArgv string | { string } Shell command string or argument array.
--- @return boolean True if the launch request was accepted by the host queue.
function proc.spawn(cmdOrArgv: string | { string }): boolean
	local runner: any = getHost()
	if runner == nil or typeof(runner.runAsync) ~= "function" then
		return false
	end
	return (runner.runAsync :: any)(cmdOrArgv) == true
end

--- Starts a long-lived streaming process and invokes `onLine` for every line emitted to stdout.
---
--- The process stream is automatically terminated by Noctalia when the host unloads the plugin entry.
---
--- ### Example:
--- ```luau
--- proc.stream("playerctl metadata --follow", function(line)
---     log.debug("Track updated", { metadata = line })
--- end)
--- ```
---
--- @param cmd string Shell command string to execute in streaming mode.
--- @param onLine (line: string) -> () Callback invoked per standard output line.
--- @return boolean True if the stream was accepted and started.
function proc.stream(cmd: string, onLine: (line: string) -> ()): boolean
	local runner: any = getHost()
	if runner == nil or typeof(runner.runStream) ~= "function" then
		return false
	end
	return (runner.runStream :: any)(cmd, onLine) == true
end

--- Checks whether a binary executable exists on the system `$PATH`.
---
--- Results are memoized in memory to eliminate repeated `$PATH` lookups during high-frequency
--- polling intervals (e.g. 400ms timers).
---
--- ### Example:
--- ```luau
--- if proc.exists("hyprctl") then
---     -- Safe to query hyprctl
--- end
--- ```
---
--- @param name string Binary executable name to check (e.g. "hyprctl", "wpctl").
--- @return boolean True if the executable binary is present and reachable.
function proc.exists(name: string): boolean
	local cached = PATH_CACHE[name]
	if cached ~= nil then
		return cached
	end

	local checker: any = getHost()
	if checker == nil or typeof(checker.commandExists) ~= "function" then
		return false
	end

	local exists = (checker.commandExists :: any)(name) == true
	PATH_CACHE[name] = exists
	return exists
end

--- Clears the memoized binary path cache.
---
--- Call this during unit tests or runtime reloads if `$PATH` binaries may have changed.
function proc.clearCache()
	table.clear(PATH_CACHE)
end

-- =============================================================================
-- Test Injection Hook
-- =============================================================================

--- Injects a custom mock host bridge for testing outside Noctalia runtimes.
---
--- Clears the binary path memoization cache. Passing `nil` restores default host resolution.
---
--- @param mockHost ProcHost? Mock host table implementing process execution methods.
function proc.__setHost(mockHost: ProcHost?)
	injectedHost = mockHost
	table.clear(PATH_CACHE)
end

return proc
