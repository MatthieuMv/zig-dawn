const std = @import("std");
const sdl = @import("sdl");

test "headless renderer draws uploaded bytes and rejects invalid inputs" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .video = true });
    defer subsystems.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "headless contract",
        .size = .{ .width = 32, .height = 32 },
        .hidden = true,
    });
    defer window.deinit();
    try std.testing.expect((try window.borrow().id()) != .invalid);
    try std.testing.expectEqual(@as(u32, 32), (try window.borrow().size()).width);
    try std.testing.expectEqual(@as(u32, 32), (try window.borrow().pixel_size()).height);
    try std.testing.expectError(
        error.SdlFailure,
        sdl.render.Renderer.init(window.borrow(), .{ .driver = "no-such-renderer" }),
    );
    try std.testing.expect(sdl.errors.message().len != 0);
    var renderer = try sdl.render.Renderer.init(window.borrow(), .{ .driver = "software" });
    defer renderer.deinit();
    const drawing = renderer.borrow();
    try std.testing.expectEqual(
        renderer.handle,
        (try sdl.render.for_window(window.borrow())).handle,
    );
    try std.testing.expectEqual(window.handle, (try drawing.window()).handle);
    try std.testing.expectEqualStrings("software", try drawing.name());
    try std.testing.expectEqualDeep(try window.borrow().pixel_size(), try drawing.output_size());

    try drawing.set_presentation(.{
        .size = .{ .width = 16, .height = 8 },
        .mode = .letterbox,
    });
    const window_point = sdl.render.Point{ .x = 8, .y = 12 };
    const logical_point = sdl.render.Point{ .x = 4, .y = 2 };
    try std.testing.expectEqualDeep(logical_point, try drawing.from_window_point(window_point));
    try std.testing.expectEqualDeep(window_point, try drawing.to_window_point(logical_point));
    try std.testing.expect((try drawing.from_window_point(.{ .x = 0, .y = 0 })).y < 0);
    try std.testing.expectError(
        error.InvalidCoordinate,
        drawing.from_window_point(.{ .x = std.math.nan(f32), .y = 0 }),
    );
    try std.testing.expectError(
        error.InvalidCoordinate,
        drawing.to_window_point(.{ .x = 0, .y = std.math.inf(f32) }),
    );
    try drawing.set_presentation(null);
    try drawing.set_color(.{ .r = 12, .g = 34, .b = 56 });
    try drawing.clear();
    try drawing.fill_rect(null);
    try drawing.set_color(.{ .r = 0, .g = 180, .b = 0 });
    try drawing.fill_rect(.{ .x = 20, .y = 20, .width = 4, .height = 4 });
    try std.testing.expectError(
        error.InvalidPixels,
        sdl.render.Texture.init_rgba(drawing, .{ .width = 1, .height = 1 }, &.{}),
    );
    var pixels = [_]u8{ 200, 100, 50, 255 };
    var texture = try sdl.render.Texture.init_rgba(drawing, .{ .width = 1, .height = 1 }, &pixels);
    defer texture.deinit();
    pixels[0] = 0; // SDL must have copied the upload before returning.
    try drawing.draw_texture(texture.borrow(), .{ .x = 4, .y = 4, .width = 8, .height = 8 });
    try check_pixel(drawing, 0, 0, .{ .r = 12, .g = 34, .b = 56 });
    try check_pixel(drawing, 6, 6, .{ .r = 200, .g = 100, .b = 50 });
    try check_pixel(drawing, 21, 21, .{ .r = 0, .g = 180, .b = 0 });
    try drawing.draw_texture(texture.borrow(), null);
    try check_pixel(drawing, 31, 31, .{ .r = 200, .g = 100, .b = 50 });
    try drawing.present();
    try check_wrong_renderer(texture.borrow());
    try check_events();
}

