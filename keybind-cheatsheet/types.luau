--!strict
-- Shared types & interfaces for keybind-cheatsheet

export type Compositor = "mango" | "hyprland" | "niri" | "auto" | string

export type ModifierPill = {
	text: string,
	bucket: string,
}

export type BindingEntry = {
	id: string,
	compositor: string,
	bindingType: string,
	modifiers: { string },
	key: string,
	action: string,
	description: string,
	section: string,
	subsection: string,
	category: string,
	baseCategory: string?,
	sourceFile: string,
	sourceLine: number,
	submap: string?,

	-- Display index for UI occurrences
	displayIndex: number?,

	-- Pre-calculated display & search fields (Service VM -> Panel VM)
	formattedKey: string,
	keyBucket: string,
	modPills: { ModifierPill },
	displayDescription: string,
	searchIndex: string,
}

export type ScanRule = {
	section: string,
	subsection: string,
	category: string,
}

export type PatternRule = {
	literalNeedles: { string },
	section: string,
	subsection: string,
	category: string,
}

export type ParseContext = {
	bindings: { BindingEntry },
	variables: { [string]: string },
	warnings: { string },
	sources: { { path: string, size: number, mtime: number } },
	exactRules: { [string]: ScanRule },
	patternRules: { PatternRule },
}

export type BindingRequest = {
	compositor: string,
	parser: string,
	root: string,
}

export type CachePayload = {
	schema: number,
	request: BindingRequest,
	bindings: { BindingEntry },
	warnings: { string },
	sources: { { path: string, size: number, mtime: number } },
}

export type SnapshotState = {
	schema: number,
	status: "ready" | "loading" | "error",
	compositor: string,
	parser: string,
	source: string,
	request: BindingRequest?,
	bindings: { BindingEntry },
	warnings: { string },
	error: string,
	refreshing: boolean,
}

export type JsonDecodeFn = (str: string) -> (any?, string?)

return {}
