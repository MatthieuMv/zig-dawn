//! Main-thread renderer/texture operations. Parents must outlive children and borrowed refs.
//! Native backends may allocate. Wrapper conversions do not allocate.
const std = @import("std");
const c = @import("sdl_abi");
const video = @import("video.zig");

/// Rendering failures: `SdlFailure` is native failure; `InvalidSize` is an invalid/overflowing
/// texture dimension/pitch, `InvalidPixels` a byte-count mismatch, `InvalidRect` a nonfinite
/// coordinate or negative extent, and `WrongRenderer` a mismatched texture owner.
/// Validation errors occur before the native draw/upload and do not set SDL diagnostic text.
pub const Error = video.Error || error{
    /// Operation would read or upload the texture currently selected as the render destination.
    TargetInUse,
    /// Native locked pixel storage has null data, invalid pitch, or overflowing row offsets.
    InvalidPixelLayout,
    /// Requested pixel operation does not support this texture format.
    UnsupportedFormat,
    /// Sampling mode is not one of the supported named policies.
    InvalidScaleMode,
    /// VSync interval is zero or an unsupported negative native identity.
    InvalidVSync,
    /// Coordinate input or transformed output is nonfinite.
    InvalidCoordinate,
    /// A color/multiplier is nonfinite. Setters reject it before mutation; getters return no value.
    InvalidColor,
    /// Driver index or upload region is outside the owning resource bounds.
    OutOfBounds,
    /// Pixel bytes have an invalid length or pitch for the requested region.
    InvalidPixels,
    /// A coordinate/extent is nonfinite, or an extent is negative.
    InvalidRect,
    /// The texture belongs to a different renderer; nothing was drawn.
    WrongRenderer,
};
/// Eight-bit RGBA drawing color with stable C-compatible channel layout.
/// Alpha alone does not enable blending.
pub const Color = extern struct {
    /// Red channel, 0..255.
    r: u8,
    /// Green channel, 0..255.
    g: u8,
    /// Blue channel, 0..255.
    b: u8,
    /// Alpha channel, 0 transparent to 255 opaque (default). Usage depends on blend mode.
    a: u8 = 255,
};
/// Floating-point drawing color. Finite HDR/negative components are retained by color state;
/// actual rendering precision/range depends on the target/backend. Alpha alone enables no blending.
pub const FloatColor = @import("pixels.zig").FloatColor;
/// Drawing compositing mode, shared with surface operations. Texture blend state is separate.
pub const BlendMode = @import("surface.zig").BlendMode;

/// RGB texture multipliers, shared with surface blit tint. White leaves stored RGB unchanged.
pub const Tint = @import("surface.zig").Tint;

/// Floating RGB texture multipliers. One preserves a channel; zero removes it.
/// Finite HDR/negative values are representable; rendering support depends on the backend.
pub const FloatTint = struct {
    /// Red multiplier.
    r: f32 = 1,
    /// Green multiplier.
    g: f32 = 1,
    /// Blue multiplier.
    b: f32 = 1,
};

/// Texture sampling policy. Queries preserve unknown native identities.
/// Surface scaling has its own ScaleMode because CPU and renderer support differ.
pub const ScaleMode = enum(c_int) {
    /// Native invalid sentinel, rejected by setters.
    invalid = c.SDL_SCALEMODE_INVALID,
    /// Select the nearest source pixel for sharp pixel replication.
    nearest = c.SDL_SCALEMODE_NEAREST,
    /// Interpolate neighboring pixels; exact output depends on the backend.
    linear = c.SDL_SCALEMODE_LINEAR,
    /// Pixel-art sampling with improved scaling where supported; backend fallback is possible.
    pixel_art = c.SDL_SCALEMODE_PIXELART,
    _,
};

/// Floating dimensions reported by SDL for rendering; not a byte-buffer allocation size.
pub const FloatSize = struct {
    /// Horizontal extent in texture pixels, potentially rounded by native float conversion.
    width: f32,
    /// Vertical extent in texture pixels, potentially rounded by native float conversion.
    height: f32,
};

/// Floating-point position; units are specified by the operation, not encoded in this value.
pub const Point = struct {
    /// Horizontal coordinate; finite negative values are allowed.
    x: f32,
    /// Vertical coordinate; positive normally points downward.
    y: f32,
};

/// Rectangle in renderer coordinates: pixels by default, or configured logical coordinates.
/// Finite negative positions are allowed; width/height must be finite and nonnegative.
pub const Rect = struct {
    /// Left edge; origin is normally the top-left of the rendering target.
    x: f32,
    /// Top edge; positive y normally points downward.
    y: f32,
    /// Horizontal extent; zero is allowed and draws no area.
    width: f32,
    /// Vertical extent; zero is allowed and draws no area.
    height: f32,
};
/// Mapping of a logical drawing resolution onto physical output pixels.
pub const PresentationMode = enum(c_uint) {
    /// Logical coordinates are disabled; output pixels determine drawing resolution.
    disabled = c.SDL_LOGICAL_PRESENTATION_DISABLED,
    /// Stretch independently in each axis to fill the output.
    stretch = c.SDL_LOGICAL_PRESENTATION_STRETCH,
    /// Preserve aspect ratio and fit inside output, leaving bars as needed.
    letterbox = c.SDL_LOGICAL_PRESENTATION_LETTERBOX,
    /// Preserve aspect ratio and fill output, cropping excess content.
    overscan = c.SDL_LOGICAL_PRESENTATION_OVERSCAN,
    /// Fit using integer scale multiples.
    integer_scale = c.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE,
    _,
};

/// Logical resolution and its presentation policy. Does not configure viewport or input conversion.
pub const Presentation = struct {
    /// Positive logical dimensions when enabling; query may report zero when disabled.
    size: video.Size,
    /// Mapping policy. Unknown native identities survive queries.
    mode: PresentationMode,
};

/// Presentation synchronization request. Support and actual timing depend on the renderer/backend.
pub const VSync = enum(i32) {
    /// Do not request synchronization to display refresh.
    disabled = c.SDL_RENDERER_VSYNC_DISABLED,
    /// Request late-swap tearing when available; not supported by every backend.
    adaptive = c.SDL_RENDERER_VSYNC_ADAPTIVE,
    /// Synchronize each presentation to one refresh; SDL may simulate this with delays.
    every_refresh = 1,
    _,

    /// Construct an interval in refresh cycles. Zero returns InvalidVSync; use disabled explicitly.
    /// This validates representation only, not backend support. No allocation or native call.
    pub fn interval(refreshes: u31) Error!VSync {
        if (refreshes == 0) return error.InvalidVSync;
        return @fromBackingInt(@as(i32, refreshes));
    }
};

/// Renderer selection; creation does not configure vsync, blending, scaling, or logical size.
pub const RendererOptions = struct {
    /// Null lets SDL choose. Otherwise a sentinel driver name (or comma-separated fallback list).
    /// Borrowed for creation only. `"software"` requests CPU rendering; availability is
    /// platform-specific.
    driver: ?[:0]const u8 = null,
};

/// Number of compiled-in rendering drivers, in SDL preference order. Any thread; no initialization
/// or allocation. Zero is valid when rendering support is disabled. Listing is not proof that a
/// driver can initialize on the current machine/window.
pub fn driver_count() usize {
    return @intCast(c.SDL_GetNumRenderDrivers());
}

/// Borrow a static ASCII driver identifier without allocation; no deinit. Any thread.
/// OutOfBounds validates index before SDL; SdlFailure reports native rejection. The identifier can
/// be passed directly to RendererOptions.driver. Availability for a particular window is separate.
///
/// ```zig
/// const render = @import("sdl").render;
/// for (0..render.driver_count()) |index| {
///     const name = try render.driver_name(index);
///     try @import("std").testing.expect(name.len > 0);
/// }
/// ```
pub fn driver_name(index: usize) Error![:0]const u8 {
    if (index >= driver_count()) return error.OutOfBounds;
    const pointer = c.SDL_GetRenderDriver(@intCast(index)) orelse return error.SdlFailure;
    return std.mem.span(pointer);
}

/// Borrow the renderer associated with a live window. Main thread under this wrapper contract.
/// SdlFailure includes a window with no renderer. No allocation/retention or ownership transfer;
/// finish using this view before renderer destruction. Never deinitialize the borrowed handle.
pub fn for_window(window: video.WindowRef) Error!RendererRef {
    const handle = c.SDL_GetRenderer(window.handle) orelse return error.SdlFailure;
    return .{ .handle = handle };
}

