//! Pixel-format identities and copied metadata. No SDL subsystem initialization is required.
//! Packed integer channel order differs from byte order on little-endian targets. Use the *32
//! aliases for explicitly ordered byte arrays. Storage sizes here do not compute image allocation,
//! row pitch, plane offsets, compression, colorspace, or backend format support.
const c = @import("sdl_abi");
const std = @import("std");
const Error = @import("errors.zig").Error;

/// Eight-bit RGBA value shared with renderer and surface operations; C-compatible field layout.
pub const Color = @import("render.zig").Color;

/// Component model: RGB or luma/chroma.
/// Unknown field-sized values survive extraction and construction. No native calls or allocation.
pub const ColorType = enum(u4) {
    /// Unknown identity.
    unknown = c.SDL_COLOR_TYPE_UNKNOWN,
    /// Red, green, blue components.
    rgb = c.SDL_COLOR_TYPE_RGB,
    /// Luma and blue/red chroma difference components.
    ycbcr = c.SDL_COLOR_TYPE_YCBCR,
    _,
};

/// Encoded component range; unknown values do not establish valid limits.
/// Unknown field-sized values survive extraction and construction. No native calls or allocation.
pub const ColorRange = enum(u4) {
    /// Unknown identity.
    unknown = c.SDL_COLOR_RANGE_UNKNOWN,
    /// Narrow range, e.g. 16-235 for 8-bit RGB and luma, and 16-240 for 8-bit chroma
    limited = c.SDL_COLOR_RANGE_LIMITED,
    /// Full range, e.g. 0-255 for 8-bit RGB and luma, and 1-255 for 8-bit chroma
    full = c.SDL_COLOR_RANGE_FULL,
    _,
};

/// Chromaticity primaries identity; does not itself supply a conversion matrix.
/// Unknown field-sized values survive extraction and construction. No native calls or allocation.
pub const ColorPrimaries = enum(u5) {
    /// Unknown identity.
    unknown = c.SDL_COLOR_PRIMARIES_UNKNOWN,
    /// ITU-R BT.709-6
    bt709 = c.SDL_COLOR_PRIMARIES_BT709,
    /// Encoding leaves this identity unspecified.
    unspecified = c.SDL_COLOR_PRIMARIES_UNSPECIFIED,
    /// ITU-R BT.470-6 System M
    bt470m = c.SDL_COLOR_PRIMARIES_BT470M,
    /// ITU-R BT.470-6 System B, G / ITU-R BT.601-7 625
    bt470bg = c.SDL_COLOR_PRIMARIES_BT470BG,
    /// ITU-R BT.601-7 525, SMPTE 170M
    bt601 = c.SDL_COLOR_PRIMARIES_BT601,
    /// SMPTE 240M, functionally the same as SDL_COLOR_PRIMARIES_BT601
    smpte240 = c.SDL_COLOR_PRIMARIES_SMPTE240,
    /// Generic film (color filters using Illuminant C)
    generic_film = c.SDL_COLOR_PRIMARIES_GENERIC_FILM,
    /// ITU-R BT.2020-2 / ITU-R BT.2100-0
    bt2020 = c.SDL_COLOR_PRIMARIES_BT2020,
    /// SMPTE ST 428-1
    xyz = c.SDL_COLOR_PRIMARIES_XYZ,
    /// SMPTE RP 431-2
    smpte431 = c.SDL_COLOR_PRIMARIES_SMPTE431,
    /// SMPTE EG 432-1 / DCI P3
    smpte432 = c.SDL_COLOR_PRIMARIES_SMPTE432,
    /// EBU Tech. 3213-E
    ebu3213 = c.SDL_COLOR_PRIMARIES_EBU3213,
    /// Custom encoding identity; interpretation requires external metadata.
    custom = c.SDL_COLOR_PRIMARIES_CUSTOM,
    _,
};

/// Transfer-function identity; does not apply the function to pixel values.
/// Unknown field-sized values survive extraction and construction. No native calls or allocation.
pub const TransferCharacteristics = enum(u5) {
    /// Unknown identity.
    unknown = c.SDL_TRANSFER_CHARACTERISTICS_UNKNOWN,
    /// Rec. ITU-R BT.709-6 / ITU-R BT1361
    bt709 = c.SDL_TRANSFER_CHARACTERISTICS_BT709,
    /// Encoding leaves this identity unspecified.
    unspecified = c.SDL_TRANSFER_CHARACTERISTICS_UNSPECIFIED,
    /// ITU-R BT.470-6 System M / ITU-R BT1700 625 PAL & SECAM
    gamma22 = c.SDL_TRANSFER_CHARACTERISTICS_GAMMA22,
    /// ITU-R BT.470-6 System B, G
    gamma28 = c.SDL_TRANSFER_CHARACTERISTICS_GAMMA28,
    /// SMPTE ST 170M / ITU-R BT.601-7 525 or 625
    bt601 = c.SDL_TRANSFER_CHARACTERISTICS_BT601,
    /// SMPTE ST 240M
    smpte240 = c.SDL_TRANSFER_CHARACTERISTICS_SMPTE240,
    /// Linear transfer without nonlinear encoding.
    linear = c.SDL_TRANSFER_CHARACTERISTICS_LINEAR,
    /// Logarithmic transfer with 100:1 range.
    log100 = c.SDL_TRANSFER_CHARACTERISTICS_LOG100,
    /// Logarithmic transfer with 100 times square-root-of-ten range.
    log100_sqrt10 = c.SDL_TRANSFER_CHARACTERISTICS_LOG100_SQRT10,
    /// IEC 61966-2-4
    iec61966 = c.SDL_TRANSFER_CHARACTERISTICS_IEC61966,
    /// ITU-R BT1361 Extended Colour Gamut
    bt1361 = c.SDL_TRANSFER_CHARACTERISTICS_BT1361,
    /// IEC 61966-2-1 (sRGB or sYCC)
    srgb = c.SDL_TRANSFER_CHARACTERISTICS_SRGB,
    /// ITU-R BT2020 for 10-bit system
    bt2020_10bit = c.SDL_TRANSFER_CHARACTERISTICS_BT2020_10BIT,
    /// ITU-R BT2020 for 12-bit system
    bt2020_12bit = c.SDL_TRANSFER_CHARACTERISTICS_BT2020_12BIT,
    /// SMPTE ST 2084 for 10-, 12-, 14- and 16-bit systems
    pq = c.SDL_TRANSFER_CHARACTERISTICS_PQ,
    /// SMPTE ST 428-1
    smpte428 = c.SDL_TRANSFER_CHARACTERISTICS_SMPTE428,
    /// ARIB STD-B67, known as "hybrid log-gamma" (HLG)
    hlg = c.SDL_TRANSFER_CHARACTERISTICS_HLG,
    /// Custom encoding identity; interpretation requires external metadata.
    custom = c.SDL_TRANSFER_CHARACTERISTICS_CUSTOM,
    _,
};

