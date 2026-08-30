--!strict
--- Declarative lifecycle binding utility for Noctalia plugin entrypoints.
---
--- Bridges typed callback contracts to the active Luau execution environment
--- (Services, Panels, and Bar Widgets) with safe global binding and test unbinding.
local lifecycle = {}

-- =============================================================================
-- Types & Contracts
-- =============================================================================

--- Valid termination reasons delivered to `onExit`.
export type ExitReason = "disable" | "uninstall" | "reload" | "shutdown"

-- =============================================================================
-- Discrete Callback Signatures
-- =============================================================================

--- Periodic update callback invoked based on `noctalia.setUpdateInterval`.
export type UpdateCallback = () -> ()

--- Called when the background service VM is initialized or enabled.
export type ServiceEnableCallback = () -> ()

--- Called when a declared plugin setting or configuration changes.
export type ConfigChangedCallback = () -> ()

--- Called when an IPC event message is received by this entry.
---
--- @param event string Event identifier or action name.
--- @param payload string Raw serialized message payload.
export type IpcCallback = (event: string, payload: string) -> ()

--- Called when the service or plugin surface is terminating.
---
--- @param signal number Process or OS termination signal.
--- @param reason ExitReason? Structured exit reason string.
export type ExitCallback = (signal: number, reason: ExitReason?) -> ()

--- Called when a panel UI view is opened.
---
--- @param context string? Optional payload string passed via `panel-open`.
export type PanelOpenCallback = (context: string?) -> ()

--- Called when a panel UI view is closed.
export type PanelCloseCallback = () -> ()

--- Called on keyboard events while the panel has input focus for chords declared in `capture_keys`.
---
--- @param chord string Key combination or chord string (e.g. "Escape", "Control+f").
--- @param pressed boolean True if keydown, false if keyup.
export type PanelKeyCallback = (chord: string, pressed: boolean) -> ()

--- Called on every display frame when `panel.setNeedsFrameTick(true)` is active.
---
--- @param deltaMs number Milliseconds elapsed since the previous display frame.
export type PanelFrameTickCallback = (deltaMs: number) -> ()

--- Called when a widget capsule is clicked with mouse buttons.
export type WidgetClickCallback = () -> ()

--- Called on mouse scroll wheel activity over a widget capsule.
---
--- @param axis "vertical" | "horizontal" Scroll direction axis.
--- @param steps number Number of scroll increments.
--- @param startsGesture boolean True if this event initiated a new touchpad/wheel gesture.
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
-- Internal State & Helpers
-- =============================================================================

--- Tracks active registered handler functions for inspection in tests.
local activeHandlers: { [string]: any } = {}

local ALL_HOOK_SYMBOLS: { string } = {
	"update",
	"onEnable",
	"onConfigChanged",
	"onIpc",
	"onExit",
	"onOpen",
	"onClose",
	"onKey",
	"onFrameTick",
	"onClick",
	"onRightClick",
	"onMiddleClick",
	"onScroll",
}

--- Internal binder that reflects hooks directly into the target chunk environment table.
local function bind(env: { [string]: any }, hooks: { [string]: any })
	if env == nil then
		return
	end

	local gTable = _G :: any

	for name, fn in pairs(hooks) do
		if fn ~= nil then
			activeHandlers[name] = fn
			env[name] = fn

			if gTable ~= nil then
				if (rawset :: any) ~= nil then
					(rawset :: any)(gTable, name, fn)
				else
					gTable[name] = fn
				end
			end
		end
	end
end

--- Internal unbinder that clears registered hooks from environment tables.
local function unbindHooks(env: { [string]: any }, hookNames: { string })
	if env == nil then
		return
	end

	local gTable = _G :: any

	for _, name in ipairs(hookNames) do
		activeHandlers[name] = nil
		env[name] = nil

		if gTable ~= nil then
			if (rawset :: any) ~= nil then
				(rawset :: any)(gTable, name, nil)
			else
				gTable[name] = nil
			end
		end
	end
end

-- =============================================================================
-- Public API
-- =============================================================================

--- Registers typed background service lifecycle hooks into the target chunk environment.
---
--- ### Example:
--- ```luau
--- lifecycle.service(getfenv(), {
---     onEnable = function()
---         bootstrap()
---     end,
---     onIpc = function(event, payload)
---         if event == "reload" then refresh() end
---     end,
---     onExit = function(_signal, _reason)
---         cleanup()
---     end,
--- })
--- ```
---
--- @param env { [string]: any } Target chunk environment table (`getfenv()`).
--- @param hooks ServiceLifecycle Table of service callback implementations.
function lifecycle.service(env: { [string]: any }, hooks: ServiceLifecycle)
	bind(env, hooks :: { [string]: any })
end

--- Registers typed panel UI surface lifecycle hooks into the target chunk environment.
---
--- ### Example:
--- ```luau
--- lifecycle.panel(getfenv(), {
---     onOpen = function(context)
---         view.reset()
---     end,
---     onKey = function(chord, pressed)
---         if chord == "Escape" and pressed then panel.close() end
---     end,
--- })
--- ```
---
--- @param env { [string]: any } Target chunk environment table (`getfenv()`).
--- @param hooks PanelLifecycle Table of panel callback implementations.
function lifecycle.panel(env: { [string]: any }, hooks: PanelLifecycle)
	bind(env, hooks :: { [string]: any })
end

--- Registers typed bar widget lifecycle hooks into the target chunk environment.
---
--- ### Example:
--- ```luau
--- lifecycle.widget(getfenv(), {
---     onClick = function()
---         proc.spawn("noctalia msg panel-toggle launcher")
---     end,
---     update = function()
---         renderCapsule()
---     end,
--- })
--- ```
---
--- @param env { [string]: any } Target chunk environment table (`getfenv()`).
--- @param hooks WidgetLifecycle Table of widget callback implementations.
function lifecycle.widget(env: { [string]: any }, hooks: WidgetLifecycle)
	bind(env, hooks :: { [string]: any })
end

--- Clears all standard lifecycle hook symbols from the given environment and `_G`.
---
--- Useful during unit test teardown (`afterEach`) to prevent hook leakage across tests.
---
--- @param env { [string]: any } Target chunk environment table (`getfenv()`).
function lifecycle.unbind(env: { [string]: any })
	unbindHooks(env, ALL_HOOK_SYMBOLS)
end

--- Test inspection helper returning a read-only table of currently registered handlers.
---
--- @return { [string]: any } Map of active lifecycle callback functions.
function lifecycle.__getActiveHandlers(): { [string]: any }
	return table.clone(activeHandlers)
end

-- =============================================================================
-- Test Injection Hook
-- =============================================================================

--- Injects or clears the mock host instance for testing, resetting all registered handlers.
---
--- @param _mockHost any? Mock host table or nil on teardown.
function lifecycle.__setHost(_mockHost: any?)
	table.clear(activeHandlers)
	lifecycle.unbind(getfenv())
end

return lifecycle