/// Owns a renderer borrowing its window or software surface. Destroy textures before deinit.
/// The backing window/surface must outlive this owner. Do not copy.
pub const Renderer = struct {
    /// Native interop handle. Never destroy separately or use after the owning renderer is
    /// destroyed.
    handle: *c.SDL_Renderer,

    /// Create a renderer on the main thread, borrowing an existing live window.
    /// The window outlives this owner; create only one renderer per window. SDL may allocate/block.
    /// `SdlFailure` returns no owner. On success, destroy textures before `Renderer.deinit`.
    /// Driver selection does not guarantee acceleration; use `driver = "software"` for CPU
    /// rendering.
    pub fn init(window: video.WindowRef, options: RendererOptions) Error!Renderer {
        const name = if (options.driver) |driver| driver.ptr else null;
        const handle = c.SDL_CreateRenderer(window.handle, name) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Create a software renderer borrowing an existing CPU surface. Main-thread wrapper contract;
    /// no video subsystem/window is required. Native storage may allocate; SdlFailure returns no
    /// owner. Defer deinit before destroying the surface, and destroy textures before the renderer.
    /// Keep backing surface layout stable and unlocked; synchronize renderer use with pixel access.
    /// Window-owned surfaces also expire on resize: use an ordinary owned surface for durable use.
    pub fn for_surface(surface: @import("surface.zig").SurfaceRef) Error!Renderer {
        const handle = c.SDL_CreateSoftwareRenderer(surface.handle) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Destroy on the main thread, after every texture but before the borrowed window/surface.
    /// Invalidates this owner and all renderer views. Call exactly once; no fallible result.
    pub fn deinit(self: *Renderer) void {
        c.SDL_DestroyRenderer(self.handle);
        self.* = undefined;
    }

    /// Return a non-owning drawing view. No allocation, native call, or ownership transfer.
    /// The owner and its backing window/surface must remain alive while the view is used.
    pub fn borrow(self: *const Renderer) RendererRef {
        return .{ .handle = self.handle };
    }
};

/// Non-owning renderer view; copyable while the owner and its backing window/surface remain alive.
/// All drawing methods require the main thread. Native backends may allocate or block;
/// no method here allocates Zig wrapper storage or takes ownership of its arguments.
pub const RendererRef = struct {
    /// Native interop handle. Never destroy separately or use after the owning renderer is
    /// destroyed.
    handle: *c.SDL_Renderer,

    /// Borrow the selected backend's ASCII name. Valid through renderer destruction; do not free.
    /// Main-thread wrapper contract. No wrapper allocation; SdlFailure returns no name.
    pub fn name(self: RendererRef) Error![:0]const u8 {
        const pointer = c.SDL_GetRendererName(self.handle) orelse return error.SdlFailure;
        return std.mem.span(pointer);
    }

    /// Borrow the backing window without retention. SdlFailure includes a surface-backed renderer.
    /// Main-thread wrapper contract; window/renderer owners must outlive this view's use.
    pub fn window(self: RendererRef) Error!video.WindowRef {
        const handle = c.SDL_GetRenderWindow(self.handle) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Query physical output pixels, ignoring targets and logical presentation. Main thread.
    /// Native query may fail with SdlFailure; zero dimensions are preserved. No ownership transfer.
    pub fn output_size(self: RendererRef) Error!video.Size {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetRenderOutputSize(self.handle, &width, &height)) return error.SdlFailure;
        if (width < 0 or height < 0) return error.SdlFailure;
        return .{ .width = @intCast(width), .height = @intCast(height) };
    }

    /// Query current presentation output dimensions in pixels on the main thread. Pinned SDL uses
    /// the mapped destination extent, not logical drawing dimensions; use presentation().size for
    /// those. Can differ from output_size. SdlFailure returns no size; zero dimensions are preserved.
    pub fn current_output_size(self: RendererRef) Error!video.Size {
        var width: c_int = 0;
        var height: c_int = 0;
        if (!c.SDL_GetCurrentRenderOutputSize(self.handle, &width, &height))
            return error.SdlFailure;
        if (width < 0 or height < 0) return error.SdlFailure;
        return .{ .width = @intCast(width), .height = @intCast(height) };
    }

    /// Configure logical drawing coordinates on the main thread; null disables presentation.
    /// Enabled sizes must be positive native integers (InvalidSize otherwise). Disabled requests
    /// use zero native dimensions. SdlFailure may leave native state changed. Applies to the current
    /// render target; target-specific state and input-coordinate conversion remain separate.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var pixels = try sdl.surface.Surface.init_rgba(.{ .width = 8, .height = 6 });
    /// defer pixels.deinit();
    /// var renderer = try sdl.render.Renderer.for_surface(pixels.borrow());
    /// defer renderer.deinit();
    /// try renderer.borrow().set_presentation(.{
    ///     .size = .{ .width = 4, .height = 2 }, .mode = .letterbox,
    /// });
    /// try renderer.borrow().set_presentation(null);
    /// ```
    pub fn set_presentation(self: RendererRef, value: ?Presentation) Error!void {
        const selected = value orelse Presentation{
            .size = .{ .width = 0, .height = 0 },
            .mode = .disabled,
        };
        const enabled = selected.mode != .disabled;
        if (enabled) try video.validate_size(selected.size);
        if (!c.SDL_SetRenderLogicalPresentation(
            self.handle,
            if (enabled) @intCast(selected.size.width) else 0,
            if (enabled) @intCast(selected.size.height) else 0,
            @backingInt(selected.mode),
        )) return error.SdlFailure;
    }

    /// Copy current target's logical presentation state on the main thread. Disabled is explicit;
    /// zero dimensions are preserved. SdlFailure returns no state. No wrapper allocation.
    pub fn presentation(self: RendererRef) Error!Presentation {
        var width: c_int = 0;
        var height: c_int = 0;
        var mode: c.SDL_RendererLogicalPresentation = undefined;
        if (!c.SDL_GetRenderLogicalPresentation(self.handle, &width, &height, &mode))
            return error.SdlFailure;
        if (width < 0 or height < 0) return error.SdlFailure;
        return .{ .size = .{ .width = @intCast(width), .height = @intCast(height) }, .mode = @fromBackingInt(mode) };
    }

    /// Copy where logical content maps in physical output coordinates, including letterbox bars
    /// or overscan extents. Main thread; SdlFailure returns no rectangle. No allocation/retention.
    pub fn presentation_rect(self: RendererRef) Error!Rect {
        var rect: c.SDL_FRect = undefined;
        if (!c.SDL_GetRenderLogicalPresentationRect(self.handle, &rect)) return error.SdlFailure;
        return .{ .x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h };
    }

    /// Map a window-coordinate point to drawing coordinates on the main thread. Accounts for DPI,
    /// main-window logical presentation, scale, and viewport. Uses main-window state even when a
    /// texture target is active. Does not clamp points in bars/outside the window or mutate events.
    /// InvalidCoordinate rejects nonfinite input/output; degenerate native state can produce an
    /// invalid result. SdlFailure reports native query failure. No allocation or retention.
    pub fn from_window_point(self: RendererRef, point: Point) Error!Point {
        try validate_point(point);
        var result: Point = undefined;
        if (!c.SDL_RenderCoordinatesFromWindow(self.handle, point.x, point.y, &result.x, &result.y))
            return error.SdlFailure;
        try validate_point(result);
        return result;
    }

    /// Map main-window drawing coordinates to window coordinates on the main thread. Includes
    /// viewport, scale, logical presentation and DPI, independent of the current texture target.
    /// Negative/outside points remain valid; conversion does not perform hit testing. Floating
    /// round trips may lose precision. InvalidCoordinate rejects nonfinite input/output;
    /// SdlFailure reports native query failure. No allocation, event mutation, or ownership transfer.
    pub fn to_window_point(self: RendererRef, point: Point) Error!Point {
        try validate_point(point);
        var result: Point = undefined;
        if (!c.SDL_RenderCoordinatesToWindow(self.handle, point.x, point.y, &result.x, &result.y))
            return error.SdlFailure;
        try validate_point(result);
        return result;
    }

    /// Borrow this object's native property group. Main thread under this wrapper contract.
    /// May allocate/block; `SdlFailure` returns no view. The object owns the group: never destroy
    /// it separately. Finish all views/locks before object destruction. Use application-specific
    /// keys for custom data; native keys retain their individual read/write and lifetime contracts.
    pub fn properties(
        self: RendererRef,
    ) @import("errors.zig").Error!@import("properties.zig").PropertiesRef {
        const handle = c.SDL_GetRendererProperties(self.handle);
        if (handle == 0) return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Set the color for subsequent clear/fill operations on the main thread.
    /// Does not tint textures or enable alpha blending. Returns `SdlFailure` on native failure.
    /// On failure native state is not guaranteed unchanged; reconfigure before relying on it.
    pub fn set_color(self: RendererRef, value: Color) Error!void {
        if (!c.SDL_SetRenderDrawColor(self.handle, value.r, value.g, value.b, value.a)) {
            return error.SdlFailure;
        }
    }

    /// Copy draw color as eight-bit RGBA on the main thread. Clamp finite components to 0..1,
    /// then truncate component*255; use color_float to retain original precision. InvalidColor
    /// rejects raw-installed NaN/infinity instead of invoking undefined native integer conversion.
    /// SdlFailure returns no color. State stays unchanged; no wrapper allocation.
    pub fn color(self: RendererRef) Error!Color {
        const value = try self.color_float();
        return .{
            .r = try color_byte(value.r),
            .g = try color_byte(value.g),
            .b = try color_byte(value.b),
            .a = try color_byte(value.a),
        };
    }

    /// Set floating RGBA for subsequent primitive drawing/clear on the main thread. InvalidColor
    /// rejects nonfinite components before mutation. Finite HDR/negative values pass unchanged;
    /// this does not promise HDR output, select a colorspace, tint textures, or enable blending.
    /// SdlFailure reports native rejection. No wrapper allocation or ownership transfer.
    pub fn set_color_float(self: RendererRef, value: FloatColor) Error!void {
        if (!std.math.isFinite(value.r) or !std.math.isFinite(value.g) or
            !std.math.isFinite(value.b) or !std.math.isFinite(value.a)) return error.InvalidColor;
        if (!c.SDL_SetRenderDrawColorFloat(self.handle, value.r, value.g, value.b, value.a))
            return error.SdlFailure;
    }

    /// Copy current floating draw color on the main thread, without quantizing it to bytes.
    /// SdlFailure returns no color. No wrapper allocation; raw-installed nonfinite values survive.
    pub fn color_float(self: RendererRef) Error!FloatColor {
        var value: FloatColor = undefined;
        if (!c.SDL_GetRenderDrawColorFloat(self.handle, &value.r, &value.g, &value.b, &value.a))
            return error.SdlFailure;
        return value;
    }

    /// Select compositing for primitives, not textures, on the main thread. Clear ignores blending.
    /// Unsupported requests may select a closest supported mode; SdlFailure does not guarantee
    /// unchanged state. Query blend_mode afterward when fallback matters. Premultiplied modes need
    /// already-premultiplied drawing colors. No ownership transfer or wrapper allocation.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer surface.deinit();
    /// var renderer = try sdl.render.Renderer.for_surface(surface.borrow());
    /// defer renderer.deinit();
    /// try renderer.borrow().set_blend_mode(.alpha);
    /// try renderer.borrow().set_color(.{ .r = 255, .g = 0, .b = 0, .a = 128 });
    /// try renderer.borrow().fill_rect(null);
    /// try renderer.borrow().present();
    /// ```
    pub fn set_blend_mode(self: RendererRef, mode: BlendMode) Error!void {
        if (!c.SDL_SetRenderDrawBlendMode(self.handle, @backingInt(mode))) return error.SdlFailure;
    }

    /// Query the actual primitive blend mode on the main thread; texture state is independent.
    /// Unknown native modes remain representable. SdlFailure returns no mode; no wrapper allocation.
    pub fn blend_mode(self: RendererRef) Error!BlendMode {
        var mode: c.SDL_BlendMode = undefined;
        if (!c.SDL_GetRenderDrawBlendMode(self.handle, &mode)) return error.SdlFailure;
        return @fromBackingInt(mode);
    }

    /// Select sampling inherited by subsequently created textures on the main thread.
    /// Existing textures are unchanged. InvalidScaleMode rejects invalid/unknown identities before
    /// mutation; SdlFailure reports native failure. Backend support may involve fallback.
    /// No ownership transfer or wrapper allocation.
    pub fn set_default_texture_scale_mode(self: RendererRef, mode: ScaleMode) Error!void {
        try validate_scale_mode(mode);
        if (!c.SDL_SetDefaultTextureScaleMode(self.handle, @backingInt(mode)))
            return error.SdlFailure;
    }

    /// Query sampling inherited by new textures on the main thread. Initially linear.
    /// Preserves unknown native values; SdlFailure returns no mode. No wrapper allocation.
    pub fn default_texture_scale_mode(self: RendererRef) Error!ScaleMode {
        var mode: c.SDL_ScaleMode = undefined;
        if (!c.SDL_GetDefaultTextureScaleMode(self.handle, &mode)) return error.SdlFailure;
        return @fromBackingInt(mode);
    }

    /// Configure presentation synchronization on the main thread. Nonnegative intervals/adaptive
    /// are passed to SDL; other negative raw identities return InvalidVSync before mutation.
    /// Unsupported requests return SdlFailure and can still change native state. SDL may simulate
    /// every_refresh; success does not prove hardware VSync. Software surfaces support disabled.
    pub fn set_vsync(self: RendererRef, value: VSync) Error!void {
        const native = @backingInt(value);
        if (native < -1) return error.InvalidVSync;
        if (!c.SDL_SetRenderVSync(self.handle, native)) return error.SdlFailure;
    }

    /// Query SDL's stored synchronization value on the main thread, preserving future integers.
    /// This is configuration metadata, not measured display timing; native failed-set side effects
    /// need not be reflected here. SdlFailure returns no value. Native property access may allocate.
    pub fn vsync(self: RendererRef) Error!VSync {
        var value: c_int = 0;
        if (!c.SDL_GetRenderVSync(self.handle, &value)) return error.SdlFailure;
        return @fromBackingInt(value);
    }

    /// Submit pending SDL renderer commands before mixing with native graphics APIs. Main thread.
    /// Does not present a frame or wait for GPU completion. Normally unnecessary for SDL-only use.
    /// Backend work can block/allocate; SdlFailure may occur after partial submission. Raw interop
    /// must separately obey backend state/context/lifetime rules. No ownership transfer.
    pub fn flush(self: RendererRef) Error!void {
        if (!c.SDL_FlushRenderer(self.handle)) return error.SdlFailure;
    }

    /// Select a live target-access texture, or null for the original window/software surface.
    /// Main thread only. WrongRenderer rejects a different parent before mutation; SdlFailure
    /// includes non-target textures. Native failure can still change the selected target; query
    /// target afterward when recovering. Switching can flush queued drawing and allocate/block.
    /// Viewport, clipping, scale, and logical presentation persist separately for each target.
    /// Selection does not retain ownership. Keep the texture alive, finish locks first, and switch
    /// away before sampling it. Prefer explicitly resetting the target before destroying it.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer surface.deinit();
    /// var renderer = try sdl.render.Renderer.for_surface(surface.borrow());
    /// defer renderer.deinit();
    /// const drawing = renderer.borrow();
    /// var source = try sdl.render.Texture.init(drawing, .{
    ///     .size = .{ .width = 2, .height = 1 }, .access = .streaming,
    /// });
    /// defer source.deinit();
    /// {
    ///     var pixels = try source.borrow().lock_rgba(null);
    ///     defer pixels.deinit();
    ///     @memcpy(try pixels.row(0), &[_]u8{ 255, 0, 0, 255, 0, 255, 0, 255 });
    /// }
    /// var output = try sdl.render.Texture.init(drawing, .{
    ///     .size = .{ .width = 1, .height = 1 }, .access = .target,
    /// });
    /// defer output.deinit();
    /// try drawing.set_target(output.borrow());
    /// try drawing.set_color(.{ .r = 0, .g = 0, .b = 0 });
    /// try drawing.clear();
    /// try drawing.draw_texture_region(
    ///     source.borrow(), .{ .x = 1, .width = 1, .height = 1 }, null,
    /// );
    /// try drawing.set_target(null);
    /// try output.borrow().set_blend_mode(.none);
    /// try drawing.draw_texture(output.borrow(), null);
    /// try drawing.flush();
    /// try @import("std").testing.expectEqual(@as(u8, 255),
    ///     (try surface.borrow().read_pixel(.{ .x = 0, .y = 0 })).g);
    /// ```
    pub fn set_target(self: RendererRef, texture: ?TextureRef) Error!void {
        if (texture) |value| {
            if (value.renderer != self.handle) return error.WrongRenderer;
        }
        if (!c.SDL_SetRenderTarget(self.handle, if (texture) |value| value.handle else null))
            return error.SdlFailure;
    }

    /// Borrow the current texture destination, or null for the original window/software surface.
    /// Main thread, live renderer required. No ownership is retained; the texture/renderer must
    /// outlive the view. Native property lookup may allocate. This does not report pending draws
    /// or distinguish an invalid raw renderer from the default destination.
    pub fn target(self: RendererRef) ?TextureRef {
        const texture = c.SDL_GetRenderTarget(self.handle) orelse return null;
        return .{ .handle = texture, .renderer = self.handle };
    }

    /// Clear the entire current rendering target to the selected draw color on the main thread.
    /// Ignores viewport/clip limits. Call before drawing each new frame, then `present` afterward.
    /// Returns `SdlFailure`; native failure does not guarantee untouched target contents.
    pub fn clear(self: RendererRef) Error!void {
        if (!c.SDL_RenderClear(self.handle)) return error.SdlFailure;
    }

    /// Submit the composed window frame on the main thread. May block for backend synchronization.
    /// Treat backbuffer contents as invalid afterward; start the next frame with `clear`.
    /// Returns `SdlFailure` on native failure, including presenting while a texture is the target.
    /// Does not promise that presentation has completed on the physical display when it returns.
    pub fn present(self: RendererRef) Error!void {
        if (!c.SDL_RenderPresent(self.handle)) return error.SdlFailure;
    }

    /// Fill a rectangle with the current draw color, respecting native clipping/blend state.
    /// Coordinates use the renderer's current coordinate system; null selects the whole target.
    /// Main thread only. `InvalidRect` rejects nonfinite values/negative extents before drawing;
    /// zero-area rectangles are allowed. `SdlFailure` may leave partially changed native contents.
    pub fn fill_rect(self: RendererRef, rect: ?Rect) Error!void {
        const native = if (rect) |value| try native_rect(value) else null;
        if (!c.SDL_RenderFillRect(self.handle, if (native) |*value| value else null)) {
            return error.SdlFailure;
        }
    }

    /// Draw the entire texture into a destination rectangle; null fills the current viewport.
    /// Main thread only. Destination uses renderer coordinates and native texture sampling/blend
    /// state. WrongRenderer rejects a different owner; TargetInUse rejects the current destination
    /// as a source; InvalidRect rejects nonfinite coordinates/negative extents before drawing.
    /// Finish texture locks first. Owners remain borrowed. Native work may allocate/block and
    /// SdlFailure can leave partially changed contents. See draw_texture_region for source crops.
    pub fn draw_texture(self: RendererRef, texture: TextureRef, destination: ?Rect) Error!void {
        return self.draw_texture_region(texture, null, destination);
    }

    /// Draw a contained integer source-pixel region into a renderer-coordinate destination.
    /// Null source selects the entire texture; null destination fills the current viewport.
    /// Source and destination are independent: the selected source is scaled to the destination.
    /// Empty sources are no-ops. OutOfBounds rejects uncontained regions without clipping them;
    /// WrongRenderer, TargetInUse, and InvalidRect are checked before drawing. Finish locks first.
    /// Main thread only; owners remain borrowed. Native sampling/blending may allocate/block;
    /// SdlFailure may leave partial output. Fractional/clipped source rectangles require raw SDL.
    pub fn draw_texture_region(
        self: RendererRef,
        texture: TextureRef,
        source: ?TextureRegion,
        destination: ?Rect,
    ) Error!void {
        if (texture.renderer != self.handle) return error.WrongRenderer;
        try texture.require_not_target();
        const selected = try texture.resolve_region(source);
        const native_destination = if (destination) |value| try native_rect(value) else null;
        if (selected.width == 0 or selected.height == 0) return;
        const native_source = c.SDL_FRect{
            .x = @floatFromInt(selected.x),
            .y = @floatFromInt(selected.y),
            .w = @floatFromInt(selected.width),
            .h = @floatFromInt(selected.height),
        };
        if (!c.SDL_RenderTexture(
            self.handle,
            texture.handle,
            &native_source,
            if (native_destination) |*value| value else null,
        )) return error.SdlFailure;
    }
};

/// Intended texture usage. Support depends on format and renderer; this does not own resources.
pub const TextureAccess = enum(c_uint) {
    /// Infrequent uploads; cannot be locked.
    static = c.SDL_TEXTUREACCESS_STATIC,
    /// Frequent CPU updates; native locking is available with its separate write-only contract.
    streaming = c.SDL_TEXTUREACCESS_STREAMING,
    /// May be selected as a renderer destination when the backend supports it.
    target = c.SDL_TEXTUREACCESS_TARGET,
};

/// Texture allocation request. Storage starts undefined; initialize before drawing from it.
pub const TextureOptions = struct {
    /// Positive source-pixel dimensions, each fitting the native signed integer range.
    size: video.Size,
    /// Requested pixel format. Unknown selects SDL's default; unsupported formats fail natively.
    format: @import("pixels.zig").Format = @import("pixels.zig").Format.rgba32,
    /// Intended update/render usage, defaulting to infrequent uploads.
    access: TextureAccess = .static,
};

/// Contained integer texture pixel region, sharing surface region representation.
/// Empty regions are accepted at resource edges; coordinates are never clipped implicitly.
pub const TextureRegion = @import("surface.zig").Region;

/// Borrowed source rows for byte-addressable texture formats. No ownership transfer.
pub const PixelRows = struct {
    /// Source pixels in the texture's public format, starting at the upload region's top-left.
    /// Must contain (height - 1) * pitch + row_bytes bytes; trailing bytes are ignored.
    bytes: []const u8,
    /// Positive byte distance between row starts, including padding; must fit a native c_int.
    pitch: usize,
};

/// Exclusive write-only RGBA texture lock. Do not copy; release once before either owner dies.
/// Acquisition initializes visible rows to transparent black, discarding prior region contents.
/// Exclude all other texture use, including nested locks, draws, uploads, and native calls, until
/// deinit. This is a caller-enforced lifetime rule, not a mutex or runtime alias detector.
pub const TextureRgbaLock = struct {
    /// Borrowed native texture; do not unlock or destroy through another path.
    handle: *c.SDL_Texture,
    /// Internal borrowed row storage; never replace/free or retain after release.
    pixels: [*]u8,
    /// Locked region width in pixels. Read-only metadata.
    width: u32,
    /// Locked region height in pixels. Read-only metadata.
    height: u32,
    /// Native byte distance between rows, including padding. Read-only metadata.
    pitch: usize,
    /// Exposed bytes per row, excluding padding. Read-only metadata.
    row_bytes: usize,

    /// Borrow a mutable RGBA row relative to the locked region's top-left. Padding is excluded.
    /// Rows start zeroed, not copied from the texture. OutOfBounds leaves storage unchanged;
    /// no allocation/native call. The slice expires on deinit; do not mutate guard metadata.
    pub fn row(self: *const TextureRgbaLock, y: u32) Error![]u8 {
        if (y >= self.height) return error.OutOfBounds;
        const offset = @as(usize, y) * self.pitch;
        return self.pixels[offset..][0..self.row_bytes];
    }

    /// Unlock and submit initialized rows on the main thread, invalidating this guard and slices.
    /// SDL may allocate/block and provides no error result; return is not proof of GPU completion
    /// or upload success. Owners must remain alive. Unwritten bytes remain transparent black.
    pub fn deinit(self: *TextureRgbaLock) void {
        c.SDL_UnlockTexture(self.handle);
        self.* = undefined;
    }
};

/// Owns a texture borrowing its renderer. Do not copy; destroy before its renderer.
pub const Texture = struct {
    /// Native interop handle; do not destroy separately or mutate the owner association.
    handle: *c.SDL_Texture,
    /// Borrowed parent used to reject cross-renderer draws. Do not replace or destroy it here.
    renderer: *c.SDL_Renderer,

    /// Allocate a texture on the main thread without initializing its pixels. Initialize storage
    /// before sampling it. The renderer must outlive the returned owner. SDL may allocate/convert
    /// backing formats; unsupported combinations return SdlFailure with no owner. InvalidSize
    /// rejects zero/oversized dimensions before allocation. Native failure may set diagnostic text.
    /// Access selection alone does not lock storage or select a render target.
    pub fn init(renderer: RendererRef, options: TextureOptions) Error!Texture {
        try video.validate_size(options.size);
        const handle = c.SDL_CreateTexture(
            renderer.handle,
            @backingInt(options.format),
            @backingInt(options.access),
            @intCast(options.size.width),
            @intCast(options.size.height),
        ) orelse return error.SdlFailure;
        return .{ .handle = handle, .renderer = renderer.handle };
    }

    /// Create/upload a static texture on the main thread. Its renderer must outlive it.
    /// `size` is in pixels; `pixels` must contain exactly width * height * 4 bytes, in R,G,B,A
    /// byte order, row-major from top-left, with no row padding. SDL copies them before return;
    /// the caller may immediately reuse/free the input. SDL may allocate or block.
    /// `InvalidSize` rejects zero/oversized dimensions or pitch/length overflow; `InvalidPixels`
    /// rejects a byte-count mismatch. These checks precede allocation. `SdlFailure` releases any
    /// newly created texture before returning no owner; cleanup can overwrite native diagnostics.
    /// Static textures suit infrequent uploads. Use init for other formats/access modes.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// sdl.raw.SDL_SetMainReady();
    /// defer sdl.raw.SDL_Quit();
    /// var subsystems = try sdl.init(.{ .video = true });
    /// defer subsystems.deinit();
    /// var window = try sdl.video.Window.init(&.{
    ///     .title = "Texture", .size = .{ .width = 32, .height = 32 }, .hidden = true,
    /// });
    /// defer window.deinit();
    /// var renderer = try sdl.render.Renderer.init(window.borrow(), .{ .driver = "software" });
    /// defer renderer.deinit();
    /// const pixels = [_]u8{ 255, 128, 0, 255 };
    /// var texture = try sdl.render.Texture.init_rgba(
    ///     renderer.borrow(), .{ .width = 1, .height = 1 }, &pixels,
    /// );
    /// defer texture.deinit();
    /// const drawing = renderer.borrow();
    /// try drawing.set_color(.{ .r = 0, .g = 0, .b = 0 });
    /// try drawing.clear();
    /// try drawing.draw_texture(texture.borrow(), null);
    /// try drawing.present();
    /// ```
    pub fn init_rgba(renderer: RendererRef, size: video.Size, pixels: []const u8) Error!Texture {
        const pitch = try rgba_pitch(size, pixels.len);
        var texture = try init(renderer, .{ .size = size });
        errdefer texture.deinit();
        if (!c.SDL_UpdateTexture(texture.handle, null, pixels.ptr, pitch)) return error.SdlFailure;
        return texture;
    }

    /// Copy a live CPU surface into a new static texture on the main thread.
    /// The surface is neither modified nor retained: it may be destroyed immediately afterward.
    /// Its color key/alpha affect native texture transparency; the texture format may differ.
    /// SDL may allocate or convert pixels. `SdlFailure` returns no texture owner, leaving the
    /// surface owned by the caller. The renderer must outlive the returned texture.
    pub fn from_surface(renderer: RendererRef, surface: @import("surface.zig").SurfaceRef) Error!Texture {
        const handle = c.SDL_CreateTextureFromSurface(renderer.handle, surface.handle) orelse
            return error.SdlFailure;
        return .{ .handle = handle, .renderer = renderer.handle };
    }

    /// Destroy on the main thread before its renderer. Invalidates this owner and its views.
    /// Call exactly once, never through an owner copy. No fallible result.
    pub fn deinit(self: *Texture) void {
        c.SDL_DestroyTexture(self.handle);
        self.* = undefined;
    }

    /// Return a non-owning view without allocation/native calls. Neither owner is retained.
    /// The texture and renderer must both outlive the view; invalid views cannot be detected.
    pub fn borrow(self: *const Texture) TextureRef {
        return .{ .handle = self.handle, .renderer = self.renderer };
    }
};

/// Non-owning texture view, copyable while the texture and its renderer remain alive.
/// The parent check catches mismatched renderers, not stale pointers or reuse after destruction.
pub const TextureRef = struct {
    /// Native interop handle. Do not destroy through this borrowed view.
    handle: *c.SDL_Texture,
    /// Borrowed parent identity. Keep the association intact when using native interop.
    renderer: *c.SDL_Renderer,

    /// Read exact integer pixel dimensions from SDL's public read-only metadata on the main thread.
    /// InvalidSize reports nonpositive native metadata. No allocation; owner must remain alive.
    pub fn pixel_size(self: TextureRef) Error!video.Size {
        if (self.handle.w <= 0 or self.handle.h <= 0) return error.InvalidSize;
        return .{ .width = @intCast(self.handle.w), .height = @intCast(self.handle.h) };
    }

    /// Read the public pixel format on the main thread, preserving unknown native identities.
    /// This is the upload format, which can differ from internal GPU storage. No allocation.
    pub fn format(self: TextureRef) @import("pixels.zig").Format {
        return @fromBackingInt(self.handle.format);
    }

    /// Replace a contained region of RGBA32 texture pixels on the main thread; null replaces all.
    /// Bytes are tightly packed R,G,B,A rows from the region's top-left, with no padding. SDL copies
    /// them before returning; caller storage is not retained. Finish native locks first and do not
    /// upload while locked. TargetInUse rejects the active render target. Native work may allocate
    /// or block.
    /// UnsupportedFormat rejects other formats; OutOfBounds rejects uncontained regions;
    /// InvalidPixels rejects a nonexact length; InvalidSize rejects pitch/length overflow. Checks
    /// precede mutation. An empty contained region accepts only empty bytes and performs no upload.
    /// SdlFailure may leave partially updated pixels. Streaming uploads do not promise preservation
    /// when storage is subsequently locked; a lock is write-only and must initialize its region.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer surface.deinit();
    /// var renderer = try sdl.render.Renderer.for_surface(surface.borrow());
    /// defer renderer.deinit();
    /// var texture = try sdl.render.Texture.init(renderer.borrow(), .{
    ///     .size = .{ .width = 2, .height = 1 }, .access = .streaming,
    /// });
    /// defer texture.deinit();
    /// try texture.borrow().update_rgba(null, &.{ 0, 0, 0, 255, 0, 0, 0, 255 });
    /// try texture.borrow().update_rgba(
    ///     .{ .x = 1, .width = 1, .height = 1 }, &.{ 255, 0, 0, 255 },
    /// );
    /// try renderer.borrow().draw_texture(texture.borrow(), null);
    /// try renderer.borrow().flush();
    /// ```
    pub fn update_rgba(self: TextureRef, region: ?TextureRegion, pixels: []const u8) Error!void {
        if (self.format() != @import("pixels.zig").Format.rgba32) return error.UnsupportedFormat;
        try self.require_not_target();
        const selected = try self.resolve_region(region);
        if (selected.width == 0 or selected.height == 0) {
            if (pixels.len != 0) return error.InvalidPixels;
            return;
        }
        const pitch = try rgba_pitch(.{
            .width = selected.width,
            .height = selected.height,
        }, pixels.len);
        const native = c.SDL_Rect{
            .x = @intCast(selected.x),
            .y = @intCast(selected.y),
            .w = @intCast(selected.width),
            .h = @intCast(selected.height),
        };
        if (!c.SDL_UpdateTexture(self.handle, &native, pixels.ptr, pitch)) return error.SdlFailure;
    }

    /// Upload contained rows in this texture's public format on the main thread. Null selects all.
    /// Supports byte-addressable non-FourCC formats, including index8 and packed/array RGB(A).
    /// Does not convert caller encoding: use format() to choose it. UnsupportedFormat rejects
    /// planar/compressed/FourCC and sub-byte formats. An indexed texture needs a palette to draw.
    /// OutOfBounds, InvalidSize (pitch/arithmetic), InvalidPixels (short rows), and TargetInUse
    /// precede upload. Empty contained regions require empty bytes and ignore pitch. Nonempty
    /// inputs need only the visible bytes of the last row; trailing bytes/padding are not pixels.
    /// Finish locks first. Source storage is borrowed only for the call and must not alias locked
    /// texture memory. SDL may allocate/block/convert internally; SdlFailure can leave partial data.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer surface.deinit();
    /// var renderer = try sdl.render.Renderer.for_surface(surface.borrow());
    /// defer renderer.deinit();
    /// var palette_owner = try sdl.pixels.Palette.init(2);
    /// defer palette_owner.deinit();
    /// try palette_owner.borrow().set_colors(0, &.{
    ///     .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 0, .g = 0, .b = 255 },
    /// });
    /// var texture = try sdl.render.Texture.init(renderer.borrow(), .{
    ///     .size = .{ .width = 2, .height = 1 }, .format = .index8,
    /// });
    /// defer texture.deinit();
    /// try texture.borrow().set_palette(palette_owner.borrow());
    /// try texture.borrow().update_pixels(null, .{ .bytes = &.{ 0, 1 }, .pitch = 2 });
    /// try renderer.borrow().draw_texture(texture.borrow(), null);
    /// try renderer.borrow().flush();
    /// ```
    pub fn update_pixels(self: TextureRef, region: ?TextureRegion, rows: PixelRows) Error!void {
        const pixel_format = self.format();
        const bytes_per_pixel = pixel_format.storage_bytes_per_pixel();
        if (pixel_format.is_fourcc() or bytes_per_pixel == 0) return error.UnsupportedFormat;
        try self.require_not_target();
        const selected = try self.resolve_region(region);
        if (selected.width == 0 or selected.height == 0) {
            if (rows.bytes.len != 0) return error.InvalidPixels;
            return;
        }
        const pitch = try validate_upload_rows(selected, bytes_per_pixel, rows);
        const native = c.SDL_Rect{
            .x = @intCast(selected.x),
            .y = @intCast(selected.y),
            .w = @intCast(selected.width),
            .h = @intCast(selected.height),
        };
        if (!c.SDL_UpdateTexture(self.handle, &native, rows.bytes.ptr, pitch))
            return error.SdlFailure;
    }

    /// Associate a shared palette with an indexed texture, or null to remove it. Main thread;
    /// synchronize with every surface/texture sharing the palette and finish texture locks first.
    /// Success retains a native reference, so the caller may release its Palette owner. Shared
    /// edits affect subsequent draws. SdlFailure includes incompatible formats/counts and can
    /// replace/remove prior state. Native work may allocate/block. Existing borrowed palette views
    /// expire on replacement/removal/destruction unless independently kept alive by another owner.
    pub fn set_palette(self: TextureRef, value: ?@import("pixels.zig").PaletteRef) Error!void {
        const handle = if (value) |palette_value| palette_value.handle else null;
        if (!c.SDL_SetTexturePalette(self.handle, handle)) return error.SdlFailure;
    }

    /// Borrow this texture's palette, or null when absent, on the main thread. No ownership is
    /// retained; never destroy the view separately. It expires when the association is replaced,
    /// removed, or destroyed. Synchronize palette access with all sharing textures/surfaces.
    pub fn palette(self: TextureRef) ?@import("pixels.zig").PaletteRef {
        const handle = c.SDL_GetTexturePalette(self.handle) orelse return null;
        return .{ .handle = handle };
    }

    /// Acquire exclusive RGBA32 streaming storage for a nonempty contained pixel region.
    /// Null selects the entire texture. Main thread only; both owners must outlive the guard.
    /// The region is write-only: this wrapper clears its visible rows to transparent black before
    /// returning, so early release never uploads uninitialized visible pixels. Cost is linear in
    /// region bytes; no Zig allocation. Prior contents are discarded, and outside pixels survive.
    /// UnsupportedFormat, OutOfBounds, TargetInUse, and InvalidSize (empty region) precede locking.
    /// SdlFailure includes non-streaming access. InvalidPixelLayout releases a malformed native
    /// lock before returning no guard; that cleanup can change pixels/diagnostics. Native work can
    /// allocate/block. No nested locks or concurrent/aliased texture access: SDL exposes no portable
    /// lock-state query, so this lifetime restriction is caller-enforced. Defer guard.deinit().
    pub fn lock_rgba(self: TextureRef, region: ?TextureRegion) Error!TextureRgbaLock {
        if (self.format() != @import("pixels.zig").Format.rgba32) return error.UnsupportedFormat;
        try self.require_not_target();
        const selected = try self.resolve_region(region);
        if (selected.width == 0 or selected.height == 0) return error.InvalidSize;
        const native = c.SDL_Rect{
            .x = @intCast(selected.x),
            .y = @intCast(selected.y),
            .w = @intCast(selected.width),
            .h = @intCast(selected.height),
        };
        var pixels: ?*anyopaque = null;
        var pitch: c_int = 0;
        if (!c.SDL_LockTexture(self.handle, &native, &pixels, &pitch)) return error.SdlFailure;
        errdefer c.SDL_UnlockTexture(self.handle);
        const row_bytes = try validate_locked_layout(selected.width, selected.height, pitch);
        const base = pixels orelse return error.InvalidPixelLayout;
        const guard = TextureRgbaLock{
            .handle = self.handle,
            .pixels = @ptrCast(base),
            .width = selected.width,
            .height = selected.height,
            .pitch = @intCast(pitch),
            .row_bytes = row_bytes,
        };
        for (0..guard.height) |y| {
            const offset = y * guard.pitch;
            @memset(guard.pixels[offset..][0..guard.row_bytes], 0);
        }
        return guard;
    }

    fn require_not_target(self: TextureRef) Error!void {
        if (c.SDL_GetRenderTarget(self.renderer) == self.handle) return error.TargetInUse;
    }

    fn resolve_region(self: TextureRef, region: ?TextureRegion) Error!TextureRegion {
        const dimensions = try self.pixel_size();
        const selected = region orelse TextureRegion{
            .width = dimensions.width,
            .height = dimensions.height,
        };
        if (selected.x > dimensions.width or selected.y > dimensions.height)
            return error.OutOfBounds;
        if (selected.width > dimensions.width - selected.x or
            selected.height > dimensions.height - selected.y) return error.OutOfBounds;
        return selected;
    }

    /// Copy texture dimensions as floating pixel extents on the main thread.
    /// This is source size, independent of destination scaling, viewport, and logical presentation.
    /// Very large integer dimensions can lose float precision; do not derive allocation lengths
    /// from this query. SdlFailure returns no size. No allocation or ownership transfer.
    pub fn size(self: TextureRef) Error!FloatSize {
        var value: FloatSize = undefined;
        if (!c.SDL_GetTextureSize(self.handle, &value.width, &value.height)) return error.SdlFailure;
        return value;
    }

    /// Select sampling for this texture on the main thread, without changing stored pixels or
    /// the renderer's default for new textures. InvalidScaleMode rejects invalid/unknown identities
    /// before mutation. Unsupported policies can fall back; SdlFailure may change native state.
    /// No ownership transfer or wrapper allocation.
    pub fn set_scale_mode(self: TextureRef, mode: ScaleMode) Error!void {
        try validate_scale_mode(mode);
        if (!c.SDL_SetTextureScaleMode(self.handle, @backingInt(mode))) return error.SdlFailure;
    }

    /// Query stored texture sampling on the main thread, preserving unknown identities.
    /// This metadata does not prove backend filtering quality. SdlFailure returns no mode;
    /// no allocation or state change.
    pub fn scale_mode(self: TextureRef) Error!ScaleMode {
        var mode: c.SDL_ScaleMode = undefined;
        if (!c.SDL_GetTextureScaleMode(self.handle, &mode)) return error.SdlFailure;
        return @fromBackingInt(mode);
    }

    /// Set RGB multipliers for texture copies on the main thread. White resets tint.
    /// Stored pixels and alpha are unchanged; renderer drawing color is independent. Native
    /// geometry drawing uses vertex colors instead. SdlFailure may follow partial state changes.
    /// No ownership transfer or wrapper allocation.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer surface.deinit();
    /// var renderer = try sdl.render.Renderer.for_surface(surface.borrow());
    /// defer renderer.deinit();
    /// var texture = try sdl.render.Texture.init_rgba(
    ///     renderer.borrow(), .{ .width = 1, .height = 1 }, &.{ 255, 255, 255, 255 },
    /// );
    /// defer texture.deinit();
    /// try texture.borrow().set_tint(.{ .g = 0, .b = 0 });
    /// try texture.borrow().set_opacity(128);
    /// try texture.borrow().set_blend_mode(.alpha);
    /// try renderer.borrow().set_color(.{ .r = 0, .g = 0, .b = 255 });
    /// try renderer.borrow().clear();
    /// try renderer.borrow().draw_texture(texture.borrow(), null);
    /// try renderer.borrow().flush();
    /// ```
    pub fn set_tint(self: TextureRef, value: Tint) Error!void {
        if (!c.SDL_SetTextureColorMod(self.handle, value.r, value.g, value.b))
            return error.SdlFailure;
    }

    /// Copy RGB multipliers as bytes on the main thread. Clamp finite values to 0..1 and round
    /// to the nearest byte, matching native texture conversion. InvalidColor rejects raw-installed
    /// nonfinite state safely; SdlFailure returns no value. State is unchanged; no allocation.
    pub fn tint(self: TextureRef) Error!Tint {
        const value = try self.tint_float();
        return .{
            .r = try modulation_byte(value.r),
            .g = try modulation_byte(value.g),
            .b = try modulation_byte(value.b),
        };
    }

    /// Set floating RGB multipliers on the main thread. InvalidColor rejects NaN/infinity before
    /// mutation. Finite HDR/negative values pass unchanged, without promising backend support or
    /// selecting a colorspace. Alpha and stored pixels stay unchanged. SdlFailure may change state;
    /// no ownership transfer or wrapper allocation. Geometry drawing ignores this tint.
    pub fn set_tint_float(self: TextureRef, value: FloatTint) Error!void {
        if (!std.math.isFinite(value.r) or !std.math.isFinite(value.g) or
            !std.math.isFinite(value.b)) return error.InvalidColor;
        if (!c.SDL_SetTextureColorModFloat(self.handle, value.r, value.g, value.b))
            return error.SdlFailure;
    }

    /// Copy unquantized RGB multipliers on the main thread. Raw-installed nonfinite values survive.
    /// SdlFailure returns no value; no wrapper allocation or state change.
    pub fn tint_float(self: TextureRef) Error!FloatTint {
        var value: FloatTint = undefined;
        if (!c.SDL_GetTextureColorModFloat(self.handle, &value.r, &value.g, &value.b))
            return error.SdlFailure;
        return value;
    }

    /// Multiply source alpha by value/255 for texture copies on the main thread; 255 resets it.
    /// Does not enable blending or change stored pixels/RGB tint. Geometry ignores this multiplier.
    /// SdlFailure may follow state changes; no wrapper allocation or ownership transfer.
    pub fn set_opacity(self: TextureRef, value: u8) Error!void {
        if (!c.SDL_SetTextureAlphaMod(self.handle, value)) return error.SdlFailure;
    }

    /// Copy alpha multiplier as a byte on the main thread, clamping finite values and rounding
    /// to the nearest byte. InvalidColor rejects nonfinite native state; SdlFailure returns no
    /// value. Does not measure effective pixel opacity; no allocation or state change.
    pub fn opacity(self: TextureRef) Error!u8 {
        return modulation_byte(try self.opacity_float());
    }

    /// Set floating source-alpha multiplier on the main thread. One resets opacity. InvalidColor
    /// rejects NaN/infinity before mutation; finite out-of-range values pass to SDL unchanged.
    /// Backend behavior depends on blending/output format. Geometry ignores this multiplier.
    /// SdlFailure may change state; stored pixels stay unchanged. No wrapper allocation.
    pub fn set_opacity_float(self: TextureRef, value: f32) Error!void {
        if (!std.math.isFinite(value)) return error.InvalidColor;
        if (!c.SDL_SetTextureAlphaModFloat(self.handle, value)) return error.SdlFailure;
    }

    /// Copy unquantized alpha multiplier on the main thread. Raw-installed nonfinite values survive.
    /// SdlFailure returns no value; no wrapper allocation or state change.
    pub fn opacity_float(self: TextureRef) Error!f32 {
        var value: f32 = undefined;
        if (!c.SDL_GetTextureAlphaModFloat(self.handle, &value)) return error.SdlFailure;
        return value;
    }

    /// Set texture compositing on the main thread, independently of primitive drawing blend state.
    /// Premultiplied modes require premultiplied source pixels. Unsupported modes return SdlFailure;
    /// do not assume failure leaves state unchanged. Query blend_mode if fallback matters.
    /// No ownership transfer or wrapper allocation.
    pub fn set_blend_mode(self: TextureRef, mode: BlendMode) Error!void {
        if (!c.SDL_SetTextureBlendMode(self.handle, @backingInt(mode))) return error.SdlFailure;
    }

    /// Query texture compositing on the main thread, preserving unknown native identities.
    /// SdlFailure returns no mode; no wrapper allocation or state change.
    pub fn blend_mode(self: TextureRef) Error!BlendMode {
        var mode: c.SDL_BlendMode = undefined;
        if (!c.SDL_GetTextureBlendMode(self.handle, &mode)) return error.SdlFailure;
        return @fromBackingInt(mode);
    }

    /// Borrow this object's native property group. Main thread under this wrapper contract.
    /// May allocate/block; `SdlFailure` returns no view. The object owns the group: never destroy
    /// it separately. Finish all views/locks before object destruction. Use application-specific
    /// keys for custom data; native keys retain their individual read/write and lifetime contracts.
    pub fn properties(
        self: TextureRef,
    ) @import("errors.zig").Error!@import("properties.zig").PropertiesRef {
        const handle = c.SDL_GetTextureProperties(self.handle);
        if (handle == 0) return error.SdlFailure;
        return .{ .handle = handle };
    }
};

fn rgba_pitch(size: video.Size, length: usize) Error!c_int {
    try video.validate_size(size);
    const pitch = std.math.mul(u32, size.width, 4) catch return error.InvalidSize;
    if (pitch > std.math.maxInt(c_int)) return error.InvalidSize;
    const bytes = std.math.mul(usize, pitch, size.height) catch return error.InvalidSize;
    if (length != bytes) return error.InvalidPixels;
    return @intCast(pitch);
}

fn native_rect(rect: Rect) Error!c.SDL_FRect {
    if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or
        !std.math.isFinite(rect.width) or !std.math.isFinite(rect.height)) return error.InvalidRect;
    if (rect.width < 0 or rect.height < 0) return error.InvalidRect;
    return .{ .x = rect.x, .y = rect.y, .w = rect.width, .h = rect.height };
}

test "texture byte and pitch bounds" {
    try std.testing.expectEqual(@as(c_int, 8), try rgba_pitch(.{ .width = 2, .height = 2 }, 16));
    try std.testing.expectError(error.InvalidPixels, rgba_pitch(.{ .width = 2, .height = 2 }, 15));
    try std.testing.expectError(error.InvalidPixels, rgba_pitch(.{ .width = 2, .height = 2 }, 17));
    try std.testing.expectError(
        error.InvalidSize,
        rgba_pitch(.{ .width = 1 << 30, .height = 1 }, 0),
    );
}

test "rectangles reject nonfinite and negative extents" {
    try std.testing.expectError(error.InvalidRect, native_rect(.{
        .x = std.math.nan(f32),
        .y = 0,
        .width = 1,
        .height = 1,
    }));
    try std.testing.expectError(error.InvalidRect, native_rect(.{
        .x = 0,
        .y = 0,
        .width = -1,
        .height = 1,
    }));
    _ = try native_rect(.{ .x = -1, .y = 0, .width = 0, .height = 0 });
}

test "driver names are bounded and reusable identifiers" {
    for (0..driver_count()) |index| {
        try std.testing.expect((try driver_name(index)).len > 0);
    }
    try std.testing.expectError(error.OutOfBounds, driver_name(driver_count()));
    try std.testing.expectError(error.OutOfBounds, driver_name(std.math.maxInt(usize)));
}

test "software renderer borrows a surface and reports backend dimensions" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer surface.deinit();
    {
        var renderer = try Renderer.for_surface(surface.borrow());
        defer renderer.deinit();
        const view = renderer.borrow();
        try std.testing.expectEqualStrings("software", try view.name());
        try std.testing.expectError(error.SdlFailure, view.window());
        try std.testing.expectEqualDeep(
            video.Size{ .width = 3, .height = 2 },
            try view.output_size(),
        );
        try std.testing.expectEqualDeep(try view.output_size(), try view.current_output_size());
        try view.set_color(.{ .r = 12, .g = 34, .b = 56 });
        try view.clear();
        try view.present();
    }
    try std.testing.expectEqualDeep(
        Color{ .r = 12, .g = 34, .b = 56 },
        try surface.borrow().read_pixel(.{ .x = 2, .y = 1 }),
    );
}

test "renderer color state preserves floats and primitive blending affects output" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const view = renderer.borrow();
    const hdr = FloatColor{ .r = 2, .g = -0.5, .b = 0.25, .a = 0.5 };
    try view.set_color_float(hdr);
    try std.testing.expectEqualDeep(hdr, try view.color_float());
    try std.testing.expect(c.SDL_SetRenderDrawColorFloat(
        view.handle,
        std.math.nan(f32),
        0,
        0,
        1,
    ));
    try std.testing.expectError(error.InvalidColor, view.color());
    try view.set_color_float(hdr);
    const quantized = try view.color();
    try std.testing.expectEqual(@as(u8, 255), quantized.r);
    try std.testing.expectEqual(@as(u8, 0), quantized.g);
    try std.testing.expectError(
        error.InvalidColor,
        view.set_color_float(.{ .r = std.math.nan(f32), .g = 0, .b = 0 }),
    );
    try std.testing.expectEqualDeep(hdr, try view.color_float());
    try view.set_blend_mode(.alpha);
    try std.testing.expectEqual(BlendMode.alpha, try view.blend_mode());
    try view.set_color(.{ .r = 0, .g = 0, .b = 255 });
    try view.clear();
    try view.set_color(.{ .r = 255, .g = 0, .b = 0, .a = 128 });
    try std.testing.expectEqualDeep(Color{ .r = 255, .g = 0, .b = 0, .a = 128 }, try view.color());
    try view.fill_rect(.{ .x = 0, .y = 0, .width = 1, .height = 1 });
    try view.present();
    const blended = try surface.borrow().read_pixel(.{ .x = 0, .y = 0 });
    try std.testing.expect(blended.r >= 127 and blended.r <= 128);
    try std.testing.expect(blended.b >= 126 and blended.b <= 127);
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 0, .b = 255 },
        try surface.borrow().read_pixel(.{ .x = 1, .y = 0 }),
    );
    try view.set_blend_mode(.none);
    try view.fill_rect(null);
    try view.present();
    try std.testing.expectEqualDeep(
        Color{ .r = 255, .g = 0, .b = 0, .a = 128 },
        try surface.borrow().read_pixel(.{ .x = 1, .y = 0 }),
    );
}