/// RGB/luma-chroma matrix identity.
/// Unknown field-sized values survive extraction and construction. No native calls or allocation.
pub const MatrixCoefficients = enum(u5) {
    /// identity.
    identity = c.SDL_MATRIX_COEFFICIENTS_IDENTITY,
    /// ITU-R BT.709-6
    bt709 = c.SDL_MATRIX_COEFFICIENTS_BT709,
    /// Encoding leaves this identity unspecified.
    unspecified = c.SDL_MATRIX_COEFFICIENTS_UNSPECIFIED,
    /// US FCC Title 47
    fcc = c.SDL_MATRIX_COEFFICIENTS_FCC,
    /// ITU-R BT.470-6 System B, G / ITU-R BT.601-7 625, functionally the same as
    /// SDL_MATRIX_COEFFICIENTS_BT601
    bt470bg = c.SDL_MATRIX_COEFFICIENTS_BT470BG,
    /// ITU-R BT.601-7 525
    bt601 = c.SDL_MATRIX_COEFFICIENTS_BT601,
    /// SMPTE 240M
    smpte240 = c.SDL_MATRIX_COEFFICIENTS_SMPTE240,
    /// YCgCo color difference matrix.
    ycgco = c.SDL_MATRIX_COEFFICIENTS_YCGCO,
    /// ITU-R BT.2020-2 non-constant luminance
    bt2020_ncl = c.SDL_MATRIX_COEFFICIENTS_BT2020_NCL,
    /// ITU-R BT.2020-2 constant luminance
    bt2020_cl = c.SDL_MATRIX_COEFFICIENTS_BT2020_CL,
    /// SMPTE ST 2085
    smpte2085 = c.SDL_MATRIX_COEFFICIENTS_SMPTE2085,
    /// Chroma-derived non-constant-luminance matrix.
    chroma_derived_ncl = c.SDL_MATRIX_COEFFICIENTS_CHROMA_DERIVED_NCL,
    /// Chroma-derived constant-luminance matrix.
    chroma_derived_cl = c.SDL_MATRIX_COEFFICIENTS_CHROMA_DERIVED_CL,
    /// ITU-R BT.2100-0 ICTCP
    ictcp = c.SDL_MATRIX_COEFFICIENTS_ICTCP,
    /// Custom encoding identity; interpretation requires external metadata.
    custom = c.SDL_MATRIX_COEFFICIENTS_CUSTOM,
    _,
};

/// Chroma sample position relative to a luma sample group.
/// Unknown field-sized values survive extraction and construction. No native calls or allocation.
pub const ChromaLocation = enum(u4) {
    /// RGB, no chroma sampling
    none = c.SDL_CHROMA_LOCATION_NONE,
    /// In MPEG-2, MPEG-4, and AVC, Cb and Cr are taken on midpoint of the left-edge of the 2x2
    /// square. In other words, they have the same horizontal location as the top-left pixel, but
    /// is shifted one-half pixel down vertically.
    left = c.SDL_CHROMA_LOCATION_LEFT,
    /// In JPEG/JFIF, H.261, and MPEG-1, Cb and Cr are taken at the center of the 2x2 square. In
    /// other words, they are offset one-half pixel to the right and one-half pixel down compared
    /// to the top-left pixel.
    center = c.SDL_CHROMA_LOCATION_CENTER,
    /// In HEVC for BT.2020 and BT.2100 content (in particular on Blu-rays), Cb and Cr are sampled
    /// at the same location as the group's top-left Y pixel ("co-sited", "co-located").
    topleft = c.SDL_CHROMA_LOCATION_TOPLEFT,
    _,
};

/// Lossless decomposition of a packed colorspace identity. Unknown component values and reserved
/// bits are retained; constructing a value does not validate compatibility or native support.
pub const ColorComponents = struct {
    /// Component model, normally RGB or YCbCr.
    kind: ColorType,
    /// Encoded range identity.
    range: ColorRange,
    /// Primaries identity.
    primaries: ColorPrimaries,
    /// Transfer-function identity.
    transfer: TransferCharacteristics,
    /// Matrix identity.
    matrix: MatrixCoefficients,
    /// Chroma sample position.
    chroma: ChromaLocation,
    /// Bits 15..19, unused by pinned SDL; preserved for future numeric round trips.
    reserved: u5 = 0,
};

