--!nocheck
-- =============================================================================
-- Noctalia Host Bridge (`noctalia.*`), Subprocesses, IO, and Async Execution
-- =============================================================================

--- Subprocess execution outcome and captured output streams.
export type AsyncResult = {
    --- Process exit status code (0 indicates success).
    exitCode: number,

    --- Captured standard output stream.
    stdout: string,

    --- Captured standard error stream.
    stderr: string,

    --- Indicates whether the process was terminated due to a timeout.
    timedOut: boolean,

    --- True if the standard output buffer exceeded capacity and was truncated.
    stdoutTruncated: boolean?,

    --- True if the standard error buffer exceeded capacity and was truncated.
    stderrTruncated: boolean?,
}

--- Configuration payload for asynchronous HTTP requests.
export type HttpRequest = {
    --- Target URL endpoint (e.g. `"https://api.example.com/v1"`).
    url: string,

    --- HTTP method verb (e.g. `"GET"`, `"POST"`, `"PUT"`, `"DELETE"`). Defaults to `"GET"`.
    method: string?,

    --- Raw request body payload.
    body: string?,

    --- List of raw HTTP header lines (e.g. `{"Authorization: Bearer token", "Accept: application/json"}`).
    headers: { string }?,

    --- Basic access authentication username.
    basic_username: string?,

    --- Basic access authentication password.
    basic_password: string?,

    --- Whether to automatically follow HTTP 3xx redirect responses. Defaults to `false`.
    follow_redirects: boolean?,

    --- Disables TLS certificate chain and hostname validation.
    --- @since API 7
    allow_insecure_tls: boolean?,
}

--- Response payload delivered upon completion of an async HTTP request.
export type HttpResponse = {
    --- True if the request received a 2xx HTTP status code.
    ok: boolean,

    --- HTTP status code returned by the server (e.g. `200`, `404`, `500`).
    status: number,

    --- Response body content as raw string.
    body: string,
}

--- Control handle for active, long-lived HTTP streams (e.g. Server-Sent Events).
--- @since API 4
export type HttpStreamHandle = {
    --- Cancels the active stream connection. Idempotent; suppresses the `onClose` callback.
    stop: () -> (),
}

--- Display output geometry and scale description descriptor.
export type OutputInfo = {
    --- DRM connector identifier name (e.g. `"DP-1"`, `"HDMI-A-1"`).
    name: string,

    --- Hardware monitor description or model name.
    description: string?,

    --- Output horizontal resolution in physical pixels.
    width: number,

    --- Output vertical resolution in physical pixels.
    height: number,

    --- Surface X coordinate in global compositor space.
    x: number,

    --- Surface Y coordinate in global compositor space.
    y: number,

    --- Output HiDPI display scale factor (e.g. `1.0`, `1.5`, `2.0`).
    scale: number,

    --- Whether this output currently possesses compositor focus.
    focused: boolean,
}

--- Local filesystem metadata snapshot.
export type FileInfo = {
    --- File size in bytes.
    size: number,

    --- Last modification timestamp in Unix epoch seconds.
    mtime: number,

    --- True if the entry represents a directory node.
    isDir: boolean,
}

