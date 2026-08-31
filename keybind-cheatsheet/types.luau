--!strict
-- Shared data contracts for keybind-cheatsheet

export type Compositor = "mango" | "hyprland" | "niri"
export type ParserKind = "mango" | "niri" | "hypr-lua" | "hypr-conf"

export type BindingRequest = {
	compositor: Compositor,
	parser: ParserKind,
	root: string,
}

export type BindingEntry = {
	id: string,
	compositor: Compositor,
	bindingType: string,
	modifiers: { string },
	key: string,
	action: string,
	description: string,
	section: string,
	subsection: string,
	category: string,
	baseCategory: string,
	sourceFile: string,
	sourceLine: number,
	submap: string?,
}

export type SourceSnapshot = {
	path: string,
	size: number,
	mtime: number,
}

export type CachePayload = {
	schema: number,
	request: BindingRequest,
	bindings: { BindingEntry },
	warnings: { string },
	sources: { SourceSnapshot },
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

export type ScanRule = {
	section: string,
	subsection: string,
	category: string,
}

export type PatternRule = {
	pattern: string,
	section: string,
	subsection: string,
	category: string,
}

export type ParseContext = {
	bindings: { BindingEntry },
	variables: { [string]: string },
	warnings: { string },
	sources: { SourceSnapshot },
	exactRules: { [string]: ScanRule },
	patternRules: { PatternRule },
}

export type JsonDecodeFn = (string) -> (any, string?)

return {}