fn color_byte(value: f32) Error!u8 {
    if (!std.math.isFinite(value)) return error.InvalidColor;
    return @intFromFloat(std.math.clamp(value, 0, 1) * 255);
}

test "logical presentation distinguishes physical output and logical drawing dimensions" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 8, .height = 6 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const view = renderer.borrow();
    const requested = Presentation{ .size = .{ .width = 4, .height = 2 }, .mode = .letterbox };
    try view.set_presentation(requested);
    try std.testing.expectEqualDeep(requested, try view.presentation());
    try std.testing.expectEqualDeep(
        video.Size{ .width = 8, .height = 4 },
        try view.current_output_size(),
    );
    try std.testing.expectEqualDeep(video.Size{ .width = 8, .height = 6 }, try view.output_size());
    try std.testing.expectEqualDeep(
        Rect{ .x = 0, .y = 1, .width = 8, .height = 4 },
        try view.presentation_rect(),
    );
    try std.testing.expectError(error.InvalidSize, view.set_presentation(.{
        .size = .{ .width = 0, .height = 2 },
        .mode = .stretch,
    }));
    try std.testing.expectEqualDeep(requested, try view.presentation());
    try view.set_presentation(null);
    try std.testing.expectEqual(PresentationMode.disabled, (try view.presentation()).mode);
    try std.testing.expectEqualDeep(try view.output_size(), try view.current_output_size());
}

