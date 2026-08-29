--!strict
--- Declarative lifecycle binding utility for Noctalia plugin entrypoints.
--- Bridges typed contracts to the active Luau execution environment.
local lifecycle = {}

--- Valid termination reasons delivered to `onExit`.
export type ExitReason = "disable" | "uninstall" | "reload" | "shutdown"

-- =============================================================================
-- Discrete Callback Signatures (Enables direct LSP type hints and docstring hovers)
-- =============================================================================

--- Periodic update callback invoked based on `noctalia.setUpdateInterval`.
export type UpdateCallback = () -> ()

--- Called when the background service VM is initialized or enabled.
export type ServiceEnableCallback = () -> ()

--- Called when a declared plugin setting or configuration changes.
export type ConfigChangedCallback = () -> ()

--- Called when an IPC event message is received by this entry.
export type IpcCallback = (event: string, payload: string) -> ()

--- Called when the service or plugin surface is terminating.
export type ExitCallback = (signal: number, reason: ExitReason?) -> ()

--- Called when a panel UI view is opened. `context` contains optional payload from `panel-open`.
export type PanelOpenCallback = (context: string?) -> ()

--- Called when a panel UI view is closed.
export type PanelCloseCallback = () -> ()

--- Called on keyboard events while the panel has input focus for chords declared in `capture_keys`.
export type PanelKeyCallback = (chord: string, pressed: boolean) -> ()

--- Called on every display frame when `panel.setNeedsFrameTick(true)` is active.
export type PanelFrameTickCallback = (deltaMs: number) -> ()

--- Called when a widget capsule is clicked with the primary mouse button.
export type WidgetClickCallback = () -> ()

--- Called on mouse scroll wheel activity over a widget capsule.
export type WidgetScrollCallback = (axis: "vertical" | "horizontal", steps: number, startsGesture: boolean) -> ()

-- =============================================================================
-- Entry Lifecycle Contracts
-- =============================================================================

--- Contract for background service entries (`[[service]]`).
export type ServiceLifecycle = {
	--- Periodic update callback invoked based on `noctalia.setUpdateInterval`.
	update: UpdateCallback?,
	--- Called when the background service VM is initialized or enabled.
	onEnable: ServiceEnableCallback?,
	--- Called when a declared plugin setting or configuration changes.
	onConfigChanged: ConfigChangedCallback?,
	--- Called when an IPC event message is received by this service.
	onIpc: IpcCallback?,
	--- Called when the service or plugin is terminating.
	onExit: ExitCallback?,
}

--- Contract for pop-up panel UI surfaces (`[[panel]]`).
export type PanelLifecycle = {
	--- Periodic update callback.
	update: UpdateCallback?,
	--- Called when the panel view is opened. `context` contains optional payload from `panel-open`.
	onOpen: PanelOpenCallback?,
	--- Called when the panel view is closed.
	onClose: PanelCloseCallback?,
	--- Called on keyboard events while the panel has input focus for chords declared in `capture_keys`.
	onKey: PanelKeyCallback?,
	--- Called on every display frame when `panel.setNeedsFrameTick(true)` is active.
	onFrameTick: PanelFrameTickCallback?,
	--- Called when an IPC event message is dispatched to this panel.
	onIpc: IpcCallback?,
	--- Called when the panel surface is terminating or reloading.
	onExit: ExitCallback?,
}

--- Contract for bar widget entries (`[[widget]]`).
export type WidgetLifecycle = {
	--- Periodic update callback invoked on `noctalia.setUpdateInterval`.
	update: UpdateCallback?,
	--- Called when the widget capsule is clicked with the primary mouse button.
	onClick: WidgetClickCallback?,
	--- Called when the widget capsule is clicked with the secondary mouse button.
	onRightClick: WidgetClickCallback?,
	--- Called when the widget capsule is clicked with the middle mouse button.
	onMiddleClick: WidgetClickCallback?,
	--- Called on mouse scroll wheel activity over the widget capsule.
	onScroll: WidgetScrollCallback?,
	--- Called when an IPC event message is received by this widget.
	onIpc: IpcCallback?,
	--- Called when the widget is terminating or reloading.
	onExit: ExitCallback?,
}

-- =============================================================================
-- Environment Reflection Binder
-- =============================================================================

--- Internal binder that reflects hooks directly into the target chunk environment table.
local function bind(env: { [string]: any }, hooks: { [string]: any })
	for name, fn in pairs(hooks) do
		if fn ~= nil then
			env[name] = fn
			if (rawget :: any) ~= nil and (rawset :: any) ~= nil then
				rawset(_G, name, fn)
			else
				_G[name] = fn
			end
		end
	end
end

--- Registers typed background service lifecycle hooks into the target chunk environment.
--- Pass `getfenv()` as the first parameter.
function lifecycle.service(env: { [string]: any }, hooks: ServiceLifecycle)
	bind(env, hooks :: { [string]: any })
end

--- Registers typed panel UI surface lifecycle hooks into the target chunk environment.
--- Pass `getfenv()` as the first parameter.
function lifecycle.panel(env: { [string]: any }, hooks: PanelLifecycle)
	bind(env, hooks :: { [string]: any })
end

--- Registers typed bar widget lifecycle hooks into the target chunk environment.
--- Pass `getfenv()` as the first parameter.
function lifecycle.widget(env: { [string]: any }, hooks: WidgetLifecycle)
	bind(env, hooks :: { [string]: any })
end

return lifecycle
