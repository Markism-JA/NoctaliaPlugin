-- definitions.d.luau
--!nocheck

-- =============================================================================
-- System Stats & Hardware Types
-- =============================================================================

--- CPU performance, load, and temperature metrics.
--- @since API 12
export type SystemCpu = {
    --- Aggregate CPU busy percentage (0-100).
    usagePercent: number,
    --- CPU package temperature in Celsius. Nil when no sensor is found.
    tempC: number?,
    --- Average current CPU frequency in MHz.
    freqMhz: number?,
    --- Highest detected CPU frequency ceiling in MHz.
    maxFreqMhz: number?,
}

--- System memory usage snapshot.
--- @since API 12
export type SystemRam = {
    usagePercent: number,
    usedMb: number,
    totalMb: number,
}

--- System swap memory usage snapshot.
--- @since API 12
export type SystemSwap = {
    usedMb: number,
    totalMb: number,
}

--- Dedicated GPU temperature, load, and VRAM utilization metrics.
--- @since API 12
export type SystemGpu = {
    tempC: number?,
    usagePercent: number?,
    vramUsedBytes: number?,
    vramTotalBytes: number?,
}

--- Real-time network throughput and interface activity.
--- @since API 12
export type SystemNet = {
    rxBytesPerSec: number,
    txBytesPerSec: number,
    --- Per-interface bandwidth consumption.
    --- @since API 16
    interfaces: { [string]: { rxBytesPerSec: number, txBytesPerSec: number } }?,
}

--- Snapshot of the host's system hardware monitor.
--- @since API 12
export type SystemStats = {
    --- Unix epoch milliseconds for the latest aggregate sample.
    --- @since API 16
    sampledAtMs: number?,
    cpu: SystemCpu,
    ram: SystemRam,
    swap: SystemSwap,
    gpu: SystemGpu,
    net: SystemNet,
    --- 1, 5, and 15 minute system load averages.
    loadAvg: { number },
}

--- Physical block-device-backed filesystem.
--- @since API 16
export type DiskMount = {
    path: string,
    source: string,
    filesystem: string,
}

--- Storage volume usage and capacity metrics.
--- @since API 16
export type DiskStats = {
    usagePercent: number,
    totalBytes: number,
    freeBytes: number,
    availableBytes: number,
}

-- =============================================================================
-- Async Execution & HTTP Types
-- =============================================================================

--- Subprocess execution outcome and captured streams.
export type AsyncResult = {
    exitCode: number,
    stdout: string,
    stderr: string,
    timedOut: boolean,
    stdoutTruncated: boolean?,
    stderrTruncated: boolean?,
}

--- Configuration table for async HTTP requests.
export type HttpRequest = {
    url: string,
    method: string?,
    body: string?,
    headers: { string }?,
    basic_username: string?,
    basic_password: string?,
    follow_redirects: boolean?,
    --- Disables certificate-chain and hostname verification.
    --- @since API 7
    allow_insecure_tls: boolean?,
}

--- Response payload from an async HTTP request.
export type HttpResponse = {
    ok: boolean,
    status: number,
    body: string,
}

--- Control handle for long-lived HTTP streams (e.g. SSE).
--- @since API 4
export type HttpStreamHandle = {
    --- Cancels the active HTTP stream. Idempotent; suppresses `onClose`.
    stop: () -> (),
}

--- Display output geometry and scale description.
export type OutputInfo = {
    name: string,
    description: string?,
    width: number,
    height: number,
    x: number,
    y: number,
    scale: number,
    focused: boolean,
}

--- Filesystem metadata entry.
export type FileInfo = {
    size: number,
    mtime: number,
    isDir: boolean,
}

-- =============================================================================
-- Context Menus & Launcher Types
-- =============================================================================

--- Single menu entry in a context menu request.
--- @since API 28
export type ContextMenuItem = {
    kind: ("item" | "header" | "separator")?,
    id: string?,
    label: string?,
    enabled: boolean?,
}