fn validate_point(point: Point) Error!void {
    if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) return error.InvalidCoordinate;
}

test "surface renderer synchronization metadata and explicit flush" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const view = renderer.borrow();
    try std.testing.expectEqual(VSync.every_refresh, try VSync.interval(1));
    try std.testing.expectEqual(@as(i32, 2), @backingInt(try VSync.interval(2)));
    try std.testing.expectError(error.InvalidVSync, VSync.interval(0));
    try view.set_vsync(.disabled);
    try std.testing.expectEqual(VSync.disabled, try view.vsync());
    try std.testing.expectError(error.SdlFailure, view.set_vsync(.every_refresh));
    try std.testing.expectError(error.InvalidVSync, view.set_vsync(@fromBackingInt(@as(i32, -2))));
    try view.set_vsync(.disabled);
    try view.set_color(.{ .r = 7, .g = 8, .b = 9 });
    try view.clear();
    try view.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 7, .g = 8, .b = 9 },
        try surface.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
}

fn modulation_byte(value: f32) Error!u8 {
    if (!std.math.isFinite(value)) return error.InvalidColor;
    return @intFromFloat(@round(std.math.clamp(value, 0, 1) * 255));
}

test "texture modulation preserves float state and validates before mutation" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    var texture = try Texture.init_rgba(
        renderer.borrow(),
        .{ .width = 1, .height = 1 },
        &.{ 255, 255, 255, 255 },
    );
    defer texture.deinit();
    const view = texture.borrow();
    const value = FloatTint{ .r = 2, .g = -1, .b = 0.5 };
    try view.set_tint_float(value);
    try std.testing.expectEqualDeep(value, try view.tint_float());
    try std.testing.expectEqualDeep(Tint{ .r = 255, .g = 0, .b = 128 }, try view.tint());
    try std.testing.expectError(
        error.InvalidColor,
        view.set_tint_float(.{ .r = std.math.nan(f32) }),
    );
    try std.testing.expectEqualDeep(value, try view.tint_float());
    try view.set_opacity_float(0.5);
    try std.testing.expectEqual(@as(u8, 128), try view.opacity());
    try std.testing.expectError(error.InvalidColor, view.set_opacity_float(std.math.inf(f32)));
    try std.testing.expectEqual(@as(f32, 0.5), try view.opacity_float());
    try std.testing.expect(c.SDL_SetTextureColorModFloat(view.handle, std.math.nan(f32), 1, 1));
    try std.testing.expectError(error.InvalidColor, view.tint());
    try std.testing.expect(c.SDL_SetTextureAlphaModFloat(view.handle, std.math.nan(f32)));
    try std.testing.expectError(error.InvalidColor, view.opacity());
    try view.set_tint(.{});
    try view.set_opacity(255);
}

