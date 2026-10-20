//! Connected display identities and desktop layout. All native operations require the main thread
//! and initialized video. IDs and query results are snapshots: hotplug/configuration can invalidate
//! them. Enumeration allocates native storage; wrappers allocate no Zig storage.
const c = @import("sdl_abi");
const std = @import("std");
/// Display failures include native failure, invalid search inputs, and out-of-range mode indices.
pub const Error = @import("errors.zig").Error || error{
    /// Search dimensions must be positive C ints and refresh rate finite/nonnegative.
    InvalidModeRequest,
    /// The requested mode index is outside the owned list.
    OutOfBounds,
};

/// Desktop location in SDL screen coordinates, which need not equal framebuffer pixel coordinates.
pub const Point = struct {
    /// Horizontal coordinate; monitors can occupy negative coordinates.
    x: i32,
    /// Vertical coordinate; monitors can occupy negative coordinates.
    y: i32,
};

/// Desktop rectangle in SDL screen coordinates. Primary displays need not start at (0,0).
pub const Bounds = struct {
    /// Left edge in desktop coordinates.
    x: i32,
    /// Top edge in desktop coordinates.
    y: i32,
    /// Nonnegative horizontal extent.
    width: u32,
    /// Nonnegative vertical extent.
    height: u32,
};

/// Native orientation report. Unknown means unavailable, not a particular physical orientation.
pub const Orientation = enum(c_uint) {
    /// Backend cannot determine orientation (also used for unavailable IDs).
    unknown = c.SDL_ORIENTATION_UNKNOWN,
    /// Landscape with the right side upward relative to portrait orientation.
    landscape = c.SDL_ORIENTATION_LANDSCAPE,
    /// Landscape with the left side upward relative to portrait orientation.
    landscape_flipped = c.SDL_ORIENTATION_LANDSCAPE_FLIPPED,
    /// Upright portrait orientation.
    portrait = c.SDL_ORIENTATION_PORTRAIT,
    /// Upside-down portrait orientation.
    portrait_flipped = c.SDL_ORIENTATION_PORTRAIT_FLIPPED,
    _,
};

/// Exact refresh fraction as supplied by SDL; numerator zero means unspecified.
pub const RefreshFraction = struct {
    /// Cycles in the numerator; preserve native values rather than rounding to integer Hz.
    numerator: i32,
    /// Divisor; do not divide without checking for a positive denominator.
    denominator: i32,
};

/// Copied display mode measurements. Retaining this value does not retain a connected monitor.
pub const ModeInfo = struct {
    /// Display associated with this mode.
    display: DisplayId,
    /// Mode dimensions; multiply by pixel_density to derive physical pixels where applicable.
    size: @import("video.zig").Size,
    /// SDL pixel-format numeric identifier, preserved for raw interop including unknown formats.
    pixel_format: u32,
    /// Scale from mode dimensions to pixels, separate from recommended UI content scale.
    pixel_density: f32,
    /// Approximate refresh frequency in Hz; zero means unspecified.
    refresh_rate: f32,
    /// Native exact fraction, including unspecified zero values.
    refresh_fraction: RefreshFraction,
};

/// Copyable native mode token. No cleanup; does not own or extend display lifetime.
/// Native internal data can expire after hotplug/configuration/video shutdown. Requery before use
/// after such changes. Mode list cleanup does not invalidate this copied token's scalar data.
pub const Mode = struct {
    /// Native interop snapshot. Treat as read-only; never fabricate/free its internal pointer.
    native: c.SDL_DisplayMode,

    /// Copy the typed pixel-format identity, preserving future values. No native call/allocation;
    /// scalar data remains readable as historical information after the display disappears.
    pub fn format(self: Mode) @import("pixels.zig").Format {
        return @fromBackingInt(self.native.format);
    }

    /// Copy measurements without native calls or allocation. Negative native sizes are SdlFailure.
    /// Scalar copies remain readable after display removal; they describe historical state only.
    pub fn info(self: Mode) Error!ModeInfo {
        if (self.native.w < 0 or self.native.h < 0) return error.SdlFailure;
        return .{
            .display = @fromBackingInt(self.native.displayID),
            .size = .{ .width = @intCast(self.native.w), .height = @intCast(self.native.h) },
            .pixel_format = @intCast(self.native.format),
            .pixel_density = self.native.pixel_density,
            .refresh_rate = self.native.refresh_rate,
            .refresh_fraction = .{
                .numerator = self.native.refresh_rate_numerator,
                .denominator = self.native.refresh_rate_denominator,
            },
        };
    }
};