fn check_pixel(
    renderer: sdl.render.RendererRef,
    x: c_int,
    y: c_int,
    expected: sdl.render.Color,
) !void {
    const surface = sdl.raw.SDL_RenderReadPixels(renderer.handle, null) orelse
        return error.SdlFailure;
    defer sdl.raw.SDL_DestroySurface(surface);
    var actual: sdl.render.Color = undefined;
    try std.testing.expect(sdl.raw.SDL_ReadSurfacePixel(
        surface,
        x,
        y,
        &actual.r,
        &actual.g,
        &actual.b,
        &actual.a,
    ));
    try std.testing.expectEqualDeep(expected, actual);
}

fn check_wrong_renderer(texture: sdl.render.TextureRef) !void {
    var window = try sdl.video.Window.init(&.{
        .title = "other",
        .size = .{ .width = 8, .height = 8 },
        .hidden = true,
    });
    defer window.deinit();
    var renderer = try sdl.render.Renderer.init(window.borrow(), .{ .driver = "software" });
    defer renderer.deinit();
    try std.testing.expectError(error.WrongRenderer, renderer.borrow().draw_texture(texture, null));
}

fn check_events() !void {
    // Bound queue draining even if the backend continues to produce events.
    for (0..256) |_| {
        _ = sdl.events.poll() orelse break;
    } else return error.EventBudgetExceeded;
    var native = std.mem.zeroes(sdl.raw.SDL_Event);
    native.type = sdl.raw.SDL_EVENT_QUIT;
    try std.testing.expect(sdl.raw.SDL_PushEvent(&native));
    for (0..256) |_| {
        const event = sdl.events.poll() orelse continue;
        if (event == .quit) return;
    }
    return error.MissingQuitEvent;
}

test "object property accessors borrow persistent independent groups" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .video = true });
    defer subsystems.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "properties",
        .size = .{ .width = 16, .height = 16 },
        .hidden = true,
    });
    defer window.deinit();
    var renderer = try sdl.render.Renderer.init(window.borrow(), .{ .driver = "software" });
    defer renderer.deinit();
    var texture = try sdl.render.Texture.init_rgba(
        renderer.borrow(),
        .{ .width = 1, .height = 1 },
        &.{ 1, 2, 3, 255 },
    );
    defer texture.deinit();
    var surface = try sdl.surface.Surface.init_rgba(.{ .width = 1, .height = 1 });
    defer surface.deinit();
    var stream = try sdl.io.Stream.from_const_memory("input");
    defer stream.deinit();
    const views = [_]sdl.properties.PropertiesRef{
        try window.borrow().properties(),  try renderer.borrow().properties(),
        try texture.borrow().properties(), try surface.borrow().properties(),
        try stream.borrow().properties(),
    };
    for (views, 0..) |view, index| try view.set("app.marker", &.{ .number = @intCast(index) });
    const again = [_]sdl.properties.PropertiesRef{
        try window.borrow().properties(),  try renderer.borrow().properties(),
        try texture.borrow().properties(), try surface.borrow().properties(),
        try stream.borrow().properties(),
    };
    for (again, 0..) |view, index| {
        try std.testing.expectEqual(views[index].handle, view.handle);
        try std.testing.expectEqual(
            @as(i64, @intCast(index)),
            (try view.get("app.marker")).?.number,
        );
    }
    const native_width = (try views[2].get(sdl.raw.SDL_PROP_TEXTURE_WIDTH_NUMBER)).?;
    try std.testing.expectEqual(@as(i64, 1), native_width.number);
}

