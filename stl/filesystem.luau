--!strict
--- Safe synchronous & persistent filesystem operations.
local filesystem = {}

--- Joins path segments using POSIX slashes.
function filesystem.join(...: string): string
	local parts = { ... }
	local cleanParts: { string } = {}
	for _, part in ipairs(parts) do
		if part ~= "" then
			table.insert(cleanParts, part)
		end
	end
	return table.concat(cleanParts, "/")
end

--- Returns the base filename from a path.
function filesystem.baseName(path: string): string
	local name = string.match(path, "([^/]+)$")
	return name or path
end

--- Returns the directory portion of a path.
function filesystem.dirName(path: string): string
	local dir = string.match(path, "^(.*)/[^/]+$")
	return dir or "."
end

--- Reads an entire text file synchronously.
function filesystem.readText(path: string): (string?, string?)
	local expanded = noctalia.expandPath(path)
	return noctalia.readFile(expanded)
end

--- Writes content to a file, recursively creating parent directories if missing.
function filesystem.writeText(path: string, content: string): (boolean, string?)
	local expanded = noctalia.expandPath(path)
	local parentDir = filesystem.dirName(expanded)

	if parentDir ~= "." and not noctalia.fileExists(parentDir) then
		local ok, err = noctalia.mkdirAll(parentDir)
		if not ok then
			return false, err
		end
	end

	return noctalia.writeFile(expanded, content)
end

--- Reads and decodes a JSON file directly into a Lua table/value.
function filesystem.readJson(path: string): (any?, string?)
	local content, err = filesystem.readText(path)
	if not content then
		return nil, err
	end

	local data, decodeErr = noctalia.json.decode(content)
	if decodeErr then
		return nil, "JSON parse error: " .. decodeErr
	end

	return data, nil
end

--- Serializes a value to JSON and writes it to disk.
function filesystem.writeJson(path: string, value: any, pretty: boolean?): (boolean, string?)
	local jsonStr, err = noctalia.json.encode(value, if pretty ~= nil then pretty else true)
	if not jsonStr then
		return false, "JSON encode error: " .. (err or "unknown")
	end

	return filesystem.writeText(path, jsonStr)
end

--- Returns the persistent storage directory for this plugin.
function filesystem.getDataDir(): (string?, string?)
	return noctalia.pluginDataDir()
end

--- Reads a JSON file from the plugin's persistent state directory.
function filesystem.readPluginData(fileName: string): (any?, string?)
	local dir, err = filesystem.getDataDir()
	if not dir then
		return nil, err
	end
	return filesystem.readJson(filesystem.join(dir, fileName))
end

--- Writes a JSON file to the plugin's persistent state directory.
function filesystem.writePluginData(fileName: string, value: any, pretty: boolean?): (boolean, string?)
	local dir, err = filesystem.getDataDir()
	if not dir then
		return false, err
	end
	return filesystem.writeJson(filesystem.join(dir, fileName), value, pretty)
end

return filesystem
