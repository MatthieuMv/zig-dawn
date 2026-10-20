//! SDL_image: image loading/saving. Requires the corresponding optional build dependency.
//! Load a CPU surface, then optionally upload with `sdl.render.Texture.from_surface`.
//! Native decoders allocate and may block; supported codecs depend on the installed library.
//! Decoding has no wrapper-enforced memory/work bound. This API does not require video init.
//! Use loading on the main thread; concurrent decoder/backend behavior is not promised here.
const sdl = @import("sdl");
/// Native C declarations sharing core SDL type identity. No Zig ownership or validation layer.
/// Native resources must use their matching native destroy function and documented lifetime.
pub const raw = @import("sdl_abi");

/// Return the linked SDL_image runtime version, without initializing the library.
/// Encoding: `major * 1_000_000 + minor * 1_000 + patch`. Callable from any thread.
/// No wrapper allocation or fallible result; the value does not establish codec availability.
pub fn version() u32 {
    return @intCast(raw.IMG_Version());
}

test "native version matches header major and meets header version" {
    const std = @import("std");
    try std.testing.expect(@import("sdl").raw.SDL_Surface == raw.SDL_Surface);
    try std.testing.expectEqual(@as(u32, 3), version() / 1_000_000);
    try std.testing.expect(version() >= raw.SDL_IMAGE_VERSION);
}

/// Load a file into an owned CPU surface. `path` is a sentinel-terminated UTF-8 path,
/// borrowed only for this call; relative paths use the process working directory.
/// Format selection uses content and filename hints. Pixel format is not guaranteed RGBA.
/// Main thread by wrapper contract. Native I/O/decoding may block and allocate; no Zig allocation.
/// `SdlFailure` returns no owner; inspect `sdl.errors.message()` immediately for diagnostics.
/// Release with `deinit`; the surface can outlive this call and any later image loads.
pub fn load(path: [:0]const u8) sdl.errors.Error!sdl.surface.Surface {
    const handle = raw.IMG_Load(path.ptr) orelse return error.SdlFailure;
    return .{ .handle = handle };
}

/// Decode encoded image bytes into an owned CPU surface using native format detection.
/// Bytes are borrowed only until return, on success and failure; the surface owns decoded pixels.
/// Formats requiring a filename/type hint may not be detected. Output format is decoder-selected.
/// Main thread by wrapper contract; native decoding/stream creation may allocate and block.
/// `SdlFailure` returns no owner, including empty, malformed, or unsupported data; temporary
/// stream storage is closed on every decode outcome. Read `sdl.errors.message()` on failure.
/// There is no decoded-size limit; a small compressed input can request substantial native memory.
///
/// ```zig
/// const image = @import("sdl_image");
/// const std = @import("std");
/// // A complete 1x1, 24-bit BMP containing an orange pixel (B,G,R and row padding).
/// const encoded = "BM\x3a\x00\x00\x00\x00\x00\x00\x00\x36\x00\x00\x00" ++
///     "\x28\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x01\x00\x18\x00" ++
///     "\x00\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
///     "\x00\x00\x00\x00\x00\x00\x00\x00\x32\x64\xc8\x00";
/// var surface = try image.load_memory(encoded);
/// defer surface.deinit();
/// try std.testing.expectEqual(@as(u32, 1), surface.borrow().size().width);
/// ```
pub fn load_memory(bytes: []const u8) sdl.errors.Error!sdl.surface.Surface {
    const stream = raw.SDL_IOFromConstMem(bytes.ptr, bytes.len) orelse return error.SdlFailure;
    // Ownership transfers even on decode failure; a separate defer would double-close.
    const handle = raw.IMG_Load_IO(stream, true) orelse return error.SdlFailure;
    return .{ .handle = handle };
}

/// Decode from the current position of a borrowed stream, using native format detection.
/// Main thread by wrapper contract. The stream must support seeking and remain exclusively
/// accessible during decoding; it is NEVER closed, on success or failure. The returned surface
/// owns decoded pixels without retaining the stream. Cursor position after failure is unspecified.
/// Native decoding may allocate/block without a decoded-size budget. `SdlFailure` returns no owner;
/// missing format hints, corrupt data, and I/O failures share this error. Read SDL diagnostics.
pub fn load_stream(stream: sdl.io.StreamRef) sdl.errors.Error!sdl.surface.Surface {
    const handle = raw.IMG_Load_IO(stream.handle, false) orelse return error.SdlFailure;
    return .{ .handle = handle };
}

/// Encode a live surface as a PNG file. UTF-8 sentinel path is borrowed only until return.
/// Relative paths use the working directory; existing files are overwritten. Main thread by
/// wrapper contract. Surface ownership stays with the caller; synchronize access during encoding.
/// Native encoding/I/O may allocate/block. `SdlFailure` may leave a partial/truncated file: saving
/// is not atomic. Read `sdl.errors.message()` immediately. No wrapper allocation or durability
/// promise.
pub fn save_png(surface: sdl.surface.SurfaceRef, path: [:0]const u8) sdl.errors.Error!void {
    if (!raw.IMG_SavePNG(surface.handle, path.ptr)) return error.SdlFailure;
}

/// Encode PNG at a borrowed stream's current cursor. Never closes or retains either argument.
/// Main thread by wrapper contract; exclusive access to surface and stream is required during use.
/// Native encoding may allocate/block. `SdlFailure` includes insufficient output space; bytes and
/// cursor may already have changed. Success does not close/flush the stream or truncate trailing
/// data. Call the stream owner's `close` separately when final output errors matter.
/// Fixed memory streams bound output capacity, not the encoder's internal native allocations.
///
/// ```zig
/// const sdl = @import("sdl");
/// const image = @import("sdl_image");
/// var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 2 });
/// defer surface.deinit();
/// var buffer: [4096]u8 = undefined;
/// var output = try sdl.io.Stream.from_memory(&buffer);
/// defer output.deinit();
/// try image.save_png_stream(surface.borrow(), output.borrow());
/// const length: usize = @intCast(try output.borrow().position());
/// // Decode only the written prefix, not the unwritten buffer capacity.
/// var decoded = try image.load_memory(buffer[0..length]);
/// defer decoded.deinit();
/// try @import("std").testing.expectEqual(@as(u32, 2), decoded.borrow().size().width);
/// ```
pub fn save_png_stream(
    surface: sdl.surface.SurfaceRef,
    stream: sdl.io.StreamRef,
) sdl.errors.Error!void {
    if (!raw.IMG_SavePNG_IO(surface.handle, stream.handle, false)) return error.SdlFailure;
}
