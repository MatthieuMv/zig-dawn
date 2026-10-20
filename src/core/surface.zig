//! Owned CPU pixel buffers and borrowed views. No video subsystem is required.
//! Native storage may allocate; wrappers allocate no Zig storage. Synchronize shared access.
//! Any-thread contracts also require the owner to permit access: window-owned surfaces require
//! the main thread and expire on window resize/release/destruction. Follow the window contract.
const c = @import("sdl_abi");
const video = @import("video.zig");

/// Eight-bit RGBA color, shared with renderer drawing operations.
pub const Color = @import("render.zig").Color;

/// Floating-point RGBA shared with pixel metadata APIs; encoding follows each operation.
pub const FloatColor = @import("pixels.zig").FloatColor;

/// Per-channel source RGB multipliers for blits. A value of 255 leaves a channel unchanged.
/// This changes blit state, not stored pixels; alpha is controlled separately by opacity.
pub const Tint = struct {
    /// Red multiplier, normalized as r / 255; zero removes source red.
    r: u8 = 255,
    /// Green multiplier, normalized as g / 255; zero removes source green.
    g: u8 = 255,
    /// Blue multiplier, normalized as b / 255; zero removes source blue.
    b: u8 = 255,
};

/// Pixel coordinates measured from the top-left corner, with positive y downward.
pub const Point = struct {
    /// Horizontal pixel index; must be smaller than surface width.
    x: u32,
    /// Vertical pixel index; must be smaller than surface height.
    y: u32,
};

/// Source compositing mode for surface blits. Channel equations use normalized values in 0..1.
/// Unknown native values are retained for interop; SDL decides whether a mode is supported.
pub const BlendMode = enum(u32) {
    /// Replace destination RGBA with source RGBA, subject to native modulation/color-key rules.
    none = c.SDL_BLENDMODE_NONE,
    /// RGB = source RGB * source alpha + destination RGB * (1 - source alpha).
    /// Alpha = source alpha + destination alpha * (1 - source alpha).
    alpha = c.SDL_BLENDMODE_BLEND,
    /// Source RGB already contains alpha multiplication; add destination * (1 - source alpha).
    premultiplied_alpha = c.SDL_BLENDMODE_BLEND_PREMULTIPLIED,
    /// Add source RGB * source alpha to destination RGB; preserve destination alpha.
    add = c.SDL_BLENDMODE_ADD,
    /// Add premultiplied source RGB to destination RGB; preserve destination alpha.
    premultiplied_add = c.SDL_BLENDMODE_ADD_PREMULTIPLIED,
    /// Multiply source and destination RGB; preserve destination alpha.
    modulate = c.SDL_BLENDMODE_MOD,
    /// RGB = source RGB * destination RGB + destination RGB * (1 - source alpha).
    /// Preserve destination alpha.
    multiply = c.SDL_BLENDMODE_MUL,
    _,
};