test "display snapshots and window display queries work with dummy video" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var displays = try sdl.display.list();
    defer displays.deinit();
    try std.testing.expect(displays.items.len > 0);
    const primary = try sdl.display.primary();
    var found = false;
    for (displays.items) |id| {
        try std.testing.expect(id != .invalid);
        if (id == primary) found = true;
        try std.testing.expect((try id.name()).len > 0);
        const bounds = try id.bounds();
        try std.testing.expect(bounds.width > 0 and bounds.height > 0);
        _ = try id.usable_bounds();
        try std.testing.expect(try id.content_scale() > 0);
        _ = id.natural_orientation();
        _ = id.orientation();
        const properties = try id.properties();
        try properties.set("zig_sdl.display.test", &.{ .number = 42 });
        defer properties.clear("zig_sdl.display.test") catch {};
        try std.testing.expectEqual(
            @as(i64, 42),
            (try properties.get("zig_sdl.display.test")).?.number,
        );
        try std.testing.expectEqual(
            id,
            try sdl.display.for_point(.{ .x = bounds.x, .y = bounds.y }),
        );
    }
    try std.testing.expect(found);
    var window = try sdl.video.Window.init(&.{
        .title = "display-query",
        .size = .{ .width = 16, .height = 16 },
        .hidden = true,
    });
    defer window.deinit();
    try std.testing.expectEqual(primary, try window.borrow().display());
    try std.testing.expect(try window.borrow().display_scale() > 0);
    const invalid = sdl.display.DisplayId.invalid;
    try std.testing.expectError(error.SdlFailure, invalid.name());
    try std.testing.expectError(error.SdlFailure, invalid.bounds());
    try std.testing.expectError(error.SdlFailure, invalid.usable_bounds());
    try std.testing.expectError(error.SdlFailure, invalid.content_scale());
    try std.testing.expectError(error.SdlFailure, invalid.properties());
    try std.testing.expectEqual(sdl.display.Orientation.unknown, invalid.orientation());
    try std.testing.expectEqual(sdl.display.Orientation.unknown, invalid.natural_orientation());
}

test "window controls preserve title ownership and validate before mutation" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .video = true });
    defer subsystems.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "initial",
        .size = .{ .width = 32, .height = 24 },
        .hidden = true,
    });
    defer window.deinit();
    const view = window.borrow();
    var title_buffer: [5:0]u8 = "hello".*;
    try view.set_title(&title_buffer);
    title_buffer[0] = 'j';
    try std.testing.expectEqualStrings("hello", try view.title());
    try view.set_title("");
    try std.testing.expectEqualStrings("", try view.title());
    try view.set_size(.{ .width = 48, .height = 36 });
    try view.sync();
    try std.testing.expectEqualDeep(sdl.video.Size{ .width = 48, .height = 36 }, try view.size());
    try std.testing.expectError(error.InvalidSize, view.set_size(.{ .width = 0, .height = 24 }));
    try std.testing.expectEqualDeep(sdl.video.Size{ .width = 48, .height = 36 }, try view.size());
    try view.set_position(.{ .x = .{ .coordinate = 12 }, .y = .{ .coordinate = 34 } });
    try view.sync();
    const position = try view.position();
    try std.testing.expectEqualDeep(sdl.display.Point{ .x = 12, .y = 34 }, position);
    try std.testing.expectError(error.InvalidPosition, view.set_position(.{
        .x = .{ .coordinate = 50 },
        .y = .{ .centered = .invalid },
    }));
    try std.testing.expectEqualDeep(position, try view.position());
    try view.set_position(.{});
    try view.sync();
    try view.show();
    try std.testing.expect(
        sdl.raw.SDL_GetWindowFlags(view.handle) & sdl.raw.SDL_WINDOW_HIDDEN == 0,
    );
    try view.hide();
    try std.testing.expect(
        sdl.raw.SDL_GetWindowFlags(view.handle) & sdl.raw.SDL_WINDOW_HIDDEN != 0,
    );
}

