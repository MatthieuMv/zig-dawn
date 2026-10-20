//! SDL_ttf: font/text rendering. Requires the corresponding optional build dependency.
//! Initialize a Context, open a Font, then measure/render UTF-8 through a borrowed FontRef.
//! Close fonts before their context and borrowed streams. Surfaces own their rendered pixels.
//! Wrapper operations use the main thread; native text shaping and caches may allocate/block.
/// Native C declarations sharing core SDL type identity. No Zig ownership or validation layer.
/// Native resources must use their matching native destroy function and documented lifetime.
pub const raw = @import("sdl_abi");

/// Return the linked SDL_ttf runtime version, without initializing the library.
/// Encoding: `major * 1_000_000 + minor * 1_000 + patch`. Callable from any thread.
/// No wrapper allocation or fallible result; the value does not establish codec availability.
pub fn version() u32 {
    return @intCast(raw.TTF_Version());
}

test "native version matches header major and meets header version" {
    try std.testing.expect(@import("sdl").raw.SDL_Surface == raw.SDL_Surface);
    try std.testing.expectEqual(@as(u32, 3), version() / 1_000_000);
    try std.testing.expect(version() >= raw.SDL_TTF_VERSION);
}

const std = @import("std");
const sdl = @import("sdl");

/// Native failures plus checked input errors. Validation failures do not set SDL diagnostic text.
pub const Error = sdl.errors.Error || error{
    /// Point size must be positive and finite.
    InvalidPointSize,
    /// Text must be valid UTF-8 without embedded NUL bytes.
    InvalidText,
    /// An empty string has no surface to render; measurement still accepts it.
    EmptyText,
};

/// Font creation parameters. DPI, faces, and variable-font axes retain native defaults.
pub const FontOptions = struct {
    /// Positive finite point size. Bitmap .fon fonts interpret this as a strike index instead.
    /// Native rasterization determines pixel dimensions; this is not a pixel-height guarantee.
    size_points: f32,
};

/// Acquire one SDL_ttf initialization reference on the main thread (wrapper contract).
/// No video initialization is required. Native code may allocate; `SdlFailure` returns no owner.
/// Close all fonts using this context before deinit; the caller owns global SDL shutdown.
pub fn init() sdl.errors.Error!Context {
    if (!raw.TTF_Init()) return error.SdlFailure;
    return .{};
}