/// Owns only an allocated snapshot of surface pointers, not references to those surfaces.
/// Keep the queried surface and its alternate associations alive and unchanged during use.
/// Removing alternates/destruction can invalidate entries even while this list still exists.
pub const Images = struct {
    /// Native pointer array; read-only, never free separately or edit entries.
    native: [*c][*c]c.SDL_Surface,
    /// Number of entries, including the queried surface at index zero. Read-only.
    count: usize,

    /// Borrow an entry without retaining it. OutOfBounds rejects an invalid index.
    /// Synchronize with list cleanup and all associated surface mutations/destruction.
    pub fn get(self: Images, index: usize) Error!SurfaceRef {
        if (index >= self.count) return error.OutOfBounds;
        const handle = self.native[index] orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Free only the pointer array. Any thread with exclusive list access; surfaces remain alive
    /// only through their own references. Invalidates this owner and outstanding list users.
    pub fn deinit(self: *Images) void {
        c.SDL_free(@ptrCast(self.native));
        self.* = undefined;
    }
};

/// Explicit destination encoding for an owned surface conversion; no implicit allocator argument.
pub const Conversion = struct {
    /// Destination pixel layout; native conversion support depends on source and destination.
    format: @import("pixels.zig").Format,
    /// Destination color encoding; this requests conversion, not just relabeling.
    colorspace: @import("pixels.zig").Colorspace,
    /// Optional indexed destination palette. Borrowed for the call; successful output may retain
    /// a shared native reference. Subsequent edits can affect all associated surfaces.
    palette: ?@import("pixels.zig").PaletteRef = null,
    /// Optional conversion color properties, borrowed through the call. Native property-specific
    /// contracts apply (e.g. SDR white point/HDR headroom); pointer values must remain valid.
    properties: ?@import("properties.zig").PropertiesRef = null,
};

/// Working RGB encoding for alpha multiplication, followed by conversion back to surface encoding.
pub const AlphaSpace = enum {
    /// Multiply in encoded sRGB; this is not linear-light compositing.
    srgb,
    /// Convert to linear sRGB for multiplication, then back to the surface colorspace.
    linear_srgb,
};

/// In-place reflection axes. Both axes produce a half turn, not a diagonal transpose.
pub const Flip = enum {
    /// Reverse columns within each row.
    horizontal,
    /// Reverse row order.
    vertical,
    /// Reverse both columns and rows.
    both,
};

/// Sampling policy for whole-surface scaled blits. Backend support remains native behavior.
pub const ScaleMode = enum {
    /// Select the nearest source pixel; useful for exact pixel replication.
    nearest,
    /// Interpolate neighboring source pixels; output can vary with native conversion/rounding.
    linear,
    /// Native pixel-art policy; the pinned SDL CPU surface blitter currently uses nearest sampling.
    pixel_art,
};

/// Pixel region fully contained within a surface. Zero extents are allowed at its edges.
/// Bounds are checked without overflowing coordinate-plus-extent arithmetic.
pub const Region = struct {
    /// Left pixel coordinate, at most the surface width.
    x: u32 = 0,
    /// Top pixel coordinate, at most the surface height.
    y: u32 = 0,
    /// Horizontal extent, at most width minus x.
    width: u32,
    /// Vertical extent, at most height minus y.
    height: u32,
};

/// Signed destination position for unscaled blits; negative positions are clipped safely.
pub const Position = struct {
    /// Horizontal destination offset in pixels.
    x: i32 = 0,
    /// Vertical destination offset in pixels.
    y: i32 = 0,
};

/// Signed rectangle for clipping/filling. Extents are nonnegative and may exceed surface bounds.
/// Intersection uses wide arithmetic, so every i32 position and u32 extent is accepted safely.
pub const ClipRect = struct {
    /// Left edge in pixels; negative coordinates are allowed.
    x: i32 = 0,
    /// Top edge in pixels; negative coordinates are allowed.
    y: i32 = 0,
    /// Horizontal extent; zero means empty.
    width: u32,
    /// Vertical extent; zero means empty.
    height: u32,
};

/// Unscaled crop/position selection. Source regions must fit; destination positions may be outside.
pub const BlitOptions = struct {
    /// Null selects the whole source; otherwise this region must be entirely in bounds.
    source: ?Region = null,
    /// Destination top-left; visible pixels are clipped to bounds and native clipping state.
    destination: Position = .{},
};

/// Scaling between contained pixel regions; zero-sized regions perform no work.
pub const ScaledBlitOptions = struct {
    /// Null selects the whole source; explicit regions must fit inside it.
    source: ?Region = null,
    /// Null selects the whole destination; explicit regions must fit inside it.
    destination: ?Region = null,
    /// Explicit sampling policy; there is no implicit filter selection.
    mode: ScaleMode,
};

/// Tiling rectangles are clipped to each surface; zero extents are successful no-ops.
pub const TiledBlitOptions = struct {
    /// Null selects the whole source; signed rectangles are intersected with source bounds.
    source: ?ClipRect = null,
    /// Null fills the destination; signed rectangles are intersected with bounds and native clip.
    destination: ?ClipRect = null,
};

/// Scaled tiling with explicit sampling. Rectangles use the same clipping/phase rules as tiling.
pub const ScaledTiledBlitOptions = struct {
    /// Null selects the whole source; signed regions are clipped to source bounds.
    source: ?ClipRect = null,
    /// Null selects the whole destination; signed regions are clipped to bounds/current clip.
    destination: ?ClipRect = null,
    /// Finite nonnegative scale. Zero or a rounded zero tile size produces no writes.
    scale: f32,
    /// Explicit native sampling algorithm.
    mode: ScaleMode,
};

/// Source border widths for nine-grid drawing; opposite borders must fit the selected source.
pub const GridBorders = struct {
    /// Width of the left source column, in pixels.
    left: u32 = 0,
    /// Width of the right source column, in pixels.
    right: u32 = 0,
    /// Height of the top source row, in pixels.
    top: u32 = 0,
    /// Height of the bottom source row, in pixels.
    bottom: u32 = 0,
};

/// Draw fixed/scaled corners with stretched edges and center into contained surface regions.
pub const NineGridOptions = struct {
    /// Null selects the whole source; otherwise the region must fit entirely inside it.
    source: ?Region = null,
    /// Null selects the whole destination; otherwise the region must fit entirely inside it.
    destination: ?Region = null,
    /// Border sizes measured in source pixels.
    borders: GridBorders,
    /// Finite nonnegative corner scale; zero has SDL's meaning of unscaled corners, like one.
    corner_scale: f32 = 1,
    /// Explicit sampling algorithm for stretched cells.
    mode: ScaleMode,
};

/// Checked surface access failures. Native diagnostics are available through sdl.errors.
pub const Error = @import("errors.zig").Error || error{
    /// Pixel coordinates or list indices are out of bounds; no native mutation was attempted.
    OutOfBounds,
    /// Nine-grid borders/scale do not fit, or an empty source band would be stretched.
    InvalidGrid,
    /// Scale is nonfinite/negative, or native tile/coordinate arithmetic would overflow.
    InvalidTileScale,
    /// Alternate-image graph exceeds the bounded validation work/stack limits.
    AlternateGraphTooLarge,
    /// Alternate-image attachment would create a reference cycle.
    AlternateCycle,
    /// Source and destination are the same surface; no blit was attempted.
    AliasedSurface,
    /// A selected region extends beyond its surface; destination pixels are unchanged.
    InvalidRegion,
    /// Storage is unsupported for the requested row access or RGB key mapping.
    UnsupportedPixelFormat,
    /// A write/clear color contains NaN or infinity; no native mutation was attempted.
    InvalidColor,
    /// Rotation angle is nonfinite or cannot fit native quarter-turn conversion.
    InvalidRotation,
    /// Rotation geometry exceeds the audited native fixed-point/row arithmetic bounds.
    RotationTooLarge,
    /// A native or wrapper pixel lock already exists; nested mutable row guards are rejected.
    AlreadyLocked,
    /// Pixel dimensions, pitch, storage, or addressable row span cannot form a valid RGBA view.
    InvalidPixelLayout,
};

/// Exclusive borrowed RGBA pixels. Do not copy; deinit once before surface destruction.
/// This guard is not a mutex. Exclude every other surface access until release, including renderer
/// uploads, encoders, blits, destruction, and native access. Row slices expire on deinit.
pub const RgbaLock = struct {
    /// Borrowed native handle; never unlock through another path while this guard is live.
    handle: *c.SDL_Surface,
    /// Pixel base acquired after locking. Internal view metadata; never modify or free it.
    pixels: [*]u8,
    /// Pixel width. Read-only view metadata.
    width: u32,
    /// Pixel height. Read-only view metadata.
    height: u32,
    /// Byte offset between rows, including padding. Read-only view metadata.
    pitch: usize,
    /// Pixel bytes exposed per row, always width * 4. Read-only view metadata.
    row_bytes: usize,

    /// Borrow one mutable row in R,G,B,A byte order; each pixel occupies four consecutive bytes.
    /// Padding is excluded. OutOfBounds leaves storage unchanged. No allocation or native call.
    /// Use only while this guard is live; slices may alias on repeated calls for the same row.
    /// Byte writes ignore clipping/blend state. Never retain a row after unlock.
    pub fn row(self: *const RgbaLock, y: u32) Error![]u8 {
        if (y >= self.height) return error.OutOfBounds;
        const offset = @as(usize, y) * self.pitch;
        return self.pixels[offset..][0..self.row_bytes];
    }

    /// Unlock once on the accessing thread and invalidate guard/slices. Owner must still be alive.
    /// Native unlock has no error result and can change internal state; this is not mutex release.
    pub fn deinit(self: *RgbaLock) void {
        c.SDL_UnlockSurface(self.handle);
        self.* = undefined;
    }
};

/// Owns a native surface and its managed pixels. Do not copy; release exactly once.
/// Loaded images may have any native pixel format, padding, palette, or color key.
pub const Surface = struct {
    /// Native interop handle. Do not destroy separately or mutate read-only native fields.
    handle: *c.SDL_Surface,

    /// Allocate zero-filled RGBA bytes in row-major order; dimensions are positive pixels.
    /// Any thread, without SDL initialization. SDL may allocate. `InvalidSize` rejects zero or
    /// dimensions exceeding signed C integers; `SdlFailure` returns no owner on native failure.
    /// Row padding is implementation-defined; do not assume tightly packed storage.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 16, .height = 8 });
    /// defer surface.deinit();
    /// const size = surface.borrow().size();
    /// try @import("std").testing.expectEqual(@as(u32, 16), size.width);
    /// ```
    pub fn init_rgba(size: video.Size) video.Error!Surface {
        return init_format(size, @import("pixels.zig").Format.rgba32);
    }

    /// Allocate zero-initialized native pixel storage in a requested typed format on any thread.
    /// No SDL initialization is needed. InvalidSize rejects zero/oversized dimensions before SDL;
    /// SdlFailure includes unsupported/unknown formats or allocation failure and returns no owner.
    /// Pitch, planes, and palette availability depend on the format; this does not guarantee every
    /// SurfaceRef operation supports it. Zero bits need not represent transparent black (e.g. YUV).
    /// No Zig allocation; defer deinit on success. SDL determines native format support.
    pub fn init_format(size: video.Size, format: @import("pixels.zig").Format) video.Error!Surface {
        try video.validate_size(size);
        const handle = c.SDL_CreateSurface(
            @intCast(size.width),
            @intCast(size.height),
            @backingInt(format),
        ) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Release on any thread with exclusive access, after all borrowed uses finish.
    /// Invalidates this owner and every view. No fallible result; call exactly once.
    pub fn deinit(self: *Surface) void {
        c.SDL_DestroySurface(self.handle);
        self.* = undefined;
    }

    /// Borrow without allocation or ownership transfer. The owner must outlive the view.
    pub fn borrow(self: *const Surface) SurfaceRef {
        return .{ .handle = self.handle };
    }
};

/// Copyable non-owning view. Synchronize all access; RGBA row guards borrow the owning surface.
pub const SurfaceRef = struct {
    /// Live native surface. Do not free through this view or change its dimensions directly.
    handle: *c.SDL_Surface,

    /// Copy the current format identity without allocation/native calls; unknown values survive.
    /// Requires a live surface. Window-owned surfaces require main-thread use and reacquisition
    /// after resize. This does not imply palette availability, colorspace, or backend support.
    pub fn format(self: SurfaceRef) @import("pixels.zig").Format {
        return @fromBackingInt(self.handle.format);
    }

    /// Query whether direct alternate images exist. No allocation or retention; synchronize with
    /// graph changes and follow the surface owner's thread rules (main for windows).
    pub fn has_alternates(self: SurfaceRef) bool {
        return c.SDL_SurfaceHasAlternateImages(self.handle);
    }

    /// Allocate a pointer-list snapshot containing this surface first, then direct alternates.
    /// Defer list.deinit; entries are borrowed and not retained. Finish entry use before removing
    /// alternates or destroying associated surfaces. SdlFailure returns no list. Native allocation;
    /// owner thread rules and exclusive access apply (main thread for window surfaces).
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var base = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer base.deinit();
    /// var list = try base.borrow().images();
    /// defer list.deinit();
    /// try @import("std").testing.expectEqual(@as(usize, 1), list.count);
    /// const first = try list.get(0);
    /// try @import("std").testing.expectEqual(@as(u32, 1), first.size().width);
    /// ```
    pub fn images(self: SurfaceRef) Error!Images {
        var count: c_int = 0;
        const native = c.SDL_GetSurfaceImages(self.handle, &count) orelse return error.SdlFailure;
        if (count < 1) {
            c.SDL_free(@ptrCast(native));
            return error.SdlFailure;
        }
        return .{ .native = native, .count = @intCast(count) };
    }

    /// Retain an owned surface as an alternate representation; its original owner may then deinit.
    /// Different size/format/content and duplicate attachments are permitted. Later pixel edits
    /// are shared, not propagated between representations. Does not consume the supplied owner.
    /// Validates against reference cycles before attachment: AlternateCycle rejects a path back
    /// to this surface; AlternateGraphTooLarge bounds pending nodes at 256 and visits at 4096.
    /// Validation allocates native lists; SdlFailure reports enumeration/append failure.
    /// No attachment occurs on failure. Requires exclusive access to the entire reachable graph
    /// on every owner's permitted thread (main for windows). Do not mutate graph via raw callbacks.
    pub fn add_alternate(self: SurfaceRef, image: *const Surface) Error!void {
        var pending: [256]SurfaceRef = undefined;
        pending[0] = image.borrow();
        var count: usize = 1;
        var visits: usize = 0;
        while (count != 0) {
            if (visits == 4096) return error.AlternateGraphTooLarge;
            visits += 1;
            count -= 1;
            const current = pending[count];
            if (current.handle == self.handle) return error.AlternateCycle;
            if (!current.has_alternates()) continue;
            var children = try current.images();
            defer children.deinit();
            if (children.count - 1 > pending.len - count) return error.AlternateGraphTooLarge;
            for (1..children.count) |index| {
                pending[count] = try children.get(index);
                count += 1;
            }
        }
        if (!c.SDL_AddSurfaceAlternateImage(self.handle, image.handle)) return error.SdlFailure;
    }

    /// Release all direct alternate references; native storage is destroyed when its last reference
    /// goes away. Invalidates association-borrowed entries. No error result; requires exclusive
    /// graph access on owner-permitted threads. The base surface and its pixels remain unchanged.
    pub fn remove_alternates(self: SurfaceRef) void {
        c.SDL_RemoveSurfaceAlternateImages(self.handle);
    }

    /// Copy native color encoding without allocation. Unknown/custom numeric identities survive.
    /// Requires a live view and synchronized access; owner thread rules apply (main for windows).
    pub fn colorspace(self: SurfaceRef) @import("pixels.zig").Colorspace {
        return @fromBackingInt(c.SDL_GetSurfaceColorspace(self.handle));
    }

    /// Relabel existing pixel values without converting them. Use converted for actual conversion.
    /// Unknown/custom values are passed to SDL; success does not validate format compatibility.
    /// No wrapper allocation or ownership transfer; SdlFailure reports native rejection.
    /// Requires exclusive access on an owner-permitted thread (main for window surfaces).
    pub fn set_colorspace(self: SurfaceRef, encoding: @import("pixels.zig").Colorspace) Error!void {
        if (!c.SDL_SetSurfaceColorspace(self.handle, @backingInt(encoding)))
            return error.SdlFailure;
    }

    /// Convert pixel layout and color encoding into a new owner; defer deinit on success.
    /// Source pixels stay unchanged; palette/alternate images may share native references and
    /// copied pointer properties keep their original external lifetime requirements. No deep graph
    /// copy is promised. Source/options must remain live and exclusively accessed during the call.
    /// Requires unlocked source (AlreadyLocked otherwise). Native conversion/storage can allocate;
    /// SdlFailure returns no owner. Color/alpha precision and format support follow SDL.
    /// Follow owner thread rules, including main-thread use for window-owned source surfaces.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer source.deinit();
    /// var linear = try source.borrow().converted(.{
    ///     .format = .rgba128_float, .colorspace = .srgb_linear,
    /// });
    /// defer linear.deinit();
    /// try @import("std").testing.expectEqual(sdl.pixels.Colorspace.srgb_linear,
    ///     linear.borrow().colorspace());
    /// ```
    pub fn converted(self: SurfaceRef, options: Conversion) Error!Surface {
        if (self.handle.flags & c.SDL_SURFACE_LOCKED != 0) return error.AlreadyLocked;
        const handle = c.SDL_ConvertSurfaceAndColorspace(
            self.handle,
            @backingInt(options.format),
            if (options.palette) |value| value.handle else null,
            @backingInt(options.colorspace),
            if (options.properties) |value| value.handle else 0,
        ) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Create/replace this indexed surface's native palette and borrow it; never destroy this view.
    /// Native allocation can fail with SdlFailure; non-indexed formats are rejected. The surface
    /// owns the reference; the view expires on palette replacement/removal or surface destruction.
    /// One-bit formats initialize white/black; other indexed formats initialize opaque white.
    /// Exclusive surface access required, on any owner-permitted thread (main for window surfaces).
    pub fn create_palette(self: SurfaceRef) Error!@import("pixels.zig").PaletteRef {
        const handle = c.SDL_CreateSurfacePalette(self.handle) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Associate a shared palette, or null to remove it, with exclusive surface/palette access.
    /// Success retains a native reference; the caller may then release its Palette owner.
    /// Shared edits affect every associated surface. SdlFailure includes incompatible format/count.
    /// Prior surface-borrowed views expire on replacement. No wrapper allocation; native map state
    /// changes. Follow owner thread restrictions, including main-thread use for window surfaces.
    pub fn set_palette(
        self: SurfaceRef,
        palette_value: ?@import("pixels.zig").PaletteRef,
    ) Error!void {
        const handle = if (palette_value) |value| value.handle else null;
        if (!c.SDL_SetSurfacePalette(self.handle, handle)) return error.SdlFailure;
    }

    /// Borrow the associated palette, or null when absent. No native reference is retained.
    /// View expires on replacement/removal or surface destruction; never destroy it separately.
    /// Synchronize with all palette sharers; follow owner thread rules (main for windows).
    pub fn palette(self: SurfaceRef) ?@import("pixels.zig").PaletteRef {
        const handle = c.SDL_GetSurfacePalette(self.handle) orelse return null;
        return .{ .handle = handle };
    }

    /// Borrow this object's native property group. Any thread while the surface remains alive.
    /// May allocate/block; `SdlFailure` returns no view. The object owns the group: never destroy
    /// it separately. Finish all views/locks before object destruction. Use application-specific
    /// keys for custom data; native keys retain their individual read/write and lifetime contracts.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn properties(
        self: SurfaceRef,
    ) @import("errors.zig").Error!@import("properties.zig").PropertiesRef {
        const handle = c.SDL_GetSurfaceProperties(self.handle);
        if (handle == 0) return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Lock positive-sized RGBA32 storage and borrow mutable rows until guard.deinit().
    /// Convert other formats with to_rgba first; no implicit conversion or ownership transfer.
    /// Rows expose existing storage; locking does not initialize pixel bytes.
    /// Any thread with exclusive access, which must continue until unlock. This is not a mutex.
    /// Native lock can allocate/decompress pixels; no Zig allocation. AlreadyLocked rejects nested
    /// guards. UnsupportedPixelFormat rejects non-RGBA32 storage. InvalidPixelLayout rejects empty
    /// dimensions, missing pixels, insufficient pitch, or overflowing row spans. Failure after
    /// native locking unlocks automatically and returns no guard. Owner must outlive the guard.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer surface.deinit();
    /// {
    ///     var pixels = try surface.borrow().lock_rgba();
    ///     defer pixels.deinit();
    ///     const row = try pixels.row(0);
    ///     @memcpy(row[4..8], &[_]u8{ 10, 20, 30, 40 });
    /// }
    /// const color = try surface.borrow().read_pixel(.{ .x = 1, .y = 0 });
    /// try @import("std").testing.expectEqual(@as(u8, 40), color.a);
    /// ```
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn lock_rgba(self: SurfaceRef) Error!RgbaLock {
        const std = @import("std");
        if (self.handle.format != c.SDL_PIXELFORMAT_RGBA32) return error.UnsupportedPixelFormat;
        if (self.handle.flags & c.SDL_SURFACE_LOCKED != 0) return error.AlreadyLocked;
        if (!c.SDL_LockSurface(self.handle)) return error.SdlFailure;
        errdefer c.SDL_UnlockSurface(self.handle);
        if (self.handle.w <= 0 or self.handle.h <= 0 or self.handle.pitch <= 0)
            return error.InvalidPixelLayout;
        const width: usize = @intCast(self.handle.w);
        const height: usize = @intCast(self.handle.h);
        const pitch: usize = @intCast(self.handle.pitch);
        const row_bytes = std.math.mul(usize, width, 4) catch return error.InvalidPixelLayout;
        if (pitch < row_bytes) return error.InvalidPixelLayout;
        const offset = std.math.mul(usize, height - 1, pitch) catch return error.InvalidPixelLayout;
        _ = std.math.add(usize, offset, row_bytes) catch return error.InvalidPixelLayout;
        const pixels = self.handle.pixels orelse return error.InvalidPixelLayout;
        return .{
            .handle = self.handle,
            .pixels = @ptrCast(pixels),
            .width = @intCast(width),
            .height = @intCast(height),
            .pitch = pitch,
            .row_bytes = row_bytes,
        };
    }

    /// Read one pixel as eight-bit RGBA, accounting for native format/padding. Any thread,
    /// exclusive access. OutOfBounds rejects invalid coordinates before native access. Native work
    /// can lock/allocate and may return SdlFailure for unsupported data. Intended for inspection,
    /// not hot pixel loops. Reduced-bit colors expand to 0..255; precision may be lost for HDR.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn read_pixel(self: SurfaceRef, point: Point) Error!Color {
        try self.validate_point(point);
        var color: Color = undefined;
        if (!c.SDL_ReadSurfacePixel(
            self.handle,
            @intCast(point.x),
            @intCast(point.y),
            &color.r,
            &color.g,
            &color.b,
            &color.a,
        )) return error.SdlFailure;
        return color;
    }

    /// Copy one pixel as floating RGBA. OutOfBounds is checked before SDL. Exclusive access
    /// required because native locking/conversion may allocate or modify caches. SdlFailure
    /// returns no color. This is a diagnostic/convenience operation, not a bulk pixel loop.
    /// Native conversion can change encoding/precision: small integer formats use eight-bit
    /// intermediates, YUV may convert the whole surface, and RGBA128_FLOAT reads preserve values.
    /// Output need not be finite or linear-light. Owner rules apply (main thread for windows).
    pub fn read_pixel_float(self: SurfaceRef, point: Point) Error!FloatColor {
        try self.validate_point(point);
        var color: FloatColor = undefined;
        if (!c.SDL_ReadSurfacePixelFloat(
            self.handle,
            @intCast(point.x),
            @intCast(point.y),
            &color.r,
            &color.g,
            &color.b,
            &color.a,
        )) return error.SdlFailure;
        return color;
    }

    /// Replace a pixel without blending/clipping. OutOfBounds/InvalidColor reject before mutation.
    /// Finite HDR/negative values are passed unchanged; native destination conversion may clamp,
    /// quantize, or discard alpha. FourCC writes are unsupported by pinned SDL. Native work may
    /// allocate/lock or return SdlFailure. Requires exclusive access on an owner-permitted thread
    /// (main for windows). Encoding follows SDL conversion, not an implicit linear-light promise.
    pub fn write_pixel_float(self: SurfaceRef, point: Point, color: FloatColor) Error!void {
        try self.validate_point(point);
        try validate_float_color(color);
        if (!c.SDL_WriteSurfacePixelFloat(
            self.handle,
            @intCast(point.x),
            @intCast(point.y),
            color.r,
            color.g,
            color.b,
            color.a,
        )) return error.SdlFailure;
    }

    /// Replace the entire surface with floating RGBA, ignoring clipping and restoring its clip.
    /// InvalidColor rejects nonfinite components before mutation; finite values are passed through.
    /// RGB encoding is the surface colorspace, except YUV input is interpreted as sRGB. Native
    /// quantization/clamping applies; small integer formats use eight-bit intermediates. Unlike
    /// fill, this can clear wide floating-point/YUV formats, subject to native support.
    /// Requires exclusive unlocked access (AlreadyLocked otherwise), on an owner-permitted thread
    /// (main for windows). Native work may fail with SdlFailure and partial writes;
    /// no wrapper allocation. This changes pixels, not blend/modulation state.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_format(
    ///     .{ .width = 2, .height = 2 }, .rgba128_float,
    /// );
    /// defer surface.deinit();
    /// try surface.borrow().clear(.{ .r = 2, .g = 0.5, .b = 0 });
    /// const color = try surface.borrow().read_pixel_float(.{ .x = 0, .y = 0 });
    /// try @import("std").testing.expectEqual(@as(f32, 2), color.r);
    /// ```
    pub fn clear(self: SurfaceRef, color: FloatColor) Error!void {
        try validate_float_color(color);
        if (self.handle.flags & c.SDL_SURFACE_LOCKED != 0) return error.AlreadyLocked;
        if (!c.SDL_ClearSurface(self.handle, color.r, color.g, color.b, color.a))
            return error.SdlFailure;
    }

    /// Replace one pixel with eight-bit RGBA, without blending or clipping. Exclusive access.
    /// OutOfBounds leaves the surface unchanged. Native conversion/locking may allocate or fail;
    /// colors may be quantized and alpha discarded by the destination format. Not a bulk-pixel API.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer surface.deinit();
    /// const color = sdl.surface.Color{ .r = 20, .g = 40, .b = 60, .a = 80 };
    /// try surface.borrow().write_pixel(.{ .x = 1, .y = 0 }, color);
    /// const pixel = try surface.borrow().read_pixel(.{ .x = 1, .y = 0 });
    /// try @import("std").testing.expectEqualDeep(color, pixel);
    /// ```
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn write_pixel(self: SurfaceRef, point: Point, color: Color) Error!void {
        try self.validate_point(point);
        if (!c.SDL_WriteSurfacePixel(
            self.handle,
            @intCast(point.x),
            @intCast(point.y),
            color.r,
            color.g,
            color.b,
            color.a,
        )) return error.SdlFailure;
    }

    /// Fill the entire surface within its current native clip rectangle. No alpha blending occurs.
    /// Any thread with exclusive access; native work may allocate/block. SDL maps RGBA to the
    /// closest native color; palette/low-depth formats can quantize or discard alpha. Unsupported
    /// formats return SdlFailure. Use to_rgba for predictable eight-bit RGBA storage first.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn fill(self: SurfaceRef, color: Color) Error!void {
        const pixel = c.SDL_MapSurfaceRGBA(self.handle, color.r, color.g, color.b, color.a);
        if (!c.SDL_FillSurfaceRect(self.handle, null, pixel)) return error.SdlFailure;
    }

    /// Query the effective destination clip as a contained region. Empty clips return all zeros.
    /// Any thread with exclusive access; no wrapper allocation or pixel mutation. Native query
    /// failure returns SdlFailure. The initial/reset clip covers the whole surface.
    /// This state affects fills/blits, but direct write_pixel deliberately ignores it.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn clip(self: SurfaceRef) Error!Region {
        var rect: c.SDL_Rect = undefined;
        if (!c.SDL_GetSurfaceClipRect(self.handle, &rect)) return error.SdlFailure;
        if (rect.w <= 0 or rect.h <= 0) return .{ .width = 0, .height = 0 };
        return .{
            .x = @intCast(rect.x),
            .y = @intCast(rect.y),
            .width = @intCast(rect.w),
            .height = @intCast(rect.h),
        };
    }

    /// Set destination clipping and return the effective contained region. Null resets to the
    /// whole surface. Offscreen/zero-area rectangles succeed with an empty region and disable
    /// fill/blit writes; they are not native failures. Every i32/u32 geometry value is supported.
    /// Any thread, exclusive access. Replaces prior clip state without changing pixels, allocating
    /// wrapper storage, or retaining the rectangle. SdlFailure reports a failed native query.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 4, .height = 3 });
    /// defer surface.deinit();
    /// const clip = try surface.borrow().set_clip(.{ .x = -1, .width = 3, .height = 2 });
    /// try @import("std").testing.expectEqual(@as(u32, 2), clip.width);
    /// const empty = try surface.borrow().set_clip(.{ .x = 9, .width = 1, .height = 1 });
    /// try @import("std").testing.expectEqual(@as(u32, 0), empty.width);
    /// _ = try surface.borrow().set_clip(null);
    /// ```
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn set_clip(self: SurfaceRef, rect: ?ClipRect) Error!Region {
        if (rect) |requested| {
            const bounded = self.intersect_rect(requested);
            // Native false means empty intersection, not failure; the getter validates the query.
            _ = c.SDL_SetSurfaceClipRect(self.handle, &bounded);
        } else {
            _ = c.SDL_SetSurfaceClipRect(self.handle, null);
        }
        return self.clip();
    }

    /// Fill a signed rectangle intersected with surface bounds and the current clip, without
    /// blending or changing clip state. Empty/offscreen input is a successful no-op. Any thread,
    /// exclusive access. Uses the same native color approximation/format limits as fill; native
    /// work may block/allocate or return SdlFailure. No pointer or ownership is retained.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn fill_rect(self: SurfaceRef, rect: ClipRect, color: Color) Error!void {
        const bounded = self.intersect_rect(rect);
        if (bounded.w == 0 or bounded.h == 0) return;
        const pixel = c.SDL_MapSurfaceRGBA(self.handle, color.r, color.g, color.b, color.a);
        if (!c.SDL_FillSurfaceRect(self.handle, &bounded, pixel)) return error.SdlFailure;
    }

    fn intersect_rect(self: SurfaceRef, rect: ClipRect) c.SDL_Rect {
        const dimensions = self.size();
        const left: i64 = @max(0, @as(i64, rect.x));
        const top: i64 = @max(0, @as(i64, rect.y));
        const right = @min(@as(i64, dimensions.width), @as(i64, rect.x) + rect.width);
        const bottom = @min(@as(i64, dimensions.height), @as(i64, rect.y) + rect.height);
        if (right <= left or bottom <= top) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        return .{
            .x = @intCast(left),
            .y = @intCast(top),
            .w = @intCast(right - left),
            .h = @intCast(bottom - top),
        };
    }

    /// Request native run-length acceleration for later blits; this is a hint, not a speed promise.
    /// Pixel contents are unchanged. Native maps/storage may allocate or decompress lazily.
    /// SdlFailure reports rejection (including FourCC surfaces). Exclusive unlocked surface access
    /// required, on an owner-permitted thread; window surfaces require the main thread.
    /// Direct pixel access must use a lock even when native storage currently looks uncompressed.
    pub fn set_rle(self: SurfaceRef, enabled: bool) Error!void {
        if (!c.SDL_SetSurfaceRLE(self.handle, enabled)) return error.SdlFailure;
    }

    /// Query the requested acceleration hint, not whether pixels are currently compressed.
    /// No allocation. Synchronize access; owner thread/lifetime rules apply (main for windows).
    pub fn rle(self: SurfaceRef) bool {
        return c.SDL_SurfaceHasRLE(self.handle);
    }

    /// Set the transparent source pixel for later blits; null disables keying. This exact encoded
    /// value is specific to the current format/palette (an index for indexed surfaces), not RGBA.
    /// Pixels are unchanged. Native blitters determine alpha/blend interactions. Invalid palette
    /// indices return SdlFailure without changing the key. No wrapper allocation; native map state
    /// may change. Requires exclusive unlocked access on an owner-permitted thread
    /// (main for window surfaces).
    pub fn set_color_key_pixel(self: SurfaceRef, pixel: ?u32) Error!void {
        if (!c.SDL_SetSurfaceColorKey(self.handle, pixel != null, pixel orelse 0))
            return error.SdlFailure;
    }

    /// Map an RGB color to this surface's native transparent pixel; null disables keying.
    /// Alpha is ignored. Quantization/nearest palette matching can map distinct colors to one key;
    /// use set_color_key_pixel for an exact index/value. UnsupportedPixelFormat rejects FourCC,
    /// float, wider-than-32-bit storage, or indexed storage without a palette.
    /// No owner transfer; native failures/thread rules match the exact
    /// setter. Changing a palette later changes the displayed color of an indexed key.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 2 });
    /// defer surface.deinit();
    /// try surface.borrow().set_color_key(.{ .r = 255, .g = 0, .b = 255 });
    /// try @import("std").testing.expect((try surface.borrow().color_key_pixel()) != null);
    /// try surface.borrow().set_color_key(null);
    /// ```
    pub fn set_color_key(self: SurfaceRef, color: ?Color) Error!void {
        const value = color orelse return self.set_color_key_pixel(null);
        const identity = self.format();
        if (identity.is_fourcc() or identity.is_float() or
            identity.storage_bytes_per_pixel() > 4 or
            (identity.is_indexed() and self.palette() == null))
            return error.UnsupportedPixelFormat;
        const pixel = c.SDL_MapSurfaceRGB(self.handle, value.r, value.g, value.b);
        try self.set_color_key_pixel(pixel);
    }

    /// Copy the exact encoded key, or null when disabled, without treating absence as an SDL error.
    /// No allocation; SdlFailure reports a failed enabled-key query. Synchronize access across the
    /// presence/query pair. Owner lifetime/thread rules apply, including main-thread window access.
    pub fn color_key_pixel(self: SurfaceRef) Error!?u32 {
        if (!c.SDL_SurfaceHasColorKey(self.handle)) return null;
        var pixel: u32 = 0;
        if (!c.SDL_GetSurfaceColorKey(self.handle, &pixel)) return error.SdlFailure;
        return pixel;
    }

    /// Multiply RGB by alpha in place using an explicit working colorspace. Alpha is preserved;
    /// native format conversion can quantize/clamp. Repeated calls multiply again: not idempotent.
    /// This does not change blend mode, opacity, or tint. Select premultiplied_alpha separately
    /// when using the result with a matching compositor. Clipping does not restrict the operation.
    /// Native conversion/storage may allocate or return SdlFailure after partial writes.
    /// Requires exclusive unlocked access; AlreadyLocked rejects an existing guard. Internally
    /// locks/unlocks storage for RLE. Follow owner thread rules (main thread for window surfaces).
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer source.deinit();
    /// try source.borrow().fill(.{ .r = 255, .g = 0, .b = 0, .a = 128 });
    /// try source.borrow().premultiply_alpha(.srgb);
    /// try source.borrow().set_blend_mode(.premultiplied_alpha);
    /// ```
    pub fn premultiply_alpha(self: SurfaceRef, space: AlphaSpace) Error!void {
        if (self.handle.flags & c.SDL_SURFACE_LOCKED != 0) return error.AlreadyLocked;
        if (!c.SDL_LockSurface(self.handle)) return error.SdlFailure;
        defer c.SDL_UnlockSurface(self.handle);
        if (!c.SDL_PremultiplySurfaceAlpha(self.handle, space == .linear_srgb))
            return error.SdlFailure;
    }

    /// Reflect pixels in place, ignoring clip/modulation/blend state. Exclusive unlocked access
    /// required; AlreadyLocked rejects an existing lock. Internally locks/unlocks native storage
    /// so RLE pixels remain accessible. UnsupportedPixelFormat rejects FourCC plane layouts.
    /// Native allocation/format failures return SdlFailure; combined-axis failure can leave a
    /// partial reflection. Owner lifetime/thread rules apply (main thread for window surfaces).
    pub fn flip(self: SurfaceRef, axes: Flip) Error!void {
        if (self.format().is_fourcc()) return error.UnsupportedPixelFormat;
        if (self.handle.flags & c.SDL_SURFACE_LOCKED != 0) return error.AlreadyLocked;
        if (!c.SDL_LockSurface(self.handle)) return error.SdlFailure;
        defer c.SDL_UnlockSurface(self.handle);
        const native: c.SDL_FlipMode = switch (axes) {
            .horizontal => c.SDL_FLIP_HORIZONTAL,
            .vertical => c.SDL_FLIP_VERTICAL,
            .both => c.SDL_FLIP_HORIZONTAL_AND_VERTICAL,
        };
        if (!c.SDL_FlipSurface(self.handle, native)) return error.SdlFailure;
    }

    /// Allocate an independently owned scaled pixel buffer; defer deinit on success.
    /// InvalidSize rejects zero/unrepresentable dimensions before SDL. Native allocation/format
    /// failure returns SdlFailure with no owner. Indexed formats use nearest sampling even when
    /// linear is requested; other conversion/rounding follows SDL. Palettes may remain shared.
    /// Source modulation is temporarily bypassed and restored by SDL; pixels stay unchanged.
    /// Requires exclusive unlocked source access (AlreadyLocked otherwise), on an owner-permitted
    /// thread. Window surfaces require the main thread. No Zig allocation or source owner transfer.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer source.deinit();
    /// var large = try source.borrow().scaled(.{ .width = 4, .height = 2 }, .nearest);
    /// defer large.deinit();
    /// try large.borrow().flip(.horizontal);
    /// ```
    pub fn scaled(
        self: SurfaceRef,
        dimensions: video.Size,
        mode: ScaleMode,
    ) (Error || video.Error)!Surface {
        try video.validate_size(dimensions);
        if (self.handle.flags & c.SDL_SURFACE_LOCKED != 0) return error.AlreadyLocked;
        const native: c.SDL_ScaleMode = switch (mode) {
            .nearest => c.SDL_SCALEMODE_NEAREST,
            .linear => c.SDL_SCALEMODE_LINEAR,
            .pixel_art => c.SDL_SCALEMODE_PIXELART,
        };
        const handle = c.SDL_ScaleSurface(
            self.handle,
            @intCast(dimensions.width),
            @intCast(dimensions.height),
            native,
        ) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Allocate a clockwise rotated copy; negative degrees rotate counter-clockwise. Defer deinit.
    /// Source pixels stay unchanged. Requires exclusive unlocked access; otherwise AlreadyLocked.
    /// InvalidRotation rejects nonfinite angles or degrees/90 outside signed native int bounds.
    /// RotationTooLarge rejects width+height above 8192, nonpositive dimensions/pitch, or a source
    /// byte span above signed native int. These conservative bounds protect SDL's fixed-point and
    /// row arithmetic; larger geometry remains available only through raw interop after auditing.
    /// Native allocation/conversion failures return SdlFailure with no owner. Non-right-angle
    /// output may expand with native interpolation/padding. Key, blend, palette, rotation-property
    /// behavior follows SDL and is not a deep metadata copy. No wrapper allocation or angle
    /// normalization. Follow owner thread rules, including main-thread use for window surfaces.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer source.deinit();
    /// var rotated = try source.borrow().rotated(90);
    /// defer rotated.deinit();
    /// try @import("std").testing.expectEqual(@as(u32, 2), rotated.borrow().size().height);
    /// ```
    pub fn rotated(self: SurfaceRef, degrees: f32) Error!Surface {
        try validate_rotation(degrees, self.handle.w, self.handle.h, self.handle.pitch);
        if (self.handle.flags & c.SDL_SURFACE_LOCKED != 0) return error.AlreadyLocked;
        const handle = c.SDL_RotateSurface(self.handle, degrees) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Multiply source RGB by tint/255 during later blits. Passing .{} restores identity tint.
    /// Any thread with exclusive surface access. Does not edit pixels or change opacity/blend mode.
    /// Native blit state may change; SdlFailure reports native rejection. No wrapper allocation.
    /// Quantization follows the native blitter; this is not color-profile correction.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer source.deinit();
    /// try source.borrow().set_tint(.{ .r = 128, .b = 0 });
    /// try source.borrow().set_opacity(64);
    /// try @import("std").testing.expectEqual(@as(u8, 128), (try source.borrow().tint()).r);
    /// try @import("std").testing.expectEqual(@as(u8, 64), try source.borrow().opacity());
    /// ```
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn set_tint(self: SurfaceRef, tint_value: Tint) Error!void {
        if (!c.SDL_SetSurfaceColorMod(self.handle, tint_value.r, tint_value.g, tint_value.b))
            return error.SdlFailure;
    }

    /// Query RGB blit multipliers, not pixel color. Any thread with exclusive surface access.
    /// Does not allocate wrapper storage or change state. Native query failure returns SdlFailure.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn tint(self: SurfaceRef) Error!Tint {
        var value: Tint = undefined;
        if (!c.SDL_GetSurfaceColorMod(self.handle, &value.r, &value.g, &value.b))
            return error.SdlFailure;
        return value;
    }

    /// Multiply source alpha by value/255 during blits; 255 preserves it and zero removes it.
    /// Any thread with exclusive access. Does not edit pixels, change tint, or enable blending:
    /// use set_blend_mode(.alpha) for straight-alpha composition. With .none this can write reduced
    /// alpha instead of making the destination visually unchanged. Native formats/blend modes
    /// determine the result. No wrapper allocation; native rejection returns SdlFailure.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn set_opacity(self: SurfaceRef, value: u8) Error!void {
        if (!c.SDL_SetSurfaceAlphaMod(self.handle, value)) return error.SdlFailure;
    }

    /// Query the blit alpha multiplier, not a pixel's alpha. Any thread, exclusive surface access.
    /// Does not allocate wrapper storage or change state. Native query failure returns SdlFailure.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn opacity(self: SurfaceRef) Error!u8 {
        var value: u8 = undefined;
        if (!c.SDL_GetSurfaceAlphaMod(self.handle, &value)) return error.SdlFailure;
        return value;
    }

    /// Set this surface's source blend mode for future blits; does not modify its pixel bytes.
    /// Any thread with exclusive access. Native state/caches may change or allocate. Unsupported
    /// modes return SdlFailure. Set none for replacement, alpha for straight-alpha composition;
    /// premultiplied modes require already-premultiplied pixels. Color/alpha modulation and color
    /// keys remain separate native state and are not reset by this call.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn set_blend_mode(self: SurfaceRef, mode: BlendMode) Error!void {
        if (!c.SDL_SetSurfaceBlendMode(self.handle, @backingInt(mode))) return error.SdlFailure;
    }

    /// Query source blend state, preserving unknown native values. No ownership transfer.
    /// Any thread with synchronized access; native failure returns SdlFailure.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn blend_mode(self: SurfaceRef) Error!BlendMode {
        var mode: c.SDL_BlendMode = undefined;
        if (!c.SDL_GetSurfaceBlendMode(self.handle, &mode)) return error.SdlFailure;
        return @fromBackingInt(mode);
    }

    /// Blit the whole source to destination pixel (0,0), without scaling. Clips to destination
    /// bounds and its native clip rectangle; source blend/modulation/color-key state applies.
    /// Both surfaces must be unlocked, alive, and exclusively accessed until return. No retention
    /// or ownership transfer. Same-handle blits return AliasedSurface before mutation; distinct
    /// handles must also have nonoverlapping pixel storage. Native conversion may allocate/block
    /// or fail with SdlFailure; failure does not promise destination rollback. Any thread.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer source.deinit();
    /// var destination = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 2 });
    /// defer destination.deinit();
    /// const color = sdl.surface.Color{ .r = 10, .g = 20, .b = 30, .a = 40 };
    /// try source.borrow().fill(color);
    /// try source.borrow().set_blend_mode(.none);
    /// try source.borrow().blit_to(destination.borrow());
    /// const pixel = try destination.borrow().read_pixel(.{ .x = 0, .y = 0 });
    /// try @import("std").testing.expectEqualDeep(color, pixel);
    /// ```
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn blit_to(self: SurfaceRef, destination: SurfaceRef) Error!void {
        if (self.handle == destination.handle) return error.AliasedSurface;
        if (!c.SDL_BlitSurface(self.handle, null, destination.handle, null))
            return error.SdlFailure;
    }

    /// Scale the whole source to the full destination dimensions using explicit sampling.
    /// Destination clipping restricts writes without changing the full-surface scaling transform.
    /// Source blend/modulation/color-key state applies; different native pixel formats can convert.
    /// Both surfaces must be unlocked, alive, and exclusively accessed on the invoking thread.
    /// Same handles return AliasedSurface; distinct handles must not share pixel storage. Native
    /// work may allocate/block or partially modify output before SdlFailure. No resources retained.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn blit_scaled_to(
        self: SurfaceRef,
        destination: SurfaceRef,
        mode: ScaleMode,
    ) Error!void {
        if (self.handle == destination.handle) return error.AliasedSurface;
        const native_mode: c.SDL_ScaleMode = switch (mode) {
            .nearest => c.SDL_SCALEMODE_NEAREST,
            .linear => c.SDL_SCALEMODE_LINEAR,
            .pixel_art => c.SDL_SCALEMODE_PIXELART,
        };
        if (!c.SDL_BlitSurfaceScaled(
            self.handle,
            null,
            destination.handle,
            null,
            native_mode,
        )) return error.SdlFailure;
    }

    /// Blit a contained source region at a signed destination position, without scaling.
    /// InvalidRegion/AliasedSurface return before mutation. Empty or entirely offscreen regions
    /// are successful no-ops, without native lock checks. Negative positions crop source pixels
    /// without shifting the image. Wider checked geometry keeps extreme i32 offsets safe.
    /// Any thread, exclusive access to both unlocked surfaces; distinct handles must not share
    /// pixels. Destination native clipping and source blend/modulation/color-key state apply.
    /// Native work may allocate/block or fail without rollback. Owners/views are not retained.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 1 });
    /// defer source.deinit();
    /// var destination = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    /// defer destination.deinit();
    /// const red = sdl.surface.Color{ .r = 255, .g = 0, .b = 0 };
    /// try source.borrow().write_pixel(.{ .x = 1, .y = 0 }, red);
    /// try source.borrow().set_blend_mode(.none);
    /// try source.borrow().blit_region_to(destination.borrow(), &.{
    ///     .destination = .{ .x = -1 },
    /// });
    /// const pixel = try destination.borrow().read_pixel(.{ .x = 0, .y = 0 });
    /// try @import("std").testing.expectEqualDeep(red, pixel);
    /// ```
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn blit_region_to(
        self: SurfaceRef,
        destination: SurfaceRef,
        options: *const BlitOptions,
    ) Error!void {
        if (self.handle == destination.handle) return error.AliasedSurface;
        var source = try self.resolve_region(options.source);
        const size_dst = destination.size();
        const left: i64 = @max(0, @as(i64, options.destination.x));
        const top: i64 = @max(0, @as(i64, options.destination.y));
        const right = @min(@as(i64, size_dst.width), @as(i64, options.destination.x) + source.w);
        const bottom = @min(@as(i64, size_dst.height), @as(i64, options.destination.y) + source.h);
        if (right <= left or bottom <= top) return;
        source.x += @intCast(left - options.destination.x);
        source.y += @intCast(top - options.destination.y);
        source.w = @intCast(right - left);
        source.h = @intCast(bottom - top);
        const target = c.SDL_Rect{
            .x = @intCast(left),
            .y = @intCast(top),
            .w = source.w,
            .h = source.h,
        };
        if (!c.SDL_BlitSurface(self.handle, &source, destination.handle, &target))
            return error.SdlFailure;
    }

    /// Scale a contained source region into a contained destination region. Native destination
    /// clipping limits writes without changing the selected scaling transform. Invalid regions
    /// and same handles fail before mutation; zero extents are no-ops without native lock checks.
    /// Any thread with exclusive access to both unlocked, nonoverlapping surfaces. Source blend,
    /// modulation, and color-key state apply. Native work can allocate/block or fail without
    /// rollback. Nothing is retained. Partially out-of-bounds scaled rectangles are not supported.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn blit_scaled_region_to(
        self: SurfaceRef,
        destination: SurfaceRef,
        options: *const ScaledBlitOptions,
    ) Error!void {
        if (self.handle == destination.handle) return error.AliasedSurface;
        const source = try self.resolve_region(options.source);
        const target = try destination.resolve_region(options.destination);
        if (source.w == 0 or source.h == 0 or target.w == 0 or target.h == 0) return;
        const mode: c.SDL_ScaleMode = switch (options.mode) {
            .nearest => c.SDL_SCALEMODE_NEAREST,
            .linear => c.SDL_SCALEMODE_LINEAR,
            .pixel_art => c.SDL_SCALEMODE_PIXELART,
        };
        if (!c.SDL_BlitSurfaceScaled(self.handle, &source, destination.handle, &target, mode))
            return error.SdlFailure;
    }

    /// Repeat source pixels across the destination region, cropping tiles at the right/bottom.
    /// Rectangles are intersected with surface bounds. Native destination clipping restarts the
    /// tile pattern at the clipped top-left; it does not preserve an offscreen tile phase.
    /// Source blend, tint, opacity, and color key apply. Empty intersections succeed without work.
    /// Same handles return AliasedSurface; distinct handles must not share backing pixel storage.
    /// Requires exclusive unlocked access to both surfaces (AlreadyLocked otherwise). Native work
    /// may allocate or partially write before SdlFailure. Nothing is retained; owner thread rules
    /// apply, including main-thread use for window surfaces. No wrapper allocation.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var tile = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 2 });
    /// defer tile.deinit();
    /// var output = try sdl.surface.Surface.init_rgba(.{ .width = 5, .height = 3 });
    /// defer output.deinit();
    /// try tile.borrow().blit_tiled_to(output.borrow(), &.{});
    /// ```
    pub fn blit_tiled_to(
        self: SurfaceRef,
        destination: SurfaceRef,
        options: *const TiledBlitOptions,
    ) Error!void {
        if (self.handle == destination.handle) return error.AliasedSurface;
        if ((self.handle.flags | destination.handle.flags) & c.SDL_SURFACE_LOCKED != 0)
            return error.AlreadyLocked;
        const source = if (options.source) |rect|
            self.intersect_rect(rect)
        else
            try self.resolve_region(null);
        const target = if (options.destination) |rect|
            destination.intersect_rect(rect)
        else
            try destination.resolve_region(null);
        if (source.w == 0 or source.h == 0 or target.w == 0 or target.h == 0) return;
        if (!c.SDL_BlitSurfaceTiled(self.handle, &source, destination.handle, &target))
            return error.SdlFailure;
    }

    /// Repeat scaled tiles using native rounding and sampling. Clipping restarts tile phase.
    /// InvalidTileScale rejects nonfinite/negative scale, unrepresentable rounded tile sizes,
    /// or overflowing fallback tile endpoints. Edges mapping to zero source pixels use complete
    /// scaled tiles clipped to the target, with the original destination clip restored afterward.
    /// RLE-requested sources use a temporary uncompressed native copy in this fallback.
    /// Zero scale/rounded-zero dimensions or empty intersections succeed without writes.
    /// AliasedSurface/AlreadyLocked reject same handles or locks; raw backing storage must not
    /// overlap. Source blend/modulation/key state apply; native failures can leave partial output.
    /// Exclusive access and owner thread rules apply to both surfaces (main for windows).
    /// Native conversion may allocate. No wrapper allocation or ownership transfer.
    pub fn blit_tiled_scaled_to(
        self: SurfaceRef,
        destination: SurfaceRef,
        options: *const ScaledTiledBlitOptions,
    ) Error!void {
        const std = @import("std");
        if (self.handle == destination.handle) return error.AliasedSurface;
        if ((self.handle.flags | destination.handle.flags) & c.SDL_SURFACE_LOCKED != 0)
            return error.AlreadyLocked;
        if (!std.math.isFinite(options.scale) or options.scale < 0) return error.InvalidTileScale;
        const source = if (options.source) |rect|
            self.intersect_rect(rect)
        else
            try self.resolve_region(null);
        var target = if (options.destination) |rect|
            destination.intersect_rect(rect)
        else
            try destination.resolve_region(null);
        if (source.w == 0 or source.h == 0 or target.w == 0 or target.h == 0) return;
        var native_clip: c.SDL_Rect = undefined;
        if (!c.SDL_GetSurfaceClipRect(destination.handle, &native_clip)) return error.SdlFailure;
        if (!c.SDL_GetRectIntersection(&target, &native_clip, &target)) return;
        if (options.scale == 0) return;
        const width = try scaled_tile_extent(source.w, options.scale);
        const height = try scaled_tile_extent(source.h, options.scale);
        if (width == 0 or height == 0) return;
        const fallback = !tile_edge_valid(@rem(target.w, width), source.w, options.scale) or
            !tile_edge_valid(@rem(target.h, height), source.h, options.scale);
        const mode: c.SDL_ScaleMode = switch (options.mode) {
            .nearest => c.SDL_SCALEMODE_NEAREST,
            .linear => c.SDL_SCALEMODE_LINEAR,
            .pixel_art => c.SDL_SCALEMODE_PIXELART,
        };
        if (fallback) {
            // Last full tile endpoint must fit C rectangle arithmetic before any pixels change.
            const last_x = @as(i64, target.x) + @divTrunc(target.w - 1, width) * @as(i64, width);
            const last_y = @as(i64, target.y) + @divTrunc(target.h - 1, height) * @as(i64, height);
            if (last_x + width > std.math.maxInt(c_int) or
                last_y + height > std.math.maxInt(c_int)) return error.InvalidTileScale;
            // SDL's clipped scaler temporarily offsets the source pixel pointer. Give it an
            // uncompressed independent copy when native RLE is requested.
            var fallback_copy: ?Surface = null;
            defer if (fallback_copy) |*owner| owner.deinit();
            if (self.rle()) {
                fallback_copy = try self.duplicate();
                try fallback_copy.?.borrow().set_rle(false);
            }
            const source_handle = if (fallback_copy) |owner| owner.handle else self.handle;
            _ = c.SDL_SetSurfaceClipRect(destination.handle, &target);
            defer _ = c.SDL_SetSurfaceClipRect(destination.handle, &native_clip);
            var y: i64 = target.y;
            while (y <= last_y) : (y += height) {
                var x: i64 = target.x;
                while (x <= last_x) : (x += width) {
                    const tile = c.SDL_Rect{
                        .x = @intCast(x),
                        .y = @intCast(y),
                        .w = width,
                        .h = height,
                    };
                    if (!c.SDL_BlitSurfaceScaled(
                        source_handle,
                        &source,
                        destination.handle,
                        &tile,
                        mode,
                    )) return error.SdlFailure;
                }
            }
            return;
        }
        if (!c.SDL_BlitSurfaceTiledWithScale(
            self.handle,
            &source,
            options.scale,
            mode,
            destination.handle,
            &target,
        )) return error.SdlFailure;
    }

    /// Draw a 3x3 grid: corners keep their scaled sizes, edges/center stretch to fill the target.
    /// InvalidRegion/InvalidGrid reject before writes. Borders must fit source and scaled borders
    /// must fit destination; a zero-width/height source band cannot fill a nonempty target band.
    /// Corner scale is finite/nonnegative; zero means unscaled. Empty regions are no-ops.
    /// Same handles/locks return AliasedSurface/AlreadyLocked; raw pixel storage must not overlap.
    /// Source blend/modulation/key state applies. Destination clip limits writes without changing
    /// grid geometry. Native failure may partially draw. RLE sources use a temporary uncompressed
    /// copy for native clipped scaling. No source ownership transfer; native allocation may occur.
    /// Requires exclusive access to both surfaces on owner-permitted threads (main for windows).
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var source = try sdl.surface.Surface.init_rgba(.{ .width = 3, .height = 3 });
    /// defer source.deinit();
    /// var output = try sdl.surface.Surface.init_rgba(.{ .width = 9, .height = 9 });
    /// defer output.deinit();
    /// try source.borrow().blit_nine_grid_to(output.borrow(), &.{
    ///     .borders = .{ .left = 1, .right = 1, .top = 1, .bottom = 1 },
    ///     .mode = .nearest,
    /// });
    /// ```
    pub fn blit_nine_grid_to(
        self: SurfaceRef,
        destination: SurfaceRef,
        options: *const NineGridOptions,
    ) Error!void {
        const std = @import("std");
        if (self.handle == destination.handle) return error.AliasedSurface;
        if ((self.handle.flags | destination.handle.flags) & c.SDL_SURFACE_LOCKED != 0)
            return error.AlreadyLocked;
        if (!std.math.isFinite(options.corner_scale) or options.corner_scale < 0)
            return error.InvalidGrid;
        const source = try self.resolve_region(options.source);
        const target = try destination.resolve_region(options.destination);
        if (source.w == 0 or source.h == 0 or target.w == 0 or target.h == 0) return;
        const borders = options.borders;
        const horizontal = @as(u64, borders.left) + borders.right;
        const vertical = @as(u64, borders.top) + borders.bottom;
        if (horizontal > @as(u32, @intCast(source.w)) or
            vertical > @as(u32, @intCast(source.h))) return error.InvalidGrid;
        const scale = if (options.corner_scale == 0) 1 else options.corner_scale;
        const left = scaled_tile_extent(@intCast(borders.left), scale) catch
            return error.InvalidGrid;
        const right = scaled_tile_extent(@intCast(borders.right), scale) catch
            return error.InvalidGrid;
        const top = scaled_tile_extent(@intCast(borders.top), scale) catch
            return error.InvalidGrid;
        const bottom = scaled_tile_extent(@intCast(borders.bottom), scale) catch
            return error.InvalidGrid;
        const target_horizontal = @as(i64, left) + right;
        const target_vertical = @as(i64, top) + bottom;
        if (target_horizontal > target.w or target_vertical > target.h) return error.InvalidGrid;
        if ((horizontal == source.w and target_horizontal < target.w) or
            (vertical == source.h and target_vertical < target.h)) return error.InvalidGrid;
        var copy: ?Surface = null;
        defer if (copy) |*owner| owner.deinit();
        if (self.rle()) {
            copy = try self.duplicate();
            try copy.?.borrow().set_rle(false);
        }
        const mode: c.SDL_ScaleMode = switch (options.mode) {
            .nearest => c.SDL_SCALEMODE_NEAREST,
            .linear => c.SDL_SCALEMODE_LINEAR,
            .pixel_art => c.SDL_SCALEMODE_PIXELART,
        };
        if (!c.SDL_BlitSurface9Grid(
            if (copy) |owner| owner.handle else self.handle,
            &source,
            @intCast(borders.left),
            @intCast(borders.right),
            @intCast(borders.top),
            @intCast(borders.bottom),
            options.corner_scale,
            mode,
            destination.handle,
            &target,
        )) return error.SdlFailure;
    }

    fn resolve_region(self: SurfaceRef, region: ?Region) Error!c.SDL_Rect {
        const dimensions = self.size();
        const selected = region orelse Region{
            .width = dimensions.width,
            .height = dimensions.height,
        };
        if (selected.x > dimensions.width or selected.y > dimensions.height)
            return error.InvalidRegion;
        if (selected.width > dimensions.width - selected.x or
            selected.height > dimensions.height - selected.y) return error.InvalidRegion;
        return .{
            .x = @intCast(selected.x),
            .y = @intCast(selected.y),
            .w = @intCast(selected.width),
            .h = @intCast(selected.height),
        };
    }

    /// Allocate an independent copy of the main surface pixels in the same format. Any thread,
    /// exclusive source access; native allocation/conversion may fail with SdlFailure. Source is
    /// retained by the caller and may be destroyed after return. Alternate images, if present,
    /// retain shared native references; this is not a deep copy of an alternate-image graph.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn duplicate(self: SurfaceRef) Error!Surface {
        const handle = c.SDL_DuplicateSurface(self.handle) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Allocate a new surface whose memory pixels use byte order R,G,B,A on every host endian.
    /// Any thread, exclusive source access; may allocate/convert and return SdlFailure. Row padding
    /// remains implementation-defined. Conversion can lose HDR precision; palette/color-key and
    /// colorspace handling follow SDL. This is format conversion, not a color-profile API. Source
    /// remains owned by caller; alternate images can retain shared native references.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn to_rgba(self: SurfaceRef) Error!Surface {
        return self.to_format(@import("pixels.zig").Format.rgba32);
    }

    /// Allocate an independent surface converted to a typed format; source ownership is unchanged.
    /// Any thread allowed by the source owner, with exclusive access and no active pixel locks.
    /// Window-owned sources require main-thread use and reacquisition after resize. Conversion
    /// may allocate/fail with SdlFailure. Unsupported pairs, missing palettes, or invalid formats
    /// can fail even if the destination identity is known. No owner escapes on failure.
    /// Conversion can lose precision/alpha; colorspace, palette, modulation/color-key state, and
    /// alternate-image reference sharing follow SDL. This is not a color-profile conversion API.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var rgb = try sdl.surface.Surface.init_format(.{ .width = 2, .height = 2 }, .rgb565);
    /// defer rgb.deinit();
    /// try rgb.borrow().fill(.{ .r = 255, .g = 0, .b = 0 });
    /// var rgba = try rgb.borrow().to_format(sdl.pixels.Format.rgba32);
    /// defer rgba.deinit();
    /// try @import("std").testing.expectEqual(sdl.pixels.Format.rgba32, rgba.borrow().format());
    /// ```
    pub fn to_format(
        self: SurfaceRef,
        destination_format: @import("pixels.zig").Format,
    ) Error!Surface {
        const handle = c.SDL_ConvertSurface(self.handle, @backingInt(destination_format)) orelse
            return error.SdlFailure;
        return .{ .handle = handle };
    }

    fn validate_point(self: SurfaceRef, point: Point) Error!void {
        const dimensions = self.size();
        if (point.x >= dimensions.width or point.y >= dimensions.height) return error.OutOfBounds;
    }

    /// Return pixel dimensions without allocation or a native call. Any thread while alive.
    /// Native interoperability must preserve nonnegative surface dimensions.
    /// Window-owned surfaces require main-thread use and a view reacquired after window resize.
    pub fn size(self: SurfaceRef) video.Size {
        return .{ .width = @intCast(self.handle.w), .height = @intCast(self.handle.h) };
    }
};

