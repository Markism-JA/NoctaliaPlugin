--!strict
--- Safe synchronous & persistent filesystem operations for Noctalia.
---
--- Provides path manipulation, atomic-safe file reading/writing, structured JSON
--- caching, plugin data persistence, and headless test host injection.
local filesystem = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- File metadata returned by fileInfo queries.
export type FileInfo = {
	--- File size in bytes.
	size: number,
	--- Last modification timestamp (POSIX epoch seconds).
	mtime: number,
	--- True if the path represents a directory.
	isDir: boolean,
}

--- Expected host runtime bridge for filesystem and JSON operations.
export type FilesystemHost = {
	readFile: ((path: string) -> (string?, string?))?,
	writeFile: ((path: string, content: string) -> (boolean, string?))?,
	mkdirAll: ((path: string) -> (boolean, string?))?,
	fileExists: ((path: string) -> boolean)?,
	fileInfo: ((path: string) -> (FileInfo?, string?))?,
	listDir: ((path: string) -> ({ string }?, string?))?,
	expandPath: ((path: string) -> string)?,
	pluginDataDir: (() -> (string?, string?))?,
	json: {
		decode: ((str: string) -> (any, string?))?,
		encode: ((val: any, pretty: boolean?) -> (string, string?))?,
	}?,
	[string]: any,
}

-- =============================================================================
-- Internal State
-- =============================================================================

--- Active mock host override injected during unit tests.
local injectedHost: FilesystemHost? = nil

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

--- Expands `~` and path aliases safely across live and test environments.
local function safeExpand(path: string): string
	local host: any = getHost()
	if string.sub(path, 1, 1) == "~" and host ~= nil and typeof(host.expandPath) == "function" then
		return (host.expandPath :: (string) -> string)(path)
	end
	return path
end

-- =============================================================================
-- Path Manipulation API
-- =============================================================================

--- Joins path segments using POSIX slashes and normalizes double slashes.
---
--- ### Example:
--- ```luau
--- filesystem.join("/home/user", ".config", "hypr") -- Returns "/home/user/.config/hypr"
--- ```
---
--- @param ... string Path segments to concatenate.
--- @return string Normalized joined path.
function filesystem.join(...: string): string
	local rawParts = { ... }
	local cleanParts: { string } = {}
	local isAbsolute = false

	for i, part in ipairs(rawParts) do
		if part ~= "" then
			if i == 1 and string.sub(part, 1, 1) == "/" then
				isAbsolute = true
			end
			-- Strip leading and trailing slashes for clean join
			local clean = string.gsub(string.gsub(part, "^/+", ""), "/+$", "")
			if clean ~= "" then
				table.insert(cleanParts, clean)
			end
		end
	end

	local joined = table.concat(cleanParts, "/")
	if isAbsolute then
		return "/" .. joined
	end
	return if joined == "" then "." else joined
end

--- Returns the base filename or trailing component from a path.
---
--- ### Example:
--- ```luau
--- filesystem.baseName("/etc/hypr/hyprland.conf") -- Returns "hyprland.conf"
--- ```
---
--- @param path string Target file or directory path.
--- @return string Base filename component.
function filesystem.baseName(path: string): string
	local name = string.match(path, "([^/]+)$")
	return name or path
end

--- Returns the parent directory portion of a path.
---
--- ### Example:
--- ```luau
--- filesystem.dirName("/etc/hypr/hyprland.conf") -- Returns "/etc/hypr"
--- ```
---
--- @param path string Target file or directory path.
--- @return string Directory component (or `"."` if none found).
function filesystem.dirName(path: string): string
	local dir = string.match(path, "^(.*)/[^/]+$")
	if dir == "" then
		return "/"
	end
	return dir or "."
end

--- Resolves the file extension without the leading dot.
---
--- @param path string Target file path.
--- @return string File extension (or empty string if none).
function filesystem.extension(path: string): string
	return string.match(path, "%.([%w_]+)$") or ""
end

-- =============================================================================
-- File I/O API
-- =============================================================================

--- Checks whether a file or directory exists at the specified path.
---
--- @param path string Target file or directory path.
--- @return boolean True if the path exists.
function filesystem.exists(path: string): boolean
	local host: any = getHost()
	if host == nil or typeof(host.fileExists) ~= "function" then
		return false
	end
	local expanded = safeExpand(path)
	return (host.fileExists :: (string) -> boolean)(expanded) == true
end

--- Retrieves file metadata such as size, modification time, and directory status.
---
--- @param path string Target file path.
--- @return (FileInfo?, string?) Metadata record on success, or nil and error message.
function filesystem.fileInfo(path: string): (FileInfo?, string?)
	local host: any = getHost()
	if host == nil or typeof(host.fileInfo) ~= "function" then
		return nil, "Host fileInfo API unavailable"
	end
	local expanded = safeExpand(path)
	return (host.fileInfo :: (string) -> (FileInfo?, string?))(expanded)
end

--- Lists entry names within a directory.
---
--- @param path string Target directory path.
--- @return ({ string }?, string?) Array of entry names on success, or nil and error.
function filesystem.listDir(path: string): ({ string }?, string?)
	local host: any = getHost()
	if host == nil or typeof(host.listDir) ~= "function" then
		return nil, "Host listDir API unavailable"
	end
	local expanded = safeExpand(path)
	return (host.listDir :: (string) -> ({ string }?, string?))(expanded)
