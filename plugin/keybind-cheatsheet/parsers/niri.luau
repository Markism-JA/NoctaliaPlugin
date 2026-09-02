--!strict
-- Parser for Niri configuration files (.kdl)

local types = require("../types.luau")
local common = require("./common.luau")

type ParseContext = types.ParseContext

local niri = {}

function niri.categoryFor(action: string): string
	local value = common.lower(action)
	if common.startsWith(value, "spawn") then
		return "Applications & Launchers"
	end
	if common.startsWith(value, "focus-column-") or common.startsWith(value, "focus-window-") then
		return "Focus & Navigation"
	end
	if common.startsWith(value, "focus-workspace-") then
		return "Workspaces & Scratchpads"
	end
	if common.startsWith(value, "move-column-") or common.startsWith(value, "move-window-") then
		return "Window Management & Placement"
	end
	if common.startsWith(value, "screenshot") then
		return "Screen Toolkit & Capture Utilities"
	end
	if common.startsWith(value, "close-window") or common.startsWith(value, "fullscreen-window") then
		return "Window Management & Placement"
	end
	if common.startsWith(value, "power-off-monitors") or common.startsWith(value, "quit") then
		return "Shell & Desktop Controls"
	end
	return "Other"
end

function niri.parseContent(content: string, sourceFile: string, context: ParseContext)
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
			else
				local bindChord, actionBody = string.match(line, "^([^{]+)%s*{%s*(.-)%s*;?%s*}%s*$")
				if bindChord and actionBody then
					local cleanAction = common.trim((string.gsub(actionBody, ";+$", "")))
					local modifiers = common.normalizeModifiers(bindChord, nil)
					local key = string.match(bindChord, "([^+%s]+)$") or ""

					local category = common.buildCategory(currentSection, currentSubsection)
					if category == "General" then
						category = niri.categoryFor(cleanAction)
					end

					common.addBinding(context.bindings, {
						compositor = "niri",
						bindingType = "bind",
						modifiers = modifiers,
						key = key,
						action = cleanAction,
						description = "",
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

return niri