fn scaled_tile_extent(extent: c_int, scale: f32) Error!c_int {
    const std = @import("std");
    const rounded = @round(@as(f32, @floatFromInt(extent)) * scale);
    if (!std.math.isFinite(rounded) or @as(f64, rounded) > std.math.maxInt(c_int))
        return error.InvalidTileScale;
    return @intFromFloat(rounded);
}

fn tile_edge_valid(remainder: c_int, source_extent: c_int, scale: f32) bool {
    if (remainder == 0) return true;
    const extent = @as(f32, @floatFromInt(remainder)) / scale;
    return extent >= 1 and @as(f64, extent) <= @as(f64, @floatFromInt(source_extent));
}

fn validate_float_color(color: FloatColor) Error!void {
    const std = @import("std");
    if (!std.math.isFinite(color.r) or !std.math.isFinite(color.g) or
        !std.math.isFinite(color.b) or !std.math.isFinite(color.a)) return error.InvalidColor;
}

// SDL_rotate.c uses signed 16.16 coordinates, int row offsets, and an int angle/90.
// With w+h <= 8192, transformed coordinates (including bounding-box rounding and a final
// pixel increment) are bounded by 2*(w+h)+8 pixels, safely below 32768. Converted RGBA
// source/destination spans fit int as well. Original unusual pitch needs a separate bound.
fn validate_rotation(degrees: f32, width: c_int, height: c_int, pitch: c_int) Error!void {
    const std = @import("std");
    const turns: f64 = @as(f64, degrees) / 90.0;
    if (!std.math.isFinite(degrees) or turns < std.math.minInt(c_int) or
        turns > std.math.maxInt(c_int)) return error.InvalidRotation;
    if (width <= 0 or height <= 0 or pitch <= 0 or
        @as(i64, width) + height > 8192 or
        @as(i64, pitch) * height > std.math.maxInt(c_int)) return error.RotationTooLarge;
}