test "texture copies use independent tint opacity and blend state" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    var texture = try Texture.init_rgba(
        drawing,
        .{ .width = 1, .height = 1 },
        &.{ 255, 255, 255, 255 },
    );
    defer texture.deinit();
    const source = texture.borrow();
    try source.set_tint(.{ .g = 0, .b = 0 });
    try source.set_opacity(128);
    try source.set_blend_mode(.alpha);
    try std.testing.expectEqualDeep(Tint{ .g = 0, .b = 0 }, try source.tint());
    try std.testing.expectEqual(@as(u8, 128), try source.opacity());
    try std.testing.expectEqual(BlendMode.alpha, try source.blend_mode());
    try drawing.set_blend_mode(.none);
    try drawing.set_color(.{ .r = 0, .g = 0, .b = 255 });
    try drawing.clear();
    try drawing.draw_texture(source, null);
    try drawing.flush();
    const blended = try surface.borrow().read_pixel(.{ .x = 0, .y = 0 });
    try std.testing.expect(blended.r >= 127 and blended.r <= 128);
    try std.testing.expectEqual(@as(u8, 0), blended.g);
    try std.testing.expect(blended.b >= 127 and blended.b <= 128);
    try source.set_tint(.{});
    try source.set_opacity(255);
    try source.set_blend_mode(.none);
    try drawing.draw_texture(source, null);
    try drawing.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 255, .g = 255, .b = 255 },
        try surface.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectEqual(BlendMode.none, try drawing.blend_mode());
}