--- Request parameters for opening a native context menu.
--- @since API 28
export type ContextMenuRequest = {
    items: { ContextMenuItem },
    onActivate: string,
    context: (string | number | boolean)?,
    maxVisible: number?,
}

--- Candidate item returned by a launcher search provider.
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

-- =============================================================================
-- Noctalia Host Bridge (noctalia.*)
-- =============================================================================

--- Primary host interface for system, shell, and runtime capabilities.
export type Noctalia = {
    --- Sets how often this entry's `update()` lifecycle function runs. Values below 16 ms are clamped.
    --- @since API 3
    setUpdateInterval: (ms: number) -> (),

    --- Writes a message to Noctalia's shell log scoped with this plugin's script context.
    --- @since API 3
    log: (msg: string) -> (),

    --- Returns whether the active shell theme mode is dark.
    --- @since API 3
    isDarkMode: () -> boolean,

    --- Reads any effective shell config value by TOML dotted path.
    --- @since API 26
    getSetting: (path: string) -> any,

    --- Returns the focused output's DRM connector name, falling back to the interactive output.
    --- @since API 3
    focusedOutputName: () -> string?,

    --- Reads a declared plugin or entry setting from `plugin.toml`.
    --- @since API 3
    getConfig: (key: string) -> any,

    --- Returns connected outputs as `{ name, description, width, height, x, y, scale, focused }` tables.
    --- @since API 3
    outputs: () -> { OutputInfo },

    --- Enables or disables Noctalia's own wallpaper surface on one DRM connector.
    --- @since API 3
    setWallpaperEnabled: (connector: string, enabled: boolean) -> (),

    --- Applies and persists a wallpaper image across all outputs or on a specific DRM connector.
    --- @since API 3
    setWallpaper: ((path: string) -> ()) & ((connector: string, path: string) -> ()),

    --- Returns the resolved wallpaper folder for the current theme mode, or nil when unset.
    --- @since API 3
    wallpaperDirectory: () -> string?,

    --- Returns the exact wallpaper source configured for an output.
    --- @since API 25
    wallpaperPath: (connector: string) -> string?,

    --- Applies or clears a source-aligned grayscale occlusion mask to desktop-widget surfaces on an output.
    --- @since API 25
    setWallpaperMask: (connector: string, mask: { path: string, wallpaperPath: string }?) -> (),

    --- Opens or closes a plugin panel by full entry ID (e.g. `"author/plugin:panel"`).
    --- @since API 3
    togglePanel: (id: string) -> (),

    --- Opens the shell settings window focused on this plugin's configuration page.
    --- @since API 15
    openSettings: () -> (),

    --- Opens the system color picker with an initial `#RRGGBB` hex color.
    --- @since API 3
    openColorPicker: (initialColor: string, onClose: (color: string?) -> ()) -> boolean,

    --- Resolves an application ID to a localized icon file path using XDG icon themes.
    --- @since API 3
    appIconPath: (appId: string, sizePx: number?) -> string?,

    --- Formats local or timezone-aware time using standard Noctalia clock tokens.
    --- @since API 19 (Timezone support), API 3 (Base)
    formatTime: ((pattern: string) -> string)
        & ((pattern: string, unixSeconds: number?) -> string)
        & ((pattern: string, unixSeconds: number?, timezone: string?) -> string),

    --- Returns the active `[shell].time_format` setting.
    --- @since API 19
    timeFormat: () -> string,

    --- Returns the active `[shell].date_format` setting.
    --- @since API 19
    dateFormat: () -> string,

    --- Validates whether a given string is a known IANA timezone name.
    --- @since API 19
    isValidTimezone: (name: string) -> boolean,

    --- Returns wall-clock milliseconds elapsed since the Unix epoch.
    --- @since API 12
    nowMs: () -> number,

    --- Displays an informational system notification popup.
    --- @since API 3
    notify: (title: string, body: string?) -> (),

    --- Displays an error system notification popup.
    --- @since API 3
    notifyError: (title: string, body: string?) -> (),

    --- Copies text content to the clipboard with an explicit MIME type.
    --- @since API 3
    copyToClipboard: (text: string, mime: string) -> boolean,

    --- Retrieves current plain-text clipboard content.
    --- @since API 3
    clipboardText: () -> string?,

    --- Retrieves an aggregated snapshot from the host's system hardware monitor.
    --- @since API 12
    systemStats: () -> SystemStats?,

    --- Retrieves per-core CPU usage percentages. Requires opting into `/proc/stat` background polling.
    --- @since API 12
    cpuCores: () -> { number }?,

    --- Lists physical block-device filesystems available for disk statistics polling.
    --- @since API 16
    diskMounts: () -> { DiskMount },

    --- Retrieves storage usage statistics for an absolute or `~/` path.
    --- @since API 16
    diskStats: (path: string) -> DiskStats?,

    --- Executes a process asynchronously. Supports shell strings or safe argv tables.
    --- @since API 24 (Argument array form), API 3 (String form)
    runAsync: ((cmdOrArgv: string | { string }) -> boolean)
        & ((cmdOrArgv: string | { string }, cb: (result: AsyncResult) -> ()) -> boolean),

    --- Runs a long-lived command and invokes `onLine(line)` for each standard output line.
    --- @since API 3
    runStream: (cmd: string, onLine: (line: string) -> ()) -> boolean,

    --- Launches a command inside the user's preferred terminal emulator.
    --- @since API 3
    runInTerminal: (cmd: string) -> boolean,

    --- Checks whether an executable binary exists on the system `$PATH`.
    --- @since API 3
    commandExists: (name: string) -> boolean,

    --- Asynchronously scans running processes to see if any match the provided patterns.
    --- @since API 3
    processMatches: (cb: (matched: boolean) -> (), ...string) -> boolean,

    --- Checks whether a Flatpak application ID is installed on the host.
    --- @since API 3
    flatpakAppInstalled: (id: string) -> boolean,

    --- Checks whether the XDG Desktop Portal service is available on the system.
    --- @since API 3
    portalAvailable: () -> boolean,

    --- Reads an environment variable by name.
    --- @since API 3
    getenv: (name: string) -> string?,

    --- Expands relative and tilde (`~/`) paths to canonical absolute system paths.
    --- @since API 3
    expandPath: (path: string) -> string,

    --- Reads an entire file synchronously as raw bytes.
    --- @since API 3
    readFile: (path: string) -> (string?, string?),

    --- Queues an asynchronous file read outside the plugin VM worker pool (Max 4 MiB).
    --- @since API 23
    readFileAsync: (path: string, cb: (contents: string?, err: string?) -> ()) -> boolean,

    --- Writes content to a file, replacing existing data.
    --- @since API 3
    writeFile: (path: string, content: string) -> (boolean, string?),

    --- Recursively creates a directory path and missing parent directories.
    --- @since API 3
    mkdirAll: (path: string) -> (boolean, string?),

    --- Deletes a single file from disk. Refuses directory targets.
    --- @since API 3
    removeFile: (path: string) -> (boolean, string?),

    --- Renames or moves a file on disk.
    --- @since API 3
    renameFile: (from: string, to: string) -> (boolean, string?),

    --- Checks whether a path exists on the filesystem.
    --- @since API 3
    fileExists: (path: string) -> boolean,

    --- Retrieves size and modification timestamp metadata for a file.
    --- @since API 3
    fileInfo: (path: string) -> (FileInfo?, string?),

    --- Lists entries within a directory.
    --- @since API 3
    listDir: (path: string) -> ({ string }?, string?),

    --- Returns the read-only installation directory of this plugin.
    --- @since API 3
    pluginDir: () -> string?,

    --- Returns the persistent state directory for this plugin, creating it on demand.
    --- @since API 3
    pluginDataDir: () -> (string?, string?),

    --- Registers a custom font file and returns its resolved font family name.
    --- @since API 3
    loadFont: (path: string) -> (string?, string?),

    --- Audio playback interface for plugin sound assets.
    --- @since API 20
    sound: {
        --- Queues an asynchronous sound file load.
        --- @since API 20
        load: (name: string, path: string, onLoaded: (ok: boolean, error: string?) -> ()) -> boolean,
        --- Plays a previously loaded sound from the plugin's sound bank.
        --- @since API 20
        play: (name: string) -> (),
    },

    --- Performs an asynchronous HTTP request.
    --- @since API 3
    http: (request: HttpRequest, cb: (response: HttpResponse) -> ()) -> boolean,

    --- Initiates a persistent HTTP stream.
    --- @since API 4
    httpStream: (
        request: HttpRequest,
        onLine: (line: string) -> (),
        onClose: (result: { ok: boolean, status: number }) -> ()
    ) -> HttpStreamHandle?,

    --- Downloads a remote URL directly to a local destination path.
    --- @since API 3
    download: (url: string, dest: string, cb: (ok: boolean) -> ()) -> boolean,

    --- Translates a localization key using `translations/<lang>.json`.
    --- @since API 3
    tr: (key: string, subst: { [string]: any }?) -> string,

    --- Pluralization translation helper with token substitution.
    --- @since API 3
    trp: (key: string, count: number, subst: { [string]: any }?) -> string,

    --- Native JSON serialization and deserialization helpers.
    --- @since API 3
    json: {
        decode: (str: string) -> (any, string?),
        encode: (value: any, pretty: boolean?) -> (string?, string?),
    },

    --- String manipulation helpers.
    --- @since API 3
    string: {
        trim: (str: string) -> string,
        urlEncode: (str: string) -> string,
        urlDecode: (str: string) -> string,
    },

    --- Computes match score against text using Noctalia's native fuzzy matching algorithm.
    --- @since API 3
    fuzzyScore: (pattern: string, text: string) -> number?,

    --- Cross-entry in-memory pub/sub channel.
    --- @since API 3
    state: {
        --- Publishes a plain value across all VM entries in this plugin.
        set: (key: string, value: any) -> (),
        --- Reads the latest published value for a state key.
        get: (key: string) -> any,
        --- Registers a callback triggered whenever a state key value changes.
        watch: (key: string, fn: (value: any) -> ()) -> (),
    },
}