end

--- Reads an entire text file synchronously.
---
--- @param path string Path to the file.
--- @return (string?, string?) File content on success, or nil and error message.
function filesystem.readText(path: string): (string?, string?)
	local host: any = getHost()
	if host == nil or typeof(host.readFile) ~= "function" then
		return nil, "Host readFile API unavailable"
	end
	local expanded = safeExpand(path)
	return (host.readFile :: (string) -> (string?, string?))(expanded)
end

--- Writes content to a file, creating intermediate parent directories if required.
---
--- @param path string Destination file path.
--- @param content string Text content to write.
--- @return (boolean, string?) True on success, or false and error message.
function filesystem.writeText(path: string, content: string): (boolean, string?)
	local host: any = getHost()
	if host == nil or typeof(host.writeFile) ~= "function" then
		return false, "Host writeFile API unavailable"
	end

	local expanded = safeExpand(path)
	local parentDir = filesystem.dirName(expanded)

	if parentDir ~= "." and parentDir ~= "/" and typeof(host.mkdirAll) == "function" then
		pcall(function()
			(host.mkdirAll :: (string) -> (boolean, string?))(parentDir)
		end)
	end

	return (host.writeFile :: (string, string) -> (boolean, string?))(expanded, content)
end

-- =============================================================================
-- JSON Persistence API
-- =============================================================================

--- Reads and parses a JSON file into a typed Luau value.
---
--- ### Example:
--- ```luau
--- local cfg, err = filesystem.readJson("~/.config/my-plugin/data.json")
--- ```
---
--- @param path string Path to the JSON file.
--- @return (any?, string?) Parsed object on success, or nil and error message.
function filesystem.readJson(path: string): (any?, string?)
	local content, err = filesystem.readText(path)
	if not content then
		return nil, err
	end

	local host: any = getHost()
	if host == nil or host.json == nil or typeof(host.json.decode) ~= "function" then
		return nil, "Host JSON decoder unavailable"
	end

	local data, decodeErr = (host.json.decode :: (string) -> (any, string?))(content)
	if decodeErr then
		return nil, "JSON parse error: " .. tostring(decodeErr)
	end

	return data, nil
end

--- Serializes a value to JSON and writes it to disk.
---
--- @param path string Destination file path.
--- @param value any Lua table/value to encode.
--- @param pretty boolean? When true, formats output with indented whitespace (defaults to true).
--- @return (boolean, string?) True on success, or false and error message.
function filesystem.writeJson(path: string, value: any, pretty: boolean?): (boolean, string?)
	local host: any = getHost()
	if host == nil or host.json == nil or typeof(host.json.encode) ~= "function" then
		return false, "Host JSON encoder unavailable"
	end

	local isPretty = if pretty ~= nil then pretty else true
	local jsonStr, err = (host.json.encode :: (any, boolean?) -> (string?, string?))(value, isPretty)
	if not jsonStr then
		return false, "JSON encode error: " .. (err or "unknown")
	end

	return filesystem.writeText(path, jsonStr)
end

-- =============================================================================
-- Plugin State Persistence API
-- =============================================================================

--- Resolves the isolated persistent storage directory allocated for this plugin.
---
--- @return (string?, string?) Absolute directory path, or nil and error message.
function filesystem.getDataDir(): (string?, string?)
	local host: any = getHost()
	if host == nil or typeof(host.pluginDataDir) ~= "function" then
		return nil, "Host pluginDataDir API unavailable"
	end
	return (host.pluginDataDir :: () -> (string?, string?))()
end

--- Reads a JSON file from the plugin's dedicated persistent state directory.
---
--- @param fileName string Relative filename (e.g. `"bindings-cache.json"`).
--- @return (any?, string?) Parsed value, or nil and error message.
function filesystem.readPluginData(fileName: string): (any?, string?)
	local dir, err = filesystem.getDataDir()
	if not dir then
		return nil, err or "Could not resolve pluginDataDir"
	end
	return filesystem.readJson(filesystem.join(dir, fileName))
end

--- Writes a JSON file to the plugin's dedicated persistent state directory.
---
--- @param fileName string Relative filename (e.g. `"bindings-cache.json"`).
--- @param value any Lua table/value to serialize.
--- @param pretty boolean? Optional pretty formatting flag (defaults to false for cache payloads).
--- @return (boolean, string?) True on success, or false and error message.
function filesystem.writePluginData(fileName: string, value: any, pretty: boolean?): (boolean, string?)
	local dir, err = filesystem.getDataDir()
	if not dir then
		return false, err or "Could not resolve pluginDataDir"
	end
	return filesystem.writeJson(filesystem.join(dir, fileName), value, pretty)
end

-- =============================================================================
-- Test Injection Hook
-- =============================================================================

--- Injects a custom mock host bridge for headless unit tests. Passing nil restores default host.
---
--- @param mockHost FilesystemHost? Mock host table implementing file and JSON methods.
function filesystem.__setHost(mockHost: FilesystemHost?)
	injectedHost = mockHost
end

return filesystem