test "display modes own snapshots and fullscreen selection is separate from entry" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    const display = try sdl.display.primary();
    const desktop = try display.desktop_mode();
    const current = try display.current_mode();
    try std.testing.expectEqual(display, (try desktop.info()).display);
    try std.testing.expectEqualDeep((try desktop.info()).size, (try current.info()).size);
    var window = try sdl.video.Window.init(&.{
        .title = "fullscreen selection",
        .size = .{ .width = 32, .height = 32 },
        .hidden = true,
    });
    defer window.deinit();
    const view = window.borrow();
    var modes = try display.modes();
    {
        defer modes.deinit();
        try std.testing.expectError(error.OutOfBounds, modes.get(modes.count));
        for (0..modes.count) |index| {
            const mode = try modes.get(index);
            const info = try mode.info();
            try std.testing.expectEqual(display, info.display);
            try std.testing.expect(info.size.width > 0 and info.size.height > 0);
        }
        if (modes.count > 0) {
            const mode = try modes.get(0);
            const closest = try display.closest_mode(.{
                .size = (try mode.info()).size,
                .include_high_density = true,
            });
            try std.testing.expectEqual(display, (try closest.info()).display);
            try view.set_fullscreen_mode(mode);
            try std.testing.expect(view.fullscreen_mode() != null);
        } else {
            try std.testing.expectError(error.SdlFailure, display.closest_mode(.{
                .size = .{ .width = 1, .height = 1 },
            }));
        }
    }
    // SDL copied the request; list cleanup must not invalidate the selected mode query.
    if (view.fullscreen_mode()) |selected| {
        try std.testing.expectEqual(display, (try selected.info()).display);
    }
    try view.set_fullscreen_mode(null);
    try std.testing.expectEqual(@as(?sdl.display.Mode, null), view.fullscreen_mode());
    try view.show();
    try view.set_fullscreen(true);
    try view.sync();
    try std.testing.expect(
        sdl.raw.SDL_GetWindowFlags(view.handle) & sdl.raw.SDL_WINDOW_FULLSCREEN != 0,
    );
    try view.set_fullscreen(false);
    try view.sync();
    try std.testing.expect(
        sdl.raw.SDL_GetWindowFlags(view.handle) & sdl.raw.SDL_WINDOW_FULLSCREEN == 0,
    );
    const invalid = sdl.display.DisplayId.invalid;
    try std.testing.expectError(error.SdlFailure, invalid.modes());
    try std.testing.expectError(error.SdlFailure, invalid.desktop_mode());
    try std.testing.expectError(error.SdlFailure, invalid.current_mode());
    try std.testing.expectError(
        error.SdlFailure,
        invalid.closest_mode(.{ .size = .{ .width = 1, .height = 1 } }),
    );
    try std.testing.expectError(
        error.InvalidModeRequest,
        display.closest_mode(.{ .size = .{ .width = 0, .height = 1 } }),
    );
}

test "window options and runtime controls expose typed state" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "window state",
        .size = .{ .width = 32, .height = 32 },
        .hidden = true,
        .borderless = true,
        .always_on_top = true,
        .utility = true,
        .focusable = false,
    });
    defer window.deinit();
    const view = window.borrow();
    const original = view.flags();
    try std.testing.expect(original.contains(.hidden));
    try std.testing.expect(original.contains(.borderless));
    try std.testing.expect(original.contains(.always_on_top));
    try std.testing.expect(original.contains(.utility));
    try std.testing.expect(original.contains(.not_focusable));
    try std.testing.expect(!original.contains(.resizable));
    // Dummy exposes these flags at creation but lacks native runtime setters/actions.
    try std.testing.expectError(error.SdlFailure, view.set_bordered(true));
    try std.testing.expectError(error.SdlFailure, view.set_resizable(true));
    try std.testing.expectError(error.SdlFailure, view.set_always_on_top(false));
    try std.testing.expectEqual(original.bits, view.flags().bits);
    try view.show();
    try std.testing.expect(!view.flags().contains(.hidden));
    try std.testing.expect(original.contains(.hidden)); // Snapshots do not change with the window.
    try view.raise(); // Accepted; no focus guarantee on this backend.
    try std.testing.expectError(error.SdlFailure, view.maximize());
    try std.testing.expectError(error.SdlFailure, view.minimize());
    try std.testing.expectError(error.SdlFailure, view.restore());
    for ([_]sdl.video.GraphicsBackend{ .opengl, .vulkan, .metal }) |backend| {
        try std.testing.expectError(error.SdlFailure, sdl.video.Window.init(&.{
            .title = "unsupported graphics",
            .size = .{ .width = 1, .height = 1 },
            .hidden = true,
            .graphics_backend = backend,
        }));
    }
}