fn validate_scale_mode(mode: ScaleMode) Error!void {
    switch (mode) {
        .nearest, .linear, .pixel_art => {},
        else => return error.InvalidScaleMode,
    }
}

test "texture sampling defaults affect new textures and nearest copies replicate pixels" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 4, .height = 2 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    try std.testing.expectEqual(ScaleMode.linear, try drawing.default_texture_scale_mode());
    const pixels = [_]u8{ 255, 0, 0, 255, 0, 0, 255, 255 };
    var first = try Texture.init_rgba(drawing, .{ .width = 2, .height = 1 }, &pixels);
    defer first.deinit();
    try drawing.set_default_texture_scale_mode(.nearest);
    try std.testing.expectEqual(ScaleMode.linear, try first.borrow().scale_mode());
    var second = try Texture.init_rgba(drawing, .{ .width = 2, .height = 1 }, &pixels);
    defer second.deinit();
    const source = second.borrow();
    try std.testing.expectEqual(ScaleMode.nearest, try source.scale_mode());
    try std.testing.expectEqualDeep(FloatSize{ .width = 2, .height = 1 }, try source.size());
    for ([_]ScaleMode{ .linear, .pixel_art, .nearest }) |mode| {
        try source.set_scale_mode(mode);
        try std.testing.expectEqual(mode, try source.scale_mode());
    }
    try std.testing.expectError(error.InvalidScaleMode, source.set_scale_mode(.invalid));
    try std.testing.expectError(
        error.InvalidScaleMode,
        drawing.set_default_texture_scale_mode(@fromBackingInt(@as(c_int, 99))),
    );
    try std.testing.expectEqual(ScaleMode.nearest, try source.scale_mode());
    try std.testing.expectEqual(ScaleMode.nearest, try drawing.default_texture_scale_mode());
    try source.set_blend_mode(.none);
    try drawing.draw_texture(source, null);
    try drawing.flush();
    for (0..2) |y| {
        for (0..4) |x| {
            const expected = if (x < 2) Color{ .r = 255, .g = 0, .b = 0 } else Color{ .r = 0, .g = 0, .b = 255 };
            try std.testing.expectEqualDeep(
                expected,
                try surface.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) }),
            );
        }
    }
}

