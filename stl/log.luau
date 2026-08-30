--!strict
--- Structured logging utility with level filtering, scoping, JSON context,
--- ring-buffered state dispatch, and headless test host injection.
---
--- Provides unified diagnostics across isolated Luau VM plugin surfaces (services,
--- panels, bar widgets), supporting console emission, cross-VM IPC log replication,
--- configuration synchronization, and test harness interception.
local log = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Valid severity levels for filtering log output.
export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR" | "NONE"

--- Structured log record stored within the in-memory IPC state ring buffer.
export type LogRecord = {
	--- ISO-like timestamp string (`YYYY-MM-DD HH:MM:SS`) when the event occurred.
	timestamp: string,
	--- Log severity level.
	level: LogLevel,
	--- Component or subsystem identifier tag.
	tag: string,
	--- Primary human-readable log message.
	message: string,
	--- Optional key-value context payload serialized alongside the message.
	context: { [string]: any }?,
}

--- Scoped logger interface for emitting structured diagnostic events.
export type Logger = {
	--- Emits a detailed trace log record (lowest severity).
	---
	--- @param msg string Primary message description.
	--- @param ctx { [string]: any }? Optional key-value structured context.
	debug: (msg: string, ctx: { [string]: any }?) -> (),

	--- Emits a standard informational log record.
	---
	--- @param msg string Primary message description.
	--- @param ctx { [string]: any }? Optional key-value structured context.
	info: (msg: string, ctx: { [string]: any }?) -> (),

	--- Emits a non-fatal warning log record.
	---
	--- @param msg string Primary message description.
	--- @param ctx { [string]: any }? Optional key-value structured context.
	warn: (msg: string, ctx: { [string]: any }?) -> (),

	--- Emits a fatal or recoverable failure log record.
	---
	--- @param msg string Primary message description.
	--- @param ctx { [string]: any }? Optional key-value structured context.
	error: (msg: string, ctx: { [string]: any }?) -> (),
}

--- Expected host runtime bridge definition required for diagnostic emission.
export type LogHost = {
	--- Host logging bridge function.
	log: ((msg: string) -> ())?,
	--- Host configuration retrieval function.
	getConfig: ((key: string) -> any)?,
	--- Formatted time resolver function.
	formatTime: ((fmt: string) -> string)?,
	--- JSON serialization namespace.
	json: {
		encode: ((val: any) -> (string, string?))?,
	}?,
	--- Shared cross-VM state storage namespace.
	state: {
		set: ((key: string, val: any) -> ())?,
	}?,
	[string]: any,
}

-- =============================================================================
-- Internal State & Constants
-- =============================================================================

--- Numeric severity mapping for log level filtering comparison.
local LEVEL_SEVERITY: { [LogLevel]: number } = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
	NONE = 5,
}

--- State storage key used for cross-VM log buffer synchronization.
local STATE_LOG_KEY = "stl.logs.recent"

--- Maximum number of log records retained in the memory ring buffer.
local MAX_RING_BUFFER_ENTRIES = 100

--- Active minimum severity threshold. Defaults to INFO (2).
local currentMinLevel: number = LEVEL_SEVERITY.INFO

--- Local ring buffer holding recent structured log records.
local ringBuffer: { LogRecord } = {}

--- Active mock host override injected during unit tests.
local injectedHost: LogHost? = nil

-- =============================================================================
-- Internal Helpers
-- =============================================================================

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

--- Recursively serializes arbitrary Lua values into JSON-compliant strings for test fallbacks.
---
--- @param val any Value to format.
--- @param depth number Current recursion depth to prevent stack overflow.
--- @return string Valid JSON representation of the value.
local function serializeValue(val: any, depth: number): string
	if depth > 4 then
		return '"..."'
	end
	local t = typeof(val)
	if t == "string" then
		return string.format("%q", val)
	elseif t == "number" or t == "boolean" then
		return tostring(val)
	elseif t == "table" then
		local parts: { string } = {}
		for k, v in pairs(val) do
			local kStr = string.format("%q", tostring(k))
			table.insert(parts, string.format("%s:%s", kStr, serializeValue(v, depth + 1)))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return string.format("%q", tostring(val))
end

--- Serializes a key-value context table into a single trailing JSON string.
---
--- @param ctx { [string]: any }? Key-value context table.
--- @return string Serialized JSON string prefixed by a space, or empty string if nil/empty.
local function serializeContext(ctx: { [string]: any }?): string
	if not ctx or next(ctx) == nil then
		return ""
	end

	local host: any = getHost()
	if host ~= nil and host.json ~= nil and typeof(host.json.encode) == "function" then
		local encoded, _ = (host.json.encode :: any)(ctx)
		if typeof(encoded) == "string" then
			return " " .. encoded
		end
	end

	return " " .. serializeValue(ctx, 1)
end

--- Formats the current local timestamp in `YYYY-MM-DD HH:MM:SS` format.
---
--- @return string Formatted timestamp.
local function getTimestamp(): string
	local host: any = getHost()
	if host ~= nil and typeof(host.formatTime) == "function" then
		return (host.formatTime :: (string) -> string)("%Y-%m-%d %H:%M:%S")
	end

	local rawDate = os.date("%Y-%m-%d %H:%M:%S")
	return if typeof(rawDate) == "string" then rawDate else tostring(rawDate)
