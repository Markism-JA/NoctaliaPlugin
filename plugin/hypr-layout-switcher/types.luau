--!strict
-- Shared type definitions for hypr-layout-switcher

export type MonitorSlice = {
	workspaceId: any,
	workspaceName: string,
	layout: string,
	focused: boolean,
}

export type TopologyState = {
	focusedOutput: string,
	focusedLayout: string,
	monitors: { [string]: MonitorSlice },
}

export type LayoutOption = {
	id: string,
	name: string,
	badge: string,
	glyph: string,
	description: string,
	shortcut: string,
}

return {}