test "surface dimensions and invalid sizes" {
    const std = @import("std");
    try std.testing.expectError(error.InvalidSize, Surface.init_rgba(.{ .width = 0, .height = 1 }));
    try std.testing.expectError(error.InvalidSize, Surface.init_rgba(.{ .width = 1, .height = 0 }));
    try std.testing.expectError(
        error.InvalidSize,
        Surface.init_rgba(.{ .width = 0xffffffff, .height = 1 }),
    );
    var surface = try Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer surface.deinit();
    try std.testing.expectEqualDeep(video.Size{ .width = 3, .height = 2 }, surface.borrow().size());
    var r: u8 = undefined;
    var g: u8 = undefined;
    var b: u8 = undefined;
    var a: u8 = undefined;
    try std.testing.expect(c.SDL_ReadSurfacePixel(surface.handle, 2, 1, &r, &g, &b, &a));
    try std.testing.expectEqual(@as(u8, 0), r | g | b | a);
}

test "pixel access validates bounds and preserves unblended RGBA" {
    const std = @import("std");
    var surface = try Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer surface.deinit();
    const color = Color{ .r = 9, .g = 87, .b = 123, .a = 42 };
    const point = Point{ .x = 2, .y = 1 };
    try surface.borrow().write_pixel(point, color);
    try std.testing.expectEqualDeep(color, try surface.borrow().read_pixel(point));
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
        try surface.borrow().read_pixel(.{ .x = 1, .y = 1 }),
    );
    for ([_]Point{ .{ .x = 3, .y = 0 }, .{ .x = 0, .y = 2 }, .{ .x = 0xffffffff, .y = 0 } }) |bad| {
        try std.testing.expectError(error.OutOfBounds, surface.borrow().read_pixel(bad));
        try std.testing.expectError(error.OutOfBounds, surface.borrow().write_pixel(bad, color));
    }
    try std.testing.expectEqualDeep(color, try surface.borrow().read_pixel(point));
}

