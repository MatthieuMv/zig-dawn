//! Window operations require the main thread and initialized video subsystem.
//! Native calls may allocate. Destroy renderers and other children before their window.
const std = @import("std");
const c = @import("sdl_abi");

/// Window failures: `SdlFailure` for native failure; `InvalidSize` for zero/oversized requested
/// dimensions or a negative dimension returned by a native query. InvalidPosition rejects native
/// sentinel collisions or display IDs that cannot fit a position hint. InvalidConstraint rejects
/// invalid size/aspect limits; InvalidOpacity rejects nonfinite/out-of-range opacity.
/// InvalidProgress rejects invalid completion fractions; OutOfBounds rejects snapshot indices.
/// InvalidParent and HierarchyTooDeep reject unsafe or excessively deep reparenting requests.
/// InvalidVSync rejects zero/oversized refresh intervals; InvalidRegion rejects invalid barriers.
/// Wrapper validation leaves SDL diagnostics unchanged.
pub const Error = @import("errors.zig").Error || error{
    /// Requested dimensions are zero/too large, or a native query returned a negative dimension.
    InvalidSize,
    /// A coordinate collides with native hints, or a hint display ID exceeds 16 bits/is invalid.
    InvalidPosition,
    /// A supplied limit is zero, oversized, nonfinite, negative, or internally inverted.
    InvalidConstraint,
    /// Window opacity must be finite and within the inclusive 0..1 interval.
    InvalidOpacity,
    /// Progress values must be finite and within the inclusive 0..1 interval.
    InvalidProgress,
    /// Window snapshot index is outside its recorded length.
    OutOfBounds,
    /// Parent request is self, sibling, or descendant, which SDL cannot safely accept.
    InvalidParent,
    /// Parent validation exceeded the 256-link traversal bound; no native mutation occurred.
    HierarchyTooDeep,
    /// A surface refresh interval must be positive and fit C int.
    InvalidVSync,
    /// A confinement rectangle has empty/oversized extents or overflowing signed end coordinates.
    InvalidRegion,
};
/// Numeric window identity, not ownership. IDs in queued events can outlive the window.
/// Unknown nonzero values are retained; compare IDs, never treat them as native pointers.
pub const WindowId = enum(u32) {
    /// No associated window. Successful `WindowRef.id` never returns this value.
    invalid = 0,
    _,

    /// Resolve an event/cached ID to a borrowed live window on the main thread.
    /// Null means SDL found no window (including invalid/stale IDs); native diagnostics remain
    /// available. Requires initialized video. No wrapper allocation/retention; owner outlives use.
    pub fn resolve(self: WindowId) ?WindowRef {
        const handle = c.SDL_GetWindowFromID(@backingInt(self)) orelse return null;
        return .{ .handle = handle };
    }
};
/// Known state bits reported by SDL. Use WindowFlags.contains; unknown bits remain in bits.
pub const WindowFlag = enum(u64) {
    /// Fullscreen mode is requested or active; inspect events for completed transitions.
    fullscreen = c.SDL_WINDOW_FULLSCREEN,
    /// Created for an OpenGL context.
    opengl = c.SDL_WINDOW_OPENGL,
    /// Backend reports the window is occluded.
    occluded = c.SDL_WINDOW_OCCLUDED,
    /// Hidden from normal desktop and taskbar visibility.
    hidden = c.SDL_WINDOW_HIDDEN,
    /// Window decorations are disabled.
    borderless = c.SDL_WINDOW_BORDERLESS,
    /// User resizing is enabled.
    resizable = c.SDL_WINDOW_RESIZABLE,
    /// Backend reports minimized state.
    minimized = c.SDL_WINDOW_MINIMIZED,
    /// Backend reports maximized state.
    maximized = c.SDL_WINDOW_MAXIMIZED,
    /// Mouse input is grabbed by this window.
    mouse_grabbed = c.SDL_WINDOW_MOUSE_GRABBED,
    /// Window currently has keyboard input focus.
    input_focus = c.SDL_WINDOW_INPUT_FOCUS,
    /// Window currently has mouse focus.
    mouse_focus = c.SDL_WINDOW_MOUSE_FOCUS,
    /// Native window was created outside SDL.
    external = c.SDL_WINDOW_EXTERNAL,
    /// Window is modal relative to its parent.
    modal = c.SDL_WINDOW_MODAL,
    /// High-density drawable was requested where supported.
    high_pixel_density = c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    /// Mouse capture is active; distinct from mouse grabbing.
    mouse_capture = c.SDL_WINDOW_MOUSE_CAPTURE,
    /// Relative mouse mode is enabled for this window.
    mouse_relative_mode = c.SDL_WINDOW_MOUSE_RELATIVE_MODE,
    /// Window requests stacking above ordinary windows.
    always_on_top = c.SDL_WINDOW_ALWAYS_ON_TOP,
    /// Utility window, normally omitted from taskbar/window lists.
    utility = c.SDL_WINDOW_UTILITY,
    /// Parented tooltip without normal input focus.
    tooltip = c.SDL_WINDOW_TOOLTIP,
    /// Parented popup menu window.
    popup_menu = c.SDL_WINDOW_POPUP_MENU,
    /// Keyboard input is grabbed by this window.
    keyboard_grabbed = c.SDL_WINDOW_KEYBOARD_GRABBED,
    /// Canvas fills the browser document on Emscripten.
    fill_document = c.SDL_WINDOW_FILL_DOCUMENT,
    /// Created for a Vulkan surface.
    vulkan = c.SDL_WINDOW_VULKAN,
    /// Created for a Metal view.
    metal = c.SDL_WINDOW_METAL,
    /// Window requests a transparent framebuffer.
    transparent = c.SDL_WINDOW_TRANSPARENT,
    /// Window is not eligible for input focus.
    not_focusable = c.SDL_WINDOW_NOT_FOCUSABLE,
};

/// Copyable window state snapshot; unknown future bits are retained for interop.
pub const WindowFlags = struct {
    /// Complete native bitset, including bits unknown to this version of the wrapper.
    bits: u64,

    /// Test a named state bit without allocation or native calls; snapshot may already be stale.
    pub fn contains(self: WindowFlags, flag: WindowFlag) bool {
        return self.bits & @backingInt(flag) != 0;
    }
};

/// Native graphics capability requested at window creation; this creates no context or renderer.
/// Support depends on the compiled SDL drivers and platform. Backends are mutually exclusive.
pub const GraphicsBackend = enum {
    /// No special native graphics flag; suitable for SDL renderer or window-surface workflows.
    none,
    /// Enable later OpenGL context creation; may load a native graphics library.
    opengl,
    /// Enable later Vulkan surface creation; may load the native Vulkan loader.
    vulkan,
    /// Enable later Metal view creation on supported Apple platforms.
    metal,
};

/// Integer dimensions. The producing/consuming operation determines coordinates versus pixels.
pub const Size = struct {
    /// Horizontal extent. Creation requires 1..maxInt(c_int); queries may return zero.
    width: u32,
    /// Vertical extent. Creation requires 1..maxInt(c_int); queries may return zero.
    height: u32,
};

/// Presentation synchronization request for a software window surface. Support is backend-specific.
pub const SurfaceVSync = union(enum) {
    /// Present without waiting for vertical refresh (native default).
    disabled,
    /// Allow late-swap tearing where adaptive synchronization is supported.
    adaptive,
    /// Present every N refreshes; positive and representable as C int.
    interval: u32,
};

/// Taskbar progress state. Unknown future numeric states are preserved by queries.
pub const ProgressState = enum(c_int) {
    /// Hide the taskbar progress indicator.
    none = c.SDL_PROGRESS_STATE_NONE,
    /// Display activity without a known completion fraction.
    indeterminate = c.SDL_PROGRESS_STATE_INDETERMINATE,
    /// Display ordinary determinate progress using progress_value.
    normal = c.SDL_PROGRESS_STATE_NORMAL,
    /// Display paused progress where supported.
    paused = c.SDL_PROGRESS_STATE_PAUSED,
    /// Display error progress where supported; this is not an API failure.
    failed = c.SDL_PROGRESS_STATE_ERROR,
    _,
};