end

--- Internal dispatcher that filters and writes log records to console and IPC ring buffer sinks.
---
--- @param levelStr LogLevel Severity level of the event.
--- @param tag string Scoped tag identifier.
--- @param msg string Primary log message.
--- @param ctx { [string]: any }? Optional structured metadata table.
local function emit(levelStr: LogLevel, tag: string, msg: string, ctx: { [string]: any }?)
	local targetSeverity = LEVEL_SEVERITY[levelStr] or LEVEL_SEVERITY.INFO
	if targetSeverity < currentMinLevel then
		return
	end

	local host: any = getHost()
	local contextStr = serializeContext(ctx)

	-- Sink 1: Host Console or Process Terminal Stdout
	if host ~= nil and typeof(host.log) == "function" then
		(host.log :: (string) -> ())(string.format("[%s] [%s] %s%s", levelStr, tag, msg, contextStr))
	else
		local ts = getTimestamp()
		print(string.format("[%s] [%s] [%s] %s%s", ts, levelStr, tag, msg, contextStr))
	end

	-- Sink 2: Cross-VM In-Memory IPC Ring Buffer
	if host ~= nil and host.state ~= nil and typeof(host.state.set) == "function" then
		local record: LogRecord = {
			timestamp = getTimestamp(),
			level = levelStr,
			tag = tag,
			message = msg,
			context = ctx,
		}

		table.insert(ringBuffer, record)
		if #ringBuffer > MAX_RING_BUFFER_ENTRIES then
			table.remove(ringBuffer, 1)
		end

		(host.state.set :: any)(STATE_LOG_KEY, table.clone(ringBuffer))
	end
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Sets the global minimum log level threshold.
---
--- Messages with a severity lower than `level` will be discarded immediately.
---
--- ### Example:
--- ```luau
--- log.setLevel("DEBUG") -- Enables all diagnostic logs
--- log.setLevel("WARN")  -- Discards DEBUG and INFO logs
--- ```
---
--- @param level LogLevel Severity threshold ("DEBUG" | "INFO" | "WARN" | "ERROR" | "NONE").
function log.setLevel(level: LogLevel)
	currentMinLevel = LEVEL_SEVERITY[level] or LEVEL_SEVERITY.INFO
end

--- Returns the current numeric severity threshold level.
---
--- Numeric levels: DEBUG (1), INFO (2), WARN (3), ERROR (4), NONE (5).
---
--- @return number The active integer severity limit.
function log.getLevel(): number
	return currentMinLevel
end

--- Dynamically syncs the global logging threshold from a declared Noctalia configuration setting.
---
--- Reads the configuration value, converts it to uppercase, and applies it if valid.
--- Defaults to inspecting the `"log_level"` configuration key if none is supplied.
---
--- ### Example:
--- ```luau
--- log.syncFromConfig("debug_mode_level")
--- ```
---
--- @param configKey string? Optional configuration key name to inspect (defaults to "log_level").
function log.syncFromConfig(configKey: string?)
	local host: any = getHost()
	if host == nil or typeof(host.getConfig) ~= "function" then
		return
	end

	local key: string = configKey or "log_level"
	local configured = (host.getConfig :: any)(key)
	if typeof(configured) == "string" then
		local upper = string.upper(configured) :: LogLevel
		if LEVEL_SEVERITY[upper] then
			log.setLevel(upper)
		end
	end
end

--- Creates a new scoped logger instance bound to a specific component or subsystem tag.
---
--- ### Example:
--- ```luau
--- local log = stl.log.scope("KeybindParser")
---
--- log.debug("Parsing binding file", { path = "/etc/hypr/hyprland.conf" })
--- log.error("Failed to read token", { line = 42, token = "bindm" })
--- ```
---
--- @param tag string Subsystem name or category tag (e.g. "KeybindService", "LayoutEngine").
--- @return Logger A scoped logger table exposing `debug`, `info`, `warn`, and `error` methods.
function log.scope(tag: string): Logger
	return {
		debug = function(msg: string, ctx: { [string]: any }?)
			emit("DEBUG", tag, msg, ctx)
		end,
		info = function(msg: string, ctx: { [string]: any }?)
			emit("INFO", tag, msg, ctx)
		end,
		warn = function(msg: string, ctx: { [string]: any }?)
			emit("WARN", tag, msg, ctx)
		end,
		error = function(msg: string, ctx: { [string]: any }?)
			emit("ERROR", tag, msg, ctx)
		end,
	}
end

--- Retrieves the in-memory array buffer of recent structured log records.
---
--- @return { LogRecord } Array containing up to 100 historical log entries.
function log.getBuffer(): { LogRecord }
	return table.clone(ringBuffer)
end

--- Purges all historical records currently held in the local memory ring buffer.
function log.clearBuffer()
	table.clear(ringBuffer)
end

-- =============================================================================
-- Test Injection Hook
-- =============================================================================

--- Injects a custom mock host bridge for testing outside Noctalia runtimes.
---
--- Resets the local memory ring buffer and restores default log level. Passing `nil` restores default host resolution.
---
--- @param mockHost LogHost? Mock host table implementing logging or state functions.
function log.__setHost(mockHost: LogHost?)
	injectedHost = mockHost
	currentMinLevel = LEVEL_SEVERITY.INFO
	table.clear(ringBuffer)
end

return log