test "whole fills respect clipping while pixel writes ignore it" {
    const std = @import("std");
    var surface = try Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer surface.deinit();
    const background = Color{ .r = 10, .g = 20, .b = 30, .a = 40 };
    const foreground = Color{ .r = 50, .g = 60, .b = 70, .a = 80 };
    try surface.borrow().fill(background);
    const clip = c.SDL_Rect{ .x = 1, .y = 0, .w = 1, .h = 1 };
    try std.testing.expect(c.SDL_SetSurfaceClipRect(surface.handle, &clip));
    try surface.borrow().fill(foreground);
    try std.testing.expectEqualDeep(
        foreground,
        try surface.borrow().read_pixel(.{ .x = 1, .y = 0 }),
    );
    try std.testing.expectEqualDeep(
        background,
        try surface.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectEqualDeep(
        background,
        try surface.borrow().read_pixel(.{ .x = 1, .y = 1 }),
    );
    try surface.borrow().write_pixel(.{ .x = 2, .y = 1 }, foreground);
    try std.testing.expectEqualDeep(
        foreground,
        try surface.borrow().read_pixel(.{ .x = 2, .y = 1 }),
    );
}

test "duplicate and RGBA conversion own independent pixels" {
    const std = @import("std");
    var source = Surface{ .handle = c.SDL_CreateSurface(3, 2, c.SDL_PIXELFORMAT_RGB24) orelse
        return error.SdlFailure };
    const color = Color{ .r = 20, .g = 40, .b = 60 };
    var duplicate: Surface = undefined;
    var converted: Surface = undefined;
    {
        defer source.deinit();
        try source.borrow().fill(color);
        duplicate = try source.borrow().duplicate();
        errdefer duplicate.deinit();
        converted = try source.borrow().to_rgba();
    }
    defer duplicate.deinit();
    defer converted.deinit();
    try std.testing.expectEqual(
        @as(c.SDL_PixelFormat, c.SDL_PIXELFORMAT_RGB24),
        duplicate.handle.format,
    );
    try std.testing.expectEqual(
        @as(c.SDL_PixelFormat, c.SDL_PIXELFORMAT_RGBA32),
        converted.handle.format,
    );
    try std.testing.expectEqualDeep(color, try duplicate.borrow().read_pixel(.{ .x = 2, .y = 1 }));
    try std.testing.expectEqualDeep(color, try converted.borrow().read_pixel(.{ .x = 2, .y = 1 }));
    try duplicate.borrow().fill(.{ .r = 0, .g = 0, .b = 0 });
    try std.testing.expectEqualDeep(color, try converted.borrow().read_pixel(.{ .x = 2, .y = 1 }));
    const pixels: [*]const u8 = @ptrCast(converted.handle.pixels.?);
    const offset: usize = @intCast(converted.handle.pitch + 2 * 4);
    try std.testing.expectEqualSlices(u8, &.{ 20, 40, 60, 255 }, pixels[offset..][0..4]);
}

test "blits respect destination clipping and reject aliases and locked surfaces" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 2, .height = 2 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer destination.deinit();
    const foreground = Color{ .r = 12, .g = 34, .b = 56, .a = 78 };
    const background = Color{ .r = 90, .g = 80, .b = 70, .a = 60 };
    try source.borrow().fill(foreground);
    try source.borrow().set_blend_mode(.none);
    try destination.borrow().fill(background);
    const clip = c.SDL_Rect{ .x = 1, .y = 0, .w = 1, .h = 1 };
    try std.testing.expect(c.SDL_SetSurfaceClipRect(destination.handle, &clip));
    try source.borrow().blit_to(destination.borrow());
    try std.testing.expectEqualDeep(
        foreground,
        try destination.borrow().read_pixel(.{ .x = 1, .y = 0 }),
    );
    try std.testing.expectEqualDeep(
        background,
        try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectEqualDeep(
        background,
        try destination.borrow().read_pixel(.{ .x = 2, .y = 1 }),
    );
    try std.testing.expectError(error.AliasedSurface, source.borrow().blit_to(source.borrow()));
    try std.testing.expectError(
        error.AliasedSurface,
        source.borrow().blit_scaled_to(source.borrow(), .nearest),
    );
    try std.testing.expect(c.SDL_LockSurface(source.handle));
    {
        defer c.SDL_UnlockSurface(source.handle);
        try std.testing.expectError(
            error.SdlFailure,
            source.borrow().blit_to(destination.borrow()),
        );
        try std.testing.expectError(
            error.SdlFailure,
            source.borrow().blit_scaled_to(destination.borrow(), .nearest),
        );
    }
    try source.borrow().blit_to(destination.borrow());
}

test "source blend modes control alpha composition without changing source pixels" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer destination.deinit();
    const red = Color{ .r = 255, .g = 0, .b = 0, .a = 128 };
    const blue = Color{ .r = 0, .g = 0, .b = 255 };
    try source.borrow().fill(red);
    for ([_]BlendMode{
        .none, .alpha, .premultiplied_alpha, .add, .premultiplied_add, .modulate, .multiply,
    }) |mode| {
        try source.borrow().set_blend_mode(mode);
        try std.testing.expectEqual(mode, try source.borrow().blend_mode());
    }
    try std.testing.expectError(
        error.SdlFailure,
        source.borrow().set_blend_mode(@fromBackingInt(@as(u32, 0xffffffff))),
    );
    try source.borrow().set_blend_mode(.none);
    try destination.borrow().fill(blue);
    try source.borrow().blit_to(destination.borrow());
    try std.testing.expectEqualDeep(red, try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try source.borrow().set_blend_mode(.alpha);
    try destination.borrow().fill(blue);
    try source.borrow().blit_to(destination.borrow());
    const mixed = try destination.borrow().read_pixel(.{ .x = 0, .y = 0 });
    // Integer SIMD/scalar blitters can differ by one at normalized-alpha rounding boundaries.
    try std.testing.expect(mixed.r >= 126 and mixed.r <= 128);
    try std.testing.expectEqual(@as(u8, 0), mixed.g);
    try std.testing.expect(mixed.b >= 126 and mixed.b <= 128);
    try std.testing.expect(mixed.a >= 254);
    try std.testing.expectEqualDeep(red, try source.borrow().read_pixel(.{ .x = 0, .y = 0 }));
}

test "scaled blits replicate nearest pixels and preserve clipping transform" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 4, .height = 2 });
    defer destination.deinit();
    const red = Color{ .r = 255, .g = 0, .b = 0 };
    const blue = Color{ .r = 0, .g = 0, .b = 255 };
    try source.borrow().write_pixel(.{ .x = 0, .y = 0 }, red);
    try source.borrow().write_pixel(.{ .x = 1, .y = 0 }, blue);
    try source.borrow().set_blend_mode(.none);
    const clip = c.SDL_Rect{ .x = 1, .y = 0, .w = 2, .h = 2 };
    try std.testing.expect(c.SDL_SetSurfaceClipRect(destination.handle, &clip));
    try source.borrow().blit_scaled_to(destination.borrow(), .nearest);
    try std.testing.expectEqualDeep(red, try destination.borrow().read_pixel(.{ .x = 1, .y = 1 }));
    try std.testing.expectEqualDeep(blue, try destination.borrow().read_pixel(.{ .x = 2, .y = 1 }));
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
        try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    _ = c.SDL_SetSurfaceClipRect(destination.handle, null);
    try source.borrow().fill(red);
    for ([_]ScaleMode{ .nearest, .linear, .pixel_art }) |mode| {
        try source.borrow().blit_scaled_to(destination.borrow(), mode);
        try std.testing.expectEqualDeep(
            red,
            try destination.borrow().read_pixel(.{ .x = 3, .y = 1 }),
        );
    }
}