/// Owns only an SDL-allocated array of borrowed window pointers. Do not copy; deinit once.
/// Does not retain any windows. Destruction can invalidate entries independently of array lifetime.
pub const Windows = struct {
    /// Native array allocation; read-only and never freed separately.
    native: [*c]?*c.SDL_Window,
    /// Recorded number of entries, excluding null sentinel; read-only.
    count: usize,

    /// Borrow the indexed window on the main thread. Its owner must still be alive and outlive use.
    /// OutOfBounds rejects invalid indices; SdlFailure rejects a null native entry. No retention or
    /// allocation. Use WindowId.resolve for IDs retained across possible window destruction.
    pub fn get(self: Windows, index: usize) Error!WindowRef {
        if (index >= self.count) return error.OutOfBounds;
        const handle = self.native[index] orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Free the pointer array on the main thread without destroying any windows. No active array
    /// users may remain. Safe even if its windows were destroyed, provided entries are not used.
    pub fn deinit(self: *Windows) void {
        c.SDL_free(@ptrCast(self.native));
        self.* = undefined;
    }
};

/// Allocate a snapshot of current windows on the main thread with initialized video.
/// Caller owns array cleanup only; windows remain borrowed and can disappear independently.
/// Empty success is valid. SdlFailure returns no owner; native allocation may fail.
///
/// ```zig
/// const sdl = @import("sdl");
/// sdl.raw.SDL_SetMainReady();
/// defer sdl.raw.SDL_Quit();
/// var video = try sdl.init(.{ .video = true });
/// defer video.deinit();
/// var windows = try sdl.video.list_windows();
/// defer windows.deinit();
/// for (0..windows.count) |index| {
///     const window = try windows.get(index);
///     _ = try window.id();
/// }
/// ```
pub fn list_windows() Error!Windows {
    var count: c_int = 0;
    const pointer = c.SDL_GetWindows(&count);
    if (pointer == null) return error.SdlFailure;
    errdefer c.SDL_free(@ptrCast(pointer));
    if (count < 0) return error.SdlFailure;
    return .{ .native = pointer, .count = @intCast(count) };
}

/// Borrow the currently grabbed window on the main thread, or null when no grab is active.
/// Requires initialized video. No wrapper allocation or retention; the window owner outlives use.
/// A pending request on a hidden/unfocused window need not produce an active grab.
pub fn grabbed_window() ?WindowRef {
    const handle = c.SDL_GetGrabbedWindow() orelse return null;
    return .{ .handle = handle };
}

/// Rectangle in client coordinates, used for safe areas and mouse confinement, not desktop layout.
pub const ClientArea = struct {
    /// Horizontal origin relative to the client area.
    x: i32,
    /// Vertical origin relative to the client area.
    y: i32,
    /// Nonnegative horizontal extent in window coordinates.
    width: u32,
    /// Nonnegative vertical extent in window coordinates.
    height: u32,
};

/// Native window decoration extents in screen coordinates; excludes the client area.
pub const BorderSizes = struct {
    /// Decoration above the client area.
    top: u32,
    /// Decoration to the left of the client area.
    left: u32,
    /// Decoration below the client area.
    bottom: u32,
    /// Decoration to the right of the client area.
    right: u32,
};

/// Request/cancel native attention notification. Actual appearance and duration are platform
/// policy.
pub const Attention = enum(c_uint) {
    /// Cancel any existing flash request.
    cancel = c.SDL_FLASH_CANCEL,
    /// Request a short attention indication.
    briefly = c.SDL_FLASH_BRIEFLY,
    /// Request continued attention indication until the window gains focus.
    until_focused = c.SDL_FLASH_UNTIL_FOCUSED,
};

/// Per-axis client-size limits in window coordinates. Null means unrestricted, independently.
pub const SizeLimits = struct {
    /// Positive horizontal limit fitting C int, or null to remove this axis limit.
    width: ?u32 = null,
    /// Positive vertical limit fitting C int, or null to remove this axis limit.
    height: ?u32 = null,
};

/// Width/height ratio interval. Null endpoints are unrestricted; equal endpoints fix a ratio.
pub const AspectLimits = struct {
    /// Finite positive lower bound, or null. Must not exceed a present maximum.
    minimum: ?f32 = null,
    /// Finite positive upper bound, or null. Must not be below a present minimum.
    maximum: ?f32 = null,
};

/// One axis of a window position request. Display hints are encoded without exposing magic
/// integers.
pub const AxisPosition = union(enum) {
    /// Desktop coordinate; native reserved hint ranges are rejected with InvalidPosition.
    coordinate: i32,
    /// Center on this display; null selects the primary display. Nonzero IDs must fit 16 bits.
    centered: ?@import("display.zig").DisplayId,
    /// Let the backend choose on this display; null selects primary. Not a retain-position promise.
    unspecified: ?@import("display.zig").DisplayId,
};

/// Requested desktop axes, independently specified. Defaults center on the primary display.
pub const PositionRequest = struct {
    /// Horizontal placement, subject to window-manager policy.
    x: AxisPosition = .{ .centered = null },
    /// Vertical placement, subject to window-manager policy.
    y: AxisPosition = .{ .centered = null },
};

/// Window creation settings. Platform support and window-manager policy constrain requests.
/// Options/title are borrowed only during `Window.init`; SDL retains its own window state.
pub const WindowOptions = struct {
    /// Zero-terminated UTF-8 title. Not validated; embedded zero bytes end the native title early.
    title: [:0]const u8,
    /// Initial client dimensions in window coordinates, not physical framebuffer pixels.
    size: Size,
    /// Allow user resizing when true; false by default. The platform may impose constraints.
    resizable: bool = false,
    /// Start hidden when true; false requests a visible window. Use WindowRef.show to show later.
    hidden: bool = false,
    /// Start in borderless desktop fullscreen; exclusive mode selection is a later operation.
    fullscreen: bool = false,
    /// Omit native decorations when supported.
    borderless: bool = false,
    /// Request stacking above ordinary windows; subject to desktop policy.
    always_on_top: bool = false,
    /// Request framebuffer transparency; platform/backend support is required.
    transparent: bool = false,
    /// Allow focus when true (default). False creates a window ineligible for input focus.
    focusable: bool = true,
    /// Request utility-window treatment, normally omitting taskbar/window-list entries.
    utility: bool = false,
    /// Native graphics capability; no context, Vulkan surface, or Metal view is created here.
    graphics_backend: GraphicsBackend = .none,
    /// Request a high-density drawable when supported; false by default. Query pixel_size
    /// separately.
    high_pixel_density: bool = false,
};

/// Mutually exclusive popup behavior; neither type is a normal top-level window.
pub const PopupKind = enum {
    /// Noninteractive tooltip; no normal input events/focus.
    tooltip,
    /// Popup menu, normally taking keyboard focus when shown unless focusable is false.
    menu,
};

/// Parented popup request. The parent must remain alive until this owner's explicit destruction.
pub const PopupOptions = struct {
    /// Choose tooltip or menu behavior. No incompatible utility/modal/fullscreen flags are exposed.
    kind: PopupKind,
    /// Positive requested client dimensions fitting C int; backend may constrain actual size.
    size: Size,
    /// Signed offsets relative to the parent's origin, not desktop coordinates or centering hints.
    offset: @import("display.zig").Point = .{ .x = 0, .y = 0 },
    /// Start explicitly hidden. Parent hiding can independently hide descendants.
    hidden: bool = false,
    /// Allow menu focus when true; tooltip behavior remains noninteractive.
    focusable: bool = true,
    /// Request a high-density drawable where available.
    high_pixel_density: bool = false,
    /// Request per-pixel transparency where supported.
    transparent: bool = false,
    /// Permit user resizing where the popup backend supports it.
    resizable: bool = false,
    /// Request stacking above other windows, subject to popup/backend policy.
    always_on_top: bool = false,
    /// Request a native graphics capability without creating its context/surface/view.
    graphics_backend: GraphicsBackend = .none,
};

/// Owns a native window. Keep it alive until every renderer/other child has been destroyed.
/// Do not copy or fabricate owners. Use `borrow` for operations; `deinit` invalidates all views.
/// For parented windows, explicitly destroy this owner before its parent: SDL also recursively
/// destroys native children during parent destruction, which would invalidate this owner.
pub const Window = struct {
    /// Native interop handle. Never destroy it separately, replace it, or use it after owner
    /// cleanup.
    handle: *c.SDL_Window,

    /// Create a window on the main thread after `sdl.init(.{ .video = true })`.
    /// `InvalidSize` rejects zero/oversized dimensions before SDL is called. `SdlFailure` means
    /// native creation failed; no owner is returned. SDL may allocate or block during creation.
    /// On success, pair `deinit` with `defer` immediately. The title/options need not outlive this
    /// call.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var subsystems = try sdl.init(.{ .video = true });
    /// defer subsystems.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Example", .size = .{ .width = 320, .height = 240 }, .hidden = true,
    /// });
    /// defer window.deinit();
    /// try window.borrow().set_title("Updated title");
    /// try window.borrow().set_size(.{ .width = 400, .height = 300 });
    /// try window.borrow().set_position(.{}); // Center on the primary display.
    /// try window.borrow().sync();
    /// const drawable = try window.borrow().pixel_size();
    /// _ = drawable;
    /// ```
    pub fn init(options: *const WindowOptions) Error!Window {
        try validate_size(options.size);
        var flags: c.SDL_WindowFlags = 0;
        if (options.resizable) flags |= c.SDL_WINDOW_RESIZABLE;
        if (options.fullscreen) flags |= c.SDL_WINDOW_FULLSCREEN;
        if (options.borderless) flags |= c.SDL_WINDOW_BORDERLESS;
        if (options.always_on_top) flags |= c.SDL_WINDOW_ALWAYS_ON_TOP;
        if (options.transparent) flags |= c.SDL_WINDOW_TRANSPARENT;
        if (!options.focusable) flags |= c.SDL_WINDOW_NOT_FOCUSABLE;
        if (options.utility) flags |= c.SDL_WINDOW_UTILITY;
        flags |= graphics_flags(options.graphics_backend);
        if (options.hidden) flags |= c.SDL_WINDOW_HIDDEN;
        if (options.high_pixel_density) flags |= c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
        const handle = c.SDL_CreateWindow(
            options.title,
            @intCast(options.size.width),
            @intCast(options.size.height),
            flags,
        ) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Create a popup on the main thread with initialized video and a live parent.
    /// Parent may itself be a popup. Parent and its ancestors must outlive this owner; immediately
    /// defer child deinit so it runs before parent cleanup. SDL recursively destroys/hides children
    /// with their parent, but this wrapper requires explicit child-first owner destruction.
    /// InvalidSize rejects dimensions; InvalidPosition rejects offset collisions with SDL hints.
    /// SdlFailure includes unsupported popup backends; no owner returned. Native creation
    /// allocates.
    /// Actual size/position/focus may be constrained. Popup reparenting/modal/fullscreen is
    /// unsupported.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// var parent = try sdl.video.Window.init(&.{
    ///     .title = "Parent", .size = .{ .width = 64, .height = 64 }, .hidden = true,
    /// });
    /// defer parent.deinit();
    /// if (sdl.video.Window.init_popup(parent.borrow(), &.{
    ///     .kind = .tooltip, .size = .{ .width = 16, .height = 16 }, .hidden = true,
    /// })) |created| {
    ///     var popup = created;
    ///     defer popup.deinit(); // Runs before parent cleanup.
    ///     const testing = @import("std").testing;
    ///     try testing.expectEqual(parent.handle, popup.borrow().parent().?.handle);
    /// } else |err| {
    ///     // A backend without popups returns SdlFailure; choose application fallback behavior.
    ///     try @import("std").testing.expectEqual(error.SdlFailure, err);
    /// }
    /// ```
    pub fn init_popup(parent: WindowRef, options: *const PopupOptions) Error!Window {
        try validate_size(options.size);
        const x = try encode_axis(.{ .coordinate = options.offset.x });
        const y = try encode_axis(.{ .coordinate = options.offset.y });
        var flags: c.SDL_WindowFlags = switch (options.kind) {
            .tooltip => c.SDL_WINDOW_TOOLTIP,
            .menu => c.SDL_WINDOW_POPUP_MENU,
        };
        flags |= graphics_flags(options.graphics_backend);
        if (options.hidden) flags |= c.SDL_WINDOW_HIDDEN;
        if (!options.focusable) flags |= c.SDL_WINDOW_NOT_FOCUSABLE;
        if (options.high_pixel_density) flags |= c.SDL_WINDOW_HIGH_PIXEL_DENSITY;
        if (options.transparent) flags |= c.SDL_WINDOW_TRANSPARENT;
        if (options.resizable) flags |= c.SDL_WINDOW_RESIZABLE;
        if (options.always_on_top) flags |= c.SDL_WINDOW_ALWAYS_ON_TOP;
        const handle = c.SDL_CreatePopupWindow(
            parent.handle,
            x,
            y,
            @intCast(options.size.width),
            @intCast(options.size.height),
            flags,
        ) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Destroy on the main thread after all children. Invalidates this owner and its views.
    /// Call exactly once; copying an owner does not acquire another window. No fallible result.
    pub fn deinit(self: *Window) void {
        c.SDL_DestroyWindow(self.handle);
        self.* = undefined;
    }

    /// Return a non-owning, freely copyable view without allocation or native calls.
    /// The window must outlive the view; borrowing neither retains nor transfers ownership.
    pub fn borrow(self: *const Window) WindowRef {
        return .{ .handle = self.handle };
    }
};

/// Non-owning window view. Its owner must outlive every operation and dependent resource.
pub const WindowRef = struct {
    /// Native interop handle. Never destroy it separately, replace it, or use it after owner
    /// cleanup.
    handle: *c.SDL_Window,

    /// Borrow this object's native property group. Main thread only.
    /// May allocate/block; `SdlFailure` returns no view. The object owns the group: never destroy
    /// it separately. Finish all views/locks before object destruction. Use application-specific
    /// keys for custom data; native keys retain their individual read/write and lifetime contracts.
    pub fn properties(
        self: WindowRef,
    ) @import("errors.zig").Error!@import("properties.zig").PropertiesRef {
        const handle = c.SDL_GetWindowProperties(self.handle);
        if (handle == 0) return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Query the display associated with this window. Main thread; no display ownership transfer.
    /// Requery after window movement/display events. SdlFailure reports native query failure.
    pub fn display(self: WindowRef) Error!@import("display.zig").DisplayId {
        const value = c.SDL_GetDisplayForWindow(self.handle);
        if (value == 0) return error.SdlFailure;
        return @fromBackingInt(value);
    }

    /// Query this window's content scale on the main thread, which may differ from its display.
    /// Requery after display/scale events. No wrapper allocation; SdlFailure rejects unavailable,
    /// nonpositive, or nonfinite values. This is separate from the pixel-size/client-size ratio.
    pub fn display_scale(self: WindowRef) Error!f32 {
        const scale = c.SDL_GetWindowDisplayScale(self.handle);
        if (!std.math.isFinite(scale) or scale <= 0) return error.SdlFailure;
        return scale;
    }

    /// Snapshot native window flags on the main thread without wrapper allocation.
    /// State may describe an in-flight request; use events/sync for completed transitions.
    /// Requires a valid live window; SDL's zero result has no distinct error representation.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Flags", .size = .{ .width = 32, .height = 32 },
    ///     .hidden = true, .resizable = true,
    /// });
    /// defer window.deinit();
    /// try @import("std").testing.expect(window.borrow().flags().contains(.resizable));
    /// ```
    pub fn flags(self: WindowRef) WindowFlags {
        return .{ .bits = c.SDL_GetWindowFlags(self.handle) };
    }

    /// Request native decorations on the main thread, subject to fullscreen/backend restrictions.
    /// Unchanged state is a no-op on supported backends. May allocate/block; rejection is
    /// SdlFailure.
    pub fn set_bordered(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowBordered(self.handle, enabled)) return error.SdlFailure;
    }

    /// Allow/disallow user resizing on the main thread, subject to fullscreen/backend restrictions.
    /// Unchanged state is a no-op on supported backends. May allocate/block; rejection is
    /// SdlFailure.
    pub fn set_resizable(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowResizable(self.handle, enabled)) return error.SdlFailure;
    }

    /// Request stacking above ordinary windows on the main thread, subject to desktop policy.
    /// May allocate/block; SdlFailure reports native rejection. Does not guarantee keyboard focus.
    pub fn set_always_on_top(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowAlwaysOnTop(self.handle, enabled)) return error.SdlFailure;
    }

    /// Request raising and input focus on the main thread, subject to focus-stealing policy.
    /// Success does not promise focus; inspect input_focus/events. May allocate/block; native
    /// rejection returns SdlFailure. Does not create or transfer ownership.
    pub fn raise(self: WindowRef) Error!void {
        if (!c.SDL_RaiseWindow(self.handle)) return error.SdlFailure;
    }

    /// Request maximization on the main thread; a non-resizable window may be rejected.
    /// May allocate/block or complete asynchronously; desktop policy can deny/constrain the result.
    /// Native rejection returns SdlFailure; use events/sync then flags for resulting state.
    pub fn maximize(self: WindowRef) Error!void {
        if (!c.SDL_MaximizeWindow(self.handle)) return error.SdlFailure;
    }

    /// Request minimization on the main thread; native rejection returns SdlFailure.
    /// May allocate/block or complete asynchronously; desktop policy may deny it. Fullscreen has
    /// no direct change, but the post-fullscreen state may change. Query flags after events/sync.
    pub fn minimize(self: WindowRef) Error!void {
        if (!c.SDL_MinimizeWindow(self.handle)) return error.SdlFailure;
    }

    /// Request restoration from minimized/maximized state on the main thread.
    /// May allocate/block or complete asynchronously; desktop policy may deny it. Fullscreen has
    /// no direct change, but post-fullscreen state may change. Native rejection is SdlFailure.
    pub fn restore(self: WindowRef) Error!void {
        if (!c.SDL_RestoreWindow(self.handle)) return error.SdlFailure;
    }

    /// Select a fullscreen mode on the main thread; null selects borderless desktop fullscreen.
    /// Use a freshly queried display mode token for exclusive fullscreen. SDL copies the request;
    /// the token/list need not outlive this call. Does not itself enter fullscreen. Native failure
    /// is SdlFailure; a visible fullscreen transition may be asynchronous and may allocate/block.
    pub fn set_fullscreen_mode(self: WindowRef, mode: ?@import("display.zig").Mode) Error!void {
        const pointer = if (mode) |*value| &value.native else null;
        if (!c.SDL_SetWindowFullscreenMode(self.handle, pointer)) return error.SdlFailure;
    }

    /// Copy the selected exclusive fullscreen mode on the main thread; null means desktop mode.
    /// SDL also returns null for unsupported popup windows, so no error distinction is available.
    /// No wrapper allocation; token lifetime follows display configuration, not the window query.
    pub fn fullscreen_mode(self: WindowRef) ?@import("display.zig").Mode {
        const pointer = c.SDL_GetWindowFullscreenMode(self.handle);
        if (pointer == null) return null;
        return .{ .native = pointer.* };
    }

    /// Request entry to or exit from fullscreen on the main thread. Mode selection is separate:
    /// null fullscreen_mode means desktop fullscreen. May allocate/block or apply asynchronously;
    /// SdlFailure reports rejection. Use events/sync and requery state after the request.
    pub fn set_fullscreen(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowFullscreen(self.handle, enabled)) return error.SdlFailure;
    }

    /// Set a UTF-8 sentinel title on the main thread; input is borrowed only during this call.
    /// Embedded zeros truncate; UTF-8 is not validated. Native copying may allocate; SdlFailure
    /// reports failure. Invalidates previous title views when SDL replaces its stored string.
    pub fn set_title(self: WindowRef, value: [:0]const u8) Error!void {
        if (!c.SDL_SetWindowTitle(self.handle, value)) return error.SdlFailure;
    }

    /// Borrow the title on the main thread, until title replacement or window destruction.
    /// Empty means no title. No ownership transfer; copy to retain. Null native result is
    /// SdlFailure.
    pub fn title(self: WindowRef) Error![:0]const u8 {
        const value = c.SDL_GetWindowTitle(self.handle);
        if (value == null) return error.SdlFailure;
        return std.mem.span(value);
    }

    /// Request client size on the main thread. Rejects zero/oversized dimensions with InvalidSize
    /// before changing state. Native failure is SdlFailure. May allocate/block; may be
    /// asynchronous,
    /// constrained, ignored in fullscreen/maximized state, or denied by the window manager.
    /// Query size/events for actual dimensions; sync waits for pending state without exact-size
    /// promises.
    pub fn set_size(self: WindowRef, value: Size) Error!void {
        try validate_size(value);
        if (!c.SDL_SetWindowSize(self.handle, @intCast(value.width), @intCast(value.height)))
            return error.SdlFailure;
    }

    /// Request desktop placement on the main thread. Both axes validate before native mutation.
    /// InvalidPosition reports unrepresentable hints/coordinates; SdlFailure reports native
    /// failure.
    /// May allocate/block. Successful requests can be asynchronous, constrained, denied, or ignored
    /// in exclusive fullscreen/maximized state. Query position/events for actual coordinates.
    pub fn set_position(self: WindowRef, value: PositionRequest) Error!void {
        const x = try encode_axis(value.x);
        const y = try encode_axis(value.y);
        if (!c.SDL_SetWindowPosition(self.handle, x, y)) return error.SdlFailure;
    }

    /// Query the last desktop coordinates reported by the backend on the main thread.
    /// No wrapper allocation; SdlFailure reports native failure. Pending requests may not appear
    /// yet.
    pub fn position(self: WindowRef) Error!@import("display.zig").Point {
        var value: @import("display.zig").Point = undefined;
        if (!c.SDL_GetWindowPosition(self.handle, &value.x, &value.y)) return error.SdlFailure;
        return value;
    }

    /// Request visibility on the main thread. May allocate/block; SdlFailure reports native
    /// failure.
    /// A visible window can still be occluded or minimized; this does not guarantee input focus.
    pub fn show(self: WindowRef) Error!void {
        if (!c.SDL_ShowWindow(self.handle)) return error.SdlFailure;
    }

    /// Hide on the main thread, removing normal desktop/taskbar visibility where supported.
    /// May allocate/block; SdlFailure reports native failure. Does not destroy the window or
    /// children.
    pub fn hide(self: WindowRef) Error!void {
        if (!c.SDL_HideWindow(self.handle)) return error.SdlFailure;
    }

    /// Wait on the main thread for pending window state. SdlFailure includes a native timeout.
    /// Native wait duration is finite but platform-defined, potentially including animations.
    /// No caller deadline or real-time bound; avoid per-frame waits. Requery actual state
    /// afterward.
    pub fn sync(self: WindowRef) Error!void {
        if (!c.SDL_SyncWindow(self.handle)) return error.SdlFailure;
    }

    /// Query a nonzero identity on the main thread. Returns `SdlFailure` on native failure.
    /// The ID may be retained for event comparisons; it does not keep the window alive.
    pub fn id(self: WindowRef) Error!WindowId {
        const value = c.SDL_GetWindowID(self.handle);
        if (value == 0) return error.SdlFailure;
        return @fromBackingInt(@intCast(value));
    }

    /// Request mouse confinement to this window on the main thread; false releases it.
    /// Popups cannot grab. Hidden-window requests can remain pending until shown; focus is required
    /// for an active grab. May allocate/block; SdlFailure reports native rejection. Enabling a grab
    /// can displace another window's grab. This is distinct from relative mode and capture.
    pub fn set_mouse_grab(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowMouseGrab(self.handle, enabled)) return error.SdlFailure;
    }

    /// Query SDL's active mouse grab for this window on the main thread; no wrapper allocation.
    /// False can coexist with a pending/enabled request when hidden or unfocused. Requires a live
    /// window. This reports SDL state, not independent proof that the OS confines the cursor.
    pub fn mouse_grabbed(self: WindowRef) bool {
        return c.SDL_GetWindowMouseGrab(self.handle);
    }

    /// Request capture of system keyboard shortcuts on the main thread; false releases it.
    /// Intended for VM/remote-desktop style workflows; not all OS shortcuts can be captured.
    /// Hidden requests may remain pending and focus is required. Enabling can replace another
    /// window's grab. Popups cannot grab. May allocate/block; SdlFailure reports native rejection.
    pub fn set_keyboard_grab(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowKeyboardGrab(self.handle, enabled)) return error.SdlFailure;
    }

    /// Query SDL's active keyboard grab on the main thread. No wrapper allocation.
    /// Requires a live window; false includes pending/disabled/unfocused state. Even true does not
    /// mean every system shortcut is captured; OS and fullscreen shortcut policies still apply.
    pub fn keyboard_grabbed(self: WindowRef) bool {
        return c.SDL_GetWindowKeyboardGrab(self.handle);
    }

    /// Set a client-coordinate mouse barrier on the main thread; null removes it.
    /// Does not grab the cursor; confinement applies with mouse focus. InvalidRegion
    /// rejects empty/oversized extents or overflowing signed endpoints before native mutation.
    /// Actual enforcement/clipping is backend policy. May allocate/block; SdlFailure includes
    /// unsupported platforms and can leave the new rectangle stored on backend failure.
    pub fn set_mouse_confinement(self: WindowRef, area: ?ClientArea) Error!void {
        const rect = if (area) |value| try encode_confinement(value) else null;
        const pointer = if (rect) |*value| value else null;
        if (!c.SDL_SetWindowMouseRect(self.handle, pointer)) return error.SdlFailure;
    }

    /// Copy the stored mouse barrier on the main thread, or null when none/empty.
    /// No wrapper allocation or borrowed rectangle pointer escapes. Requires a live window; SDL's
    /// null result also covers invalid handles. InvalidSize rejects negative native extents.
    /// This reports stored policy, not actual cursor confinement, and is independent of grab state.
    pub fn mouse_confinement(self: WindowRef) Error!?ClientArea {
        const rect = c.SDL_GetWindowMouseRect(self.handle);
        if (rect == null) return null;
        const dimensions = try checked_size(rect.*.w, rect.*.h);
        return .{
            .x = rect.*.x,
            .y = rect.*.y,
            .width = dimensions.width,
            .height = dimensions.height,
        };
    }

    /// Enable/disable relative mouse mode on the main thread. With focus, SDL hides/constrains the
    /// cursor and reports continuous relative motion at edges. Flushes pending mouse motion for
    /// this window and disables warp-emulation fallback. May allocate/block; SdlFailure reports
    /// native rejection. A request without focus need not activate physical relative mode.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Relative input", .size = .{ .width = 32, .height = 32 }, .hidden = true,
    /// });
    /// defer window.deinit();
    /// try window.borrow().set_relative_mouse_mode(true);
    /// try @import("std").testing.expect(window.borrow().relative_mouse_mode());
    /// try window.borrow().set_relative_mouse_mode(false);
    /// ```
    pub fn set_relative_mouse_mode(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowRelativeMouseMode(self.handle, enabled)) return error.SdlFailure;
    }

    /// Query whether relative mode is enabled for this live window on the main thread.
    /// No wrapper allocation. Enabled state does not establish focus or active physical mode.
    pub fn relative_mouse_mode(self: WindowRef) bool {
        return c.SDL_GetWindowRelativeMouseMode(self.handle);
    }

    /// Check whether a window-owned surface exists on the main thread. No wrapper allocation.
    /// True does not establish freshness after resizing; reacquire with surface before drawing.
    pub fn has_surface(self: WindowRef) bool {
        return c.SDL_WindowHasSurface(self.handle);
    }

    /// Borrow/create the window's optimal-format software surface on the main thread.
    /// SDL owns it: never wrap it in a Surface owner or destroy it directly. Native creation may
    /// allocate; SdlFailure returns no view. Do not combine this workflow with a renderer/3D API
    /// on the same window. The format is not necessarily RGBA32; use general surface operations.
    /// Window resize, release_surface, or destruction invalidates the view. Reacquire after resize.
    /// All access to this window-owned surface follows the main-thread window contract. Finish
    /// pixel locks before presentation/resizing/release; do not retain raw pixel pointers across
    /// them.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Software", .size = .{ .width = 32, .height = 32 }, .hidden = true,
    /// });
    /// defer window.deinit();
    /// const pixels = try window.borrow().surface();
    /// try pixels.fill(.{ .r = 20, .g = 40, .b = 80 });
    /// try window.borrow().present_surface();
    /// // No pixels.deinit(): the window owns this surface.
    /// ```
    pub fn surface(self: WindowRef) Error!@import("surface.zig").SurfaceRef {
        const handle = c.SDL_GetWindowSurface(self.handle) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Present the whole software surface on the main thread. Acquire it first and reacquire after
    /// resize; invalid/missing surfaces return SdlFailure. Finish all pixel locks before this call.
    /// Native presentation may allocate/block and can replace pixel storage; retain no raw rows or
    /// pixel pointers across it. Does not transfer ownership or guarantee a visible/instant
    /// display.
    pub fn present_surface(self: WindowRef) Error!void {
        if (!c.SDL_UpdateWindowSurface(self.handle)) return error.SdlFailure;
    }

    /// Release the window-owned software surface/framebuffer on the main thread; window stays
    /// alive.
    /// All borrowed surface/property/pixel views must be finished first and become invalid.
    /// Native failure is SdlFailure; no surface is needed for successful cleanup. A later surface()
    /// can allocate a new buffer. Never destroy the borrowed SurfaceRef through raw interop.
    pub fn release_surface(self: WindowRef) Error!void {
        if (!c.SDL_DestroyWindowSurface(self.handle)) return error.SdlFailure;
    }

    /// Request synchronization for an existing window surface on the main thread.
    /// InvalidVSync rejects invalid intervals before SDL runs; SdlFailure includes unsupported
    /// modes/backends. Native code may allocate/block; no guarantee of a particular frame rate.
    pub fn set_surface_vsync(self: WindowRef, mode: SurfaceVSync) Error!void {
        const value = try encode_surface_vsync(mode);
        if (!c.SDL_SetWindowSurfaceVSync(self.handle, value)) return error.SdlFailure;
    }

    /// Query software-surface synchronization on the main thread. No wrapper allocation.
    /// SdlFailure includes unsupported query/backend and invalid returned native intervals.
    pub fn surface_vsync(self: WindowRef) Error!SurfaceVSync {
        var value: c_int = 0;
        if (!c.SDL_GetWindowSurfaceVSync(self.handle, &value)) return error.SdlFailure;
        return decode_surface_vsync(value);
    }

    /// Query the window's native pixel format on the main thread. No wrapper allocation.
    /// SdlFailure represents SDL's unknown result; this does not create a software surface or
    /// describe every renderer texture format. Unknown future nonzero format values are preserved.
    pub fn pixel_format(self: WindowRef) Error!@import("pixels.zig").Format {
        const value = c.SDL_GetWindowPixelFormat(self.handle);
        if (value == c.SDL_PIXELFORMAT_UNKNOWN) return error.SdlFailure;
        return @fromBackingInt(value);
    }

    /// Query drawable pixels per window-coordinate unit on the main thread.
    /// Distinct from display_scale (recommended UI scale). Requery after DPI/display changes.
    /// No wrapper allocation; SdlFailure rejects unavailable/nonpositive/nonfinite native values.
    pub fn pixel_density(self: WindowRef) Error!f32 {
        const value = c.SDL_GetWindowPixelDensity(self.handle);
        if (!std.math.isFinite(value) or value <= 0) return error.SdlFailure;
        return value;
    }

    /// Query client space suitable for important/interactable content on the main thread.
    /// Render backgrounds outside this rectangle if desired. Requery after size/safe-area changes.
    /// No wrapper allocation; SdlFailure reports native failure, InvalidSize negative extents.
    /// This is a snapshot in window coordinates, not pixels or guaranteed permanent insets.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Safe area", .size = .{ .width = 320, .height = 240 }, .hidden = true,
    /// });
    /// defer window.deinit();
    /// const safe = try window.borrow().safe_area();
    /// const density = try window.borrow().pixel_density();
    /// _ = safe;
    /// try @import("std").testing.expect(density > 0);
    /// ```
    pub fn safe_area(self: WindowRef) Error!ClientArea {
        var native: c.SDL_Rect = undefined;
        if (!c.SDL_GetWindowSafeArea(self.handle, &native)) return error.SdlFailure;
        const dimensions = try checked_size(native.w, native.h);
        return .{
            .x = native.x,
            .y = native.y,
            .width = dimensions.width,
            .height = dimensions.height,
        };
    }

    /// Query native decoration extents on the main thread. SdlFailure includes unsupported queries
    /// and windows not yet decorated/composited; it is not converted to a borderless zero result.
    /// Negative native extents are InvalidSize. No wrapper allocation; retry after presentation
    /// when appropriate. Successful zeros can describe a borderless window.
    pub fn border_sizes(self: WindowRef) Error!BorderSizes {
        var top: c_int = 0;
        var left: c_int = 0;
        var bottom: c_int = 0;
        var right: c_int = 0;
        if (!c.SDL_GetWindowBordersSize(self.handle, &top, &left, &bottom, &right))
            return error.SdlFailure;
        if (top < 0 or left < 0 or bottom < 0 or right < 0) return error.InvalidSize;
        return .{
            .top = @intCast(top),
            .left = @intCast(left),
            .bottom = @intCast(bottom),
            .right = @intCast(right),
        };
    }

    /// Set whole-window opacity on the main thread: zero transparent, one opaque.
    /// InvalidOpacity rejects nonfinite/out-of-range input before native calls, rather than native
    /// clamping. SdlFailure includes unsupported compositing. May allocate/block. This is separate
    /// from per-pixel framebuffer alpha and surface blit opacity; requests no hit-test policy.
    pub fn set_opacity(self: WindowRef, value: f32) Error!void {
        try validate_opacity(value);
        if (!c.SDL_SetWindowOpacity(self.handle, value)) return error.SdlFailure;
    }

    /// Query whole-window opacity on the main thread. Unsupported transparency reports one.
    /// No wrapper allocation; SdlFailure rejects failure/nonfinite/out-of-range native results.
    /// A value of one does not establish that opacity changes are supported.
    pub fn opacity(self: WindowRef) Error!f32 {
        const value = c.SDL_GetWindowOpacity(self.handle);
        validate_opacity(value) catch return error.SdlFailure;
        return value;
    }

    /// Set taskbar progress state on the main thread; none hides the indicator.
    /// May allocate/block. SdlFailure includes invalid/unsupported states and native rejection;
    /// Native state may change even on failure. Success need not show a physical indicator.
    pub fn set_progress_state(self: WindowRef, state: ProgressState) Error!void {
        if (!c.SDL_SetWindowProgressState(self.handle, @backingInt(state))) return error.SdlFailure;
    }

    /// Query stored taskbar progress state on the main thread, not proof of physical presentation.
    /// Native invalid sentinel becomes SdlFailure; unknown states are preserved.
    /// No wrapper allocation; SDL may allocate diagnostic storage on failure.
    pub fn progress_state(self: WindowRef) Error!ProgressState {
        const value = c.SDL_GetWindowProgressState(self.handle);
        if (value == c.SDL_PROGRESS_STATE_INVALID) return error.SdlFailure;
        return @fromBackingInt(value);
    }

    /// Set taskbar completion fraction on the main thread; does not select/show a progress state.
    /// InvalidProgress rejects nonfinite/out-of-range values before SDL runs; no silent clamping.
    /// May allocate/block. SdlFailure can leave the new value stored; requery on native failure.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Progress", .size = .{ .width = 32, .height = 32 }, .hidden = true,
    /// });
    /// defer window.deinit();
    /// try window.borrow().set_progress_state(.normal);
    /// try window.borrow().set_progress_value(0.25);
    /// const testing = @import("std").testing;
    /// try testing.expectEqual(@as(f32, 0.25), try window.borrow().progress_value());
    /// try window.borrow().set_progress_state(.none); // Hide without resetting the fraction.
    /// ```
    pub fn set_progress_value(self: WindowRef, value: f32) Error!void {
        validate_opacity(value) catch return error.InvalidProgress;
        if (!c.SDL_SetWindowProgressValue(self.handle, value)) return error.SdlFailure;
    }

    /// Query the stored taskbar completion fraction on the main thread, independent of state.
    /// No wrapper allocation; SdlFailure rejects native failure/nonfinite/out-of-range results.
    pub fn progress_value(self: WindowRef) Error!f32 {
        const value = c.SDL_GetWindowProgressValue(self.handle);
        validate_opacity(value) catch return error.SdlFailure;
        return value;
    }

    /// Reparent a regular window on the main thread; null detaches it. No owner is consumed.
    /// Child owner must be destroyed before its new parent; the parent must outlive all child uses.
    /// InvalidParent rejects self/sibling/descendant links; HierarchyTooDeep rejects more than 256
    /// ancestors before mutation. Clear modal state first; popups cannot reparent or parent top
    /// levels.
    /// Native calls may allocate/block. SdlFailure can detach the old parent on backend failure;
    /// requery parent afterward. Requires a valid acyclic live hierarchy, including raw interop.
    pub fn set_parent(self: WindowRef, new_parent: ?WindowRef) Error!void {
        if (new_parent) |candidate| try validate_parent(self, candidate);
        const handle = if (new_parent) |candidate| candidate.handle else null;
        if (!c.SDL_SetWindowParent(self.handle, handle)) return error.SdlFailure;
    }

    /// Request modal status on the main thread; enabling requires a current parent.
    /// Popup windows cannot be modal. May allocate/block; SdlFailure can leave changed modal flags.
    /// Success may defer native application while hidden. Clear modal before reparenting.
    /// Does not transfer ownership or relieve child-before-parent cleanup obligations.
    pub fn set_modal(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowModal(self.handle, enabled)) return error.SdlFailure;
    }

    /// Borrow the current parent on the main thread, or null if there is none.
    /// No wrapper allocation/retention. Requires a live window; null also represents invalid
    /// handles.
    /// The parent must outlive use; reparenting/destruction can invalidate cached relationships.
    pub fn parent(self: WindowRef) ?WindowRef {
        const handle = c.SDL_GetWindowParent(self.handle) orelse return null;
        return .{ .handle = handle };
    }

    /// Request input-focus eligibility on the main thread, not focus itself.
    /// Native backends may accept without changing state; requery not_focusable in flags.
    /// May allocate/block; SdlFailure reports rejection and can leave updated native flags.
    pub fn set_focusable(self: WindowRef, enabled: bool) Error!void {
        if (!c.SDL_SetWindowFocusable(self.handle, enabled)) return error.SdlFailure;
    }

    /// Copy an icon from a live unlocked surface on the main thread; native conversion allocates.
    /// Borrow the source only for the call, including alternate images. SDL owns its converted
    /// copy;
    /// the caller retains and may destroy the source afterward. SdlFailure includes conversion or
    /// backend rejection and can still replace/discard the previous native icon. No rollback
    /// promise.
    pub fn set_icon(self: WindowRef, source: @import("surface.zig").SurfaceRef) Error!void {
        if (!c.SDL_SetWindowIcon(self.handle, source.handle)) return error.SdlFailure;
    }

    /// Request or cancel attention on the main thread. May allocate/block; SdlFailure includes
    /// unsupported backends/popups. Success does not guarantee notification appearance or focus.
    pub fn request_attention(self: WindowRef, operation: Attention) Error!void {
        if (!c.SDL_FlashWindow(self.handle, @backingInt(operation))) return error.SdlFailure;
    }

    /// Set minimum client dimensions on the main thread; null axes remove limits.
    /// InvalidConstraint rejects zero/oversized supplied values before SDL runs. Native conflicts
    /// with existing maximums return SdlFailure. May allocate/block/resize asynchronously. Native
    /// failure after storing constraints can leave changed state; requery after such failures.
    pub fn set_minimum_size(self: WindowRef, limits: SizeLimits) Error!void {
        const value = try encode_size_limits(limits);
        if (!c.SDL_SetWindowMinimumSize(self.handle, @intCast(value.width), @intCast(value.height)))
            return error.SdlFailure;
    }

    /// Query stored minimum client limits on the main thread, not current dimensions.
    /// Native zero axes become null. SdlFailure reports query failure; negative sizes are
    /// InvalidSize.
    /// No wrapper allocation. Window-manager policy still controls actual client sizing.
    pub fn minimum_size(self: WindowRef) Error!SizeLimits {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowMinimumSize(self.handle, &width, &height)) return error.SdlFailure;
        return decode_size_limits(try checked_size(width, height));
    }

    /// Set maximum client dimensions on the main thread; null axes remove limits.
    /// InvalidConstraint rejects zero/oversized supplied values before SDL runs. Native conflicts
    /// with existing minimums return SdlFailure. May allocate/block/resize asynchronously; native
    /// failure can leave updated constraints. Maximization policy may ignore maximum limits.
    pub fn set_maximum_size(self: WindowRef, limits: SizeLimits) Error!void {
        const value = try encode_size_limits(limits);
        if (!c.SDL_SetWindowMaximumSize(self.handle, @intCast(value.width), @intCast(value.height)))
            return error.SdlFailure;
    }

    /// Query stored maximum client limits on the main thread, not current dimensions.
    /// Native zero axes become null. SdlFailure reports query failure; negative sizes are
    /// InvalidSize.
    /// No wrapper allocation. This reports requested constraints, not guaranteed desktop policy.
    pub fn maximum_size(self: WindowRef) Error!SizeLimits {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowMaximumSize(self.handle, &width, &height)) return error.SdlFailure;
        return decode_size_limits(try checked_size(width, height));
    }

    /// Request a client width/height ratio interval on the main thread. Null removes an endpoint.
    /// InvalidConstraint rejects nonpositive/nonfinite/inverted limits before native mutation.
    /// May allocate/block/resize asynchronously; fullscreen/maximized changes can defer
    /// enforcement.
    /// SdlFailure can occur after SDL stored the limits; requery on failure. Desktop policy may
    /// deny or constrain actual dimensions. Equal endpoints request a fixed ratio.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Limits", .size = .{ .width = 320, .height = 240 }, .hidden = true,
    /// });
    /// defer window.deinit();
    /// try window.borrow().set_minimum_size(.{ .width = 160 });
    /// try window.borrow().set_aspect_limits(.{ .minimum = 1, .maximum = 2 });
    /// try window.borrow().set_aspect_limits(.{}); // Remove both ratio limits.
    /// ```
    pub fn set_aspect_limits(self: WindowRef, limits: AspectLimits) Error!void {
        try validate_aspect_limits(limits);
        if (!c.SDL_SetWindowAspectRatio(
            self.handle,
            limits.minimum orelse 0,
            limits.maximum orelse 0,
        )) return error.SdlFailure;
    }

    /// Query stored width/height ratio limits on the main thread. Native zero becomes null.
    /// No wrapper allocation; SdlFailure reports query failure. InvalidConstraint rejects invalid
    /// native intervals (including ones introduced by raw interop); this is not current aspect
    /// ratio.
    pub fn aspect_limits(self: WindowRef) Error!AspectLimits {
        var minimum: f32 = 0;
        var maximum: f32 = 0;
        if (!c.SDL_GetWindowAspectRatio(self.handle, &minimum, &maximum)) return error.SdlFailure;
        const limits = AspectLimits{
            .minimum = if (minimum == 0) null else minimum,
            .maximum = if (maximum == 0) null else maximum,
        };
        try validate_aspect_limits(limits);
        return limits;
    }

    /// Query client width/height in window coordinates on the main thread.
    /// Use `pixel_size` for framebuffer dimensions; high-density windows can differ.
    /// Returns `SdlFailure` on native failure, `InvalidSize` for negative native dimensions.
    /// Zero dimensions are preserved. No wrapper allocation; does not resize the window.
    pub fn size(self: WindowRef) Error!Size {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSize(self.handle, &width, &height)) return error.SdlFailure;
        return checked_size(width, height);
    }

    /// Query drawable width/height in pixels on the main thread; no wrapper allocation.
    /// Requery after `events.Event.window_pixel_size_changed`. This can differ from `size`.
    /// Returns `SdlFailure` on native failure, `InvalidSize` for negative native dimensions.
    /// Zero dimensions are preserved; do not assume a permanently valid framebuffer size.
    pub fn pixel_size(self: WindowRef) Error!Size {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetWindowSizeInPixels(self.handle, &width, &height)) return error.SdlFailure;
        return checked_size(width, height);
    }
};

