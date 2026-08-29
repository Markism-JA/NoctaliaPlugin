-- !strict
local lifecycle = {}

export type ExitReason = "disable" | "uninstall" | "reload" | "shutdown"

--- Contract for background service entries.
export type ServiceLifecycle = {
	--- Periodic update callback invoked based on `noctalia.setUpdateInterval`.
	update: (() -> ())?,
	--- Called when the background service is initialized or enabled.
	onEnable: (() -> ())?,
	--- Called when a plugin setting or configuration changes.
	onConfigChanged: (() -> ())?,
	--- Called when an IPC event message is received by this service.
	onIpc: ((event: string, payload: string) -> ())?,
	--- Called when the service or plugin is terminating.
	onExit: ((signal: number, reason: ExitReason?) -> ())?,
}

--- Contract for pop-up panel surfaces.
export type PanelLifecycle = {
	--- Periodic update callback.
	update: (() -> ())?,
	--- Called when the panel view is opened.
	onOpen: ((context: string?) -> ())?,
	--- Called when the panel view is closed.
	onClose: (() -> ())?,
	--- Called on keyboard events while the panel has input focus.
	onKey: ((chord: string, pressed: boolean) -> ())?,
	--- Called on every display frame when `setNeedsFrameTick(true)` is enabled.
	onFrameTick: ((deltaMs: number) -> ())?,
	--- Called when an IPC event message is received.
	onIpc: ((event: string, payload: string) -> ())?,
	--- Called when the panel entry is terminating.
	onExit: ((signal: number, reason: ExitReason?) -> ())?,
}

--- Contract for bar widget entries.
export type WidgetLifecycle = {
	--- Periodic update callback.
	update: (() -> ())?,
	--- Called when the widget is clicked with the primary mouse button.
	onClick: (() -> ())?,
	--- Called when the widget is clicked with the secondary mouse button.
	onRightClick: (() -> ())?,
	--- Called when the widget is clicked with the middle mouse button.
	onMiddleClick: (() -> ())?,
	--- Called on mouse scroll wheel activity over the widget capsule.
	onScroll: ((axis: "vertical" | "horizontal", steps: number, startsGesture: boolean) -> ())?,
	--- Called when an IPC event message is received.
	onIpc: ((event: string, payload: string) -> ())?,
	--- Called when the widget entry is terminating.
	onExit: ((signal: number, reason: ExitReason?) -> ())?,
}

local function bind(hooks: { [string]: any })
	for name, fn in hooks do
		_G[name] = fn
	end
end

--- Registers background service lifecycle hooks.
function lifecycle.service(hooks: ServiceLifecycle)
	bind(hooks :: { [string]: any })
end

--- Registers panel UI surface lifecycle hooks.
function lifecycle.panel(hooks: PanelLifecycle)
	bind(hooks :: { [string]: any })
end

--- Registers bar widget lifecycle hooks.
function lifecycle.widget(hooks: WidgetLifecycle)
	bind(hooks :: { [string]: any })
end

return lifecycle