-- =============================================================================
-- Declarative UI Controls (ui.*)
-- =============================================================================

export type UiNode = any
export type UiCallback = string | ((...any) -> ())

--- Shared layout, size, and interaction properties accepted by all UI nodes.
export type UiCommonProps = {
    --- Stable reconciler identity key across re-renders.
    key: (string | number)?,
    --- Width in logical px or "fill".
    width: (number | string)?,
    --- Height in logical px or "fill".
    height: (number | string)?,
    --- Flexbox growth factor.
    flexGrow: number?,
    --- Group opacity (0.0 - 1.0) affecting container and children.
    opacity: number?,
    --- Visibility flag.
    visible: boolean?,
}

--- Declarative virtual UI node constructors.
export type Ui = {
    --- Vertical flex container.
    column: (props: UiCommonProps & { [string]: any }, children: { UiNode }?) -> UiNode,

    --- Horizontal flex container.
    row: (props: UiCommonProps & { [string]: any }, children: { UiNode }?) -> UiNode,

    --- Vertically scrolling container.
    --- @since API 21 (stickToBottom / scrollToBottomRev)
    scroll: (
        props: UiCommonProps
            & { stickToBottom: boolean?, scrollToBottomRev: number?, onScroll: UiCallback?, [string]: any },
        children: { UiNode }?
    ) -> UiNode,

    --- Text display label.
    label: (
        props: UiCommonProps
            & { text: string, fontSize: number?, color: string?, fontWeight: string?, fontFamily: string?, [string]: any }
    ) -> UiNode,

    --- Formatted Markdown text renderer block.
    --- @since API 21
    markdown: (props: UiCommonProps & { text: string, [string]: any }) -> UiNode,

    --- Vector icon glyph (Tabler / Nerd-Font).
    glyph: (props: UiCommonProps & { name: string, size: number?, color: string?, [string]: any }) -> UiNode,

    --- Local image renderer.
    image: (props: UiCommonProps & { path: string, fit: ("contain" | "cover" | "stretch")?, [string]: any }) -> UiNode,

    --- Generic styled container box with fill and border.
    box: (
        props: UiCommonProps & { fill: string?, radius: number?, border: string?, borderWidth: number?, [string]: any },
        children: { UiNode }?
    ) -> UiNode,

    --- Visual divider line.
    separator: (
        props: UiCommonProps
            & { orientation: ("auto" | "horizontal" | "vertical")?, thickness: number?, color: string?, [string]: any }
    ) -> UiNode,

    --- Flexible layout spacer.
    spacer: (props: UiCommonProps & { [string]: any }) -> UiNode,

    --- Determinate progress bar indicator (0.0 - 1.0).
    progress: (
        props: UiCommonProps & { progress: number, fill: string?, track: string?, radius: number?, [string]: any }
    ) -> UiNode,

    --- Interactive push button.
    --- @since API 9 (Direct closures in onClick)
    button: (
        props: UiCommonProps & {
            text: string?,
            glyph: string?,
            variant: ("default" | "primary" | "secondary" | "destructive" | "outline" | "ghost")?,
            onClick: UiCallback?,
            onRightClick: UiCallback?,
            onHover: UiCallback?,
            [string]: any,
        }
    ) -> UiNode,

    --- Lightweight line/fill trend graph.
    graph: (
        props: UiCommonProps & {
            values: { number },
            values2: { number }?,
            color: string?,
            color2: string?,
            lineWidth: number?,
            fillOpacity: number?,
            [string]: any,
        }
    ) -> UiNode,

    --- Boolean switch toggle.
    toggle: (
        props: UiCommonProps & { checked: boolean, enabled: boolean?, onChange: UiCallback?, [string]: any }
    ) -> UiNode,

    --- Continuous or stepped range slider.
    slider: (
        props: UiCommonProps & {
            min: number,
            max: number,
            step: number?,
            value: number,
            onChange: UiCallback?,
            onDragEnd: UiCallback?,
            [string]: any,
        }
    ) -> UiNode,

    --- Dropdown selection menu (Panels only).
    select: (
        props: UiCommonProps
            & { options: { string }, selectedIndex: number?, placeholder: string?, onChange: UiCallback?, [string]: any }
    ) -> UiNode,

    --- Uncontrolled single-line or multi-line text input field.
    --- @since API 21 (submitOnEnter), API 27 (frameVisible)
    input: (
        props: UiCommonProps & {
            value: string?,
            placeholder: string?,
            multiline: boolean?,
            submitOnEnter: boolean?,
            frameVisible: boolean?,
            focus: boolean?,
            onChange: UiCallback?,
            onSubmit: UiCallback?,
            [string]: any,
        }
    ) -> UiNode,

    --- Marks a subtree as an interactive drag source.
    --- @since API 5
    dragSource: (
        props: UiCommonProps
            & { dragType: string, payload: string, previewAncestor: number?, liftFromLayout: boolean?, [string]: any },
        children: { UiNode }?
    ) -> UiNode,

    --- Marks a flex container as an accepted drop target.
    --- @since API 5
    dropZone: (
        props: UiCommonProps & {
            accepts: { string },
            value: string,
            onDrop: UiCallback,
            expandOnDrag: boolean?,
            hitSlop: number?,
            [string]: any,
        },
        children: { UiNode }?
    ) -> UiNode,
}