/// Owned fullscreen mode snapshot in SDL preference order. Do not copy; deinit exactly once.
/// SDL allocates pointers and mode records together. Individual records must never be freed.
pub const Modes = struct {
    /// Internal native allocation. Read-only; never replace or free separately.
    native: [*c][*c]c.SDL_DisplayMode,
    /// Number of accessible records, excluding the native null sentinel. Read-only.
    count: usize,

    /// Copy a mode token at index without allocation. OutOfBounds leaves the list unchanged.
    /// Keep this owner alive during access; no main-thread call is made, but serialize with
    /// cleanup.
    pub fn get(self: Modes, index: usize) Error!Mode {
        if (index >= self.count) return error.OutOfBounds;
        const pointer = self.native[index];
        if (pointer == null) return error.SdlFailure;
        return .{ .native = pointer.* };
    }

    /// Free the native snapshot on the main thread with no active list users; does not close
    /// displays.
    pub fn deinit(self: *Modes) void {
        c.SDL_free(@ptrCast(self.native));
        self.* = undefined;
    }
};

/// Closest fullscreen mode search. Native selection prioritizes size and then refresh matching.
pub const ModeRequest = struct {
    /// Positive desired dimensions fitting C int; SDL searches modes at least this large.
    size: @import("video.zig").Size,
    /// Desired Hz, or zero for desktop refresh. Must be finite and nonnegative.
    refresh_rate: f32 = 0,
    /// Include modes with high pixel density when true; false by default.
    include_high_density: bool = false,
};