test "general textures and checked region uploads preserve untouched pixels" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 2, .height = 2 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    try std.testing.expectError(error.InvalidSize, Texture.init(drawing, .{
        .size = .{ .width = 0, .height = 2 },
    }));
    for ([_]TextureAccess{ .static, .streaming, .target }) |access| {
        var texture = try Texture.init(drawing, .{
            .size = .{ .width = 2, .height = 2 },
            .access = access,
        });
        defer texture.deinit();
        const view = texture.borrow();
        try std.testing.expectEqual(@import("pixels.zig").Format.rgba32, view.format());
        try std.testing.expectEqualDeep(
            video.Size{ .width = 2, .height = 2 },
            try view.pixel_size(),
        );
        const blue = [_]u8{ 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255 };
        try view.update_rgba(null, &blue);
        const bottom_right = TextureRegion{ .x = 1, .y = 1, .width = 1, .height = 1 };
        try view.update_rgba(bottom_right, &.{ 255, 0, 0, 255 });
        try std.testing.expectError(
            error.InvalidPixels,
            view.update_rgba(bottom_right, &.{ 0, 0 }),
        );
        try std.testing.expectError(error.OutOfBounds, view.update_rgba(.{
            .x = std.math.maxInt(u32),
            .width = 1,
            .height = 1,
        }, &.{ 0, 0, 0, 0 }));
        const empty = TextureRegion{ .x = 2, .width = 0, .height = 2 };
        try view.update_rgba(empty, &.{});
        try std.testing.expectError(error.InvalidPixels, view.update_rgba(empty, &.{0}));
        try view.set_blend_mode(.none);
        try drawing.draw_texture(view, null);
        try drawing.flush();
        for (0..2) |y| {
            for (0..2) |x| {
                const expected: Color = if (x == 1 and y == 1)
                    .{ .r = 255, .g = 0, .b = 0 }
                else
                    .{ .r = 0, .g = 0, .b = 255 };
                try std.testing.expectEqualDeep(
                    expected,
                    try surface.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) }),
                );
            }
        }
    }
    var alternate = try Texture.init(drawing, .{
        .size = .{ .width = 1, .height = 1 },
        .format = .rgb565,
    });
    defer alternate.deinit();
    try std.testing.expectEqual(@import("pixels.zig").Format.rgb565, alternate.borrow().format());
    try std.testing.expectError(
        error.UnsupportedFormat,
        alternate.borrow().update_rgba(null, &.{ 0, 0, 0, 0 }),
    );
}

fn validate_locked_layout(width: u32, height: u32, pitch: c_int) Error!usize {
    if (width == 0 or height == 0 or pitch <= 0) return error.InvalidPixelLayout;
    const row_bytes = std.math.mul(usize, width, 4) catch return error.InvalidPixelLayout;
    const stride: usize = @intCast(pitch);
    if (stride < row_bytes) return error.InvalidPixelLayout;
    const offset = std.math.mul(usize, height - 1, stride) catch return error.InvalidPixelLayout;
    _ = std.math.add(usize, offset, row_bytes) catch return error.InvalidPixelLayout;
    return row_bytes;
}

test "streaming locks discard their region and preserve outside pixels" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    var texture = try Texture.init(drawing, .{
        .size = .{ .width = 3, .height = 2 },
        .access = .streaming,
    });
    defer texture.deinit();
    const view = texture.borrow();
    const blue = [_]u8{
        0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255,
        0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255,
    };
    try view.update_rgba(null, &blue);
    {
        var guard = try view.lock_rgba(.{ .x = 1, .width = 1, .height = 2 });
        defer guard.deinit();
        try std.testing.expectEqual(@as(usize, 4), guard.row_bytes);
        try std.testing.expect(guard.pitch >= guard.row_bytes);
        try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, try guard.row(0));
        try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, try guard.row(1));
        @memcpy(try guard.row(0), &[_]u8{ 255, 0, 0, 255 });
        @memcpy(try guard.row(1), &[_]u8{ 0, 255, 0, 255 });
        try std.testing.expectError(error.OutOfBounds, guard.row(2));
    }
    try std.testing.expectError(error.InvalidSize, view.lock_rgba(.{
        .x = 3,
        .width = 0,
        .height = 1,
    }));
    try std.testing.expectError(error.OutOfBounds, view.lock_rgba(.{
        .x = 2,
        .width = 2,
        .height = 1,
    }));
    try view.set_blend_mode(.none);
    try drawing.draw_texture(view, null);
    try drawing.flush();
    for (0..2) |y| {
        for (0..3) |x| {
            const expected: Color = if (x != 1)
                .{ .r = 0, .g = 0, .b = 255 }
            else if (y == 0)
                .{ .r = 255, .g = 0, .b = 0 }
            else
                .{ .r = 0, .g = 255, .b = 0 };
            try std.testing.expectEqualDeep(
                expected,
                try surface.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) }),
            );
        }
    }
    try std.testing.expectError(error.InvalidPixels, abandon_texture_edit(view));
    try drawing.draw_texture(view, null);
    try drawing.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
        try surface.borrow().read_pixel(.{ .x = 1, .y = 1 }),
    );
    // A new acquisition after the error path proves the earlier guard was released.
    var again = try view.lock_rgba(.{ .width = 1, .height = 1 });
    again.deinit();

    var static_texture = try Texture.init(drawing, .{ .size = .{ .width = 1, .height = 1 } });
    defer static_texture.deinit();
    try std.testing.expectError(error.SdlFailure, static_texture.borrow().lock_rgba(null));
    var rgb = try Texture.init(drawing, .{
        .size = .{ .width = 1, .height = 1 },
        .format = .rgb565,
        .access = .streaming,
    });
    defer rgb.deinit();
    try std.testing.expectError(error.UnsupportedFormat, rgb.borrow().lock_rgba(null));
}

fn abandon_texture_edit(texture: TextureRef) Error!void {
    var guard = try texture.lock_rgba(.{ .x = 1, .y = 1, .width = 1, .height = 1 });
    defer guard.deinit();
    return error.InvalidPixels;
}