/// Native color encoding identity. Unknown/custom integers are preserved; naming an encoding does
/// not guarantee format compatibility, native conversion support, or display HDR capability.
pub const Colorspace = enum(u32) {
    /// Unspecified encoding; not proof of a usable conversion.
    unknown = c.SDL_COLORSPACE_UNKNOWN,
    /// Full-range nonlinear sRGB with BT.709 primaries; typical eight-bit RGB default.
    srgb = c.SDL_COLORSPACE_SRGB,
    /// Linear sRGB with BT.709 primaries; native floating-point default.
    srgb_linear = c.SDL_COLORSPACE_SRGB_LINEAR,
    /// Full-range RGB with BT.2020 primaries and PQ transfer for HDR10.
    hdr10 = c.SDL_COLORSPACE_HDR10,
    /// Full-range YCbCr, BT.709 primaries and BT.601 matrix/transfer; JPEG convention.
    jpeg = c.SDL_COLORSPACE_JPEG,
    /// Limited-range BT.601 YCbCr with left-sited chroma.
    bt601_limited = c.SDL_COLORSPACE_BT601_LIMITED,
    /// Full-range BT.601 YCbCr with left-sited chroma.
    bt601_full = c.SDL_COLORSPACE_BT601_FULL,
    /// Limited-range BT.709 YCbCr with left-sited chroma.
    bt709_limited = c.SDL_COLORSPACE_BT709_LIMITED,
    /// Full-range BT.709 YCbCr with left-sited chroma.
    bt709_full = c.SDL_COLORSPACE_BT709_FULL,
    /// Limited-range BT.2020 YCbCr with PQ transfer and left-sited chroma.
    bt2020_limited = c.SDL_COLORSPACE_BT2020_LIMITED,
    /// Full-range BT.2020 YCbCr with PQ transfer and left-sited chroma.
    bt2020_full = c.SDL_COLORSPACE_BT2020_FULL,
    _,

    /// Split the packed identity without validation, native calls, or allocation. Any thread.
    /// Reserved bits and unknown component values survive a from_components round trip.
    pub fn components(self: Colorspace) ColorComponents {
        const value = @backingInt(self);
        return .{
            .kind = @fromBackingInt(@as(u4, @truncate(value >> 28))),
            .range = @fromBackingInt(@as(u4, @truncate(value >> 24))),
            .chroma = @fromBackingInt(@as(u4, @truncate(value >> 20))),
            .primaries = @fromBackingInt(@as(u5, @truncate(value >> 10))),
            .transfer = @fromBackingInt(@as(u5, @truncate(value >> 5))),
            .matrix = @fromBackingInt(@as(u5, @truncate(value))),
            .reserved = @truncate(value >> 15),
        };
    }

    /// Pack typed field-width components without allocation or validation of their meaning.
    /// No SDL subsystem is needed. Native conversion/display support must be checked separately.
    ///
    /// ```zig
    /// const p = @import("sdl").pixels;
    /// const value = p.Colorspace.from_components(.{
    ///     .kind = .rgb, .range = .full, .primaries = .bt709,
    ///     .transfer = .srgb, .matrix = .identity, .chroma = .none,
    /// });
    /// try @import("std").testing.expectEqual(p.Colorspace.srgb, value);
    /// ```
    pub fn from_components(value: ColorComponents) Colorspace {
        return @fromBackingInt(
            (@as(u32, @backingInt(value.kind)) << 28) |
                (@as(u32, @backingInt(value.range)) << 24) |
                (@as(u32, @backingInt(value.chroma)) << 20) |
                (@as(u32, value.reserved) << 15) |
                (@as(u32, @backingInt(value.primaries)) << 10) |
                (@as(u32, @backingInt(value.transfer)) << 5) |
                @as(u32, @backingInt(value.matrix)),
        );
    }

    /// True for BT.601 or BT.470BG matrix identities; does not inspect transfer/primaries.
    /// Pure identity query; no allocation or subsystem/thread restrictions.
    pub fn is_bt601_matrix(self: Colorspace) bool {
        const matrix = self.components().matrix;
        return matrix == .bt601 or matrix == .bt470bg;
    }

    /// True for the BT.709 matrix identity, independent of transfer/primaries.
    /// Pure identity query; no allocation or subsystem/thread restrictions.
    pub fn is_bt709_matrix(self: Colorspace) bool {
        return self.components().matrix == .bt709;
    }

    /// True for BT.2020 non-constant-luminance matrix only.
    /// Pure identity query; no allocation or subsystem/thread restrictions.
    pub fn is_bt2020_ncl_matrix(self: Colorspace) bool {
        return self.components().matrix == .bt2020_ncl;
    }

    /// True only for the full-range identity; unknown identities return false.
    /// Pure identity query; no allocation or subsystem/thread restrictions.
    pub fn is_full_range(self: Colorspace) bool {
        return self.components().range == .full;
    }

    /// Native predicate: true for every non-full range, including unknown/custom values.
    /// Use components().range == .limited to test specifically for the named limited range.
    /// Pure identity query; no allocation or subsystem/thread restrictions.
    pub fn is_limited_range(self: Colorspace) bool {
        return !self.is_full_range();
    }

    /// Native default alias for ordinary RGB surfaces; floating/10-bit defaults differ.
    pub const rgb_default: Colorspace = .srgb;
    /// Native default alias for ordinary YUV surfaces.
    pub const yuv_default: Colorspace = .bt601_limited;
};

/// Floating-point RGBA components. Conventional values are 0..1, but HDR/negative values may
/// be meaningful for a particular format/colorspace. This value does not imply linear light.
/// Surface write/clear methods reject nonfinite components before native conversion.
pub const FloatColor = extern struct {
    /// Red component in the operation's color encoding.
    r: f32,
    /// Green component in the operation's color encoding.
    g: f32,
    /// Blue component in the operation's color encoding.
    b: f32,
    /// Alpha coverage/opacity; defaults to fully opaque.
    a: f32 = 1,
};

/// Palette validation failures occur before native mutation and leave SDL diagnostics unchanged.
pub const PaletteError = Error || error{
    /// Palette count is zero or cannot fit native count/allocation arithmetic.
    InvalidPaletteSize,
    /// An index or complete update range falls outside the palette.
    OutOfBounds,
};