-- =============================================================================
-- Surface Controllers
-- =============================================================================

--- Controller for pop-up panel surfaces.
export type Panel = {
    --- Commits a declarative UI tree to the panel surface.
    render: (tree: UiNode) -> (),
    --- Dismisses and closes this panel.
    close: () -> (),
    --- Displays a native context menu anchored to the current cursor position.
    --- @since API 28
    openContextMenu: (request: ContextMenuRequest) -> boolean,
    --- Requests `update()` execution on whole second boundaries.
    setWantsSecondTicks: (bool: boolean) -> (),
    --- Subscribes to per-frame `onFrameTick(deltaMs)` animations.
    --- @since API 18
    setNeedsFrameTick: (bool: boolean) -> (),
}

--- Controller for persistent desktop widget surfaces.
export type DesktopWidget = {
    --- Commits a declarative UI tree to the desktop widget surface.
    render: (tree: UiNode) -> (),
    --- Requests `update()` execution on whole second boundaries.
    setWantsSecondTicks: (bool: boolean) -> (),
    --- Subscribes to per-frame `onFrameTick(deltaMs)` animations.
    setNeedsFrameTick: (bool: boolean) -> (),
}

--- Controller for bar widget entries.
export type BarWidget = {
    --- Imperatively updates widget primary label text.
    setText: (text: string) -> (),
    --- Imperatively updates widget primary icon glyph.
    setGlyph: (glyph: string) -> (),
    --- Imperatively sets an image asset as the widget icon.
    setImage: (path: string) -> (),
    --- Sets tooltip text displayed on cursor hover.
    setTooltip: (tip: string) -> (),
    --- Clears any active hover tooltip.
    clearTooltip: () -> (),
    --- Overrides the font family and baseline alignment for the bar capsule.
    setFont: (family: string, baseline: ("text" | "textFixedHeight" | "inkCentered" | "pictographic")?) -> (),
    --- Overrides primary label text color.
    setColor: (color: string) -> (),
    --- Overrides primary glyph icon color.
    setGlyphColor: (color: string) -> (),
    --- Controls widget visibility on the bar.
    setVisible: (visible: boolean) -> (),
    --- Returns whether the parent bar is vertically oriented.
    isVertical: () -> boolean,
    --- Returns the DRM connector name of the monitor hosting this bar instance.
    outputName: () -> string?,
    --- Commits a declarative `ui.*` tree, overriding imperative text/glyph controls.
    render: (tree: UiNode) -> (),
}

