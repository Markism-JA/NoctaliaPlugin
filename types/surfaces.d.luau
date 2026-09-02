--!strict
-- =============================================================================
-- Noctalia Surface Controllers & Host Surface Injections
-- =============================================================================

--- Classification variant for an entry within a native context menu.
--- - `"item"`: Standard interactive, clickable menu action item.
--- - `"header"`: Non-interactive section header row for grouping entries.
--- - `"separator"`: Visual horizontal rule dividing distinct action clusters.
export type ContextMenuItemKind = "item" | "header" | "separator"

--- Single menu entry descriptor passed to `panel.openContextMenu`.
--- @since API 28
export type ContextMenuItem = {
    --- Entry classification. Defaults to `"item"` when omitted.
    kind: ContextMenuItemKind?,

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
    --- Unique result identifier used for activation tracking and deduplication.
    id: string,

    --- Primary title text displayed on the search result row.
    title: string,

    --- Secondary description or subtitle metadata displayed under the title.
    subtitle: string?,

    --- Vector glyph icon name (Tabler / Nerd-Font) displayed beside the title.
    glyph: string?,

    --- Local or theme icon path displayed beside the title.
    icon: string?,

    --- Short category tag or status badge text displayed on the right edge.
    badge: string?,

    --- Exact search query term or command line associated with this result.
    query: string?,

    --- Relevance ranking score used for search sorting (higher values appear first).
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
    --- Sets the text displayed inside the bar capsule.
    setText: (text: string) -> (),

    --- Sets the vector icon glyph displayed inside the bar capsule.
    setGlyph: (glyph: string) -> (),

    --- Sets the local image path displayed inside the bar capsule.
    setImage: (path: string) -> (),

    --- Displays a hover tooltip string when pointing over the bar widget capsule.
    setTooltip: (tip: string) -> (),

    --- Removes any configured hover tooltip from the bar widget capsule.
    clearTooltip: () -> (),

    --- Configures the font family and baseline alignment for the label text.
    setFont: (family: string, baseline: UiBaseline?) -> (),

    --- Sets the text and background tint color token or hex string.
    setColor: (color: string) -> (),

    --- Sets the icon glyph stroke color token or hex string.
    setGlyphColor: (color: string) -> (),

    --- Toggles whether the bar widget capsule is visible on the bar surface.
    setVisible: (visible: boolean) -> (),

    --- Returns whether the host bar is oriented vertically instead of horizontally.
    isVertical: () -> boolean,

    --- Returns the DRM connector name of the monitor displaying this bar widget instance.
    outputName: () -> string?,

    --- Replaces the built-in imperative label/glyph row with a declarative `ui.*` tree.
    --- @since API 3
    render: (tree: UiNode) -> (),
}

--- Surface controller for Control Center quick-action shortcut tiles.
export type Shortcut = {
    --- Sets the user-visible label displayed below the shortcut tile icon.
    setLabel: (text: string) -> (),

    --- Sets the icon glyph paths or identifiers for both the active and inactive toggle states.
    setIcon: (on: string, off: string?) -> (),

    --- Toggles the active highlight state of the shortcut tile.
    setActive: (bool: boolean) -> (),

    --- Enables or disables user interaction with the shortcut tile.
    setEnabled: (bool: boolean) -> (),
}

--- Surface controller for application launcher search provider entries.
export type Launcher = {
    --- Delivers a list of search matches back to the launcher UI for a given query string.
    setResults: (query: string, results: { LauncherResult }) -> (),

    --- Updates the active search query input string in the launcher search bar.
    setQuery: (query: string) -> (),
}

declare panel: Panel;
declare desktopWidget: DesktopWidget;
declare barWidget: BarWidget;
declare shortcut: Shortcut;
declare launcher: Launcher;
