const std = @import("std");
const sdl = @import("sdl");
const ttf = @import("sdl_ttf");
const font_path = @import("fixtures").font_path ++ "";
const font_bytes = @embedFile("fixtures/box.ttf");

test "initialization references and font input failures" {
    const before = ttf.raw.TTF_WasInit();
    {
        var first = try ttf.init();
        defer first.deinit();
        {
            var second = try ttf.init();
            defer second.deinit();
            try std.testing.expectEqual(before + 2, ttf.raw.TTF_WasInit());
        }
        try std.testing.expectEqual(before + 1, ttf.raw.TTF_WasInit());
        for ([_]f32{ 0, -1, std.math.nan(f32), std.math.inf(f32) }) |size| {
            try std.testing.expectError(
                error.InvalidPointSize,
                first.open_font(font_path, .{ .size_points = size }),
            );
        }
        try std.testing.expectError(
            error.SdlFailure,
            first.open_font("", .{ .size_points = 24 }),
        );
        try std.testing.expect(sdl.errors.message().len > 0);
        var invalid = try sdl.io.Stream.from_const_memory("not a font");
        defer invalid.deinit();
        try std.testing.expectError(
            error.SdlFailure,
            first.open_font_stream(invalid.borrow(), .{ .size_points = 24 }),
        );
        _ = try invalid.borrow().seek(0, .start);
        var font = try first.open_font(font_path, .{ .size_points = 24 });
        defer font.deinit();
        try check_text_validation(font.borrow());
    }
    try std.testing.expectEqual(before, ttf.raw.TTF_WasInit());
}

fn check_text_validation(font: ttf.FontRef) !void {
    try std.testing.expectError(error.InvalidText, font.measure("\xff"));
    try std.testing.expectError(error.InvalidText, font.measure("A\x00A"));
    try std.testing.expectError(
        error.InvalidText,
        font.render("\xc3", .{ .r = 1, .g = 2, .b = 3 }),
    );
    try std.testing.expectError(error.EmptyText, font.render("", .{ .r = 1, .g = 2, .b = 3 }));
    // The backing bytes are not NUL-terminated; even a zero-length subslice must be safe.
    const bytes = [_]u8{ 'A', 0xc3, 0xa9, 'A' };
    try std.testing.expectEqual(@as(u32, 0), (try font.measure(bytes[1..1])).width);
    const two = try font.measure(bytes[0..3]);
    const three = try font.measure(&bytes);
    try std.testing.expect(two.width > 0 and three.width > two.width);
    var surface = try font.render(bytes[0..3], .{ .r = 1, .g = 2, .b = 3 });
    defer surface.deinit();
    try std.testing.expectEqualDeep(two, surface.borrow().size());
}

test "stream font retains input until close and surfaces outlive font and context" {
    var input = try sdl.io.Stream.from_const_memory(font_bytes);
    defer input.deinit();
    var surface = rendered: {
        var context = try ttf.init();
        defer context.deinit();
        var font = try context.open_font_stream(input.borrow(), .{ .size_points = 24 });
        defer font.deinit();
        const measured = try font.borrow().measure("Aé");
        var pixels = try font.borrow().render("Aé", .{ .r = 220, .g = 80, .b = 40 });
        errdefer pixels.deinit();
        try std.testing.expectEqualDeep(measured, pixels.borrow().size());
        break :rendered pixels;
    };
    defer surface.deinit();
    try check_pixels(surface.borrow());
    try std.testing.expectEqual(@as(u64, 0), try input.borrow().seek(0, .start));
}

fn check_pixels(surface: sdl.surface.SurfaceRef) !void {
    const size = surface.size();
    try std.testing.expect(size.width > 0 and size.width < 128);
    try std.testing.expect(size.height > 0 and size.height < 128);
    var opaque_pixels: usize = 0;
    var transparent: usize = 0;
    for (0..size.height) |y| {
        for (0..size.width) |x| {
            var color: sdl.render.Color = undefined;
            try std.testing.expect(sdl.raw.SDL_ReadSurfacePixel(
                surface.handle,
                @intCast(x),
                @intCast(y),
                &color.r,
                &color.g,
                &color.b,
                &color.a,
            ));
            if (color.a == 255) {
                try std.testing.expectEqualDeep(
                    sdl.render.Color{ .r = 220, .g = 80, .b = 40 },
                    color,
                );
                opaque_pixels += 1;
            }
            if (color.a == 0) transparent += 1;
        }
    }
    try std.testing.expect(opaque_pixels > 0 and transparent > 0);
}

test "text surface uploads to a renderer texture" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .video = true });
    defer subsystems.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "text upload",
        .size = .{ .width = 64, .height = 64 },
        .hidden = true,
    });
    defer window.deinit();
    var renderer = try sdl.render.Renderer.init(window.borrow(), .{ .driver = "software" });
    defer renderer.deinit();
    var texture = uploaded: {
        var context = try ttf.init();
        defer context.deinit();
        var font = try context.open_font(font_path, .{ .size_points = 24 });
        defer font.deinit();
        var surface = try font.borrow().render("A", .{ .r = 255, .g = 255, .b = 255 });
        defer surface.deinit();
        break :uploaded try sdl.render.Texture.from_surface(renderer.borrow(), surface.borrow());
    };
    defer texture.deinit();
    try renderer.borrow().set_color(.{ .r = 0, .g = 0, .b = 0 });
    try renderer.borrow().clear();
    try renderer.borrow().draw_texture(texture.borrow(), null);
    const pixels = sdl.raw.SDL_RenderReadPixels(renderer.handle, null) orelse
        return error.SdlFailure;
    defer sdl.raw.SDL_DestroySurface(pixels);
    var color: sdl.render.Color = undefined;
    try std.testing.expect(sdl.raw.SDL_ReadSurfacePixel(
        pixels,
        32,
        32,
        &color.r,
        &color.g,
        &color.b,
        &color.a,
    ));
    try std.testing.expectEqualDeep(sdl.render.Color{ .r = 255, .g = 255, .b = 255 }, color);
}
