const std = @import("std");
const sdl = @import("sdl");
const image = @import("sdl_image");
const bmp = @embedFile("fixtures/orange.bmp");

test "file and memory decoding own pixels and recover after malformed input" {
    var file = try image.load(@import("fixtures").image_path ++ "");
    defer file.deinit();
    try expect_orange(file.borrow());
    var bytes = bmp.*;
    var memory = try image.load_memory(&bytes);
    defer memory.deinit();
    @memset(&bytes, 0);
    try expect_orange(memory.borrow());
    try std.testing.expectError(error.SdlFailure, image.load(""));
    try std.testing.expect(sdl.errors.message().len > 0);
    try std.testing.expectError(error.SdlFailure, image.load_memory(&.{}));
    try std.testing.expectError(error.SdlFailure, image.load_memory("not an image"));
    try std.testing.expectError(error.SdlFailure, image.load_memory(bmp[0..20]));
    var recovered = try image.load_memory(bmp);
    defer recovered.deinit();
    try expect_orange(recovered.borrow());
}

fn expect_orange(surface: sdl.surface.SurfaceRef) !void {
    try std.testing.expectEqualDeep(sdl.video.Size{ .width = 1, .height = 1 }, surface.size());
    var color: sdl.render.Color = undefined;
    try std.testing.expect(sdl.raw.SDL_ReadSurfacePixel(
        surface.handle,
        0,
        0,
        &color.r,
        &color.g,
        &color.b,
        &color.a,
    ));
    try std.testing.expectEqualDeep(sdl.render.Color{ .r = 200, .g = 100, .b = 50 }, color);
}

test "uploaded image survives surface destruction" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .video = true });
    defer subsystems.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "image upload",
        .size = .{ .width = 8, .height = 8 },
        .hidden = true,
    });
    defer window.deinit();
    var renderer = try sdl.render.Renderer.init(window.borrow(), .{ .driver = "software" });
    defer renderer.deinit();
    var texture = uploaded: {
        var surface = try image.load_memory(bmp);
        defer surface.deinit();
        break :uploaded try sdl.render.Texture.from_surface(renderer.borrow(), surface.borrow());
    };
    defer texture.deinit();
    try renderer.borrow().draw_texture(texture.borrow(), null);
    const readback = sdl.raw.SDL_RenderReadPixels(renderer.handle, null) orelse
        return error.SdlFailure;
    defer sdl.raw.SDL_DestroySurface(readback);
    var color: sdl.render.Color = undefined;
    try std.testing.expect(sdl.raw.SDL_ReadSurfacePixel(
        readback,
        7,
        7,
        &color.r,
        &color.g,
        &color.b,
        &color.a,
    ));
    try std.testing.expectEqualDeep(sdl.render.Color{ .r = 200, .g = 100, .b = 50 }, color);
}

test "PNG memory roundtrip preserves pixels and borrows streams" {
    var source = try sdl.io.Stream.from_const_memory(bmp);
    defer source.deinit();
    var surface = try image.load_stream(source.borrow());
    defer surface.deinit();
    try expect_orange(surface.borrow());
    _ = try source.borrow().seek(0, .start);
    var again = try image.load_stream(source.borrow());
    defer again.deinit();
    var buffer: [4096]u8 = undefined;
    var output = try sdl.io.Stream.from_memory(&buffer);
    defer output.deinit();
    try image.save_png_stream(surface.borrow(), output.borrow());
    const length: usize = @intCast(try output.borrow().position());
    try std.testing.expect(length > 8 and length <= buffer.len);
    try std.testing.expectEqualSlices(u8, "\x89PNG\r\n\x1a\n", buffer[0..8]);
    var decoded = try image.load_memory(buffer[0..length]);
    defer decoded.deinit();
    try expect_orange(decoded.borrow());
}

