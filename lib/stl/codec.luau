local host = require("./host.luau")

local codec = {}

function codec.jsonDecode(raw: string): (any?, string?)
	local currentHost = host.get()
	if currentHost == nil or currentHost.json == nil or typeof(currentHost.json.decode) ~= "function" then
		return nil, "Host JSON decoder unavailable"
	end
	return currentHost.json.decode(raw)
end

function codec.jsonEncode(val: any, pretty: boolean?): (string?, string?)
	local currentHost = host.get()
	if currentHost == nil or currentHost.json == nil or typeof(currentHost.json.encode) ~= "function" then
		return nil, "Host JSON encoder unavailable"
	end
	return currentHost.json.encode(val, pretty)
end

return codec