/// Non-owning display identity, not a monitor lifetime guarantee. Requery after display events.
pub const DisplayId = enum(u32) {
    /// No display; successful discovery never returns this value.
    invalid = 0,
    _,

    /// Allocate a fullscreen mode snapshot on the main thread; pair deinit immediately.
    /// SDL sorts largest dimensions first, then pixel format, refresh, and density. Empty success
    /// is valid. SdlFailure returns no owner. Hotplug can invalidate mode applicability
    /// independently.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var video = try sdl.init(.{ .video = true });
    /// defer video.deinit();
    /// const display = try sdl.display.primary();
    /// var modes = try display.modes();
    /// defer modes.deinit();
    /// for (0..modes.count) |index| {
    ///     const info = try (try modes.get(index)).info();
    ///     try @import("std").testing.expectEqual(display, info.display);
    /// }
    /// ```
    pub fn modes(self: DisplayId) Error!Modes {
        var count: c_int = 0;
        const pointer = c.SDL_GetFullscreenDisplayModes(@backingInt(self), &count);
        if (pointer == null) return error.SdlFailure;
        errdefer c.SDL_free(@ptrCast(pointer));
        if (count < 0) return error.SdlFailure;
        return .{ .native = pointer, .count = @intCast(count) };
    }

    /// Copy the desktop mode on the main thread. During exclusive fullscreen this describes the
    /// original desktop configuration, not necessarily current scanout. SdlFailure returns no
    /// token.
    pub fn desktop_mode(self: DisplayId) Error!Mode {
        const pointer = c.SDL_GetDesktopDisplayMode(@backingInt(self));
        if (pointer == null) return error.SdlFailure;
        return .{ .native = pointer.* };
    }

    /// Copy the current mode on the main thread, including exclusive fullscreen changes.
    /// SdlFailure returns no token; no wrapper allocation. Requery after configuration changes.
    pub fn current_mode(self: DisplayId) Error!Mode {
        const pointer = c.SDL_GetCurrentDisplayMode(@backingInt(self));
        if (pointer == null) return error.SdlFailure;
        return .{ .native = pointer.* };
    }

    /// Search fullscreen modes on the main thread. InvalidModeRequest rejects invalid inputs before
    /// SDL runs. SdlFailure includes no sufficiently large mode or native failure; no token
    /// returned.
    /// Native enumeration may allocate/block. Does not change display or window state.
    pub fn closest_mode(self: DisplayId, request: ModeRequest) Error!Mode {
        try validate_request(request);
        var native: c.SDL_DisplayMode = undefined;
        if (!c.SDL_GetClosestFullscreenDisplayMode(
            @backingInt(self),
            @intCast(request.size.width),
            @intCast(request.size.height),
            request.refresh_rate,
            request.include_high_density,
            &native,
        )) return error.SdlFailure;
        return .{ .native = native };
    }

    /// Borrow the UTF-8 display name. Copy if retaining across hotplug/video shutdown or native
    /// display changes. Main thread; do not free. SdlFailure means unavailable ID/native failure.
    pub fn name(self: DisplayId) Error![:0]const u8 {
        const pointer = c.SDL_GetDisplayName(@backingInt(self));
        if (pointer == null) return error.SdlFailure;
        return std.mem.span(pointer);
    }

    /// Snapshot full desktop bounds on the main thread. Can change with layout/DPI configuration.
    /// Native failure or invalid returned dimensions gives SdlFailure. No wrapper allocation.
    pub fn bounds(self: DisplayId) Error!Bounds {
        var rect: c.SDL_Rect = undefined;
        if (!c.SDL_GetDisplayBounds(@backingInt(self), &rect)) return error.SdlFailure;
        return checked_bounds(rect);
    }

    /// Snapshot desktop bounds excluding taskbars/reserved areas where the backend supports it.
    /// Main thread; SdlFailure includes unavailable backend information or disconnected displays.
    /// No wrapper allocation. Do not assume a usable-area query succeeds just because bounds does.
    pub fn usable_bounds(self: DisplayId) Error!Bounds {
        var rect: c.SDL_Rect = undefined;
        if (!c.SDL_GetDisplayUsableBounds(@backingInt(self), &rect)) return error.SdlFailure;
        return checked_bounds(rect);
    }

    /// Query recommended content scale, not framebuffer pixel density. Main thread; may change.
    /// SdlFailure rejects unavailable/nonpositive/nonfinite results. For an existing window use
    /// WindowRef.display_scale instead: its scale can differ from the display's base scale.
    pub fn content_scale(self: DisplayId) Error!f32 {
        const scale = c.SDL_GetDisplayContentScale(@backingInt(self));
        if (!std.math.isFinite(scale) or scale <= 0) return error.SdlFailure;
        return scale;
    }

    /// Query unrotated physical orientation on the main thread; unknown means unavailable.
    /// No wrapper allocation or ownership change. Unknown future enum values are preserved.
    pub fn natural_orientation(self: DisplayId) Orientation {
        return @fromBackingInt(@intCast(c.SDL_GetNaturalDisplayOrientation(@backingInt(self))));
    }

    /// Query current orientation on the main thread; unknown means unavailable. This is a snapshot.
    /// No wrapper allocation or ownership change. Unknown future enum values are preserved.
    pub fn orientation(self: DisplayId) Orientation {
        return @fromBackingInt(@intCast(c.SDL_GetCurrentDisplayOrientation(@backingInt(self))));
    }

    /// Borrow the native display-owned property group. Main thread; may allocate/block.
    /// SdlFailure returns no view. Never destroy it separately or retain it across display removal
    /// or video shutdown. Native keys retain their own read/write and lifetime restrictions.
    pub fn properties(self: DisplayId) Error!@import("properties.zig").PropertiesRef {
        const handle = c.SDL_GetDisplayProperties(@backingInt(self));
        if (handle == 0) return error.SdlFailure;
        return .{ .handle = handle };
    }
};

/// Owns an SDL-allocated snapshot of display IDs. Do not copy; call deinit once.
/// The array stays valid until cleanup, but its IDs can become disconnected independently.
pub const Displays = struct {
    /// Borrowed immutable elements until deinit. Do not replace the slice or free it separately.
    items: []const DisplayId,

    /// Release the native array and invalidate its slice. Main thread, with no active slice users.
    /// Does not close displays or retain video initialization. Native allocator hooks may run.
    pub fn deinit(self: *Displays) void {
        c.SDL_free(@constCast(self.items.ptr));
        self.* = undefined;
    }
};

/// Snapshot connected IDs on the main thread. Caller owns array cleanup; no sentinel is exposed.
/// Native allocation can fail with SdlFailure. An empty successful array is valid, and no monitor
/// resources are owned. Keep video initialized for queries; the snapshot alone grants no lifetime.
///
/// ```zig
/// const sdl = @import("sdl");
/// sdl.raw.SDL_SetMainReady();
/// defer sdl.raw.SDL_Quit();
/// var video = try sdl.init(.{ .video = true });
/// defer video.deinit();
/// var displays = try sdl.display.list();
/// defer displays.deinit();
/// for (displays.items) |id| {
///     try @import("std").testing.expect(id != .invalid);
/// }
/// ```
pub fn list() Error!Displays {
    comptime {
        std.debug.assert(@sizeOf(DisplayId) == @sizeOf(c.SDL_DisplayID));
        std.debug.assert(@alignOf(DisplayId) == @alignOf(c.SDL_DisplayID));
    }
    var count: c_int = 0;
    const pointer = c.SDL_GetDisplays(&count);
    if (pointer == null) return error.SdlFailure;
    errdefer c.SDL_free(@ptrCast(pointer));
    if (count < 0) return error.SdlFailure;
    const items: [*]const DisplayId = @ptrCast(pointer);
    return .{ .items = items[0..@intCast(count)] };
}