test "failed image operations leave borrowed streams open" {
    var bad = try sdl.io.Stream.from_const_memory("invalid image");
    defer bad.deinit();
    try std.testing.expectError(error.SdlFailure, image.load_stream(bad.borrow()));
    try std.testing.expectEqual(@as(u64, 0), try bad.borrow().seek(0, .start));
    var surface = try image.load_memory(bmp);
    defer surface.deinit();
    var guard: [10]u8 = undefined;
    @memset(&guard, 0xa5);
    var output = try sdl.io.Stream.from_memory(guard[1..9]);
    defer output.deinit();
    try std.testing.expectError(
        error.SdlFailure,
        image.save_png_stream(surface.borrow(), output.borrow()),
    );
    try std.testing.expectEqual(@as(u8, 0xa5), guard[0]);
    try std.testing.expectEqual(@as(u8, 0xa5), guard[9]);
    try std.testing.expectEqual(@as(u64, 0), try output.borrow().seek(0, .start));
    var readonly = try sdl.io.Stream.from_const_memory(bmp);
    defer readonly.deinit();
    try std.testing.expectError(
        error.SdlFailure,
        image.save_png_stream(surface.borrow(), readonly.borrow()),
    );
    _ = try readonly.borrow().seek(0, .start);
    var recovered = try image.load_stream(readonly.borrow());
    defer recovered.deinit();
    try expect_orange(recovered.borrow());
}

test "PNG file saving and file stream modes" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    var directory: [4096]u8 = undefined;
    const directory_len = try temp.dir.realPath(std.testing.io, &directory);
    var path_buffer: [8192]u8 = undefined;
    const path = try std.mem.printSentinel(
        &path_buffer,
        "{s}/roundtrip.png",
        .{directory[0..directory_len]},
        0,
    );
    try std.testing.expectError(error.SdlFailure, sdl.io.Stream.open(path, .read));
    var surface = try image.load_memory(bmp);
    defer surface.deinit();
    try image.save_png(surface.borrow(), path);
    {
        var input = try sdl.io.Stream.open(path, .read);
        defer input.deinit();
        var decoded = try image.load_stream(input.borrow());
        defer decoded.deinit();
        try expect_orange(decoded.borrow());
    }
    {
        var update = try sdl.io.Stream.open(path, .update);
        defer update.deinit();
        try std.testing.expect((try update.borrow().seek(0, .end)) > 8);
    }
    {
        var output = try sdl.io.Stream.open(path, .create);
        // Best-effort cleanup applies only before explicit close consumes the owner.
        {
            errdefer output.deinit();
            try std.testing.expectEqual(@as(u64, 0), try output.borrow().seek(0, .end));
            try image.save_png_stream(surface.borrow(), output.borrow());
        }
        try output.close();
    }
    var decoded = try image.load(path);
    defer decoded.deinit();
    try expect_orange(decoded.borrow());
    try std.testing.expectError(error.SdlFailure, image.save_png(surface.borrow(), ""));
}

test "PNG dynamic output transfers bytes beyond stream lifetime" {
    var surface = try image.load_memory(bmp);
    defer surface.deinit();
    var output = try sdl.io.DynamicStream.init(.{ .chunk_size = 32 });
    var consumed = false;
    defer if (!consumed) output.deinit();
    try image.save_png_stream(surface.borrow(), output.borrow());
    try std.testing.expect((try output.bytes()).len > 8);
    consumed = true;
    var encoded = try output.finish();
    defer encoded.deinit();
    var decoded = try image.load_memory(encoded.borrow());
    defer decoded.deinit();
    try expect_orange(decoded.borrow());
}

