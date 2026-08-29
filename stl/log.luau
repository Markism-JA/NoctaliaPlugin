--!strict
--- Structured logging utility with level filtering, scoping, JSON context,
--- and multi-sink publishing (host logs + in-memory state ring buffer).
local log = {}

--- Valid severity levels for filtering log output.
export type LogLevel = "DEBUG" | "INFO" | "WARN" | "ERROR" | "NONE"

export type LogRecord = {
	timestamp: string,
	level: LogLevel,
	tag: string,
	message: string,
	context: { [string]: any }?,
}

local LEVEL_SEVERITY: { [LogLevel]: number } = {
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
	NONE = 5,
}

local STATE_LOG_KEY = "stl.logs.recent"
local MAX_RING_BUFFER_ENTRIES = 150

local currentMinLevel: number = LEVEL_SEVERITY.INFO
local ringBuffer: { LogRecord } = {}

--- Sets the global minimum log level threshold. Logs below this severity will be ignored.
function log.setLevel(level: LogLevel)
	currentMinLevel = LEVEL_SEVERITY[level] or LEVEL_SEVERITY.INFO
end

--- Returns the current numeric severity threshold.
function log.getLevel(): number
	return currentMinLevel
end

--- Dynamically configures the log level from a declared Noctalia configuration setting.
function log.syncFromConfig(configKey: string?)
	if (noctalia :: any) == nil or (noctalia :: any).getConfig == nil then
		return
	end

	local key: string = configKey or "log_level"
	local configured = noctalia.getConfig(key)
	if typeof(configured) == "string" then
		local upper = string.upper(configured) :: LogLevel
		if LEVEL_SEVERITY[upper] then
			log.setLevel(upper)
		end
	end
end

--- Serializes a context table into JSON safely across host and CLI environments.
local function serializeContext(ctx: { [string]: any }?): string
	if not ctx or next(ctx) == nil then
		return ""
	end

	if (noctalia :: any) ~= nil and (noctalia :: any).json ~= nil then
		local encoded: string?, _ = noctalia.json.encode(ctx)
		if typeof(encoded) == "string" then
			return " " .. encoded
		end
	end

	-- Fallback simple serializer for standalone CLI testing
	local parts: { string } = {}
	for k, v in pairs(ctx) do
		table.insert(parts, string.format("%q:%s", tostring(k), tostring(v)))
	end
	return " {" .. table.concat(parts, ",") .. "}"
end

--- Resolves the current ISO-like timestamp.
local function getTimestamp(): string
	if (noctalia :: any) ~= nil and (noctalia :: any).formatTime ~= nil then
		local formatTime = noctalia.formatTime :: (string) -> string
		return formatTime("%Y-%m-%d %H:%M:%S")
	end
	return os.date("%Y-%m-%d %H:%M:%S")
end

--- Internal log emitter that dispatches to stdout and state channels.
local function emit(levelStr: LogLevel, tag: string, msg: string, ctx: { [string]: any }?)
	if LEVEL_SEVERITY[levelStr] < currentMinLevel then
		return
	end

	local ts = getTimestamp()
	local contextStr = serializeContext(ctx)
	local formatted = string.format("[%s] [%s] [%s] %s%s", ts, levelStr :: string, tag, msg, contextStr)

	-- Sink 1: Noctalia Host Console / stdout
	if (noctalia :: any) ~= nil and (noctalia :: any).log ~= nil then
		noctalia.log(formatted)
	else
		print(formatted)
	end

	-- Sink 2: Cross-VM In-Memory IPC Ring Buffer
	if (noctalia :: any) ~= nil and (noctalia :: any).state ~= nil and (noctalia :: any).state.set ~= nil then
		local record: LogRecord = {
			timestamp = ts,
			level = levelStr,
			tag = tag,
			message = msg,
			context = ctx,
		}
		table.insert(ringBuffer, record)
		if #ringBuffer > MAX_RING_BUFFER_ENTRIES then
			table.remove(ringBuffer, 1)
		end
		noctalia.state.set(STATE_LOG_KEY, ringBuffer)
	end
end

--- Scoped logger interface for emitting structured logs.
export type Logger = {
	debug: (msg: string, ctx: { [string]: any }?) -> (),
	info: (msg: string, ctx: { [string]: any }?) -> (),
	warn: (msg: string, ctx: { [string]: any }?) -> (),
	error: (msg: string, ctx: { [string]: any }?) -> (),
}

--- Creates a new scoped logger instance identified by a specific tag.
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

return log
