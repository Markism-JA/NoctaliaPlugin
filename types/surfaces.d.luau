--!nocheck
-- =============================================================================
-- Noctalia Surface Controllers & Host Surface Injections
-- =============================================================================

--- Single menu entry descriptor passed to `panel.openContextMenu`.
--- @since API 28
export type ContextMenuItem = {
    --- Entry classification. Defaults to `"item"` when omitted.
    kind: ("item" | "header" | "separator")?,

    --- Unique string identifier for action dispatch. Required for clickable `"item"` rows (Max 128 bytes).
    id: string?,

    --- Display text label rendered on the menu item or section header (Max 512 bytes).
    label: string?,

    --- Interaction availability flag. Defaults to `true` when omitted.
    enabled: boolean?,
}

--- Parameter payload for opening a native context menu anchored to the triggering pointer position.
--- Must be invoked synchronously inside a `ui.button`'s `onRightClick` callback.
--- @since API 28
export type ContextMenuRequest = {
    --- Ordered list of menu entries (1 to 64 items; must contain at least one enabled action).
    items: { ContextMenuItem },

    --- Global panel callback function name receiving `(actionId: string, context?: string | number | boolean)`.
    onActivate: string,

    --- Optional scalar payload forwarded to `onActivate` alongside the chosen `actionId`.
    context: (string | number | boolean)?,

    --- Maximum visible menu items before scrolling activates (clamped to 1 - 30; defaults to 12).
    maxVisible: number?,
}

--- Search result item returned by an application launcher provider.
export type LauncherResult = {
    id: string,
    title: string,
    subtitle: string?,
    glyph: string?,
    icon: string?,
    badge: string?,
    query: string?,
    score: number?,
}

--- Surface controller for pop-up panel instances.
export type Panel = {
    --- Commits a declarative virtual UI node tree to the panel surface for reconciler diffing.
    --- @since API 3
    render: (tree: UiNode) -> (),

    --- Dismisses and closes this panel instance.
    --- @since API 3
    close: () -> (),

    --- Displays a native, theme-aware context menu at the pointer position during a right-click event.
    --- @since API 28
    openContextMenu: (request: ContextMenuRequest) -> boolean,

    --- Requests that `update()` be executed on synchronized whole-second wall-clock boundaries.
    --- @since API 3
    setWantsSecondTicks: (bool: boolean) -> (),

    --- Subscribes to per-frame `onFrameTick(deltaMs)` callbacks for smooth script-driven animations.
    --- @since API 18
    setNeedsFrameTick: (bool: boolean) -> (),
}

--- Surface controller for persistent desktop widget instances.
export type DesktopWidget = {
    --- Commits a declarative virtual UI node tree to the desktop widget surface for reconciler diffing.
    --- @since API 3
    render: (tree: UiNode) -> (),

    --- Requests that `update()` be executed on synchronized whole-second wall-clock boundaries.
    --- @since API 3
    setWantsSecondTicks: (bool: boolean) -> (),

    --- Subscribes to per-frame `onFrameTick(deltaMs)` animation updates while the widget is visible.
    --- @since API 18
    setNeedsFrameTick: (bool: boolean) -> (),
}

--- Surface controller for status bar widget capsules.
export type BarWidget = {
    setText: (text: string) -> (),
    setGlyph: (glyph: string) -> (),
    setImage: (path: string) -> (),
    setTooltip: (tip: string) -> (),
    clearTooltip: () -> (),
    setFont: (family: string, baseline: ("text" | "textFixedHeight" | "inkCentered" | "pictographic")?) -> (),
    setColor: (color: string) -> (),
    setGlyphColor: (color: string) -> (),
    setVisible: (visible: boolean) -> (),
    isVertical: () -> boolean,
    outputName: () -> string?,

    --- Replaces the built-in imperative label/glyph row with a declarative `ui.*` tree.
    --- @since API 3
    render: (tree: UiNode) -> (),
}

--- Surface controller for Control Center quick-action shortcut tiles.
export type Shortcut = {
    setLabel: (text: string) -> (),
    setIcon: (on: string, off: string?) -> (),
    setActive: (bool: boolean) -> (),
    setEnabled: (bool: boolean) -> (),
}

--- Surface controller for application launcher search provider entries.
export type Launcher = {
    setResults: (query: string, results: { LauncherResult }) -> (),
    setQuery: (query: string) -> (),
}

declare panel: Panel
declare desktopWidget: DesktopWidget
declare barWidget: BarWidget
declare shortcut: Shortcut
declare launcher: Launcher
