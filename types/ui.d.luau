--!strict
-- =============================================================================
-- Noctalia Declarative Virtual UI Framework (ui.*)
-- =============================================================================

--- Abstract Virtual UI Node returned by constructors and passed to surface reconcilers.
export type UiNode = any

--- Callback identifier. Accepts either a direct closure or the global name of a script function.
export type UiCallback = string | ((...any) -> ())

--- Alignment of items along the cross axis inside a flex container.
--- - `"start"`: Packs items flush to the cross-axis start edge.
--- - `"center"`: Centers items along the cross axis.
--- - `"end"`: Packs items flush to the cross-axis finish edge.
--- - `"stretch"`: Stretches items to occupy the full container cross axis.
export type UiAlign = "start" | "center" | "end" | "stretch"

--- Distribution of items along the main layout axis inside a flex container.
--- - `"start"`: Items packed toward the start line.
--- - `"center"`: Items packed along the center line.
--- - `"end"`: Items packed toward the finish line.
--- - `"space_between"`: Even distribution; first item at start, last item at finish.
--- - `"space_around"`: Even distribution with half-size space before first and after last.
--- - `"space_evenly"`: Even distribution with equal spacing between items and container edges.
export type UiJustify = "start" | "center" | "end" | "space_between" | "space_around" | "space_evenly"

--- Standardized height and padding sizing tier for interactive controls.
--- - `"sm"`: Compact control height (32px).
--- - `"md"`: Standard control height (38px).
--- - `"lg"`: Prominent control height (44px).
export type UiControlSize = "sm" | "md" | "lg"

--- Visual appearance tier and semantic role for push buttons.
--- - `"default"`: Subtle filled tonal surface.
--- - `"primary"`: High-emphasis accent color role.
--- - `"secondary"`: Medium-emphasis container role.
--- - `"destructive"`: Error/warning colored role indicating destructive consequences.
--- - `"outline"`: Transparent fill framed by an outline stroke.
--- - `"ghost"`: Frameless transparent surface highlighting only on hover or focus.
export type UiButtonVariant = "default" | "primary" | "secondary" | "destructive" | "outline" | "ghost"

--- Horizontal alignment of text runs within a bounded container or button.
--- - `"start"`: Left-aligned for LTR typography, right-aligned for RTL typography.
--- - `"center"`: Centered horizontally.
--- - `"end"`: Right-aligned for LTR typography, left-aligned for RTL typography.
export type UiTextAlign = "start" | "center" | "end"

--- Typographic font weight tier name or custom font numeric face weight.
--- Predefined weights map to: `"thin"` (100), `"light"` (300), `"normal"` (400),
--- `"medium"` (500), `"bold"` (700), `"heavy"` (800), and `"black"` (900).
export type UiFontWeight = "thin" | "light" | "normal" | "medium" | "bold" | "black" | "heavy" | string

--- Metric baseline alignment mode for typography rendering.
--- - `"text"`: Standard font alphabetic baseline.
--- - `"textFixedHeight"`: Fixed line-height container metrics.
--- - `"inkCentered"`: Centered strictly based on pixel glyph bounding boxes.
--- - `"pictographic"`: Ideographic/pictographic baseline optimized for icon alignment.
export type UiBaseline = "text" | "textFixedHeight" | "inkCentered" | "pictographic"

--- Display orientation mode for layout containers and dividers.
--- - `"auto"`: Infers layout perpendicular to the enclosing container.
--- - `"horizontal"`: Stretches along the horizontal axis.
--- - `"vertical"`: Stretches along the vertical axis.
export type UiOrientation = "auto" | "horizontal" | "vertical"

--- Image scaling algorithm within bounded layout dimensions.
--- - `"contain"`: Scales proportionally to fit entirely inside the container without cropping.
--- - `"cover"`: Scales proportionally to fill the container, clipping overflow.
--- - `"stretch"`: Stretches non-proportionally to match explicit node boundaries.
export type UiImageFit = "contain" | "cover" | "stretch"

-- =============================================================================
-- Component Property Traits & Configurations
-- =============================================================================

--- Base layout, geometry, and styling properties accepted by all UI nodes.
export type UiCommonProps = {
    --- Stable reconciler identity key across re-renders. Reusing keys preserves native control state and focus.
    key: (string | number)?,

    --- Explicit width in logical px or `"fill"` to expand across the container extent.
    width: (number | string)?,

    --- Explicit height in logical px or `"fill"` to expand across the container extent.
    height: (number | string)?,

    --- Flexbox growth factor relative to siblings inside a `column` or `row`.
    flexGrow: number?,

    --- Group opacity (0.0 - 1.0). Fades the container and all descendant children recursively.
    opacity: number?,

    --- Visibility flag. When `false`, hides the node from layout calculation and rendering.
    visible: boolean?,

    --- Click activation handler. Fires on pointer press or Space/Enter keyboard activation.
    onClick: UiCallback?,

    --- Secondary pointer activation handler. Fires on right-click.
    onRightClick: UiCallback?,

    --- Pointer hover transition handler: `fn(state: "true" | "false", key: string)`.
    onHover: UiCallback?,
}