test "locked texture layout rejects unusable strides" {
    try std.testing.expectEqual(@as(usize, 8), try validate_locked_layout(2, 3, 16));
    try std.testing.expectError(error.InvalidPixelLayout, validate_locked_layout(2, 3, 7));
    try std.testing.expectError(error.InvalidPixelLayout, validate_locked_layout(1, 1, -1));
    try std.testing.expectError(error.InvalidPixelLayout, validate_locked_layout(0, 1, 4));
    try std.testing.expectError(error.InvalidPixelLayout, validate_locked_layout(1, 0, 4));
    try std.testing.expectError(
        error.InvalidPixelLayout,
        validate_locked_layout(std.math.maxInt(u32), 1, std.math.maxInt(c_int)),
    );
}

test "render targets preserve presentation and reject feedback or foreign owners" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 4, .height = 4 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    var texture = try Texture.init(drawing, .{
        .size = .{ .width = 4, .height = 2 },
        .access = .target,
    });
    defer texture.deinit();
    var static_texture = try Texture.init(drawing, .{ .size = .{ .width = 1, .height = 1 } });
    defer static_texture.deinit();
    try std.testing.expect(drawing.target() == null);
    const main_presentation = Presentation{
        .size = .{ .width = 2, .height = 2 },
        .mode = .stretch,
    };
    try drawing.set_presentation(main_presentation);
    try drawing.set_target(texture.borrow());
    defer drawing.set_target(null) catch {};
    try std.testing.expect(drawing.target().?.handle == texture.handle);
    try std.testing.expectEqual(PresentationMode.disabled, (try drawing.presentation()).mode);
    const texture_presentation = Presentation{
        .size = .{ .width = 2, .height = 1 },
        .mode = .stretch,
    };
    try drawing.set_presentation(texture_presentation);
    try drawing.set_color(.{ .r = 255, .g = 0, .b = 0 });
    try drawing.clear();
    try std.testing.expectError(error.TargetInUse, drawing.draw_texture(texture.borrow(), null));
    try std.testing.expectError(error.TargetInUse, texture.borrow().update_rgba(null, &.{}));
    try std.testing.expectError(error.TargetInUse, texture.borrow().lock_rgba(null));
    try std.testing.expectError(error.SdlFailure, drawing.set_target(static_texture.borrow()));
    try std.testing.expect(drawing.target().?.handle == texture.handle);

    var other_surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer other_surface.deinit();
    var other_renderer = try Renderer.for_surface(other_surface.borrow());
    defer other_renderer.deinit();
    try std.testing.expectError(
        error.WrongRenderer,
        other_renderer.borrow().set_target(texture.borrow()),
    );
    try std.testing.expectError(
        error.WrongRenderer,
        other_renderer.borrow().draw_texture_region(texture.borrow(), null, null),
    );
    try std.testing.expect(other_renderer.borrow().target() == null);
    try drawing.set_target(null);
    try std.testing.expectEqualDeep(main_presentation, try drawing.presentation());
    try drawing.set_target(texture.borrow());
    try std.testing.expectEqualDeep(texture_presentation, try drawing.presentation());
    try drawing.set_target(null);
    try texture.borrow().set_blend_mode(.none);
    try drawing.draw_texture(texture.borrow(), null);
    try drawing.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 255, .g = 0, .b = 0 },
        try surface.borrow().read_pixel(.{ .x = 3, .y = 3 }),
    );
}

test "streaming source regions render through an offscreen target" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 4, .height = 2 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    var source = try Texture.init(drawing, .{
        .size = .{ .width = 3, .height = 1 },
        .access = .streaming,
    });
    defer source.deinit();
    {
        var guard = try source.borrow().lock_rgba(null);
        defer guard.deinit();
        @memcpy(try guard.row(0), &[_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255 });
    }
    try source.borrow().set_scale_mode(.nearest);
    try source.borrow().set_blend_mode(.none);
    var offscreen = try Texture.init(drawing, .{
        .size = .{ .width = 2, .height = 1 },
        .access = .target,
    });
    defer offscreen.deinit();
    try drawing.set_target(offscreen.borrow());
    defer drawing.set_target(null) catch {};
    try drawing.draw_texture_region(source.borrow(), .{ .x = 1, .width = 2, .height = 1 }, null);
    try drawing.set_target(null);
    try offscreen.borrow().set_scale_mode(.nearest);
    try offscreen.borrow().set_blend_mode(.none);
    try drawing.draw_texture(offscreen.borrow(), null);
    try std.testing.expectError(error.OutOfBounds, drawing.draw_texture_region(source.borrow(), .{
        .x = 2,
        .width = std.math.maxInt(u32),
        .height = 1,
    }, null));
    try drawing.draw_texture_region(source.borrow(), .{ .x = 3, .width = 0, .height = 1 }, null);
    try std.testing.expectError(error.InvalidRect, drawing.draw_texture_region(source.borrow(), null, .{
        .x = std.math.nan(f32),
        .y = 0,
        .width = 1,
        .height = 1,
    }));
    try drawing.flush();
    for (0..2) |y| {
        for (0..4) |x| {
            const expected: Color = if (x < 2)
                .{ .r = 0, .g = 255, .b = 0 }
            else
                .{ .r = 0, .g = 0, .b = 255 };
            try std.testing.expectEqualDeep(
                expected,
                try surface.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) }),
            );
        }
    }
}

fn validate_upload_rows(region: TextureRegion, bytes_per_pixel: u8, rows: PixelRows) Error!c_int {
    if (region.width == 0 or region.height == 0 or bytes_per_pixel == 0)
        return error.InvalidSize;
    if (rows.pitch == 0 or rows.pitch > std.math.maxInt(c_int)) return error.InvalidSize;
    const row_bytes = std.math.mul(usize, region.width, bytes_per_pixel) catch
        return error.InvalidSize;
    if (row_bytes > std.math.maxInt(c_int)) return error.InvalidSize;
    if (rows.pitch < row_bytes) return error.InvalidPixels;
    const offset = std.math.mul(usize, region.height - 1, rows.pitch) catch
        return error.InvalidSize;
    const required = std.math.add(usize, offset, row_bytes) catch return error.InvalidSize;
    if (rows.bytes.len < required) return error.InvalidPixels;
    return @intCast(rows.pitch);
}

test "padded uploads validate row extents and preserve non-RGBA encoding" {
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 1, .height = 2 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    var texture = try Texture.init(drawing, .{
        .size = .{ .width = 1, .height = 2 },
        .format = .rgb24,
    });
    defer texture.deinit();
    const source = texture.borrow();
    // RGB byte arrays are endian-independent; the final row has no padding in caller storage.
    const data = [_]u8{ 255, 0, 0, 77, 88, 0, 255, 0 };
    try source.update_pixels(null, .{ .bytes = &data, .pitch = 5 });
    try std.testing.expectError(error.InvalidPixels, source.update_pixels(null, .{
        .bytes = data[0..7],
        .pitch = 5,
    }));
    try std.testing.expectError(error.InvalidPixels, source.update_pixels(null, .{
        .bytes = &data,
        .pitch = 2,
    }));
    try std.testing.expectError(error.InvalidSize, source.update_pixels(null, .{
        .bytes = &data,
        .pitch = std.math.maxInt(usize),
    }));
    try source.update_pixels(.{ .x = 1, .width = 0, .height = 2 }, .{
        .bytes = &.{},
        .pitch = 0,
    });
    try drawing.draw_texture(source, null);
    try drawing.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 255, .g = 0, .b = 0 },
        try surface.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 255, .b = 0 },
        try surface.borrow().read_pixel(.{ .x = 0, .y = 1 }),
    );
    const shape = TextureRegion{ .width = 1, .height = 2 };
    try std.testing.expectEqual(@as(c_int, 5), try validate_upload_rows(shape, 3, .{
        .bytes = &data,
        .pitch = 5,
    }));
    try std.testing.expectError(error.InvalidSize, validate_upload_rows(.{
        .width = std.math.maxInt(u32),
        .height = std.math.maxInt(u32),
    }, 16, .{ .bytes = &data, .pitch = 16 }));
}

test "indexed textures retain shared palettes and reflect palette edits" {
    const pixels_module = @import("pixels.zig");
    var surface = try @import("surface.zig").Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer surface.deinit();
    var renderer = try Renderer.for_surface(surface.borrow());
    defer renderer.deinit();
    const drawing = renderer.borrow();
    var texture = try Texture.init(drawing, .{
        .size = .{ .width = 2, .height = 1 },
        .format = .index8,
    });
    defer texture.deinit();
    const source = texture.borrow();
    {
        var palette_owner = try pixels_module.Palette.init(2);
        defer palette_owner.deinit();
        try palette_owner.borrow().set_colors(0, &.{
            .{ .r = 255, .g = 0, .b = 0 }, .{ .r = 0, .g = 0, .b = 255 },
        });
        try source.set_palette(palette_owner.borrow());
        try std.testing.expect(source.palette().?.handle == palette_owner.handle);
    }
    try source.update_pixels(null, .{ .bytes = &.{ 0, 1 }, .pitch = 2 });
    try drawing.draw_texture(source, null);
    try drawing.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 255, .g = 0, .b = 0 },
        try surface.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 0, .b = 255 },
        try surface.borrow().read_pixel(.{ .x = 1, .y = 0 }),
    );
    try source.palette().?.set_colors(1, &.{.{ .r = 0, .g = 255, .b = 0 }});
    try drawing.draw_texture(source, null);
    try drawing.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 255, .b = 0 },
        try surface.borrow().read_pixel(.{ .x = 1, .y = 0 }),
    );
    var oversized = try pixels_module.Palette.init(257);
    defer oversized.deinit();
    const retained = source.palette().?.handle;
    try std.testing.expectError(error.SdlFailure, source.set_palette(oversized.borrow()));
    try std.testing.expect(source.palette().?.handle == retained);
    var shared = try Texture.init(drawing, .{
        .size = .{ .width = 2, .height = 1 },
        .format = .index8,
    });
    defer shared.deinit();
    try shared.borrow().set_palette(source.palette());
    try source.set_palette(null);
    try std.testing.expect(source.palette() == null);
    try std.testing.expect(shared.borrow().palette().?.handle == retained);
    try shared.borrow().update_pixels(null, .{ .bytes = &.{ 1, 0 }, .pitch = 2 });
    try drawing.draw_texture(shared.borrow(), null);
    try drawing.flush();
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 255, .b = 0 },
        try surface.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    var rgba = try Texture.init(drawing, .{ .size = .{ .width = 1, .height = 1 } });
    defer rgba.deinit();
    try std.testing.expectError(error.SdlFailure, rgba.borrow().set_palette(oversized.borrow()));
}
