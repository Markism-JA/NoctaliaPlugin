--!strict
-- Parser for Mango configuration files (.conf)

local types = require("../types.luau")
local common = require("./common.luau")

type ParseContext = types.ParseContext

local mango = {}

function mango.parseContent(content: string, sourceFile: string, context: ParseContext)
	local currentSection = "General"
	local currentSubsection = ""
	local lineNumber = 0

	for rawLine in string.gmatch(content, "[^\r\n]+") do
		lineNumber += 1
		local line = common.trim(rawLine)
		if line ~= "" then
			local heading = common.parseHeading(line)
			if heading then
				if heading.level == 1 then
					currentSection = heading.title
					currentSubsection = ""
				elseif heading.level == 2 then
					currentSubsection = heading.title
				end
			elseif string.find(line, "bind", 1, true) ~= nil then
				local clean, description = common.extractTrailingDescription(line)
				local directive, body = string.match(clean, "^([%a]*bind[%a]*)%s*=%s*(.*)$")
				if directive ~= nil and body ~= nil then
					local fields = common.splitCsv(body)
					local modifiers = common.normalizeModifiers(fields[1], nil)
					local key = fields[2] or ""
					local command = fields[3] or ""

					local restParts: { string } = {}
					for i = 4, #fields do
						if fields[i] ~= "" then
							table.insert(restParts, fields[i])
						end
					end
					local parameters = table.concat(restParts, " ")

					if key ~= "" and command ~= "" then
						local category = common.buildCategory(currentSection, currentSubsection)
						if category == "General" and description == "" then
							category = common.fallbackCategory(command, parameters, description)
						end

						local action = if parameters ~= "" then (command .. " " .. parameters) else command

						common.addBinding(context.bindings, {
							compositor = "mango",
							bindingType = common.lower(directive),
							modifiers = modifiers,
							key = key,
							action = action,
							description = description,
							section = currentSection,
							subsection = currentSubsection,
							category = category,
							sourceFile = sourceFile,
							sourceLine = lineNumber,
						})
					end
				end
			end
		end
	end
end

return mango