--- Alignment, layout distribution, and border/padding properties for flex containers.
export type UiFlexProps = UiCommonProps & {
    --- Spacing in logical px between child elements along the main layout axis.
    gap: number?,

    --- Cross-axis alignment for children. Columns default to `"stretch"`; rows default to `"stretch"`.
    align: UiAlign?,

    --- Main-axis distribution for child layout spacing.
    justify: UiJustify?,

    --- Uniform internal padding in logical px applied to all four edges.
    padding: number?,

    --- Horizontal internal padding in logical px (left and right).
    paddingH: number?,

    --- Vertical internal padding in logical px (top and bottom).
    paddingV: number?,

    --- Top internal edge padding in logical px.
    paddingTop: number?,

    --- Bottom internal edge padding in logical px.
    paddingBottom: number?,

    --- Left internal edge padding in logical px.
    paddingLeft: number?,

    --- Right internal edge padding in logical px.
    paddingRight: number?,

    --- Minimum allowed width constraint in logical px.
    minWidth: number?,

    --- Minimum allowed height constraint in logical px.
    minHeight: number?,

    --- Background fill color. Accepts theme tokens (`"primary"`, `"surface_variant/0.6"`) or hex values (`"#RRGGBB"`).
    fill: string?,

    --- Corner border radius in logical px.
    radius: number?,

    --- Stroke color for the outer container boundary. Accepts theme tokens or hex strings.
    border: string?,

    --- Stroke width in logical px for the outer boundary outline.
    borderWidth: number?,
}

--- Visual bounding box container properties with optional edge softness.
export type UiBoxProps = UiFlexProps & {
    --- Edge blur / drop softness radius in logical px.
    softness: number?,
}

--- Vertically scrolling container properties.
--- @since API 21
export type UiScrollProps = UiFlexProps & {
    --- Automatically keeps scroll pinned to the bottom as content expands until the user scrolls away.
    stickToBottom: boolean?,

    --- Incremental counter trigger; jumps scroll position to the bottom on change after layout pass.
    scrollToBottomRev: number?,

    --- Scroll offset stream handler: `fn(offset: string, maxOffset: string)`.
    onScroll: UiCallback?,
}

--- Text display label properties.
export type UiLabelProps = UiCommonProps & {
    --- Primary string content displayed by the label.
    text: string,

    --- Explicit font size in logical px. Overrides host surface defaults.
    fontSize: number?,

    --- Text foreground color. Accepts theme tokens (`"primary"`, `"on_surface"`) or hex values.
    color: string?,

    --- Typographic font weight tier.
    fontWeight: UiFontWeight?,

    --- Registered font family name (loaded via `noctalia.loadFont`).
    fontFamily: string?,

    --- Baseline metric alignment mode for typography rendering.
    baseline: UiBaseline?,

    --- Maximum allowed width constraint in logical px before truncation/wrapping.
    maxWidth: number?,

    --- Maximum line count threshold before truncating text.
    maxLines: number?,

    --- Text line alignment within the label's bounded width.
    textAlign: UiTextAlign?,
}

--- Formatted Markdown text renderer block properties.
--- @since API 21
export type UiMarkdownProps = UiCommonProps & {
    --- Markdown source string supporting headings, lists, inline formatting, and tables.
    text: string,
}

--- Vector icon glyph properties.
export type UiGlyphProps = UiCommonProps & {
    --- Icon identifier name resolved from Tabler or Nerd-Font glyph sets (e.g. `"layout-grid"`, `"cpu"`).
    name: string,

    --- Glyph bounding dimension in logical px.
    size: number?,

    --- Glyph stroke/fill color. Accepts theme tokens (`"primary"`, `"on_surface_variant"`) or hex strings.
    color: string?,
}

--- Local image renderer properties.
export type UiImageProps = UiCommonProps & {
    --- Local filesystem image path (relative to plugin, `~/`, or absolute). Remote URLs must be downloaded first.
    path: string,

    --- Corner clipping radius in logical px.
    radius: number?,

    --- Scaling behavior within layout dimensions.
    fit: UiImageFit?,

    --- Border stroke color surrounding the image boundary.
    border: string?,

    --- Border stroke width in logical px.
    borderWidth: number?,
}