/// Owns one native palette reference. Do not copy; release exactly once with deinit.
/// Surfaces can retain additional references independently after set_palette succeeds.
pub const Palette = struct {
    /// Native interop handle; never destroy separately or edit read-only native metadata.
    handle: *c.SDL_Palette,

    /// Allocate count opaque-white entries without subsystem initialization. Any thread.
    /// InvalidPaletteSize rejects zero/unrepresentable allocation sizes before SDL; SdlFailure
    /// returns no owner on native allocation failure. Native storage may allocate; defer deinit.
    pub fn init(count: usize) PaletteError!Palette {
        if (count == 0 or count > std.math.maxInt(c_int) or
            count > std.math.maxInt(usize) / @sizeOf(c.SDL_Color)) return error.InvalidPaletteSize;
        const handle = c.SDL_CreatePalette(@intCast(count)) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Release this reference with exclusive access and no outstanding owner-borrowed users.
    /// Native storage survives if surfaces/textures retain references. Follow all sharer thread rules;
    /// texture/window-related palettes require main-thread use. Invalidates this Zig owner regardless.
    pub fn deinit(self: *Palette) void {
        c.SDL_DestroyPalette(self.handle);
        self.* = undefined;
    }

    /// Borrow without allocation/retention; finish this view before releasing its owning reference.
    pub fn borrow(self: *const Palette) PaletteRef {
        return .{ .handle = self.handle };
    }
};

/// Non-owning palette view. A live owner/reference must outlive use; synchronize with all sharing
/// surfaces/textures. Association-borrowed views expire on replacement/removal/destruction.
pub const PaletteRef = struct {
    /// Live native handle; never free it through a borrowed view or mutate raw colors/metadata.
    handle: *c.SDL_Palette,

    /// Query immutable entry count without allocation. Any thread permitted by the owner/sharers.
    /// Requires valid native metadata; raw interop must not replace count/storage.
    pub fn len(self: PaletteRef) usize {
        return @intCast(self.handle.ncolors);
    }

    /// Copy one entry with synchronized read access. OutOfBounds returns no color.
    /// Any thread permitted by owner/sharers, including main-thread-only texture/window associations.
    pub fn get(self: PaletteRef, index: usize) PaletteError!Color {
        if (index >= self.len()) return error.OutOfBounds;
        const value = self.handle.colors[index];
        return .{ .r = value.r, .g = value.g, .b = value.b, .a = value.a };
    }

    /// Copy a color range with exclusive access to the palette and all sharing surfaces/textures.
    /// Validates the full range before native mutation, preventing SDL's truncated partial update
    /// on overflow. Empty input at a valid boundary is a no-op.
    /// OutOfBounds leaves colors unchanged.
    /// Input is borrowed only for the call and must not alias native palette storage. No wrapper
    /// allocation. SdlFailure reports native failure; thread restrictions of all sharers apply.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var palette = try sdl.pixels.Palette.init(2);
    /// defer palette.deinit();
    /// try palette.borrow().set_colors(0, &.{
    ///     .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
    /// });
    /// try @import("std").testing.expectEqual(@as(u8, 255), (try palette.borrow().get(1)).r);
    /// ```
    pub fn set_colors(self: PaletteRef, first: usize, colors: []const Color) PaletteError!void {
        const count = self.len();
        if (first > count or colors.len > count - first) return error.OutOfBounds;
        if (colors.len == 0) return;
        comptime {
            std.debug.assert(@sizeOf(Color) == @sizeOf(c.SDL_Color));
            std.debug.assert(@alignOf(Color) == @alignOf(c.SDL_Color));
            for (.{ "r", "g", "b", "a" }) |field| {
                std.debug.assert(@offsetOf(Color, field) == @offsetOf(c.SDL_Color, field));
            }
        }
        if (!c.SDL_SetPaletteColors(
            self.handle,
            @ptrCast(colors.ptr),
            @intCast(first),
            @intCast(colors.len),
        )) return error.SdlFailure;
    }
};

/// Native pixel-format identity. Unknown future integers survive round trips; validity/support
/// must be checked by the consuming operation. X channels are unused, not alpha.
pub const Format = enum(u32) {
    /// No recognized pixel format.
    unknown = c.SDL_PIXELFORMAT_UNKNOWN,
    /// 1-bit palette indices; leftmost pixel uses least significant bits first.
    index1lsb = c.SDL_PIXELFORMAT_INDEX1LSB,
    /// 1-bit palette indices; leftmost pixel uses most significant bits first.
    index1msb = c.SDL_PIXELFORMAT_INDEX1MSB,
    /// 2-bit palette indices; leftmost pixel uses least significant bits first.
    index2lsb = c.SDL_PIXELFORMAT_INDEX2LSB,
    /// 2-bit palette indices; leftmost pixel uses most significant bits first.
    index2msb = c.SDL_PIXELFORMAT_INDEX2MSB,
    /// 4-bit palette indices; leftmost pixel uses least significant bits first.
    index4lsb = c.SDL_PIXELFORMAT_INDEX4LSB,
    /// 4-bit palette indices; leftmost pixel uses most significant bits first.
    index4msb = c.SDL_PIXELFORMAT_INDEX4MSB,
    /// 8-bit palette indices; one index per byte.
    index8 = c.SDL_PIXELFORMAT_INDEX8,
    /// Native-endian packed RGB332 channels, ordered from most to least significant bits.
    rgb332 = c.SDL_PIXELFORMAT_RGB332,
    /// Native-endian packed XRGB4444 channels, ordered from most to least significant bits.
    xrgb4444 = c.SDL_PIXELFORMAT_XRGB4444,
    /// Native-endian packed XBGR4444 channels, ordered from most to least significant bits.
    xbgr4444 = c.SDL_PIXELFORMAT_XBGR4444,
    /// Native-endian packed XRGB1555 channels, ordered from most to least significant bits.
    xrgb1555 = c.SDL_PIXELFORMAT_XRGB1555,
    /// Native-endian packed XBGR1555 channels, ordered from most to least significant bits.
    xbgr1555 = c.SDL_PIXELFORMAT_XBGR1555,
    /// Native-endian packed ARGB4444 channels, ordered from most to least significant bits.
    argb4444 = c.SDL_PIXELFORMAT_ARGB4444,
    /// Native-endian packed RGBA4444 channels, ordered from most to least significant bits.
    rgba4444 = c.SDL_PIXELFORMAT_RGBA4444,
    /// Native-endian packed ABGR4444 channels, ordered from most to least significant bits.
    abgr4444 = c.SDL_PIXELFORMAT_ABGR4444,
    /// Native-endian packed BGRA4444 channels, ordered from most to least significant bits.
    bgra4444 = c.SDL_PIXELFORMAT_BGRA4444,
    /// Native-endian packed ARGB1555 channels, ordered from most to least significant bits.
    argb1555 = c.SDL_PIXELFORMAT_ARGB1555,
    /// Native-endian packed RGBA5551 channels, ordered from most to least significant bits.
    rgba5551 = c.SDL_PIXELFORMAT_RGBA5551,
    /// Native-endian packed ABGR1555 channels, ordered from most to least significant bits.
    abgr1555 = c.SDL_PIXELFORMAT_ABGR1555,
    /// Native-endian packed BGRA5551 channels, ordered from most to least significant bits.
    bgra5551 = c.SDL_PIXELFORMAT_BGRA5551,
    /// Native-endian packed RGB565 channels, ordered from most to least significant bits.
    rgb565 = c.SDL_PIXELFORMAT_RGB565,
    /// Native-endian packed BGR565 channels, ordered from most to least significant bits.
    bgr565 = c.SDL_PIXELFORMAT_BGR565,
    /// RGB array order with 8-bit unsigned integer components.
    rgb24 = c.SDL_PIXELFORMAT_RGB24,
    /// BGR array order with 8-bit unsigned integer components.
    bgr24 = c.SDL_PIXELFORMAT_BGR24,
    /// Native-endian packed XRGB8888 channels, ordered from most to least significant bits.
    xrgb8888 = c.SDL_PIXELFORMAT_XRGB8888,
    /// Native-endian packed RGBX8888 channels, ordered from most to least significant bits.
    rgbx8888 = c.SDL_PIXELFORMAT_RGBX8888,
    /// Native-endian packed XBGR8888 channels, ordered from most to least significant bits.
    xbgr8888 = c.SDL_PIXELFORMAT_XBGR8888,
    /// Native-endian packed BGRX8888 channels, ordered from most to least significant bits.
    bgrx8888 = c.SDL_PIXELFORMAT_BGRX8888,
    /// Native-endian packed ARGB8888 channels, ordered from most to least significant bits.
    argb8888 = c.SDL_PIXELFORMAT_ARGB8888,
    /// Native-endian packed RGBA8888 channels, ordered from most to least significant bits.
    rgba8888 = c.SDL_PIXELFORMAT_RGBA8888,
    /// Native-endian packed ABGR8888 channels, ordered from most to least significant bits.
    abgr8888 = c.SDL_PIXELFORMAT_ABGR8888,
    /// Native-endian packed BGRA8888 channels, ordered from most to least significant bits.
    bgra8888 = c.SDL_PIXELFORMAT_BGRA8888,
    /// Native-endian packed XRGB2101010 channels, ordered from most to least significant bits.
    xrgb2101010 = c.SDL_PIXELFORMAT_XRGB2101010,
    /// Native-endian packed XBGR2101010 channels, ordered from most to least significant bits.
    xbgr2101010 = c.SDL_PIXELFORMAT_XBGR2101010,
    /// Native-endian packed ARGB2101010 channels, ordered from most to least significant bits.
    argb2101010 = c.SDL_PIXELFORMAT_ARGB2101010,
    /// Native-endian packed ABGR2101010 channels, ordered from most to least significant bits.
    abgr2101010 = c.SDL_PIXELFORMAT_ABGR2101010,
    /// RGB array order with 16-bit unsigned integer components.
    rgb48 = c.SDL_PIXELFORMAT_RGB48,
    /// BGR array order with 16-bit unsigned integer components.
    bgr48 = c.SDL_PIXELFORMAT_BGR48,
    /// RGBA array order with 16-bit unsigned integer components.
    rgba64 = c.SDL_PIXELFORMAT_RGBA64,
    /// ARGB array order with 16-bit unsigned integer components.
    argb64 = c.SDL_PIXELFORMAT_ARGB64,
    /// BGRA array order with 16-bit unsigned integer components.
    bgra64 = c.SDL_PIXELFORMAT_BGRA64,
    /// ABGR array order with 16-bit unsigned integer components.
    abgr64 = c.SDL_PIXELFORMAT_ABGR64,
    /// RGB array order with 16-bit floating-point components.
    rgb48_float = c.SDL_PIXELFORMAT_RGB48_FLOAT,
    /// BGR array order with 16-bit floating-point components.
    bgr48_float = c.SDL_PIXELFORMAT_BGR48_FLOAT,
    /// RGBA array order with 16-bit floating-point components.
    rgba64_float = c.SDL_PIXELFORMAT_RGBA64_FLOAT,
    /// ARGB array order with 16-bit floating-point components.
    argb64_float = c.SDL_PIXELFORMAT_ARGB64_FLOAT,
    /// BGRA array order with 16-bit floating-point components.
    bgra64_float = c.SDL_PIXELFORMAT_BGRA64_FLOAT,
    /// ABGR array order with 16-bit floating-point components.
    abgr64_float = c.SDL_PIXELFORMAT_ABGR64_FLOAT,
    /// RGB array order with 32-bit floating-point components.
    rgb96_float = c.SDL_PIXELFORMAT_RGB96_FLOAT,
    /// BGR array order with 32-bit floating-point components.
    bgr96_float = c.SDL_PIXELFORMAT_BGR96_FLOAT,
    /// RGBA array order with 32-bit floating-point components.
    rgba128_float = c.SDL_PIXELFORMAT_RGBA128_FLOAT,
    /// ARGB array order with 32-bit floating-point components.
    argb128_float = c.SDL_PIXELFORMAT_ARGB128_FLOAT,
    /// BGRA array order with 32-bit floating-point components.
    bgra128_float = c.SDL_PIXELFORMAT_BGRA128_FLOAT,
    /// ABGR array order with 32-bit floating-point components.
    abgr128_float = c.SDL_PIXELFORMAT_ABGR128_FLOAT,
    /// Planar 4:2:0 Y, V, U planes; pitches and subsampling require separate layout handling.
    yv12 = c.SDL_PIXELFORMAT_YV12,
    /// Planar 4:2:0 Y, U, V planes; not one packed pixel per sample.
    iyuv = c.SDL_PIXELFORMAT_IYUV,
    /// Packed 4:2:2 Y0, U, Y1, V groups shared by pairs of pixels.
    yuy2 = c.SDL_PIXELFORMAT_YUY2,
    /// Packed 4:2:2 U, Y0, V, Y1 groups shared by pairs of pixels.
    uyvy = c.SDL_PIXELFORMAT_UYVY,
    /// Packed 4:2:2 Y0, V, Y1, U groups shared by pairs of pixels.
    yvyu = c.SDL_PIXELFORMAT_YVYU,
    /// 4:2:0 luma plane followed by interleaved U/V chroma.
    nv12 = c.SDL_PIXELFORMAT_NV12,
    /// 4:2:0 luma plane followed by interleaved V/U chroma.
    nv21 = c.SDL_PIXELFORMAT_NV21,
    /// 10-bit 4:2:0 samples in 16-bit storage; luma plus interleaved U/V planes.
    p010 = c.SDL_PIXELFORMAT_P010,
    /// External Android GLES texture format; not a CPU pixel-buffer layout.
    external_oes = c.SDL_PIXELFORMAT_EXTERNAL_OES,
    /// Motion JPEG encoded data; size depends on the compressed frame.
    mjpg = c.SDL_PIXELFORMAT_MJPG,
    _,

    /// RGBA bytes in memory on either endian target; alias, not a distinct format value.
    pub const rgba32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_RGBA32);

    /// ARGB bytes in memory on either endian target; alias, not a distinct format value.
    pub const argb32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_ARGB32);

    /// BGRA bytes in memory on either endian target; alias, not a distinct format value.
    pub const bgra32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_BGRA32);

    /// ABGR bytes in memory on either endian target; alias, not a distinct format value.
    pub const abgr32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_ABGR32);

    /// RGBX bytes in memory on either endian target; alias, not a distinct format value.
    pub const rgbx32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_RGBX32);

    /// XRGB bytes in memory on either endian target; alias, not a distinct format value.
    pub const xrgb32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_XRGB32);

    /// BGRX bytes in memory on either endian target; alias, not a distinct format value.
    pub const bgrx32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_BGRX32);

    /// XBGR bytes in memory on either endian target; alias, not a distinct format value.
    pub const xbgr32: Format = @fromBackingInt(c.SDL_PIXELFORMAT_XBGR32);

    /// Borrow a static native name on any thread. Never free; unknown identities return the native
    /// unknown label. No wrapper allocation; this does not establish format support for a backend.
    pub fn name(self: Format) [:0]const u8 {
        return std.mem.span(c.SDL_GetPixelFormatName(@backingInt(self)));
    }

    /// Classify custom/FourCC encodings, including planar/compressed formats. Pure, any thread.
    pub fn is_fourcc(self: Format) bool {
        return @backingInt(self) != 0 and (@backingInt(self) >> 28) != 1;
    }

    /// Test palette-index encoding, not whether a surface actually has a palette. Pure, any thread.
    pub fn is_indexed(self: Format) bool {
        const kind = pixel_type(self);
        return !self.is_fourcc() and (kind == c.SDL_PIXELTYPE_INDEX1 or
            kind == c.SDL_PIXELTYPE_INDEX2 or kind == c.SDL_PIXELTYPE_INDEX4 or
            kind == c.SDL_PIXELTYPE_INDEX8);
    }

    /// Test native-endian packed-integer encoding. Byte-array aliases may also be packed.
    /// Pure, any thread; this is format classification, not a memory alignment guarantee.
    pub fn is_packed(self: Format) bool {
        const kind = pixel_type(self);
        return !self.is_fourcc() and (kind == c.SDL_PIXELTYPE_PACKED8 or
            kind == c.SDL_PIXELTYPE_PACKED16 or kind == c.SDL_PIXELTYPE_PACKED32);
    }

    /// Test component-array encoding, excluding packed-integer byte aliases. Pure, any thread.
    pub fn is_array(self: Format) bool {
        const kind = pixel_type(self);
        return !self.is_fourcc() and (kind == c.SDL_PIXELTYPE_ARRAYU8 or
            kind == c.SDL_PIXELTYPE_ARRAYU16 or kind == c.SDL_PIXELTYPE_ARRAYU32 or
            kind == c.SDL_PIXELTYPE_ARRAYF16 or kind == c.SDL_PIXELTYPE_ARRAYF32);
    }

    /// Test floating component storage, not colorspace or linear-light encoding. Pure, any thread.
    pub fn is_float(self: Format) bool {
        const kind = pixel_type(self);
        return !self.is_fourcc() and
            (kind == c.SDL_PIXELTYPE_ARRAYF16 or kind == c.SDL_PIXELTYPE_ARRAYF32);
    }

    /// Test SDL's packed 2/10/10/10 classification. Does not include FourCC P010. Pure, any thread.
    pub fn is_10bit(self: Format) bool {
        const layout = (@backingInt(self) >> 16) & 15;
        return !self.is_fourcc() and pixel_type(self) == c.SDL_PIXELTYPE_PACKED32 and
            layout == c.SDL_PACKEDLAYOUT_2101010;
    }

    /// Test an explicit alpha component in packed/array formats, not palette transparency or
    /// color-key state. FourCC formats are not classified as alpha by this predicate. Pure.
    pub fn has_alpha(self: Format) bool {
        const order = (@backingInt(self) >> 20) & 15;
        return (self.is_packed() and (order == c.SDL_PACKEDORDER_ARGB or
            order == c.SDL_PACKEDORDER_RGBA or order == c.SDL_PACKEDORDER_ABGR or
            order == c.SDL_PACKEDORDER_BGRA)) or
            (self.is_array() and (order == c.SDL_ARRAYORDER_ARGB or
                order == c.SDL_ARRAYORDER_RGBA or order == c.SDL_ARRAYORDER_ABGR or
                order == c.SDL_ARRAYORDER_BGRA));
    }

    /// Return the encoded bit count per pixel; FourCC formats return zero. Pure, any thread.
    /// This excludes unused X bits in some packed formats and cannot determine allocation size.
    pub fn bits_per_pixel(self: Format) u8 {
        return if (self.is_fourcc()) 0 else @truncate(@backingInt(self) >> 8);
    }

    /// Return SDL's storage-byte hint; sub-byte indexed formats return zero. FourCC results are
    /// approximate (often one, or two for selected formats). Never use width*height*this as a
    /// general image allocation formula: pitch, planes, padding and compression are separate. Pure.
    pub fn storage_bytes_per_pixel(self: Format) u8 {
        if (!self.is_fourcc()) return @truncate(@backingInt(self));
        return switch (self) {
            .yuy2, .uyvy, .yvyu, .p010 => 2,
            else => 1,
        };
    }

    /// Copy cached native format details on any thread; never exposes a mutable cache pointer.
    /// SDL may allocate/cache internally; native rejection returns SdlFailure. FourCC/custom
    /// identities can succeed with zero layout metadata; success does not prove format support.
    /// Masks/shifts describe integer channels; they are not a complete planar/float layout.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// const format = sdl.pixels.Format.rgba32;
    /// const details = try format.details();
    /// try @import("std").testing.expectEqual(@as(u8, 4), details.bytes_per_pixel);
    /// try @import("std").testing.expect(format.has_alpha());
    /// ```
    pub fn details(self: Format) Error!Details {
        const value = c.SDL_GetPixelFormatDetails(@backingInt(self));
        if (value == null) return error.SdlFailure;
        return .{
            .format = @fromBackingInt(value.*.format),
            .bits_per_pixel = value.*.bits_per_pixel,
            .bytes_per_pixel = value.*.bytes_per_pixel,
            .red = .{ .mask = value.*.Rmask, .bits = value.*.Rbits, .shift = value.*.Rshift },
            .green = .{ .mask = value.*.Gmask, .bits = value.*.Gbits, .shift = value.*.Gshift },
            .blue = .{ .mask = value.*.Bmask, .bits = value.*.Bbits, .shift = value.*.Bshift },
            .alpha = .{ .mask = value.*.Amask, .bits = value.*.Abits, .shift = value.*.Ashift },
        };
    }

    /// Query native bit count and integer masks on any thread; rejection returns SdlFailure.
    /// Non-integer/FourCC/unknown formats can succeed with zero masks; this is not a support test.
    /// No wrapper allocation. Bits describe native storage/mask interpretation, not plane sizes.
    pub fn masks(self: Format) Error!Masks {
        var bits: c_int = 0;
        var value: Masks = undefined;
        if (!c.SDL_GetMasksForPixelFormat(
            @backingInt(self),
            &bits,
            &value.red,
            &value.green,
            &value.blue,
            &value.alpha,
        )) return error.SdlFailure;
        if (bits < 0 or bits > 255) return error.SdlFailure;
        value.bits_per_pixel = @intCast(bits);
        return value;
    }
};

