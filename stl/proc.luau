--!strict
--- Subprocess execution and stream handling helpers for Noctalia.
--- Provides safe asynchronous execution, detached process spawning, persistent stream
--- management, and host environment fallback for both live shell runtimes and CLI test harnesses.
local test = require("./test")

local proc = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

export type ExecOptions = {
	--- When true, automatically trims leading and trailing whitespace from stdout and stderr.
	trimOutput: boolean?,
}

export type ProcessResult = {
	exitCode: number,
	stdout: string,
	stderr: string,
	timedOut: boolean,
	stdoutTruncated: boolean?,
	stderrTruncated: boolean?,
}

--- Standard completion callback for asynchronous subprocess execution.
--- @param err string? Non-nil if the process failed to launch, timed out, or returned a non-zero exit code.
--- @param stdout string The captured standard output of the process.
--- @param exitCode number The numeric status code returned by the process (-1 for launch/runner errors).
export type ExecCallback = (err: string?, stdout: string, exitCode: number) -> ()

-- =============================================================================
-- Internal Helpers
-- =============================================================================

--- Resolves the effective subprocess host bridge, prioritizing active test mocks over the global runtime.
local function resolveRunner(): any
	if test.host and test.host.runAsync ~= nil then
		return test.host
	end
	if (noctalia :: any) ~= nil and (noctalia :: any).runAsync ~= nil then
		return noctalia
	end
	return nil
end

--- Resolves the effective command existence checker.
local function resolveChecker(): any
	if test.host and test.host.commandExists ~= nil then
		return test.host
	end
	if (noctalia :: any) ~= nil and (noctalia :: any).commandExists ~= nil then
		return noctalia
	end
	return nil
end

--- Resolves the effective stream runner.
local function resolveStreamRunner(): any
	if test.host and test.host.runStream ~= nil then
		return test.host
	end
	if (noctalia :: any) ~= nil and (noctalia :: any).runStream ~= nil then
		return noctalia
	end
	return nil
end

local function safeTrim(str: string?): string
	if not str or str == "" then
		return ""
	end
	local from = string.match(str, "^%s*()")
	if not from then
		return ""
	end
	return if from > #str then "" else (string.match(str, ".*%S", from) or "")
end

-- =============================================================================
-- Public Interface
-- =============================================================================

--- Runs a command or argument array asynchronously and captures its output.
--- If the host rejects the task queue or the runner is unavailable, the callback is
--- invoked immediately with an error rather than hanging.
---
--- @param cmdOrArgv string | { string } Shell command string or argv table.
--- @param cb ExecCallback Callback invoked upon process completion or immediate failure.
--- @param options ExecOptions? Optional execution controls (e.g. `trimOutput`).
--- @return boolean True if the execution request was queued by the host.
function proc.exec(cmdOrArgv: string | { string }, cb: ExecCallback, options: ExecOptions?): boolean
	local opts = options or { trimOutput = true }
	local runner = resolveRunner()

	if runner == nil then
		cb("Host process runner unavailable (running outside Noctalia runtime)", "", -1)
		return false
	end

	local accepted = runner.runAsync(cmdOrArgv, function(res: ProcessResult)
		if res.timedOut then
			cb("Process timed out", "", res.exitCode)
			return
		end

		if res.exitCode ~= 0 then
			local errMsg = if res.stderr and res.stderr ~= ""
				then res.stderr
				else string.format("Process exited with code %d", res.exitCode)

			if opts.trimOutput then
				errMsg = safeTrim(errMsg)
			end
			cb(errMsg, res.stdout or "", res.exitCode)
			return
		end

		local stdout = res.stdout or ""
		if opts.trimOutput then
			stdout = safeTrim(stdout)
		end

		cb(nil, stdout, res.exitCode)
	end)

	if not accepted then
		cb("Failed to queue subprocess (host task queue full or invalid command)", "", -1)
	end

	return accepted
end

--- Starts a detached process without output capture (fire-and-forget).
---
--- @param cmdOrArgv string | { string } Shell command string or argv table.
--- @return boolean True if the process successfully launched.
function proc.spawn(cmdOrArgv: string | { string }): boolean
	local runner = resolveRunner()
	if runner == nil then
		return false
	end
	return runner.runAsync(cmdOrArgv)
end

--- Starts a long-lived stream process and calls `onLine` for every emitted stdout line.
--- The stream is automatically terminated by Noctalia when the plugin runtime unloads.
---
--- @param cmd string Shell command to run in streaming mode.
--- @param onLine (line: string) -> () Callback invoked per output line (carriage returns trimmed).
--- @return boolean True if the stream was accepted and initiated.
function proc.stream(cmd: string, onLine: (line: string) -> ()): boolean
	local runner = resolveStreamRunner()
	if runner == nil then
		return false
	end
	return runner.runStream(cmd, onLine)
end

--- Checks if an executable is available on the system PATH.
---
--- @param name string Binary executable name to check (e.g. "hyprctl").
--- @return boolean True if the command is found.
function proc.exists(name: string): boolean
	local checker = resolveChecker()
	if checker == nil then
		return false
	end
	return checker.commandExists(name)
end

return proc