test "window constraints roundtrip and invalid requests preserve stored limits" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "constraints",
        .size = .{ .width = 64, .height = 48 },
        .hidden = true,
    });
    defer window.deinit();
    const view = window.borrow();
    try std.testing.expectEqualDeep(sdl.video.SizeLimits{}, try view.minimum_size());
    try std.testing.expectEqualDeep(sdl.video.SizeLimits{}, try view.maximum_size());
    try std.testing.expectEqualDeep(sdl.video.AspectLimits{}, try view.aspect_limits());
    const minimum = sdl.video.SizeLimits{ .width = 32, .height = 24 };
    const maximum = sdl.video.SizeLimits{ .width = 128, .height = 96 };
    try view.set_minimum_size(minimum);
    try view.set_maximum_size(maximum);
    try std.testing.expectEqualDeep(minimum, try view.minimum_size());
    try std.testing.expectEqualDeep(maximum, try view.maximum_size());
    try std.testing.expectError(error.InvalidConstraint, view.set_minimum_size(.{ .width = 0 }));
    try std.testing.expectError(error.SdlFailure, view.set_minimum_size(.{ .width = 129 }));
    try std.testing.expectError(error.SdlFailure, view.set_maximum_size(.{ .height = 23 }));
    try std.testing.expectEqualDeep(minimum, try view.minimum_size());
    try std.testing.expectEqualDeep(maximum, try view.maximum_size());
    const ratios = sdl.video.AspectLimits{ .minimum = 1, .maximum = 2 };
    try view.set_aspect_limits(ratios);
    try std.testing.expectEqualDeep(ratios, try view.aspect_limits());
    try std.testing.expectError(
        error.InvalidConstraint,
        view.set_aspect_limits(.{ .minimum = 3, .maximum = 2 }),
    );
    try std.testing.expectEqualDeep(ratios, try view.aspect_limits());
    try view.set_aspect_limits(.{ .minimum = 1.5, .maximum = 1.5 });
    try std.testing.expectEqual(@as(?f32, 1.5), (try view.aspect_limits()).minimum);
    try view.set_aspect_limits(.{});
    try view.set_minimum_size(.{ .height = 24 });
    try view.set_maximum_size(.{ .width = 128 });
    try std.testing.expectEqualDeep(sdl.video.SizeLimits{ .height = 24 }, try view.minimum_size());
    try std.testing.expectEqualDeep(sdl.video.SizeLimits{ .width = 128 }, try view.maximum_size());
    try view.set_minimum_size(.{});
    try view.set_maximum_size(.{});
    try std.testing.expectEqualDeep(sdl.video.SizeLimits{}, try view.minimum_size());
    try std.testing.expectEqualDeep(sdl.video.SizeLimits{}, try view.maximum_size());
    try std.testing.expectEqualDeep(sdl.video.AspectLimits{}, try view.aspect_limits());
}

test "window geometry queries and backend-specific presentation controls" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "geometry",
        .size = .{ .width = 64, .height = 48 },
        .hidden = true,
    });
    defer window.deinit();
    const view = window.borrow();
    try std.testing.expectEqualDeep(
        sdl.video.ClientArea{ .x = 0, .y = 0, .width = 64, .height = 48 },
        try view.safe_area(),
    );
    try std.testing.expectEqual(@as(f32, 1), try view.pixel_density());
    try view.set_size(.{ .width = 32, .height = 24 });
    try view.sync();
    try std.testing.expectEqual(@as(u32, 32), (try view.safe_area()).width);
    try std.testing.expectError(error.SdlFailure, view.border_sizes());
    try std.testing.expectEqual(@as(f32, 1), try view.opacity());
    try std.testing.expectError(error.InvalidOpacity, view.set_opacity(-1));
    try std.testing.expectError(error.InvalidOpacity, view.set_opacity(std.math.nan(f32)));
    try std.testing.expectError(error.SdlFailure, view.set_opacity(0.5));
    try std.testing.expectEqual(@as(f32, 1), try view.opacity());
    try view.set_focusable(false); // Dummy accepts without a native implementation/state change.
    try std.testing.expect(!view.flags().contains(.not_focusable));
    try view.set_focusable(true);
    {
        var icon = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 2 });
        defer icon.deinit();
        try icon.borrow().fill(.{ .r = 255, .g = 0, .b = 0 });
        try std.testing.expectError(error.SdlFailure, view.set_icon(icon.borrow()));
        try std.testing.expectEqual(
            @as(u8, 255),
            (try icon.borrow().read_pixel(.{ .x = 0, .y = 0 })).r,
        );
    } // Source is released before the window and its internally converted icon.
    for ([_]sdl.video.Attention{ .cancel, .briefly, .until_focused }) |operation| {
        try std.testing.expectError(error.SdlFailure, view.request_attention(operation));
    }
}