/// Copied integer-channel layout; a zero mask/bits count means no such channel.
pub const Channel = struct {
    /// Native integer bitmask. Not a byte offset or a palette lookup.
    mask: u32,
    /// Number of significant channel bits.
    bits: u8,
    /// Right shift for extracting the channel from the native packed integer.
    shift: u8,
};

/// Independent copy of SDL's format metadata, with no cleanup or retained native pointers.
pub const Details = struct {
    /// Native identity associated with these details.
    format: Format,
    /// Native declared bit count; treatment of unused channel bits depends on the format.
    bits_per_pixel: u8,
    /// Storage bytes reported by SDL; does not include row pitch/padding.
    bytes_per_pixel: u8,
    /// Red integer-channel layout where applicable.
    red: Channel,
    /// Green integer-channel layout where applicable.
    green: Channel,
    /// Blue integer-channel layout where applicable.
    blue: Channel,
    /// Alpha integer-channel layout where applicable.
    alpha: Channel,
};

/// Native integer pixel masks for format lookup. Overlap/noncanonical combinations may not match.
pub const Masks = struct {
    /// Native bits-per-pixel argument; commonly 15, 16, 24, or 32.
    bits_per_pixel: u8,
    /// Red channel mask.
    red: u32,
    /// Green channel mask.
    green: u32,
    /// Blue channel mask.
    blue: u32,
    /// Alpha mask; zero means absent.
    alpha: u32,

    /// Find SDL's matching canonical identity on any thread, or null for no match. Pure wrapper;
    /// no ownership transfer. Lookup can normalize aliases or ambiguous indexed/unused-bit layouts.
    pub fn format(self: Masks) ?Format {
        const value = c.SDL_GetPixelFormatForMasks(
            self.bits_per_pixel,
            self.red,
            self.green,
            self.blue,
            self.alpha,
        );
        if (value == c.SDL_PIXELFORMAT_UNKNOWN) return null;
        return @fromBackingInt(value);
    }
};