--- Visual divider separator line properties.
export type UiSeparatorProps = UiCommonProps & {
    --- Line direction. When `"auto"`, infers perpendicular axis relative to parent flex container.
    orientation: UiOrientation?,

    --- Thickness of the line stroke in logical px.
    thickness: number?,

    --- Stroke color. Accepts theme role tokens or hex codes.
    color: string?,

    --- Empty layout spacing surrounding the separator in logical px.
    spacing: number?,
}

--- Determinate progress indicator bar properties.
export type UiProgressProps = UiCommonProps & {
    --- Normalized fill progress ratio ranging from `0.0` (empty) to `1.0` (full).
    progress: number,

    --- Active progress indicator bar fill color token.
    fill: string?,

    --- Inactive background track fill color token.
    track: string?,

    --- Corner border radius in logical px for both track and bar.
    radius: number?,
}

--- Interactive push button properties.
export type UiButtonProps = UiCommonProps & {
    --- Primary textual label displayed on the button surface.
    text: string?,

    --- Leading icon glyph name. If set without `text`, renders as an icon-only button.
    glyph: string?,

    --- Label font size in logical px.
    fontSize: number?,

    --- Icon glyph size in logical px.
    glyphSize: number?,

    --- Visual style tier mapping to theme color roles.
    variant: UiButtonVariant?,

    --- Content alignment inside the button boundary.
    contentAlign: UiTextAlign?,

    --- Preset height tier: `"sm"` (32px), `"md"` (38px, default), or `"lg"` (44px).
    controlSize: UiControlSize?,

    --- Hover tooltip message (displayed on bar widgets and panels).
    tooltip: string?,

    --- Interactive state flag. When `false`, dims the button and disables pointer events.
    enabled: boolean?,

    --- Selected / toggled visual state indicator.
    selected: boolean?,
}

--- Lightweight sparkline/trend data graph properties.
export type UiGraphProps = UiCommonProps & {
    --- Primary series array of numeric data points normalized between `0.0` and `1.0`.
    values: { number },

    --- Optional secondary series array of numeric data points (`0.0` - `1.0`).
    values2: { number }?,

    --- Stroke color for the primary series line.
    color: string?,

    --- Stroke color for the secondary series line.
    color2: string?,

    --- Stroke width in logical px for rendered graph lines.
    lineWidth: number?,

    --- Fill opacity (0.0 - 1.0) under the primary graph curve.
    fillOpacity: number?,
}

--- Boolean switch toggle properties.
export type UiToggleProps = UiCommonProps & {
    --- Current boolean state of the switch.
    checked: boolean,

    --- Interaction availability flag.
    enabled: boolean?,

    --- State mutation handler: `fn(value: string)` receiving `"true"` or `"false"`.
    onChange: UiCallback?,
}

--- Continuous or stepped range slider properties.
export type UiSliderProps = UiCommonProps & {
    --- Minimum numeric range bound.
    min: number,

    --- Maximum numeric range bound.
    max: number,

    --- Step interval increment. Defaults to continuous adjustment when unset.
    step: number?,

    --- Current numeric value of the slider handle.
    value: number,

    --- Preset slider thickness / height tier.
    controlSize: UiControlSize?,

    --- Interaction availability flag.
    enabled: boolean?,

    --- Continuous value adjustment handler: `fn(value: number)`.
    onChange: UiCallback?,

    --- Pointer release handler committed on drag completion.
    onDragEnd: UiCallback?,
}

--- Dropdown selection menu properties (Panels only).
export type UiSelectProps = UiCommonProps & {
    --- Array of selectable string options.
    options: { string },

    --- Zero-based or one-based index of the currently active option.
    selectedIndex: number?,

    --- Placeholder string displayed when no item is selected.
    placeholder: string?,

    --- Preset height tier: `"sm"`, `"md"`, or `"lg"`.
    controlSize: UiControlSize?,

    --- Interaction availability flag.
    enabled: boolean?,

    --- Selection mutation handler: `fn(index: number)`.
    onChange: UiCallback?,
}

--- Uncontrolled single-line or multi-line text input field properties.
export type UiInputProps = UiCommonProps & {
    --- Seed text value applied on creation. Uncontrolled across subsequent re-renders unless keyed.
    value: string?,

    --- Hint text displayed when input buffer is empty.
    placeholder: string?,

    --- Text font size in logical px.
    fontSize: number?,

    --- Preset height tier: `"sm"`, `"md"`, or `"lg"`.
    controlSize: UiControlSize?,

    --- Obscures text entries for credential input (mutually exclusive with `multiline`).
    password: boolean?,

    --- Transforms control into a wrapping multiline text area with vertical scrolling.
    multiline: boolean?,

    --- Swaps Enter key behavior: Enter submits (`onSubmit`), Shift+Enter inserts newline.
    --- @since API 21
    submitOnEnter: boolean?,

    --- Hides native background frame and border for custom parent container framing.
    --- @since API 27
    frameVisible: boolean?,

    --- Steals initial keyboard focus once upon node mounting.
    focus: boolean?,

    --- Interaction availability flag.
    enabled: boolean?,

    --- Text change event stream handler: `fn(text: string)`.
    onChange: UiCallback?,

    --- Form submission handler triggered by Enter or Ctrl+Enter: `fn(text: string)`.
    onSubmit: UiCallback?,
}