test "window lists borrow live owners and stale IDs resolve to absence" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var empty = try sdl.video.list_windows();
    defer empty.deinit();
    try std.testing.expectEqual(@as(usize, 0), empty.count);
    try std.testing.expectError(error.OutOfBounds, empty.get(0));
    var first = try sdl.video.Window.init(&.{
        .title = "first",
        .size = .{ .width = 16, .height = 16 },
        .hidden = true,
    });
    defer first.deinit();
    const first_id = try first.borrow().id();
    try std.testing.expectEqual(first.handle, first_id.resolve().?.handle);
    try std.testing.expect(first.borrow().parent() == null);
    try std.testing.expect(sdl.video.WindowId.invalid.resolve() == null);
    var snapshot: sdl.video.Windows = undefined;
    var second_id: sdl.video.WindowId = .invalid;
    {
        var second = try sdl.video.Window.init(&.{
            .title = "second",
            .size = .{ .width = 16, .height = 16 },
            .hidden = true,
        });
        defer second.deinit();
        second_id = try second.borrow().id();
        snapshot = try sdl.video.list_windows();
        errdefer snapshot.deinit();
        try std.testing.expectEqual(@as(usize, 2), snapshot.count);
        var found_first = false;
        var found_second = false;
        for (0..snapshot.count) |index| {
            const id = try (try snapshot.get(index)).id();
            found_first = found_first or id == first_id;
            found_second = found_second or id == second_id;
        }
        try std.testing.expect(found_first and found_second);
        try std.testing.expectError(error.OutOfBounds, snapshot.get(snapshot.count));
    }
    defer snapshot.deinit(); // Only frees the array, even though one window is already gone.
    try std.testing.expectEqual(@as(usize, 2), snapshot.count);
    try std.testing.expect(second_id.resolve() == null);
    var current = try sdl.video.list_windows();
    defer current.deinit();
    try std.testing.expectEqual(@as(usize, 1), current.count);
    try std.testing.expectEqual(first_id, try (try current.get(0)).id());
}

test "taskbar progress stores state independently of validated completion values" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "progress",
        .size = .{ .width = 16, .height = 16 },
        .hidden = true,
    });
    defer window.deinit();
    const view = window.borrow();
    try std.testing.expectEqual(sdl.video.ProgressState.none, try view.progress_state());
    try std.testing.expectEqual(@as(f32, 0), try view.progress_value());
    try view.set_progress_value(0.5);
    for ([_]sdl.video.ProgressState{ .normal, .paused, .failed, .indeterminate, .none }) |state| {
        try view.set_progress_state(state);
        try std.testing.expectEqual(state, try view.progress_state());
        try std.testing.expectEqual(@as(f32, 0.5), try view.progress_value());
    }
    for ([_]f32{ -1, 2, std.math.nan(f32), std.math.inf(f32) }) |value| {
        try std.testing.expectError(error.InvalidProgress, view.set_progress_value(value));
        try std.testing.expectEqual(@as(f32, 0.5), try view.progress_value());
    }
    try std.testing.expectError(
        error.SdlFailure,
        view.set_progress_state(@fromBackingInt(@as(c_int, -1))),
    );
    try std.testing.expectError(
        error.SdlFailure,
        view.set_progress_state(@fromBackingInt(@as(c_int, 99))),
    );
    try std.testing.expectEqual(sdl.video.ProgressState.none, try view.progress_state());
    try view.set_progress_value(0);
    try std.testing.expectEqual(@as(f32, 0), try view.progress_value());
    try view.set_progress_value(1);
    try std.testing.expectEqual(@as(f32, 1), try view.progress_value());
}