test "positioned cropped blits match bounded pixel model across destination edges" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 4, .height = 3 });
    defer destination.deinit();
    for (0..2) |y| for (0..3) |x| {
        try source.borrow().write_pixel(.{ .x = @intCast(x), .y = @intCast(y) }, .{
            .r = @intCast(x + 1),
            .g = @intCast(y + 1),
            .b = 0,
        });
    };
    try source.borrow().set_blend_mode(.none);
    const background = Color{ .r = 99, .g = 98, .b = 97 };
    for (0..6) |iy| for (0..8) |ix| {
        const position = Position{
            .x = @as(i32, @intCast(ix)) - 3,
            .y = @as(i32, @intCast(iy)) - 2,
        };
        try destination.borrow().fill(background);
        try source.borrow().blit_region_to(destination.borrow(), &.{
            .source = .{ .x = 1, .width = 2, .height = 2 },
            .destination = position,
        });
        for (0..3) |y| for (0..4) |x| {
            const sx = @as(i64, @intCast(x)) - position.x;
            const sy = @as(i64, @intCast(y)) - position.y;
            const expected = if (sx >= 0 and sx < 2 and sy >= 0 and sy < 2)
                Color{ .r = @intCast(sx + 2), .g = @intCast(sy + 1), .b = 0 }
            else
                background;
            try std.testing.expectEqualDeep(expected, try destination.borrow().read_pixel(.{
                .x = @intCast(x),
                .y = @intCast(y),
            }));
        };
    };
    for ([_]i32{ std.math.minInt(i32), std.math.maxInt(i32) }) |offset| {
        try destination.borrow().fill(background);
        try source.borrow().blit_region_to(destination.borrow(), &.{
            .destination = .{ .x = offset, .y = offset },
        });
        try std.testing.expectEqualDeep(
            background,
            try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }),
        );
    }
}

test "scaled subregions preserve untouched pixels for each sampling mode" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 3, .height = 1 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 4, .height = 4 });
    defer destination.deinit();
    const foreground = Color{ .r = 7, .g = 8, .b = 9 };
    const background = Color{ .r = 1, .g = 2, .b = 3 };
    try source.borrow().write_pixel(.{ .x = 1, .y = 0 }, foreground);
    try source.borrow().set_blend_mode(.none);
    for ([_]ScaleMode{ .nearest, .linear, .pixel_art }) |mode| {
        try destination.borrow().fill(background);
        try source.borrow().blit_scaled_region_to(destination.borrow(), &.{
            .source = .{ .x = 1, .width = 1, .height = 1 },
            .destination = .{ .x = 1, .y = 1, .width = 2, .height = 2 },
            .mode = mode,
        });
        for (0..4) |y| for (0..4) |x| {
            const expected = if (x >= 1 and x < 3 and y >= 1 and y < 3) foreground else background;
            try std.testing.expectEqualDeep(expected, try destination.borrow().read_pixel(.{
                .x = @intCast(x),
                .y = @intCast(y),
            }));
        };
    }
}

test "invalid and empty blit regions do not modify destination" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 2, .height = 2 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 2, .height = 2 });
    defer destination.deinit();
    const background = Color{ .r = 11, .g = 22, .b = 33 };
    try destination.borrow().fill(background);
    const invalid = [_]Region{
        .{ .x = 3, .width = 0, .height = 0 },
        .{ .x = 1, .width = 2, .height = 1 },
        .{ .y = 1, .width = 1, .height = 2 },
        .{ .x = 0xffffffff, .width = 0xffffffff, .height = 1 },
    };
    for (invalid) |region| {
        try std.testing.expectError(
            error.InvalidRegion,
            source.borrow().blit_region_to(destination.borrow(), &.{ .source = region }),
        );
        try std.testing.expectError(
            error.InvalidRegion,
            source.borrow().blit_scaled_region_to(destination.borrow(), &.{
                .destination = region,
                .mode = .nearest,
            }),
        );
    }
    const empty = Region{ .x = 2, .y = 2, .width = 0, .height = 0 };
    try source.borrow().blit_region_to(destination.borrow(), &.{ .source = empty });
    try source.borrow().blit_scaled_region_to(destination.borrow(), &.{
        .destination = empty,
        .mode = .nearest,
    });
    try std.testing.expectError(
        error.AliasedSurface,
        source.borrow().blit_region_to(source.borrow(), &.{}),
    );
    try std.testing.expectError(
        error.AliasedSurface,
        source.borrow().blit_scaled_region_to(source.borrow(), &.{
            .mode = .nearest,
        }),
    );
    for (0..2) |y| for (0..2) |x| {
        try std.testing.expectEqualDeep(background, try destination.borrow().read_pixel(.{
            .x = @intCast(x),
            .y = @intCast(y),
        }));
    };
}

test "clip queries distinguish empty from failure and reset restores full bounds" {
    const std = @import("std");
    var surface = try Surface.init_rgba(.{ .width = 4, .height = 3 });
    defer surface.deinit();
    const full = Region{ .width = 4, .height = 3 };
    try std.testing.expectEqualDeep(full, try surface.borrow().clip());
    try std.testing.expectEqualDeep(
        Region{ .width = 2, .height = 2 },
        try surface.borrow().set_clip(.{ .x = -1, .width = 3, .height = 2 }),
    );
    _ = c.SDL_SetError("stale diagnostic must not turn an empty clip into failure");
    defer _ = c.SDL_ClearError();
    const empty = try surface.borrow().set_clip(.{ .x = 99, .width = 1, .height = 1 });
    try std.testing.expectEqualDeep(Region{ .width = 0, .height = 0 }, empty);
    try std.testing.expectEqualDeep(empty, try surface.borrow().clip());
    try std.testing.expectEqualDeep(full, try surface.borrow().set_clip(null));
    const huge = ClipRect{
        .x = std.math.minInt(i32),
        .y = std.math.minInt(i32),
        .width = std.math.maxInt(u32),
        .height = std.math.maxInt(u32),
    };
    try std.testing.expectEqualDeep(full, try surface.borrow().set_clip(huge));
    const distant = ClipRect{
        .x = std.math.maxInt(i32),
        .y = std.math.maxInt(i32),
        .width = std.math.maxInt(u32),
        .height = std.math.maxInt(u32),
    };
    try std.testing.expectEqualDeep(empty, try surface.borrow().set_clip(distant));
}

test "rectangle fills match pixel intersections and preserve clipping state" {
    const std = @import("std");
    var surface = try Surface.init_rgba(.{ .width = 4, .height = 3 });
    defer surface.deinit();
    const background = Color{ .r = 1, .g = 2, .b = 3 };
    const foreground = Color{ .r = 4, .g = 5, .b = 6, .a = 7 };
    const rectangles = [_]ClipRect{
        .{ .x = -2, .y = -1, .width = 5, .height = 3 },
        .{ .x = 2, .y = 1, .width = 8, .height = 8 },
        .{ .width = 0, .height = 2 },
        .{ .x = std.math.minInt(i32), .width = std.math.maxInt(u32), .height = 3 },
        .{ .x = std.math.maxInt(i32), .width = std.math.maxInt(u32), .height = 3 },
    };
    for (rectangles) |rect| {
        _ = try surface.borrow().set_clip(null);
        try surface.borrow().fill(background);
        const clip = try surface.borrow().set_clip(.{ .x = 1, .y = 1, .width = 2, .height = 1 });
        try surface.borrow().fill_rect(rect, foreground);
        try std.testing.expectEqualDeep(clip, try surface.borrow().clip());
        for (0..3) |y| for (0..4) |x| {
            const px: i64 = @intCast(x);
            const py: i64 = @intCast(y);
            const in_rect = px >= rect.x and py >= rect.y and
                px - rect.x < rect.width and py - rect.y < rect.height;
            const expected = if (in_rect and x >= 1 and x < 3 and y == 1)
                foreground
            else
                background;
            try std.testing.expectEqualDeep(expected, try surface.borrow().read_pixel(.{
                .x = @intCast(x),
                .y = @intCast(y),
            }));
        };
    }
}

test "empty clipping disables fills and blits until reset" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 3, .height = 3 });
    defer destination.deinit();
    const color = Color{ .r = 10, .g = 20, .b = 30 };
    const clear = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
    try source.borrow().fill(color);
    try source.borrow().set_blend_mode(.none);
    _ = try destination.borrow().set_clip(.{ .width = 0, .height = 0 });
    try destination.borrow().fill(color);
    try destination.borrow().fill_rect(.{ .width = 3, .height = 3 }, color);
    try source.borrow().blit_to(destination.borrow());
    try source.borrow().blit_scaled_to(destination.borrow(), .nearest);
    try std.testing.expectEqualDeep(
        clear,
        try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    _ = try destination.borrow().set_clip(.{ .x = 2, .y = 1, .width = 1, .height = 1 });
    try source.borrow().blit_scaled_region_to(destination.borrow(), &.{ .mode = .nearest });
    try std.testing.expectEqualDeep(
        color,
        try destination.borrow().read_pixel(.{ .x = 2, .y = 1 }),
    );
    try std.testing.expectEqualDeep(
        clear,
        try destination.borrow().read_pixel(.{ .x = 1, .y = 1 }),
    );
    _ = try destination.borrow().set_clip(null);
    try source.borrow().blit_region_to(destination.borrow(), &.{ .destination = .{ .x = 1 } });
    try std.testing.expectEqualDeep(
        color,
        try destination.borrow().read_pixel(.{ .x = 1, .y = 0 }),
    );
}

test "RGBA row locks edit pixels reject nesting and release for subsequent access" {
    const std = @import("std");
    var surface = try Surface.init_rgba(.{ .width = 2, .height = 2 });
    defer surface.deinit();
    {
        var lock = try surface.borrow().lock_rgba();
        defer lock.deinit();
        try std.testing.expectEqual(@as(u32, 2), lock.width);
        try std.testing.expectEqual(@as(u32, 2), lock.height);
        try std.testing.expectEqual(@as(usize, 8), (try lock.row(0)).len);
        try std.testing.expectError(error.AlreadyLocked, surface.borrow().lock_rgba());
        try std.testing.expectError(error.OutOfBounds, lock.row(2));
        try std.testing.expectError(error.OutOfBounds, lock.row(0xffffffff));
        const row = try lock.row(1);
        @memcpy(row[4..8], &[_]u8{ 10, 20, 30, 40 });
    }
    try std.testing.expect(surface.handle.flags & c.SDL_SURFACE_LOCKED == 0);
    try std.testing.expectEqualDeep(
        Color{ .r = 10, .g = 20, .b = 30, .a = 40 },
        try surface.borrow().read_pixel(.{ .x = 1, .y = 1 }),
    );
    var again = try surface.borrow().lock_rgba();
    defer again.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 10, 20, 30, 40 }, (try again.row(1))[4..8]);
}

test "RGBA rows exclude padding and protect caller-owned guard bytes" {
    const std = @import("std");
    var storage: [32]u8 = undefined;
    @memset(&storage, 0xaa);
    var surface = Surface{ .handle = c.SDL_CreateSurfaceFrom(
        2,
        2,
        c.SDL_PIXELFORMAT_RGBA32,
        storage[4..].ptr,
        12,
    ) orelse return error.SdlFailure };
    defer surface.deinit();
    {
        var lock = try surface.borrow().lock_rgba();
        defer lock.deinit();
        try std.testing.expectEqual(@as(usize, 12), lock.pitch);
        @memset(try lock.row(0), 0x11);
        @memset(try lock.row(1), 0x22);
    }
    for (storage, 0..) |byte, index| {
        const expected: u8 = if (index >= 4 and index < 12)
            0x11
        else if (index >= 16 and index < 24)
            0x22
        else
            0xaa;
        try std.testing.expectEqual(expected, byte);
    }
}

test "unsupported or unavailable pixel storage returns no live lock" {
    const std = @import("std");
    var rgb = Surface{ .handle = c.SDL_CreateSurface(2, 1, c.SDL_PIXELFORMAT_RGB24) orelse
        return error.SdlFailure };
    defer rgb.deinit();
    try std.testing.expectError(error.UnsupportedPixelFormat, rgb.borrow().lock_rgba());
    try std.testing.expect(rgb.handle.flags & c.SDL_SURFACE_LOCKED == 0);
    var converted = try rgb.borrow().to_rgba();
    defer converted.deinit();
    {
        var lock = try converted.borrow().lock_rgba();
        defer lock.deinit();
        try std.testing.expectEqual(@as(usize, 8), (try lock.row(0)).len);
    }
    var missing = Surface{ .handle = c.SDL_CreateSurfaceFrom(
        2,
        2,
        c.SDL_PIXELFORMAT_RGBA32,
        null,
        0,
    ) orelse return error.SdlFailure };
    defer missing.deinit();
    try std.testing.expectError(error.InvalidPixelLayout, missing.borrow().lock_rgba());
    try std.testing.expect(missing.handle.flags & c.SDL_SURFACE_LOCKED == 0);
    var empty = Surface{ .handle = c.SDL_CreateSurface(0, 0, c.SDL_PIXELFORMAT_RGBA32) orelse
        return error.SdlFailure };
    defer empty.deinit();
    try std.testing.expectError(error.InvalidPixelLayout, empty.borrow().lock_rgba());
    try std.testing.expect(empty.handle.flags & c.SDL_SURFACE_LOCKED == 0);
}