--- Interactive pointer drag source wrapper (Panels only).
--- @since API 5
export type UiDragSourceProps = UiFlexProps & {
    --- Discriminator string identifying payload type; matched against `dropZone.accepts`.
    dragType: string,

    --- Opaque payload string forwarded to `dropZone.onDrop` (Max 16 KiB).
    payload: string,

    --- Drag availability flag.
    enabled: boolean?,

    --- Optional tooltip displayed on hover.
    tooltip: string?,

    --- Number of parent layout hierarchy levels (0-8) included in floating ghost preview.
    previewAncestor: number?,

    --- Removes source row from standard flex layout during active drag operations.
    liftFromLayout: boolean?,
}

--- Interactive drop target flex container (Panels only).
--- @since API 5
export type UiDropZoneProps = UiFlexProps & {
    --- Array of accepted `dragType` identifiers (Max 16 entries).
    accepts: { string },

    --- Identifier value passed as second argument to `onDrop` describing destination context.
    value: string,

    --- Drop completion handler: `fn(payload: string, value: string)`.
    onDrop: UiCallback,

    --- Flex direction orientation of the drop container zone.
    direction: ("column" | "row")?,

    --- Interaction availability flag.
    enabled: boolean?,

    --- Expands fixed height to match dragged row height when actively targeted.
    expandOnDrag: boolean?,

    --- Extended pointer capture margin in logical px outside layout bounds.
    hitSlop: number?,
}

-- =============================================================================
-- Global Declarative UI Constructor Table
-- =============================================================================

--- Declarative virtual UI node constructors for retained UI tree generation.
export type Ui = {
    --- Constructs a vertical flex container node. Cross-axis defaults to `"stretch"`.
    column: (props: UiFlexProps, children: { UiNode }?) -> UiNode,

    --- Constructs a horizontal flex container node. Cross-axis defaults to `"stretch"`.
    row: (props: UiFlexProps, children: { UiNode }?) -> UiNode,

    --- Constructs a vertically scrolling flex container node.
    --- @since API 21
    scroll: (props: UiScrollProps, children: { UiNode }?) -> UiNode,

    --- Constructs a text display label node.
    label: (props: UiLabelProps) -> UiNode,

    --- Constructs a formatted Markdown text renderer block node.
    --- @since API 21
    markdown: (props: UiMarkdownProps) -> UiNode,

    --- Constructs a vector glyph icon node (Tabler / Nerd-Font).
    glyph: (props: UiGlyphProps) -> UiNode,

    --- Constructs a local image renderer node.
    image: (props: UiImageProps) -> UiNode,

    --- Constructs a styled rectangular visual container box node.
    box: (props: UiBoxProps, children: { UiNode }?) -> UiNode,

    --- Constructs a visual divider line separator node.
    separator: (props: UiSeparatorProps?) -> UiNode,

    --- Constructs an empty flexible layout spacer node.
    spacer: (props: UiCommonProps?) -> UiNode,

    --- Constructs a determinate progress indicator bar node.
    progress: (props: UiProgressProps) -> UiNode,

    --- Constructs an interactive push button node.
    --- @since API 9
    button: (props: UiButtonProps) -> UiNode,

    --- Constructs a trend/sparkline line graph node.
    graph: (props: UiGraphProps) -> UiNode,

    --- Constructs a boolean switch toggle node.
    toggle: (props: UiToggleProps) -> UiNode,

    --- Constructs a range slider control node.
    slider: (props: UiSliderProps) -> UiNode,

    --- Constructs a dropdown selection menu node (Panels only).
    select: (props: UiSelectProps) -> UiNode,

    --- Constructs an uncontrolled text input field node.
    --- @since API 21
    input: (props: UiInputProps) -> UiNode,

    --- Constructs a draggable subtree source wrapper (Panels only).
    --- @since API 5
    dragSource: (props: UiDragSourceProps, children: { UiNode }?) -> UiNode,

    --- Constructs an interactive drag-and-drop target flex container (Panels only).
    --- @since API 5
    dropZone: (props: UiDropZoneProps, children: { UiNode }?) -> UiNode,
}

declare ui: Ui;