test "popup requests and hierarchy validation reject unsafe parent links" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var root = try sdl.video.Window.init(&.{
        .title = "root",
        .size = .{ .width = 16, .height = 16 },
        .hidden = true,
    });
    defer root.deinit();
    for ([_]sdl.video.PopupKind{ .tooltip, .menu }) |kind| {
        try std.testing.expectError(error.SdlFailure, sdl.video.Window.init_popup(root.borrow(), &.{
            .kind = kind,
            .size = .{ .width = 16, .height = 16 },
            .hidden = true,
        }));
    }
    try std.testing.expectError(error.InvalidSize, sdl.video.Window.init_popup(root.borrow(), &.{
        .kind = .tooltip,
        .size = .{ .width = 0, .height = 16 },
    }));
    try std.testing.expectError(
        error.InvalidPosition,
        sdl.video.Window.init_popup(root.borrow(), &.{
            .kind = .tooltip,
            .size = .{ .width = 16, .height = 16 },
            .offset = .{ .x = sdl.raw.SDL_WINDOWPOS_CENTERED, .y = 0 },
        }),
    );
    var first = try hierarchy_fixture_child(root.borrow());
    defer first.deinit();
    var sibling = try hierarchy_fixture_child(root.borrow());
    defer sibling.deinit();
    var descendant = try hierarchy_fixture_child(first.borrow());
    defer descendant.deinit();
    try std.testing.expectEqual(root.handle, first.borrow().parent().?.handle);
    try std.testing.expectEqual(first.handle, descendant.borrow().parent().?.handle);
    try std.testing.expectError(error.InvalidParent, first.borrow().set_parent(first.borrow()));
    try std.testing.expectError(error.InvalidParent, first.borrow().set_parent(sibling.borrow()));
    try std.testing.expectError(
        error.InvalidParent,
        first.borrow().set_parent(descendant.borrow()),
    );
    try std.testing.expectError(error.InvalidParent, root.borrow().set_parent(descendant.borrow()));
    try std.testing.expectError(error.SdlFailure, first.borrow().set_parent(null));
    try std.testing.expectError(error.SdlFailure, first.borrow().set_modal(true));
    try std.testing.expectEqual(root.handle, first.borrow().parent().?.handle);
    try std.testing.expect(!first.borrow().flags().contains(.modal));
}

test "parent validation bounds traversal without mutating deep native hierarchies" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var root = try sdl.video.Window.init(&.{
        .title = "deep root",
        .size = .{ .width = 1, .height = 1 },
        .hidden = true,
    });
    defer root.deinit();
    var children: [257]sdl.video.Window = undefined;
    var count: usize = 0;
    defer {
        while (count > 0) {
            count -= 1;
            children[count].deinit();
        }
    }
    var parent = root.borrow();
    for (&children) |*child| {
        child.* = try hierarchy_fixture_child(parent);
        count += 1;
        parent = child.borrow();
    }
    try std.testing.expectError(error.HierarchyTooDeep, root.borrow().set_parent(parent));
    try std.testing.expect(root.borrow().parent() == null);
}

// Dummy supports stored creation-time regular-window relationships, but not runtime reparenting
// or popups. Raw properties construct the hierarchy fixture; this is not popup-platform evidence.
fn hierarchy_fixture_child(parent: sdl.video.WindowRef) !sdl.video.Window {
    var properties = try sdl.properties.Properties.init();
    defer properties.deinit();
    const values = properties.borrow();
    try values.set(sdl.raw.SDL_PROP_WINDOW_CREATE_PARENT_POINTER, &.{ .pointer = parent.handle });
    try values.set(sdl.raw.SDL_PROP_WINDOW_CREATE_HIDDEN_BOOLEAN, &.{ .boolean = true });
    try values.set(sdl.raw.SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, &.{ .number = 16 });
    try values.set(sdl.raw.SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, &.{ .number = 16 });
    const handle = sdl.raw.SDL_CreateWindowWithProperties(properties.handle) orelse
        return error.SdlFailure;
    return .{ .handle = handle };
}