/// Check creation dimensions without SDL calls, allocation, or initialization.
/// Returns `InvalidSize` unless both dimensions are positive and representable as C int.
/// This only validates representation; it does not guarantee platform/GPU size support.
/// Callable on any thread; leaves input and native error state unchanged.
pub fn validate_size(size: Size) error{InvalidSize}!void {
    if (size.width == 0 or size.height == 0) return error.InvalidSize;
    if (size.width > std.math.maxInt(c_int) or size.height > std.math.maxInt(c_int)) {
        return error.InvalidSize;
    }
}

fn checked_size(width: c_int, height: c_int) error{InvalidSize}!Size {
    if (width < 0 or height < 0) return error.InvalidSize;
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

test "window sizes reject invalid external input before native calls" {
    try std.testing.expectError(error.InvalidSize, validate_size(.{ .width = 0, .height = 1 }));
    try std.testing.expectError(error.InvalidSize, validate_size(.{ .width = 1, .height = 0 }));
    try std.testing.expectError(error.InvalidSize, validate_size(.{
        .width = std.math.maxInt(u32),
        .height = 1,
    }));
    try validate_size(.{ .width = 1, .height = 1 });
}

fn encode_axis(value: AxisPosition) error{InvalidPosition}!c_int {
    switch (value) {
        .coordinate => |coordinate| {
            const bits: u32 = @bitCast(coordinate);
            const high = bits & 0xffff0000;
            if (high == c.SDL_WINDOWPOS_CENTERED_MASK or high == c.SDL_WINDOWPOS_UNDEFINED_MASK)
                return error.InvalidPosition;
            return coordinate;
        },
        .centered, .unspecified => |display| {
            const id: u32 = if (display) |known| @backingInt(known) else 0;
            if (display != null and (id == 0 or id > 0xffff)) return error.InvalidPosition;
            const mask: u32 = if (value == .centered)
                c.SDL_WINDOWPOS_CENTERED_MASK
            else
                c.SDL_WINDOWPOS_UNDEFINED_MASK;
            return @intCast(mask | id);
        },
    }
}

test "window axis encoding separates coordinates from display hints" {
    try std.testing.expectEqual(@as(c_int, -123), try encode_axis(.{ .coordinate = -123 }));
    try std.testing.expectEqual(
        @as(c_int, c.SDL_WINDOWPOS_CENTERED),
        try encode_axis(.{ .centered = null }),
    );
    try std.testing.expectEqual(
        @as(c_int, c.SDL_WINDOWPOS_UNDEFINED_MASK | 42),
        try encode_axis(.{ .unspecified = @fromBackingInt(@as(u32, 42)) }),
    );
    try std.testing.expectError(error.InvalidPosition, encode_axis(.{ .centered = .invalid }));
    try std.testing.expectError(
        error.InvalidPosition,
        encode_axis(.{ .centered = @fromBackingInt(@as(u32, 65536)) }),
    );
    try std.testing.expectError(
        error.InvalidPosition,
        encode_axis(.{ .coordinate = c.SDL_WINDOWPOS_CENTERED }),
    );
    try std.testing.expectError(
        error.InvalidPosition,
        encode_axis(.{ .coordinate = c.SDL_WINDOWPOS_UNDEFINED_MASK | 42 }),
    );
}

test "window flag snapshots preserve unknown bits and query named state" {
    const unknown: u64 = @as(u64, 1) << 63;
    const flags = WindowFlags{ .bits = unknown | c.SDL_WINDOW_HIDDEN | c.SDL_WINDOW_RESIZABLE };
    try std.testing.expect(flags.contains(.hidden));
    try std.testing.expect(flags.contains(.resizable));
    try std.testing.expect(!flags.contains(.fullscreen));
    try std.testing.expectEqual(unknown, flags.bits & unknown);
}

fn encode_size_limits(limits: SizeLimits) error{InvalidConstraint}!Size {
    const axes = [_]?u32{ limits.width, limits.height };
    for (axes) |axis| {
        if (axis) |value| {
            if (value == 0 or value > std.math.maxInt(c_int)) return error.InvalidConstraint;
        }
    }
    return .{ .width = limits.width orelse 0, .height = limits.height orelse 0 };
}

fn decode_size_limits(size: Size) SizeLimits {
    return .{
        .width = if (size.width == 0) null else size.width,
        .height = if (size.height == 0) null else size.height,
    };
}

fn validate_aspect_limits(limits: AspectLimits) error{InvalidConstraint}!void {
    const endpoints = [_]?f32{ limits.minimum, limits.maximum };
    for (endpoints) |endpoint| {
        if (endpoint) |value| {
            if (!std.math.isFinite(value) or value <= 0) return error.InvalidConstraint;
        }
    }
    if (limits.minimum != null and limits.maximum != null and limits.minimum.? > limits.maximum.?)
        return error.InvalidConstraint;
}

test "window constraints distinguish unrestricted axes and validate before encoding" {
    try std.testing.expectEqualDeep(
        Size{ .width = 0, .height = 42 },
        try encode_size_limits(.{ .height = 42 }),
    );
    try std.testing.expectError(error.InvalidConstraint, encode_size_limits(.{ .width = 0 }));
    try std.testing.expectError(
        error.InvalidConstraint,
        encode_size_limits(.{ .height = std.math.maxInt(u32) }),
    );
    for ([_]f32{ 0, -1, std.math.inf(f32), std.math.nan(f32) }) |value| {
        try std.testing.expectError(
            error.InvalidConstraint,
            validate_aspect_limits(.{ .minimum = value }),
        );
        try std.testing.expectError(
            error.InvalidConstraint,
            validate_aspect_limits(.{ .maximum = value }),
        );
    }
    try std.testing.expectError(
        error.InvalidConstraint,
        validate_aspect_limits(.{ .minimum = 2, .maximum = 1 }),
    );
    try validate_aspect_limits(.{});
    try validate_aspect_limits(.{ .minimum = 1, .maximum = 1 });
}

fn validate_opacity(value: f32) error{InvalidOpacity}!void {
    if (!std.math.isFinite(value) or value < 0 or value > 1) return error.InvalidOpacity;
}

test "window opacity rejects nonfinite and out-of-range values" {
    for ([_]f32{ 0, 0.5, 1 }) |value| try validate_opacity(value);
    for ([_]f32{ -0.1, 1.1, std.math.inf(f32), std.math.nan(f32) }) |value| {
        try std.testing.expectError(error.InvalidOpacity, validate_opacity(value));
    }
}

fn graphics_flags(backend: GraphicsBackend) c.SDL_WindowFlags {
    return switch (backend) {
        .none => 0,
        .opengl => c.SDL_WINDOW_OPENGL,
        .vulkan => c.SDL_WINDOW_VULKAN,
        .metal => c.SDL_WINDOW_METAL,
    };
}

fn validate_parent(child: WindowRef, candidate: WindowRef) Error!void {
    if (child.handle == candidate.handle) return error.InvalidParent;
    if (child.parent()) |current| {
        if (candidate.parent()) |other| {
            if (current.handle == other.handle) return error.InvalidParent;
        }
    }
    var ancestor: ?WindowRef = candidate;
    for (0..256) |_| {
        const current = ancestor orelse return;
        if (current.handle == child.handle) return error.InvalidParent;
        ancestor = current.parent();
    }
    if (ancestor != null) return error.HierarchyTooDeep;
}

fn encode_surface_vsync(mode: SurfaceVSync) error{InvalidVSync}!c_int {
    return switch (mode) {
        .disabled => c.SDL_WINDOW_SURFACE_VSYNC_DISABLED,
        .adaptive => c.SDL_WINDOW_SURFACE_VSYNC_ADAPTIVE,
        .interval => |value| blk: {
            if (value == 0 or value > std.math.maxInt(c_int)) return error.InvalidVSync;
            break :blk @intCast(value);
        },
    };
}

fn decode_surface_vsync(value: c_int) error{SdlFailure}!SurfaceVSync {
    return switch (value) {
        c.SDL_WINDOW_SURFACE_VSYNC_DISABLED => .disabled,
        c.SDL_WINDOW_SURFACE_VSYNC_ADAPTIVE => .adaptive,
        else => if (value > 0) .{ .interval = @intCast(value) } else error.SdlFailure,
    };
}

test "surface synchronization preserves intervals and rejects invalid requests/results" {
    const modes = [_]SurfaceVSync{ .disabled, .adaptive, .{ .interval = 1 }, .{ .interval = 3 } };
    for (modes) |mode| {
        try std.testing.expectEqualDeep(
            mode,
            try decode_surface_vsync(try encode_surface_vsync(mode)),
        );
    }
    try std.testing.expectError(error.InvalidVSync, encode_surface_vsync(.{ .interval = 0 }));
    try std.testing.expectError(
        error.InvalidVSync,
        encode_surface_vsync(.{ .interval = std.math.maxInt(u32) }),
    );
    try std.testing.expectError(error.SdlFailure, decode_surface_vsync(-2));
}

fn encode_confinement(area: ClientArea) error{InvalidRegion}!c.SDL_Rect {
    if (area.width == 0 or area.height == 0 or
        area.width > std.math.maxInt(c_int) or area.height > std.math.maxInt(c_int) or
        @as(i64, area.x) + area.width > std.math.maxInt(c_int) or
        @as(i64, area.y) + area.height > std.math.maxInt(c_int)) return error.InvalidRegion;
    return .{
        .x = area.x,
        .y = area.y,
        .w = @intCast(area.width),
        .h = @intCast(area.height),
    };
}

test "confinement rectangles reject empty and overflowing native geometry" {
    const native = try encode_confinement(.{ .x = -10, .y = 2, .width = 30, .height = 40 });
    try std.testing.expectEqual(@as(c_int, -10), native.x);
    try std.testing.expectEqual(@as(c_int, 40), native.h);
    const invalid = [_]ClientArea{
        .{ .x = 0, .y = 0, .width = 0, .height = 1 },
        .{ .x = 0, .y = 0, .width = 1, .height = 0 },
        .{ .x = 0, .y = 0, .width = std.math.maxInt(u32), .height = 1 },
        .{ .x = std.math.maxInt(i32), .y = 0, .width = 1, .height = 1 },
        .{ .x = 0, .y = std.math.maxInt(i32), .width = 1, .height = 1 },
    };
    for (invalid) |area| try std.testing.expectError(error.InvalidRegion, encode_confinement(area));
}