test "tint and opacity state are independent from pixels and blend mode" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer destination.deinit();
    const original = Color{ .r = 200, .g = 100, .b = 50, .a = 128 };
    try source.borrow().fill(original);
    try source.borrow().set_blend_mode(.none);
    try std.testing.expectEqualDeep(Tint{}, try source.borrow().tint());
    try std.testing.expectEqual(@as(u8, 255), try source.borrow().opacity());
    const selected = Tint{ .r = 128, .g = 255, .b = 0 };
    try source.borrow().set_tint(selected);
    try source.borrow().set_opacity(64);
    try std.testing.expectEqualDeep(selected, try source.borrow().tint());
    try std.testing.expectEqual(@as(u8, 64), try source.borrow().opacity());
    try std.testing.expectEqual(BlendMode.none, try source.borrow().blend_mode());
    try source.borrow().blit_to(destination.borrow());
    const result = try destination.borrow().read_pixel(.{ .x = 0, .y = 0 });
    try std.testing.expect(result.r >= 99 and result.r <= 101);
    try std.testing.expectEqual(@as(u8, 100), result.g);
    try std.testing.expectEqual(@as(u8, 0), result.b);
    try std.testing.expect(result.a >= 31 and result.a <= 32);
    try std.testing.expectEqualDeep(
        original,
        try source.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    try source.borrow().set_tint(.{});
    try std.testing.expectEqual(@as(u8, 64), try source.borrow().opacity());
    try source.borrow().set_opacity(255);
    try source.borrow().blit_to(destination.borrow());
    try std.testing.expectEqualDeep(
        original,
        try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
}

test "opacity affects scaled alpha composition with zero and full endpoints" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 2, .height = 2 });
    defer destination.deinit();
    const red = Color{ .r = 255, .g = 0, .b = 0 };
    const blue = Color{ .r = 0, .g = 0, .b = 255 };
    try source.borrow().fill(red);
    try source.borrow().set_blend_mode(.alpha);
    try destination.borrow().fill(blue);
    try source.borrow().set_opacity(0);
    try source.borrow().blit_scaled_to(destination.borrow(), .nearest);
    try std.testing.expectEqualDeep(
        blue,
        try destination.borrow().read_pixel(.{ .x = 1, .y = 1 }),
    );
    try source.borrow().set_opacity(128);
    try source.borrow().blit_scaled_to(destination.borrow(), .nearest);
    const mixed = try destination.borrow().read_pixel(.{ .x = 1, .y = 1 });
    try std.testing.expect(mixed.r >= 126 and mixed.r <= 128);
    try std.testing.expect(mixed.b >= 126 and mixed.b <= 128);
    try std.testing.expectEqual(@as(u8, 0), mixed.g);
    try source.borrow().set_opacity(255);
    try source.borrow().blit_scaled_to(destination.borrow(), .nearest);
    try std.testing.expectEqualDeep(
        red,
        try destination.borrow().read_pixel(.{ .x = 1, .y = 1 }),
    );
}