--- Controller for Control Center shortcut tiles.
export type Shortcut = {
    setLabel: (text: string) -> (),
    setIcon: (on: string, off: string?) -> (),
    setActive: (bool: boolean) -> (),
    setEnabled: (bool: boolean) -> (),
}

--- Controller for application launcher search providers.
export type Launcher = {
    setResults: (query: string, results: { LauncherResult }) -> (),
    setQuery: (query: string) -> (),
}

-- =============================================================================
-- Global Host Injections
-- =============================================================================

declare noctalia: Noctalia
declare ui: Ui
declare panel: Panel
declare desktopWidget: DesktopWidget
declare barWidget: BarWidget
declare shortcut: Shortcut
declare launcher: Launcher

-- =============================================================================
-- Declarative Lifecycle Hook Declarations
-- =============================================================================

--- Periodic update lifecycle callback invoked based on `noctalia.setUpdateInterval`.
declare function update(): ()

--- Called when a background service is initialized or enabled.
declare function onEnable(): ()

--- Called when a plugin setting or configuration changes in `plugin.toml` or UI.
declare function onConfigChanged(): ()

--- Called when an IPC event message is received by this entry.
declare function onIpc(event: string, payload: string): ()

--- Called when the plugin or entry is terminating.
declare function onExit(signal: number, reason: ("disable" | "uninstall" | "reload" | "shutdown")?): ()

--- Called when the panel view is opened.
declare function onOpen(context: string?): ()

--- Called when the panel view is closed.
declare function onClose(): ()

--- Called on keyboard events while the panel has input focus.
declare function onKey(chord: string, pressed: boolean): ()

--- Called on every display frame when `setNeedsFrameTick(true)` is enabled.
declare function onFrameTick(deltaMs: number): ()

--- Called when a bar widget is clicked with the primary mouse button.
declare function onClick(): ()

--- Called when a bar widget is clicked with the secondary mouse button.
declare function onRightClick(): ()

--- Called when a bar widget is clicked with the middle mouse button.
declare function onMiddleClick(): ()

--- Called on mouse scroll wheel activity over a bar widget capsule.
declare function onScroll(axis: "vertical" | "horizontal", steps: number, startsGesture: boolean): ()