--- Primary host interface for system integration, shell configuration, and runtime execution.
export type Noctalia = {
    --- Sets how often this entry's `update()` lifecycle function runs. Clamped to a minimum of 16 ms.
    --- @since API 3
    setUpdateInterval: (ms: number) -> (),

    --- Writes a message to Noctalia's shell log, tagged with this plugin's script context.
    --- @since API 3
    log: (msg: string) -> (),

    --- Returns whether the active shell theme is currently in dark mode.
    --- @since API 3
    isDarkMode: () -> boolean,

    --- Reads any effective shell configuration value by its TOML dotted path (e.g. `"shell.offline_mode"`).
    --- Array indices are zero-based (e.g. `"bar.order[0]"`). Returns `nil` on missing paths.
    --- @since API 26
    getSetting: (path: string) -> any,

    --- Returns the focused output's DRM connector name, falling back to the interactive output.
    --- @since API 3
    focusedOutputName: () -> string?,

    --- Reads a declared plugin or entry setting defined in `plugin.toml`. Undeclared keys return `nil`.
    --- @since API 3
    getConfig: (key: string) -> any,

    --- Returns connected outputs as `{ name, description, width, height, x, y, scale, focused }` tables.
    --- @since API 3
    outputs: () -> { OutputInfo },

    --- Enables or disables Noctalia's native wallpaper surface on a specific DRM connector. Runtime-only.
    --- @since API 3
    setWallpaperEnabled: (connector: string, enabled: boolean) -> (),

    --- Applies and persists a wallpaper image across all outputs or on a specific DRM connector.
    --- @since API 3
    setWallpaper: ((path: string) -> ()) & ((connector: string, path: string) -> ()),

    --- Returns the resolved wallpaper directory path for the current theme mode, or `nil` when unset.
    --- @since API 3
    wallpaperDirectory: () -> string?,

    --- Returns the exact wallpaper image path currently configured for a DRM connector output.
    --- @since API 25
    wallpaperPath: (connector: string) -> string?,

    --- Applies or clears a source-aligned grayscale occlusion mask on desktop-widget surfaces for an output.
    --- Mask pixel value 0 leaves widgets visible, 255 erases them. `wallpaperPath` must match `noctalia.wallpaperPath`.
    --- @since API 25
    setWallpaperMask: (connector: string, mask: { path: string, wallpaperPath: string }?) -> (),

    --- Opens or closes a plugin panel by full entry ID (e.g. `"author/plugin:panel"`).
    --- @since API 3
    togglePanel: (id: string) -> (),

    --- Opens the shell settings window focused on this plugin's configuration page, closing any active panel.
    --- @since API 15
    openSettings: () -> (),

    --- Opens the system color picker with an initial `#RRGGBB` hex color.
    --- Returns `true` if accepted; callback receives `#RRGGBB` or `nil` on cancellation.
    --- @since API 3
    openColorPicker: (initialColor: string, onClose: (color: string?) -> ()) -> boolean,

    --- Resolves an application or desktop ID to an icon path using the host XDG icon theme resolver.
    --- @since API 3
    appIconPath: (appId: string, sizePx: number?) -> string?,

    --- Formats a timestamp with Noctalia clock tokens (e.g. `"{:%H:%M}"`, `"%A, %x"`).
    --- Supports optional Unix timestamp and IANA timezone name (e.g. `"Europe/Berlin"`).
    --- @since API 19 (Timezone support), API 3 (Base)
    formatTime: ((pattern: string) -> string)
        & ((pattern: string, unixSeconds: number?) -> string)
        & ((pattern: string, unixSeconds: number?, timezone: string?) -> string),

    --- Returns the active `[shell].time_format` setting string (e.g. `"{:%H:%M}"`).
    --- @since API 19
    timeFormat: () -> string,

    --- Returns the active `[shell].date_format` setting string (e.g. `"%A, %x"`).
    --- @since API 19
    dateFormat: () -> string,

    --- Validates whether a given string is an empty string (local time) or a known IANA timezone name.
    --- @since API 19
    isValidTimezone: (name: string) -> boolean,

    --- Returns the elapsed wall-clock milliseconds since the Unix epoch.
    --- @since API 12
    nowMs: () -> number,

    --- Displays an informational system desktop notification popup.
    --- @since API 3
    notify: (title: string, body: string?) -> (),

    --- Displays an error system desktop notification popup.
    --- @since API 3
    notifyError: (title: string, body: string?) -> (),

    --- Copies raw text to the system clipboard with an explicit MIME type (e.g. `"text/plain"`, `"text/uri-list"`).
    --- @since API 3
    copyToClipboard: (text: string, mime: string) -> boolean,

    --- Retrieves current plain-text clipboard content. Returns `nil` if clipboard is empty or non-text.
    --- @since API 3
    clipboardText: () -> string?,

    --- Retrieves an aggregated snapshot from the host system hardware monitor. Opts into thermal/GPU probes.
    --- Returns `nil` if `[system.monitor]` is disabled.
    --- @since API 12
    systemStats: () -> SystemStats?,

    --- Retrieves per-core CPU usage percentages (0 - 100). Opts into `/proc/stat` 1s polling.
    --- @since API 12
    cpuCores: () -> { number }?,

    --- Lists physical block-device filesystems available for disk statistics polling.
    --- @since API 16
    diskMounts: () -> { DiskMount },

    --- Retrieves storage usage statistics for an absolute or `~/` path.
    --- @since API 16
    diskStats: (path: string) -> DiskStats?,

    --- Executes a process asynchronously. Supports shell command strings or safe argument arrays.
    --- Non-capturing form returns whether process launched; callback form delivers an `AsyncResult`.
    --- @since API 24 (Argument array form), API 3 (String form)
    runAsync: ((cmdOrArgv: string | { string }) -> boolean)
        & ((cmdOrArgv: string | { string }, cb: (result: AsyncResult) -> ()) -> boolean),

    --- Runs a long-lived command and invokes `onLine(line)` for each line emitted on standard output.
    --- @since API 3
    runStream: (cmd: string, onLine: (line: string) -> ()) -> boolean,

    --- Launches a command in the user's preferred terminal emulator (`$TERMINAL` or `$PATH` discovery).
    --- @since API 3
    runInTerminal: (cmd: string) -> boolean,

    --- Checks whether an executable binary exists on the system `$PATH`.
    --- @since API 3
    commandExists: (name: string) -> boolean,

    --- Asynchronously scans active system processes against substring pattern needles.
    --- @since API 3
    processMatches: (cb: (matched: boolean) -> (), ...string) -> boolean,

    --- Checks whether a Flatpak application ID is installed on the host system.
    --- @since API 3
    flatpakAppInstalled: (id: string) -> boolean,

    --- Checks whether the XDG Desktop Portal D-Bus service is reachable.
    --- @since API 3
    portalAvailable: () -> boolean,

    --- Reads the value of an environment variable by name.
    --- @since API 3
    getenv: (name: string) -> string?,

    --- Expands relative and tilde (`~/`) paths to canonical absolute system paths.
    --- @since API 3
    expandPath: (path: string) -> string,

    --- Reads an entire file synchronously as raw bytes.
    --- @since API 3
    readFile: (path: string) -> (string?, string?),

    --- Queues an asynchronous file read outside the plugin VM worker pool (bounded queue, max 4 MiB).
    --- @since API 23
    readFileAsync: (path: string, cb: (contents: string?, err: string?) -> ()) -> boolean,

    --- Writes byte content to a file, replacing any existing content.
    --- @since API 3
    writeFile: (path: string, content: string) -> (boolean, string?),

    --- Recursively creates a directory path and any missing parent directories.
    --- @since API 3
    mkdirAll: (path: string) -> (boolean, string?),

    --- Deletes a single file from disk. Refuses directory targets.
    --- @since API 3
    removeFile: (path: string) -> (boolean, string?),

    --- Renames or moves a file on disk.
    --- @since API 3
    renameFile: (from: string, to: string) -> (boolean, string?),

    --- Checks whether a file or directory path exists on the filesystem.
    --- @since API 3
    fileExists: (path: string) -> boolean,

    --- Retrieves size (bytes) and modification timestamp (unix seconds) metadata for a path.
    --- @since API 3
    fileInfo: (path: string) -> (FileInfo?, string?),

    --- Lists entry filenames contained within a directory.
    --- @since API 3
    listDir: (path: string) -> ({ string }?, string?),

    --- Returns the read-only installation directory path of this plugin.
    --- @since API 3
    pluginDir: () -> string?,

    --- Returns the persistent state directory path for this plugin, creating it on demand.
    --- @since API 3
    pluginDataDir: () -> (string?, string?),

    --- Registers a custom font file and returns its resolved font family name.
    --- @since API 3
    loadFont: (path: string) -> (string?, string?),

    --- Audio playback subsystem for loaded sound bank assets.
    --- @since API 20
    sound: {
        --- Queues an asynchronous audio file load (max 8 pending). Invokes `onLoaded(ok, err)`.
        --- @since API 20
        load: (name: string, path: string, onLoaded: (ok: boolean, error: string?) -> ()) -> boolean,

        --- Plays a previously loaded sound from the plugin's sound bank.
        --- @since API 20
        play: (name: string) -> (),
    },

    --- Performs an asynchronous HTTP request, delivering the completed `HttpResponse` to `cb`.
    --- @since API 3
    http: (request: HttpRequest, cb: (response: HttpResponse) -> ()) -> boolean,

    --- Initiates a persistent streaming HTTP request (e.g. SSE). Delivers lines incrementally.
    --- @since API 4
    httpStream: (
        request: HttpRequest,
        onLine: (line: string) -> (),
        onClose: (result: { ok: boolean, status: number }) -> ()
    ) -> HttpStreamHandle?,

    --- Downloads a remote URL directly to a local destination file path.
    --- @since API 3
    download: (url: string, dest: string, cb: (ok: boolean) -> ()) -> boolean,

    --- Translates a localization key using `translations/<lang>.json`, falling back to the key.
    --- @since API 3
    tr: (key: string, subst: { [string]: any }?) -> string,

    --- Pluralization translation helper with count checks and token substitution.
    --- @since API 3
    trp: (key: string, count: number, subst: { [string]: any }?) -> string,

    --- Native JSON serialization and deserialization helpers.
    --- @since API 3
    json: {
        --- Parses a JSON string into corresponding Luau tables, primitives, or nil.
        decode: (str: string) -> (any, string?),

        --- Encodes a Luau value as compact or formatted JSON.
        encode: (value: any, pretty: boolean?) -> (string?, string?),
    },

    --- Native string utility helpers.
    --- @since API 3
    string: {
        --- Trims leading and trailing whitespace characters.
        trim: (str: string) -> string,

        --- URL percent-encodes a string for query parameters or path segments.
        urlEncode: (str: string) -> string,

        --- Decodes a percent-encoded URL string.
        urlDecode: (str: string) -> string,
    },

    --- Computes a match score against text using Noctalia's native fuzzy matching algorithm.
    --- Returns `nil` when there is no match.
    --- @since API 3
    fuzzyScore: (pattern: string, text: string) -> number?,

    --- Cross-VM in-memory publish/subscribe state channel scoped to this plugin.
    --- @since API 3
    state: {
        --- Publishes a plain data value across all VM entries in this plugin.
        set: (key: string, value: any) -> (),

        --- Reads the latest published value for a state key.
        get: (key: string) -> any,

        --- Registers a listener callback triggered whenever a state key value updates.
        watch: (key: string, fn: (value: any) -> ()) -> (),
    },
}

declare noctalia: Noctalia