/// Construct a custom four-byte code without allocation or native calls. Does not establish SDL
/// support or even a FourCC classification for arbitrary bytes; all zeros produce Format.unknown.
pub fn from_fourcc(bytes: [4]u8) Format {
    const value = @as(u32, bytes[0]) | (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16) | (@as(u32, bytes[3]) << 24);
    return @fromBackingInt(value);
}

fn pixel_type(format: Format) u4 {
    return @truncate(@backingInt(format) >> 24);
}

test "pixel metadata masks and aliases preserve integer and byte semantics" {
    const details = try Format.rgb565.details();
    try std.testing.expectEqual(@as(u8, 16), details.bits_per_pixel);
    try std.testing.expectEqualDeep(Channel{ .mask = 0xf800, .bits = 5, .shift = 11 }, details.red);
    try std.testing.expectEqualDeep(
        Channel{ .mask = 0x07e0, .bits = 6, .shift = 5 },
        details.green,
    );
    try std.testing.expectEqualDeep(Channel{ .mask = 0x001f, .bits = 5, .shift = 0 }, details.blue);
    try std.testing.expectEqual(@as(u32, 0), details.alpha.mask);
    const masks = try Format.rgb565.masks();
    try std.testing.expectEqual(@as(?Format, .rgb565), masks.format());
    try std.testing.expectEqual(@as(u8, 4), Format.rgba32.storage_bytes_per_pixel());
    try std.testing.expect(Format.rgba32.has_alpha());
    try std.testing.expect(!Format.rgbx32.has_alpha());
    const rgba = try Format.rgba32.details();
    const bytes = [_]u8{ 1, 2, 3, 4 };
    const native: u32 = @bitCast(bytes);
    try std.testing.expectEqual(@as(u32, 1), (native & rgba.red.mask) >> @intCast(rgba.red.shift));
    try std.testing.expectEqual(
        @as(u32, 4),
        (native & rgba.alpha.mask) >> @intCast(rgba.alpha.shift),
    );
    try std.testing.expectEqual(@as(u8, 24), Format.xrgb8888.bits_per_pixel());
    try std.testing.expectEqual(@as(u8, 32), (try Format.xrgb8888.details()).bits_per_pixel);
    const unknown: Format = @fromBackingInt(@as(u32, 0xdeadbeef));
    try std.testing.expectEqual(@as(u32, 0xdeadbeef), @backingInt(unknown));
    try std.testing.expectEqualStrings("SDL_PIXELFORMAT_UNKNOWN", unknown.name());
    try std.testing.expectEqual(@as(u8, 0), (try Format.unknown.details()).bytes_per_pixel);
    const malformed: Format = @fromBackingInt(@as(u32, 0x14ff0801));
    try std.testing.expectError(error.SdlFailure, malformed.details());
    try std.testing.expectError(error.SdlFailure, malformed.masks());
    if (Format.nv12.masks()) |yuv| {
        try std.testing.expectEqual(@as(u8, 0), yuv.bits_per_pixel);
        try std.testing.expectEqual(@as(u32, 0), yuv.red | yuv.green | yuv.blue | yuv.alpha);
    } else |err| {
        // Native builds without YUV support can reject FourCC queries.
        try std.testing.expectEqual(error.SdlFailure, err);
    }
    try std.testing.expectEqual(@as(?Format, null), (Masks{
        .bits_per_pixel = 0,
        .red = 0,
        .green = 0,
        .blue = 0,
        .alpha = 0,
    }).format());
    try std.testing.expectEqual(Format.nv12, from_fourcc("NV12".*));
    try std.testing.expectEqual(Format.unknown, from_fourcc(.{ 0, 0, 0, 0 }));
}