test "typed surface allocation and conversion preserve independent pixel ownership" {
    const std = @import("std");
    const Format = @import("pixels.zig").Format;
    var rgb = try Surface.init_format(.{ .width = 3, .height = 2 }, .rgb24);
    defer rgb.deinit();
    try std.testing.expectEqual(Format.rgb24, rgb.borrow().format());
    try std.testing.expectEqualDeep(
        Color{ .r = 0, .g = 0, .b = 0 },
        try rgb.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    const magenta = Color{ .r = 255, .g = 0, .b = 255 };
    try rgb.borrow().fill(magenta);
    var rgb565 = try rgb.borrow().to_format(.rgb565);
    defer rgb565.deinit();
    try std.testing.expectEqual(Format.rgb565, rgb565.borrow().format());
    try std.testing.expectEqualDeep(magenta, try rgb565.borrow().read_pixel(.{ .x = 2, .y = 1 }));
    try rgb.borrow().fill(.{ .r = 0, .g = 0, .b = 0 });
    try std.testing.expectEqualDeep(magenta, try rgb565.borrow().read_pixel(.{ .x = 2, .y = 1 }));
    var rgba = try rgb565.borrow().to_rgba();
    defer rgba.deinit();
    try std.testing.expectEqual(Format.rgba32, rgba.borrow().format());
    try std.testing.expectEqualDeep(magenta, try rgba.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try std.testing.expectError(error.SdlFailure, rgb565.borrow().to_format(.unknown));
    try std.testing.expectEqualDeep(magenta, try rgb565.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try std.testing.expectError(
        error.SdlFailure,
        Surface.init_format(.{ .width = 1, .height = 1 }, .unknown),
    );
    try std.testing.expectError(
        error.InvalidSize,
        Surface.init_format(.{ .width = 0, .height = 1 }, .rgb24),
    );
}

test "surfaces retain shared palettes after owner release and observe shared edits" {
    const std = @import("std");
    const pixels = @import("pixels.zig");
    var first = try Surface.init_format(.{ .width = 2, .height = 1 }, .index8);
    defer first.deinit();
    var second = try Surface.init_format(.{ .width = 2, .height = 1 }, .index8);
    defer second.deinit();
    {
        var owned = try pixels.Palette.init(2);
        defer owned.deinit();
        try owned.borrow().set_colors(0, &.{
            .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
        });
        try first.borrow().set_palette(owned.borrow());
        try second.borrow().set_palette(owned.borrow());
    }
    const red = Color{ .r = 255, .g = 0, .b = 0 };
    const green = Color{ .r = 0, .g = 255, .b = 0 };
    try first.borrow().fill(red);
    try second.borrow().fill(red);
    {
        const borrowed = first.borrow().palette().?;
        try std.testing.expectEqual(@as(usize, 2), borrowed.len());
        try borrowed.set_colors(1, &.{green});
        try std.testing.expectEqualDeep(green, try first.borrow().read_pixel(.{ .x = 0, .y = 0 }));
        try std.testing.expectEqualDeep(green, try second.borrow().read_pixel(.{ .x = 1, .y = 0 }));
        var too_large = try pixels.Palette.init(257);
        defer too_large.deinit();
        try std.testing.expectError(
            error.SdlFailure,
            first.borrow().set_palette(too_large.borrow()),
        );
        try std.testing.expectEqual(@as(usize, 2), first.borrow().palette().?.len());
    }
    var rgba = try first.borrow().to_rgba();
    defer rgba.deinit();
    try std.testing.expectEqualDeep(green, try rgba.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try first.borrow().set_palette(null);
    try std.testing.expect(first.borrow().palette() == null);
    try std.testing.expectEqualDeep(green, try second.borrow().palette().?.get(1));
    const replacement = try second.borrow().create_palette();
    try std.testing.expectEqual(@as(usize, 256), replacement.len());
    try std.testing.expectEqualDeep(Color{ .r = 255, .g = 255, .b = 255 }, try replacement.get(1));
    try std.testing.expectError(error.SdlFailure, rgba.borrow().create_palette());
    try std.testing.expectError(error.SdlFailure, rgba.borrow().set_palette(replacement));
    try std.testing.expect(rgba.borrow().palette() == null);
}

test "one-bit surface palettes initialize white then black" {
    const std = @import("std");
    var bitmap = try Surface.init_format(.{ .width = 8, .height = 1 }, .index1msb);
    defer bitmap.deinit();
    const palette = try bitmap.borrow().create_palette();
    try std.testing.expectEqual(@as(usize, 2), palette.len());
    try std.testing.expectEqualDeep(Color{ .r = 255, .g = 255, .b = 255 }, try palette.get(0));
    try std.testing.expectEqualDeep(Color{ .r = 0, .g = 0, .b = 0 }, try palette.get(1));
}

test "color keys skip matching pixels and RLE preserves locked RGBA access" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer source.deinit();
    var destination = try Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer destination.deinit();
    const red = Color{ .r = 255, .g = 0, .b = 0 };
    const blue = Color{ .r = 0, .g = 0, .b = 255 };
    try source.borrow().fill(red);
    try source.borrow().set_blend_mode(.none);
    try std.testing.expectEqual(@as(?u32, null), try source.borrow().color_key_pixel());
    try std.testing.expect(!source.borrow().rle());
    try source.borrow().set_color_key(red);
    try source.borrow().set_rle(true);
    try std.testing.expect(source.borrow().rle());
    try destination.borrow().fill(blue);
    try source.borrow().blit_to(destination.borrow());
    try std.testing.expectEqualDeep(blue, try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    {
        var guard = try source.borrow().lock_rgba();
        defer guard.deinit();
        const row = try guard.row(0);
        try std.testing.expectEqualSlices(u8, &.{ 255, 0, 0, 255 }, row[0..4]);
        @memcpy(row[4..8], &[_]u8{ 0, 255, 0, 255 });
    }
    try source.borrow().blit_to(destination.borrow());
    try std.testing.expectEqualDeep(blue, try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try std.testing.expectEqual(
        @as(u8, 255),
        (try destination.borrow().read_pixel(.{ .x = 1, .y = 0 })).g,
    );
    try source.borrow().set_color_key(null);
    try source.borrow().set_rle(false);
    try std.testing.expect(!source.borrow().rle());
    try source.borrow().blit_to(destination.borrow());
    try std.testing.expectEqualDeep(red, try destination.borrow().read_pixel(.{ .x = 0, .y = 0 }));
}

test "indexed keys retain exact indices and reject out of range without mutation" {
    const std = @import("std");
    var source = try Surface.init_format(.{ .width = 1, .height = 1 }, .index8);
    defer source.deinit();
    try std.testing.expectError(
        error.UnsupportedPixelFormat,
        source.borrow().set_color_key(.{ .r = 0, .g = 0, .b = 0 }),
    );
    var palette_owner = try @import("pixels.zig").Palette.init(2);
    defer palette_owner.deinit();
    try source.borrow().set_palette(palette_owner.borrow());
    try source.borrow().set_color_key_pixel(1);
    try std.testing.expectEqual(@as(?u32, 1), try source.borrow().color_key_pixel());
    try std.testing.expectError(error.SdlFailure, source.borrow().set_color_key_pixel(2));
    try std.testing.expectEqual(@as(?u32, 1), try source.borrow().color_key_pixel());
    try source.borrow().set_color_key_pixel(null);
    try std.testing.expectEqual(@as(?u32, null), try source.borrow().color_key_pixel());
}

test "surface reflections and scaled copies preserve pixel order and ownership" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 2, .height = 2 });
    defer source.deinit();
    {
        var guard = try source.borrow().lock_rgba();
        defer guard.deinit();
        @memcpy(try guard.row(0), &[_]u8{ 1, 0, 0, 255, 2, 0, 0, 255 });
        @memcpy(try guard.row(1), &[_]u8{ 3, 0, 0, 255, 4, 0, 0, 255 });
        try std.testing.expectError(error.AlreadyLocked, source.borrow().flip(.horizontal));
        try std.testing.expectError(
            error.AlreadyLocked,
            source.borrow().scaled(.{ .width = 4, .height = 4 }, .nearest),
        );
    }
    try source.borrow().set_rle(true);
    try source.borrow().flip(.horizontal);
    try std.testing.expectEqual(
        @as(u8, 2),
        (try source.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
    try source.borrow().flip(.vertical);
    try std.testing.expectEqual(
        @as(u8, 4),
        (try source.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
    try source.borrow().flip(.both);
    try source.borrow().set_tint(.{ .r = 0 });
    var large = try source.borrow().scaled(.{ .width = 4, .height = 4 }, .nearest);
    defer large.deinit();
    for (0..4) |y| for (0..4) |x| {
        try std.testing.expectEqual(
            @as(u8, @intCast(1 + x / 2 + 2 * (y / 2))),
            (try large.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) })).r,
        );
    };
    try std.testing.expectEqual(@as(u8, 0), (try source.borrow().tint()).r);
    try source.borrow().fill(.{ .r = 99, .g = 0, .b = 0 });
    try std.testing.expectEqual(@as(u8, 1), (try large.borrow().read_pixel(.{ .x = 0, .y = 0 })).r);
    try std.testing.expectError(
        error.InvalidSize,
        source.borrow().scaled(.{ .width = 0, .height = 4 }, .nearest),
    );
}

test "rotated copies preserve direction and independent source pixels" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer source.deinit();
    {
        var guard = try source.borrow().lock_rgba();
        defer guard.deinit();
        @memcpy(try guard.row(0), &[_]u8{ 1, 0, 0, 255, 2, 0, 0, 255 });
        try std.testing.expectError(error.AlreadyLocked, source.borrow().rotated(90));
    }
    var clockwise = try source.borrow().rotated(90);
    defer clockwise.deinit();
    var counter = try source.borrow().rotated(-90);
    defer counter.deinit();
    try std.testing.expectEqual(video.Size{ .width = 1, .height = 2 }, clockwise.borrow().size());
    try std.testing.expectEqual(
        @as(u8, 1),
        (try clockwise.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
    try std.testing.expectEqual(
        @as(u8, 2),
        (try counter.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
    try source.borrow().fill(.{ .r = 99, .g = 0, .b = 0 });
    try std.testing.expectEqual(
        @as(u8, 1),
        (try clockwise.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
    var square = try Surface.init_rgba(.{ .width = 4, .height = 4 });
    defer square.deinit();
    var tilted = try square.borrow().rotated(45);
    defer tilted.deinit();
    try std.testing.expect(tilted.borrow().size().height > square.borrow().size().height);
    try std.testing.expectError(error.InvalidRotation, source.borrow().rotated(std.math.nan(f32)));
    try std.testing.expectError(error.InvalidRotation, source.borrow().rotated(std.math.inf(f32)));
}

test "rotation validation bounds native arithmetic before allocation" {
    const std = @import("std");
    try validate_rotation(0, 4096, 4096, 16384);
    try validate_rotation(-360, 1, 1, 4);
    try std.testing.expectError(error.RotationTooLarge, validate_rotation(45, 4097, 4096, 16388));
    try std.testing.expectError(error.RotationTooLarge, validate_rotation(45, 0, 1, 4));
    try std.testing.expectError(
        error.RotationTooLarge,
        validate_rotation(45, 1, 2, std.math.maxInt(c_int)),
    );
    try std.testing.expectError(
        error.InvalidRotation,
        validate_rotation(std.math.floatMax(f32), 1, 1, 4),
    );
}

test "floating surface colors preserve HDR and clear ignores and restores clipping" {
    const std = @import("std");
    var surface = try Surface.init_format(.{ .width = 2, .height = 2 }, .rgba128_float);
    defer surface.deinit();
    const clip = try surface.borrow().set_clip(.{ .x = 0, .y = 0, .width = 1, .height = 1 });
    const hdr = FloatColor{ .r = 2, .g = 0.25, .b = -0.5, .a = 0.75 };
    try surface.borrow().clear(hdr);
    try std.testing.expectEqualDeep(clip, try surface.borrow().clip());
    try std.testing.expectEqualDeep(
        hdr,
        try surface.borrow().read_pixel_float(.{ .x = 1, .y = 1 }),
    );
    const changed = FloatColor{ .r = 4, .g = 0.125, .b = -1, .a = 0.5 };
    try surface.borrow().write_pixel_float(.{ .x = 1, .y = 1 }, changed);
    try std.testing.expectEqualDeep(
        changed,
        try surface.borrow().read_pixel_float(.{ .x = 1, .y = 1 }),
    );
    try std.testing.expectEqualDeep(
        hdr,
        try surface.borrow().read_pixel_float(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectError(
        error.OutOfBounds,
        surface.borrow().write_pixel_float(.{ .x = 2, .y = 0 }, changed),
    );
    try std.testing.expectError(
        error.OutOfBounds,
        surface.borrow().read_pixel_float(.{ .x = 0, .y = 2 }),
    );
    try std.testing.expectError(
        error.InvalidColor,
        surface.borrow().clear(.{ .r = std.math.nan(f32), .g = 0, .b = 0 }),
    );
    try std.testing.expectError(
        error.InvalidColor,
        surface.borrow().write_pixel_float(
            .{ .x = 1, .y = 1 },
            .{ .r = 0, .g = 0, .b = 0, .a = std.math.inf(f32) },
        ),
    );
    try std.testing.expectEqualDeep(
        changed,
        try surface.borrow().read_pixel_float(.{ .x = 1, .y = 1 }),
    );
    try std.testing.expectEqualDeep(clip, try surface.borrow().clip());
}

test "floating color conversion clamps integer storage and clear rejects locks" {
    const std = @import("std");
    var surface = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer surface.deinit();
    try surface.borrow().write_pixel_float(.{ .x = 0, .y = 0 }, .{ .r = 2, .g = -1, .b = 0.5 });
    try std.testing.expectEqualDeep(
        Color{ .r = 255, .g = 0, .b = 128 },
        try surface.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectEqual(
        @as(f32, 128.0 / 255.0),
        (try surface.borrow().read_pixel_float(.{ .x = 0, .y = 0 })).b,
    );
    var guard = try surface.borrow().lock_rgba();
    defer guard.deinit();
    try std.testing.expectError(
        error.AlreadyLocked,
        surface.borrow().clear(.{ .r = 0, .g = 0, .b = 0 }),
    );
}

test "premultiplication preserves alpha and state and distinguishes working spaces" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer source.deinit();
    const half = Color{ .r = 255, .g = 0, .b = 0, .a = 128 };
    try source.borrow().fill(half);
    var linear = try source.borrow().duplicate();
    defer linear.deinit();
    const clip = try source.borrow().set_clip(.{ .width = 1, .height = 1 });
    try source.borrow().set_tint(.{ .r = 99 });
    try source.borrow().set_opacity(77);
    const blend = try source.borrow().blend_mode();
    try source.borrow().set_rle(true);
    try source.borrow().premultiply_alpha(.srgb);
    const encoded = try source.borrow().read_pixel(.{ .x = 1, .y = 0 });
    try std.testing.expectEqualDeep(Color{ .r = 128, .g = 0, .b = 0, .a = 128 }, encoded);
    try std.testing.expectEqualDeep(clip, try source.borrow().clip());
    try std.testing.expectEqual(@as(u8, 99), (try source.borrow().tint()).r);
    try std.testing.expectEqual(@as(u8, 77), try source.borrow().opacity());
    try std.testing.expectEqual(blend, try source.borrow().blend_mode());
    try linear.borrow().premultiply_alpha(.linear_srgb);
    const light = try linear.borrow().read_pixel(.{ .x = 0, .y = 0 });
    try std.testing.expect(light.r > encoded.r);
    try std.testing.expectEqual(@as(u8, 128), light.a);
    try source.borrow().premultiply_alpha(.srgb);
    try std.testing.expectEqual(
        @as(u8, 64),
        (try source.borrow().read_pixel(.{ .x = 1, .y = 0 })).r,
    );
    var guard = try source.borrow().lock_rgba();
    defer guard.deinit();
    try std.testing.expectError(error.AlreadyLocked, source.borrow().premultiply_alpha(.srgb));
}

test "colorspace labels preserve pixels while conversion changes their encoding" {
    const std = @import("std");
    const Colorspace = @import("pixels.zig").Colorspace;
    var source = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer source.deinit();
    try std.testing.expectEqual(Colorspace.srgb, source.borrow().colorspace());
    const gray = Color{ .r = 128, .g = 128, .b = 128 };
    try source.borrow().fill(gray);
    const custom: Colorspace = @fromBackingInt(@as(u32, 0x12345678));
    try source.borrow().set_colorspace(custom);
    try std.testing.expectEqual(custom, source.borrow().colorspace());
    try std.testing.expectEqualDeep(gray, try source.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try source.borrow().set_colorspace(.srgb);
    var linear = try source.borrow().converted(.{
        .format = .rgba128_float,
        .colorspace = .srgb_linear,
    });
    defer linear.deinit();
    try std.testing.expectEqual(Colorspace.srgb_linear, linear.borrow().colorspace());
    const sample = try linear.borrow().read_pixel_float(.{ .x = 0, .y = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 0.21586), sample.r, 0.001);
    try std.testing.expectEqualDeep(gray, try source.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try source.borrow().fill(.{ .r = 0, .g = 0, .b = 0 });
    try std.testing.expectEqualDeep(
        sample,
        try linear.borrow().read_pixel_float(.{ .x = 0, .y = 0 }),
    );
    try std.testing.expectError(
        error.SdlFailure,
        source.borrow().converted(.{ .format = .unknown, .colorspace = .srgb }),
    );
    var guard = try source.borrow().lock_rgba();
    defer guard.deinit();
    try std.testing.expectError(
        error.AlreadyLocked,
        source.borrow().converted(.{ .format = .rgba128_float, .colorspace = .srgb_linear }),
    );
}

test "explicit indexed conversion retains the selected palette" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer source.deinit();
    const red = Color{ .r = 255, .g = 0, .b = 0 };
    try source.borrow().fill(red);
    var output = block: {
        var palette_owner = try @import("pixels.zig").Palette.init(2);
        defer palette_owner.deinit();
        try palette_owner.borrow().set_colors(0, &.{ .{ .r = 0, .g = 0, .b = 0 }, red });
        break :block try source.borrow().converted(.{
            .format = .index8,
            .colorspace = .srgb,
            .palette = palette_owner.borrow(),
        });
    };
    defer output.deinit();
    try std.testing.expectEqualDeep(red, try output.borrow().read_pixel(.{ .x = 0, .y = 0 }));
    try std.testing.expectEqual(@as(usize, 2), output.borrow().palette().?.len());
}

test "alternate lists borrow retained images and attachment rejects reference cycles" {
    const std = @import("std");
    var base = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer base.deinit();
    try std.testing.expect(!base.borrow().has_alternates());
    {
        var alternate = try Surface.init_rgba(.{ .width = 2, .height = 2 });
        defer alternate.deinit();
        try alternate.borrow().fill(.{ .r = 255, .g = 0, .b = 0 });
        try base.borrow().add_alternate(&alternate);
        try std.testing.expectError(error.AlternateCycle, alternate.borrow().add_alternate(&base));
        try std.testing.expectError(error.AlternateCycle, base.borrow().add_alternate(&base));
    }
    try std.testing.expect(base.borrow().has_alternates());
    {
        var list = try base.borrow().images();
        defer list.deinit();
        try std.testing.expectEqual(@as(usize, 2), list.count);
        try std.testing.expectEqual(base.handle, (try list.get(0)).handle);
        const alternate = try list.get(1);
        try std.testing.expectEqual(@as(u32, 2), alternate.size().width);
        try std.testing.expectEqual(
            @as(u8, 255),
            (try alternate.read_pixel(.{ .x = 0, .y = 0 })).r,
        );
        try std.testing.expectError(error.OutOfBounds, list.get(2));
    }
    base.borrow().remove_alternates();
    try std.testing.expect(!base.borrow().has_alternates());
    var remaining = try base.borrow().images();
    defer remaining.deinit();
    try std.testing.expectEqual(@as(usize, 1), remaining.count);
}

test "alternate graph validation bounds breadth before changing the destination" {
    const std = @import("std");
    var base = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer base.deinit();
    var candidate = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer candidate.deinit();
    var leaf = try Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer leaf.deinit();
    for (0..257) |_| try candidate.borrow().add_alternate(&leaf);
    try std.testing.expectError(
        error.AlternateGraphTooLarge,
        base.borrow().add_alternate(&candidate),
    );
    try std.testing.expect(!base.borrow().has_alternates());
}

test "tiled blits repeat partial edge tiles and restart at destination clip origin" {
    const std = @import("std");
    var tile = try Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer tile.deinit();
    try tile.borrow().set_blend_mode(.none);
    try tile.borrow().write_pixel(.{ .x = 0, .y = 0 }, .{ .r = 10, .g = 0, .b = 0 });
    try tile.borrow().write_pixel(.{ .x = 1, .y = 0 }, .{ .r = 20, .g = 0, .b = 0 });
    var output = try Surface.init_rgba(.{ .width = 5, .height = 3 });
    defer output.deinit();
    try tile.borrow().blit_tiled_to(output.borrow(), &.{});
    for (0..3) |y| for (0..5) |x| {
        const pixel = try output.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) });
        try std.testing.expectEqual(@as(u8, if (x % 2 == 0) 10 else 20), pixel.r);
    };
    try output.borrow().clear(.{ .r = 0, .g = 0, .b = 0 });
    _ = try output.borrow().set_clip(.{ .x = 1, .y = 0, .width = 3, .height = 2 });
    try tile.borrow().blit_tiled_to(output.borrow(), &.{
        .destination = .{ .x = -1, .y = 0, .width = 6, .height = 3 },
    });
    try std.testing.expectEqual(
        @as(u8, 10),
        (try output.borrow().read_pixel(.{ .x = 1, .y = 0 })).r,
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        (try output.borrow().read_pixel(.{ .x = 4, .y = 0 })).r,
    );
    try tile.borrow().blit_tiled_to(output.borrow(), &.{
        .source = .{ .x = 99, .width = 1, .height = 1 },
    });
    try std.testing.expectError(
        error.AliasedSurface,
        tile.borrow().blit_tiled_to(tile.borrow(), &.{}),
    );
    var guard = try output.borrow().lock_rgba();
    defer guard.deinit();
    try std.testing.expectError(
        error.AlreadyLocked,
        tile.borrow().blit_tiled_to(output.borrow(), &.{}),
    );
}

test "scaled tiling validates rounded extents and partial source edge pixels" {
    const std = @import("std");
    var tile = try Surface.init_rgba(.{ .width = 2, .height = 1 });
    defer tile.deinit();
    try tile.borrow().set_blend_mode(.none);
    try tile.borrow().write_pixel(.{ .x = 0, .y = 0 }, .{ .r = 10, .g = 0, .b = 0 });
    try tile.borrow().write_pixel(.{ .x = 1, .y = 0 }, .{ .r = 20, .g = 0, .b = 0 });
    var output = try Surface.init_rgba(.{ .width = 6, .height = 2 });
    defer output.deinit();
    try tile.borrow().blit_tiled_scaled_to(output.borrow(), &.{ .scale = 2, .mode = .nearest });
    for (0..2) |y| for (0..6) |x| {
        const pixel = try output.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) });
        try std.testing.expectEqual(@as(u8, if ((x / 2) % 2 == 0) 10 else 20), pixel.r);
    };
    try output.borrow().clear(.{ .r = 0, .g = 0, .b = 0 });
    try tile.borrow().set_rle(true);
    const saved_clip = try output.borrow().clip();
    try tile.borrow().blit_tiled_scaled_to(output.borrow(), &.{
        .scale = 2,
        .mode = .nearest,
        .destination = .{ .width = 5, .height = 1 },
    });
    try std.testing.expectEqualDeep(saved_clip, try output.borrow().clip());
    for (0..5) |x| {
        const pixel = try output.borrow().read_pixel(.{ .x = @intCast(x), .y = 0 });
        try std.testing.expectEqual(@as(u8, if ((x / 2) % 2 == 0) 10 else 20), pixel.r);
    }
    try std.testing.expectEqual(
        @as(u8, 0),
        (try output.borrow().read_pixel(.{ .x = 5, .y = 0 })).r,
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        (try output.borrow().read_pixel(.{ .x = 0, .y = 1 })).r,
    );
    try output.borrow().clear(.{ .r = 0, .g = 0, .b = 0 });
    for ([_]f32{ -1, std.math.nan(f32), std.math.inf(f32), std.math.floatMax(f32) }) |scale| {
        try std.testing.expectError(
            error.InvalidTileScale,
            tile.borrow().blit_tiled_scaled_to(
                output.borrow(),
                &.{ .scale = scale, .mode = .nearest },
            ),
        );
    }
    for ([_]f32{ 0, 0.01 }) |scale| {
        try tile.borrow().blit_tiled_scaled_to(
            output.borrow(),
            &.{ .scale = scale, .mode = .nearest },
        );
    }
    try std.testing.expectEqual(
        @as(u8, 0),
        (try output.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
}

test "nine-grid preserves scaled corners and stretches edges and center" {
    const std = @import("std");
    var source = try Surface.init_rgba(.{ .width = 3, .height = 3 });
    defer source.deinit();
    try source.borrow().set_blend_mode(.none);
    for (0..3) |y| for (0..3) |x| {
        try source.borrow().write_pixel(
            .{ .x = @intCast(x), .y = @intCast(y) },
            .{ .r = @intCast(1 + x + y * 3), .g = 0, .b = 0 },
        );
    };
    var output = try Surface.init_rgba(.{ .width = 7, .height = 7 });
    defer output.deinit();
    const borders = GridBorders{ .left = 1, .right = 1, .top = 1, .bottom = 1 };
    try source.borrow().set_rle(true);
    try source.borrow().blit_nine_grid_to(output.borrow(), &.{
        .borders = borders,
        .corner_scale = 2,
        .mode = .nearest,
    });
    for (0..7) |y| for (0..7) |x| {
        const sx: u8 = if (x < 2) 0 else if (x >= 5) 2 else 1;
        const sy: u8 = if (y < 2) 0 else if (y >= 5) 2 else 1;
        try std.testing.expectEqual(
            @as(u8, 1 + sx + sy * 3),
            (try output.borrow().read_pixel(.{ .x = @intCast(x), .y = @intCast(y) })).r,
        );
    };
    try output.borrow().clear(.{ .r = 0, .g = 0, .b = 0 });
    try std.testing.expectError(
        error.InvalidGrid,
        source.borrow().blit_nine_grid_to(output.borrow(), &.{
            .borders = .{ .left = 4 },
            .mode = .nearest,
        }),
    );
    try std.testing.expectError(
        error.InvalidGrid,
        source.borrow().blit_nine_grid_to(output.borrow(), &.{
            .borders = borders,
            .corner_scale = 4,
            .mode = .nearest,
        }),
    );
    try std.testing.expectError(
        error.InvalidGrid,
        source.borrow().blit_nine_grid_to(output.borrow(), &.{
            .borders = .{ .left = 3 },
            .mode = .nearest,
        }),
    );
    try std.testing.expectError(
        error.InvalidGrid,
        source.borrow().blit_nine_grid_to(output.borrow(), &.{
            .borders = borders,
            .corner_scale = std.math.nan(f32),
            .mode = .nearest,
        }),
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        (try output.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
    try source.borrow().blit_nine_grid_to(output.borrow(), &.{
        .borders = borders,
        .corner_scale = 0,
        .mode = .nearest,
    });
    try std.testing.expectEqual(
        @as(u8, 1),
        (try output.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
    );
    try std.testing.expectEqual(
        @as(u8, 5),
        (try output.borrow().read_pixel(.{ .x = 1, .y = 1 })).r,
    );
}