test "software window surfaces present, invalidate on resize, and release independently" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "software surface",
        .size = .{ .width = 16, .height = 12 },
        .hidden = true,
    });
    defer window.deinit();
    const view = window.borrow();
    try std.testing.expect(!view.has_surface());
    try std.testing.expectError(error.SdlFailure, view.present_surface());
    {
        const pixels = try view.surface();
        try std.testing.expect(view.has_surface());
        try std.testing.expectEqualDeep(sdl.video.Size{ .width = 16, .height = 12 }, pixels.size());
        const color = sdl.surface.Color{ .r = 42, .g = 84, .b = 126 };
        try pixels.fill(color);
        try std.testing.expectEqualDeep(color, try pixels.read_pixel(.{ .x = 5, .y = 5 }));
        try view.present_surface();
    }
    try view.set_size(.{ .width = 24, .height = 18 });
    try view.sync();
    // No access to the old surface: resize invalidates it, even when SDL retains a pointer.
    try std.testing.expectError(error.SdlFailure, view.present_surface());
    {
        const resized = try view.surface();
        try std.testing.expectEqualDeep(
            sdl.video.Size{ .width = 24, .height = 18 },
            resized.size(),
        );
        try resized.fill(.{ .r = 0, .g = 128, .b = 255 });
        try view.present_surface();
    }
    try std.testing.expectError(error.InvalidVSync, view.set_surface_vsync(.{ .interval = 0 }));
    for ([_]sdl.video.SurfaceVSync{ .disabled, .adaptive, .{ .interval = 1 } }) |mode| {
        try std.testing.expectError(error.SdlFailure, view.set_surface_vsync(mode));
    }
    try std.testing.expectError(error.SdlFailure, view.surface_vsync());
    try view.release_surface();
    try std.testing.expect(!view.has_surface());
    try std.testing.expectEqual(@as(u32, 24), (try view.size()).width);
    try std.testing.expectError(error.SdlFailure, view.present_surface());
    try view.release_surface(); // Native cleanup is valid without a surface.
    {
        const fresh = try view.surface();
        try fresh.fill(.{ .r = 12, .g = 34, .b = 56 });
        try view.present_surface();
    }
    try std.testing.expect(view.has_surface()); // Final surface belongs to window cleanup.
}

test "hidden window input requests differ from active grabs and confinement support" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var video = try sdl.init(.{ .video = true });
    defer video.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "input policy",
        .size = .{ .width = 32, .height = 32 },
        .hidden = true,
    });
    defer window.deinit();
    const view = window.borrow();
    try std.testing.expect(!view.mouse_grabbed());
    try std.testing.expect(!view.keyboard_grabbed());
    try std.testing.expect(sdl.video.grabbed_window() == null);
    try view.set_mouse_grab(true);
    try view.set_keyboard_grab(true);
    try std.testing.expect(!view.mouse_grabbed());
    try std.testing.expect(!view.keyboard_grabbed());
    try std.testing.expect(sdl.video.grabbed_window() == null);
    try view.set_mouse_grab(false);
    try view.set_keyboard_grab(false);
    try std.testing.expect(!view.relative_mouse_mode());
    try view.set_relative_mouse_mode(true);
    try std.testing.expect(view.relative_mouse_mode());
    try std.testing.expect(view.flags().contains(.mouse_relative_mode));
    try std.testing.expect(!view.mouse_grabbed());
    try view.set_relative_mouse_mode(false);
    try std.testing.expect(!view.relative_mouse_mode());
    try std.testing.expect(try view.mouse_confinement() == null);
    try std.testing.expectError(error.InvalidRegion, view.set_mouse_confinement(.{
        .x = 0,
        .y = 0,
        .width = 0,
        .height = 1,
    }));
    try std.testing.expectError(error.SdlFailure, view.set_mouse_confinement(.{
        .x = 0,
        .y = 0,
        .width = 16,
        .height = 16,
    }));
    try std.testing.expectError(error.SdlFailure, view.set_mouse_confinement(null));
    try std.testing.expect(try view.mouse_confinement() == null);
}