test "classification matches independent pinned C macro reference" {
    const reference = @embedFile("fixtures/pixel-formats.tsv");
    var lines = std.mem.tokenizeScalar(u8, reference, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeScalar(u8, line, '\t');
        const format: Format = @fromBackingInt(try std.fmt.parseInt(u32, fields.next().?, 10));
        const bits = try std.fmt.parseInt(u8, fields.next().?, 10);
        const bytes = try std.fmt.parseInt(u8, fields.next().?, 10);
        const flags = try std.fmt.parseInt(u8, fields.next().?, 10);
        try std.testing.expectEqual(bits, format.bits_per_pixel());
        try std.testing.expectEqual(bytes, format.storage_bytes_per_pixel());
        const actual = [_]bool{
            format.is_fourcc(),
            format.is_indexed(),
            format.is_packed(),
            format.is_array(),
            format.is_float(),
            format.is_10bit(),
            format.has_alpha(),
        };
        for (actual, 0..) |value, index| {
            try std.testing.expectEqual(flags & (@as(u8, 1) << @intCast(index)) != 0, value);
        }
    }
}

test "palette updates copy inputs and validate the whole range before mutation" {
    try std.testing.expectError(error.InvalidPaletteSize, Palette.init(0));
    try std.testing.expectError(error.InvalidPaletteSize, Palette.init(std.math.maxInt(usize)));
    var palette = try Palette.init(2);
    defer palette.deinit();
    const view = palette.borrow();
    try std.testing.expectEqual(@as(usize, 2), view.len());
    try std.testing.expectEqualDeep(Color{ .r = 255, .g = 255, .b = 255 }, try view.get(0));
    var colors = [_]Color{ .{ .r = 1, .g = 2, .b = 3 }, .{ .r = 4, .g = 5, .b = 6 } };
    try view.set_colors(0, &colors);
    colors[0].r = 99;
    try std.testing.expectEqual(@as(u8, 1), (try view.get(0)).r);
    try std.testing.expectError(error.OutOfBounds, view.set_colors(1, &colors));
    try std.testing.expectEqual(@as(u8, 4), (try view.get(1)).r);
    try view.set_colors(2, &.{});
    try std.testing.expectError(error.OutOfBounds, view.set_colors(3, &.{}));
    try std.testing.expectError(
        error.OutOfBounds,
        view.set_colors(std.math.maxInt(usize), &colors),
    );
    try std.testing.expectError(error.OutOfBounds, view.get(2));
}