/// Owns one initialization reference, not the fonts created through it. Do not copy.
/// Keep this context alive until all its fonts close; never balance it with a raw TTF_Quit call.
pub const Context = struct {
    /// Release this reference on the main thread, after closing its fonts. Call exactly once.
    /// Does not close live fonts. No fallible result; invalidates this owner.
    pub fn deinit(self: *Context) void {
        raw.TTF_Quit();
        self.* = undefined;
    }

    /// Open a font from a UTF-8 sentinel path borrowed for the call; relative paths use the cwd.
    /// The context must remain alive until the font closes. Create and use fonts on the main
    /// thread under this wrapper's contract. Native font loading/caching may allocate and block.
    /// `InvalidPointSize` precedes native calls; `SdlFailure` returns no owner. Read SDL errors.
    ///
    /// ```zig
    /// const ttf = @import("sdl_ttf");
    /// // Documentation-test fixture; replace with your application's font path.
    /// const path = @import("example_assets").font_path ++ "";
    /// var context = try ttf.init();
    /// defer context.deinit();
    /// var font = try context.open_font(path, .{ .size_points = 24 });
    /// defer font.deinit();
    /// const size = try font.borrow().measure("Aé");
    /// var surface = try font.borrow().render("Aé", .{ .r = 255, .g = 255, .b = 255 });
    /// defer surface.deinit();
    /// try @import("std").testing.expectEqual(size.width, surface.borrow().size().width);
    /// // Upload with sdl.render.Texture.from_surface when a renderer is available.
    /// ```
    pub fn open_font(self: *const Context, path: [:0]const u8, options: FontOptions) Error!Font {
        _ = self;
        try validate_options(options);
        const handle = raw.TTF_OpenFont(path.ptr, options.size_points) orelse
            return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Open a font borrowing a seekable stream from its current position. Main thread only.
    /// The stream AND its backing memory must outlive the font, with no other access until the
    /// font closes: decoding can read lazily. The context must also remain alive. This operation
    /// never closes the stream, even on failure; failure may change its cursor.
    /// `InvalidPointSize` precedes native calls; `SdlFailure` returns no font. Native code may
    /// allocate/block without a resource budget. Close font, then stream, then context.
    pub fn open_font_stream(
        self: *const Context,
        stream: sdl.io.StreamRef,
        options: FontOptions,
    ) Error!Font {
        _ = self;
        try validate_options(options);
        const handle = raw.TTF_OpenFontIO(stream.handle, false, options.size_points) orelse
            return error.SdlFailure;
        return .{ .handle = handle };
    }
};

/// Owns a font and its native caches. Do not copy. Context and any borrowed stream outlive it.
pub const Font = struct {
    /// Native interop handle. Never close separately or mutate it concurrently with wrapper calls.
    handle: *raw.TTF_Font,

    /// Close on the main thread before its context and any borrowed stream. Call exactly once.
    /// Invalidates font/views; rendered surfaces remain valid. No fallible result.
    pub fn deinit(self: *Font) void {
        raw.TTF_CloseFont(self.handle);
        self.* = undefined;
    }

    /// Borrow without native calls/allocation. Does not retain font, context, or backing stream.
    pub fn borrow(self: *const Font) FontRef {
        return .{ .handle = self.handle };
    }
};

/// Copyable view of a live font. All operations require the main thread under this API contract.
/// Text slices need no sentinel; calls borrow them only until return. Native caches may allocate.
pub const FontRef = struct {
    /// Live native font; never close it through a borrowed view.
    handle: *raw.TTF_Font,

    /// Measure single-line UTF-8 text in pixels; no wrapping or newline layout is performed.
    /// Accepts an empty slice safely (width zero); height follows native font metrics.
    /// `InvalidText` rejects malformed UTF-8 or embedded NUL before native work. `SdlFailure`
    /// reports native measurement failure. May allocate/block in native shaping or glyph caches.
    pub fn measure(self: FontRef, text: []const u8) Error!sdl.video.Size {
        try validate_text(text);
        var width: c_int = 0;
        var height: c_int = 0;
        // Native length zero means strlen, so never pass an arbitrary empty slice pointer.
        const pointer = if (text.len == 0) "".ptr else text.ptr;
        if (!raw.TTF_GetStringSize(self.handle, pointer, text.len, &width, &height)) {
            return error.SdlFailure;
        }
        if (width < 0 or height < 0) return error.SdlFailure;
        return .{ .width = @intCast(width), .height = @intCast(height) };
    }

    /// Render one line of UTF-8 to an owned, antialiased 32-bit ARGB CPU surface.
    /// Color uses eight-bit channels; glyph coverage modulates alpha. No newline/word wrapping.
    /// The surface owns its pixels independently of font/context and must be released with deinit.
    /// Upload via `sdl.render.Texture.from_surface` for drawing. Do not assume RGBA byte order.
    /// `InvalidText` and `EmptyText` precede rendering; `SdlFailure` returns no surface owner.
    /// Native shaping, caches, and surface storage may allocate/block without a size/work budget.
    pub fn render(
        self: FontRef,
        text: []const u8,
        color: sdl.render.Color,
    ) Error!sdl.surface.Surface {
        try validate_text(text);
        if (text.len == 0) return error.EmptyText;
        const handle = raw.TTF_RenderText_Blended(self.handle, text.ptr, text.len, .{
            .r = color.r,
            .g = color.g,
            .b = color.b,
            .a = color.a,
        }) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }
};

fn validate_options(options: FontOptions) Error!void {
    if (!std.math.isFinite(options.size_points) or options.size_points <= 0) {
        return error.InvalidPointSize;
    }
}

fn validate_text(text: []const u8) Error!void {
    if (std.mem.indexOfScalar(u8, text, 0) != null or !std.unicode.utf8ValidateSlice(text)) {
        return error.InvalidText;
    }
}