/// Query the primary display ID on the main thread. Does not retain a display or video context.
/// SdlFailure means no primary display/native failure; requery after display changes.
pub fn primary() Error!DisplayId {
    const value = c.SDL_GetPrimaryDisplay();
    if (value == 0) return error.SdlFailure;
    return @fromBackingInt(value);
}

/// Resolve a desktop point to the display selected by SDL. Main thread; no ownership transfer.
/// Native layout selection applies outside display bounds; zero native result becomes SdlFailure.
pub fn for_point(point: Point) Error!DisplayId {
    const native = c.SDL_Point{ .x = point.x, .y = point.y };
    const value = c.SDL_GetDisplayForPoint(&native);
    if (value == 0) return error.SdlFailure;
    return @fromBackingInt(value);
}

fn checked_bounds(rect: c.SDL_Rect) Error!Bounds {
    if (rect.w < 0 or rect.h < 0) return error.SdlFailure;
    return .{ .x = rect.x, .y = rect.y, .width = @intCast(rect.w), .height = @intCast(rect.h) };
}

test "display rectangles preserve signed origins and reject negative extents" {
    try std.testing.expectEqualDeep(
        Bounds{ .x = -10, .y = -20, .width = 0, .height = 3 },
        try checked_bounds(.{ .x = -10, .y = -20, .w = 0, .h = 3 }),
    );
    try std.testing.expectError(
        error.SdlFailure,
        checked_bounds(.{ .x = 0, .y = 0, .w = -1, .h = 3 }),
    );
    try std.testing.expectError(
        error.SdlFailure,
        checked_bounds(.{ .x = 0, .y = 0, .w = 3, .h = -1 }),
    );
}

fn validate_request(request: ModeRequest) error{InvalidModeRequest}!void {
    if (request.size.width == 0 or request.size.height == 0 or
        request.size.width > std.math.maxInt(c_int) or
        request.size.height > std.math.maxInt(c_int) or
        !std.math.isFinite(request.refresh_rate) or request.refresh_rate < 0)
        return error.InvalidModeRequest;
}

test "mode requests validate dimensions and refresh before native calls" {
    try validate_request(.{ .size = .{ .width = 1920, .height = 1080 } });
    const rates = [_]f32{ -1, std.math.inf(f32), std.math.nan(f32) };
    for (rates) |rate| {
        try std.testing.expectError(
            error.InvalidModeRequest,
            validate_request(.{ .size = .{ .width = 1, .height = 1 }, .refresh_rate = rate }),
        );
    }
    try std.testing.expectError(
        error.InvalidModeRequest,
        validate_request(.{ .size = .{ .width = 0, .height = 1 } }),
    );
    try std.testing.expectError(
        error.InvalidModeRequest,
        validate_request(.{ .size = .{ .width = 1, .height = std.math.maxInt(u32) } }),
    );
}

test "mode measurements preserve fractional rates and reject negative native sizes" {
    var mode = Mode{ .native = std.mem.zeroes(c.SDL_DisplayMode) };
    mode.native.displayID = 42;
    mode.native.w = 1920;
    mode.native.h = 1080;
    mode.native.refresh_rate = 59.94;
    mode.native.refresh_rate_numerator = 60000;
    mode.native.refresh_rate_denominator = 1001;
    const info = try mode.info();
    try std.testing.expectEqual(@as(u32, 42), @backingInt(info.display));
    try std.testing.expectEqual(@as(u32, 1920), info.size.width);
    try std.testing.expectEqual(@as(f32, 59.94), info.refresh_rate);
    try std.testing.expectEqualDeep(
        RefreshFraction{ .numerator = 60000, .denominator = 1001 },
        info.refresh_fraction,
    );
    mode.native.w = -1;
    try std.testing.expectError(error.SdlFailure, mode.info());
}