test "image decoding uses typed callbacks without closing the borrowed backend" {
    const Backend = struct {
        /// Borrowed source cursor; its owner outlives the adapter.
        source: sdl.io.StreamRef,
        /// Backend close notifications.
        closes: u32 = 0,
        fn read(self: *@This(), bytes: []u8) anyerror!sdl.io.Transfer {
            return self.source.read(bytes);
        }
        fn seek(self: *@This(), offset: i64, origin: sdl.io.SeekOrigin) anyerror!u64 {
            return self.source.seek(offset, origin);
        }
        fn close(self: *@This()) anyerror!void {
            self.closes += 1;
        }
    };
    var source = try sdl.io.Stream.from_const_memory(bmp);
    defer source.deinit();
    var backend = Backend{ .source = source.borrow() };
    var stream = try sdl.io.Stream.from_callbacks(Backend, &backend, .{
        .read = Backend.read,
        .seek = Backend.seek,
        .close = Backend.close,
    });
    var closed = false;
    defer if (!closed) stream.deinit();
    _ = try stream.borrow().seek(2, .start);
    try std.testing.expectEqual(@as(u64, bmp.len), try stream.borrow().size());
    try std.testing.expectEqual(@as(u64, 2), try stream.borrow().position());
    _ = try stream.borrow().seek(0, .start);
    var surface = try image.load_stream(stream.borrow());
    defer surface.deinit();
    try expect_orange(surface.borrow());
    try std.testing.expectEqual(@as(u32, 0), backend.closes);
    closed = true;
    try stream.close();
    try std.testing.expectEqual(@as(u32, 1), backend.closes);
    _ = try source.borrow().seek(0, .start);
    try std.testing.expectEqual(@as(u64, 0), try source.borrow().position());
}

test "loaded images support checked surface editing and independent RGBA conversion" {
    var converted: sdl.surface.Surface = undefined;
    {
        var loaded = try image.load_memory(bmp);
        defer loaded.deinit();
        const original = try loaded.borrow().read_pixel(.{ .x = 0, .y = 0 });
        try std.testing.expectEqualDeep(sdl.surface.Color{ .r = 200, .g = 100, .b = 50 }, original);
        converted = try loaded.borrow().to_rgba();
    }
    defer converted.deinit();
    const edited = sdl.surface.Color{ .r = 1, .g = 2, .b = 3, .a = 4 };
    try converted.borrow().write_pixel(.{ .x = 0, .y = 0 }, edited);
    var output = try sdl.io.DynamicStream.init(.{});
    var consumed = false;
    defer if (!consumed) output.deinit();
    try image.save_png_stream(converted.borrow(), output.borrow());
    consumed = true;
    var bytes = try output.finish();
    defer bytes.deinit();
    var decoded = try image.load_memory(bytes.borrow());
    defer decoded.deinit();
    try std.testing.expectEqualDeep(edited, try decoded.borrow().read_pixel(.{ .x = 0, .y = 0 }));
}

test "loaded image blits convert formats and leave independent destination pixels" {
    var destination = try sdl.surface.Surface.init_rgba(.{ .width = 3, .height = 2 });
    defer destination.deinit();
    {
        var source = try image.load_memory(bmp);
        defer source.deinit();
        try source.borrow().set_blend_mode(.none);
        try source.borrow().blit_scaled_to(destination.borrow(), .nearest);
    }
    try std.testing.expectEqualDeep(
        sdl.surface.Color{ .r = 200, .g = 100, .b = 50 },
        try destination.borrow().read_pixel(.{ .x = 2, .y = 1 }),
    );
}

test "RGBA row edits survive PNG encoding after unlock" {
    var source = try image.load_memory(bmp);
    defer source.deinit();
    var rgba = try source.borrow().to_rgba();
    defer rgba.deinit();
    {
        var pixels = try rgba.borrow().lock_rgba();
        defer pixels.deinit();
        @memcpy(try pixels.row(0), &[_]u8{ 15, 25, 35, 45 });
    }
    var output = try sdl.io.DynamicStream.init(.{});
    var consumed = false;
    defer if (!consumed) output.deinit();
    try image.save_png_stream(rgba.borrow(), output.borrow());
    consumed = true;
    var encoded = try output.finish();
    defer encoded.deinit();
    var decoded = try image.load_memory(encoded.borrow());
    defer decoded.deinit();
    try std.testing.expectEqualDeep(
        sdl.surface.Color{ .r = 15, .g = 25, .b = 35, .a = 45 },
        try decoded.borrow().read_pixel(.{ .x = 0, .y = 0 }),
    );
}