test "colorspace components match native macros and preserve every numeric field" {
    const samples = [_]u32{
        0,                      0xffffffff,                     0x12345678, c.SDL_COLORSPACE_SRGB,
        c.SDL_COLORSPACE_HDR10, c.SDL_COLORSPACE_BT601_LIMITED,
    };
    for (samples) |value| {
        const encoding: Colorspace = @fromBackingInt(value);
        try std.testing.expectEqual(
            c.SDL_ISCOLORSPACE_MATRIX_BT601(value),
            encoding.is_bt601_matrix(),
        );
        try std.testing.expectEqual(
            c.SDL_ISCOLORSPACE_MATRIX_BT709(value),
            encoding.is_bt709_matrix(),
        );
        try std.testing.expectEqual(
            c.SDL_ISCOLORSPACE_MATRIX_BT2020_NCL(value),
            encoding.is_bt2020_ncl_matrix(),
        );
        try std.testing.expectEqual(c.SDL_ISCOLORSPACE_FULL_RANGE(value), encoding.is_full_range());
        try std.testing.expectEqual(
            c.SDL_ISCOLORSPACE_LIMITED_RANGE(value),
            encoding.is_limited_range(),
        );
        const parts = encoding.components();
        try std.testing.expectEqual(encoding, Colorspace.from_components(parts));
        try std.testing.expectEqual(
            c.SDL_COLORSPACETYPE(value),
            @as(c_uint, @backingInt(parts.kind)),
        );
        try std.testing.expectEqual(
            c.SDL_COLORSPACERANGE(value),
            @as(c_uint, @backingInt(parts.range)),
        );
        try std.testing.expectEqual(
            c.SDL_COLORSPACECHROMA(value),
            @as(c_uint, @backingInt(parts.chroma)),
        );
        try std.testing.expectEqual(
            c.SDL_COLORSPACEPRIMARIES(value),
            @as(c_uint, @backingInt(parts.primaries)),
        );
        try std.testing.expectEqual(
            c.SDL_COLORSPACETRANSFER(value),
            @as(c_uint, @backingInt(parts.transfer)),
        );
        try std.testing.expectEqual(
            c.SDL_COLORSPACEMATRIX(value),
            @as(c_uint, @backingInt(parts.matrix)),
        );
    }
    const parts = Colorspace.hdr10.components();
    try std.testing.expectEqual(ColorPrimaries.bt2020, parts.primaries);
    try std.testing.expectEqual(TransferCharacteristics.pq, parts.transfer);
    try std.testing.expectEqual(
        @as(u32, c.SDL_DEFINE_COLORSPACE(1, 2, 9, 16, 0, 0)),
        @backingInt(Colorspace.from_components(parts)),
    );
}
