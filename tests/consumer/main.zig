const sdl = @import("sdl");

pub fn main() !void {
    // Application owns process-global shutdown, after its subsystem owners are gone.
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .events = true, .video = true });
    defer subsystems.deinit();
    try check_properties();
    try check_property_callbacks();
    try check_window_state();
    var displays = try sdl.display.list();
    defer displays.deinit();
    const primary = try sdl.display.primary();
    if (displays.items.len == 0 or (try primary.bounds()).width == 0)
        return error.MissingDisplay;
    var modes = try primary.modes();
    defer modes.deinit();
    const desktop = try primary.desktop_mode();
    if (desktop.format().name().len == 0) return error.MissingFormatName;
    if ((try desktop.info()).display != primary) return error.WrongModeDisplay;
    for (0..modes.count) |index| {
        if ((try (try modes.get(index)).info()).display != primary)
            return error.WrongModeDisplay;
    }
    try check_streams();
    try check_dynamic_stream();
    try check_callback_stream();
    try check_surface_pixels();
    try check_palettes();
    if (sdl.version() < sdl.raw.SDL_VERSION) return error.RuntimeTooOld;
    if (@import("options").extensions) {
        const image = @import("sdl_image");
        const mixer = @import("sdl_mixer");
        const ttf = @import("sdl_ttf");
        comptime {
            if (sdl.raw.SDL_Surface != image.raw.SDL_Surface or
                sdl.raw.SDL_AudioStream != mixer.raw.SDL_AudioStream or
                sdl.raw.SDL_Renderer != ttf.raw.SDL_Renderer)
                @compileError("extension ABI type identity differs from core");
        }
        var context = try ttf.init();
        defer context.deinit();
        var font = try context.open_font(@import("options").font_path ++ "", .{ .size_points = 24 });
        defer font.deinit();
        var text = try font.borrow().render("Aé", .{ .r = 255, .g = 255, .b = 255 });
        defer text.deinit();
        if (text.borrow().size().width == 0) return error.EmptyTextSurface;
        var surface = try sdl.surface.Surface.init_rgba(.{ .width = 2, .height = 2 });
        defer surface.deinit();
        var buffer: [4096]u8 = undefined;
        var output = try sdl.io.Stream.from_memory(&buffer);
        defer output.deinit();
        try image.save_png_stream(surface.borrow(), output.borrow());
        const length: usize = @intCast(try output.borrow().position());
        var decoded = try image.load_memory(buffer[0..length]);
        defer decoded.deinit();
        if (decoded.borrow().size().width != 2) return error.WrongImageSize;
        var audio_context = try mixer.init();
        defer audio_context.deinit();
        var offline = try audio_context.create_offline(.{ .channels = .mono });
        defer offline.deinit();
        var audio = try offline.borrow().load_audio(@import("options").audio_path ++ "", .{});
        defer audio.deinit();
        var track = try offline.borrow().create_track();
        defer track.deinit();
        try track.borrow().set_audio(audio.borrow());
        try track.borrow().play_with_options(.{ .looping = .{ .additional = 1 } });
        var samples: [32]f32 = undefined;
        if (try offline.generate(&samples) != samples.len) return error.MissingAudio;
        if (image.version() < image.raw.SDL_IMAGE_VERSION or
            mixer.version() < mixer.raw.SDL_MIXER_VERSION or
            ttf.version() < ttf.raw.SDL_TTF_VERSION) return error.RuntimeTooOld;
    }
}

fn check_properties() !void {
    var properties = try sdl.properties.Properties.init();
    defer properties.deinit();
    try properties.borrow().set("consumer", &.{ .boolean = true });
    if (!(try properties.borrow().get("consumer")).?.boolean) return error.MissingProperty;
    var names: [1][:0]const u8 = undefined;
    var bytes: [9]u8 = undefined;
    const snapshot = try properties.borrow().copy_names(&names, &bytes);
    if (!@import("std").mem.eql(u8, snapshot[0], "consumer")) return error.WrongPropertyName;
    var destination = try sdl.properties.Properties.init();
    defer destination.deinit();
    try properties.borrow().copy_to(destination.borrow());
    if (!(try destination.borrow().get("consumer")).?.boolean) return error.MissingCopy;
}

fn check_streams() !void {
    var storage: [3]u8 = undefined;
    var stream = try sdl.io.Stream.from_memory(&storage);
    defer stream.deinit();
    const view = stream.borrow();
    if (try view.size() != 3) return error.WrongStreamSize;
    const written = view.write("abc");
    if (written.count != 3 or written.status != .ready) return error.IncompleteWrite;
    try view.flush();
    _ = try view.seek(0, .start);
    var bytes: [4]u8 = undefined;
    const read = view.read(&bytes);
    if (!@import("std").mem.eql(u8, bytes[0..read.count], "abc")) return error.WrongStreamBytes;
    if (read.status != .end_of_stream) return error.MissingEndOfStream;
    _ = try view.seek(0, .start);
    if (view.write_int(u16, 0x1234, .big).count != 2) return error.IncompleteInteger;
    _ = try view.seek(0, .start);
    if (view.read_int(u16, .big).value != 0x1234) return error.WrongInteger;
}

fn check_dynamic_stream() !void {
    var stream = try sdl.io.DynamicStream.init(.{});
    const result = stream.borrow().write_int(u32, 0x12345678, .big);
    var bytes = try stream.finish();
    defer bytes.deinit();
    if (result.count != 4) return error.IncompleteDynamicWrite;
    if (!@import("std").mem.eql(u8, bytes.borrow(), &.{ 0x12, 0x34, 0x56, 0x78 }))
        return error.WrongDynamicBytes;
}

fn check_callback_stream() !void {
    const Sink = struct {
        count: usize = 0,
        fn write(self: *@This(), bytes: []const u8) anyerror!sdl.io.Transfer {
            self.count += bytes.len;
            return .{ .count = bytes.len, .status = .ready };
        }
    };
    var sink = Sink{};
    var stream = try sdl.io.Stream.from_callbacks(Sink, &sink, .{ .write = Sink.write });
    defer stream.deinit();
    if (stream.borrow().write_all("abc").count != 3 or sink.count != 3)
        return error.IncompleteCallbackWrite;
}

fn check_surface_pixels() !void {
    var surface = try sdl.surface.Surface.init_format(
        .{ .width = 2, .height = 1 },
        sdl.pixels.Format.rgba32,
    );
    defer surface.deinit();
    try surface.borrow().fill(.{ .r = 1, .g = 2, .b = 3 });
    const clip = try surface.borrow().set_clip(.{ .width = 1, .height = 1 });
    if (clip.width != 1 or (try surface.borrow().clip()).width != 1) return error.WrongClip;
    try surface.borrow().fill_rect(
        .{ .x = -1, .width = 3, .height = 1 },
        .{ .r = 3, .g = 2, .b = 1 },
    );
    _ = try surface.borrow().set_clip(null);
    try surface.borrow().write_pixel(.{ .x = 1, .y = 0 }, .{ .r = 9, .g = 8, .b = 7 });
    var copy = try surface.borrow().duplicate();
    defer copy.deinit();
    var reduced = try copy.borrow().to_format(.rgb565);
    defer reduced.deinit();
    if (reduced.borrow().format() != .rgb565) return error.WrongConvertedFormat;
    var rgba = try copy.borrow().to_rgba();
    defer rgba.deinit();
    {
        var pixels = try rgba.borrow().lock_rgba();
        defer pixels.deinit();
        const row = try pixels.row(0);
        @memcpy(row[4..8], &[_]u8{ 9, 8, 7, 255 });
    }
    try rgba.borrow().set_tint(.{ .r = 128 });
    try rgba.borrow().set_opacity(64);
    if ((try rgba.borrow().tint()).r != 128 or try rgba.borrow().opacity() != 64)
        return error.WrongSurfaceModulation;
    try rgba.borrow().set_tint(.{});
    try rgba.borrow().set_opacity(255);
    try rgba.borrow().set_blend_mode(.none);
    if (try rgba.borrow().blend_mode() != .none) return error.WrongBlendMode;
    try rgba.borrow().blit_to(surface.borrow());
    var scaled = try sdl.surface.Surface.init_rgba(.{ .width = 4, .height = 2 });
    defer scaled.deinit();
    try rgba.borrow().blit_scaled_to(scaled.borrow(), .nearest);
    try rgba.borrow().blit_region_to(scaled.borrow(), &.{
        .source = .{ .x = 1, .width = 1, .height = 1 },
        .destination = .{ .x = 3, .y = 1 },
    });
    try rgba.borrow().blit_scaled_region_to(scaled.borrow(), &.{
        .source = .{ .x = 1, .width = 1, .height = 1 },
        .destination = .{ .x = 2, .width = 2, .height = 2 },
        .mode = .nearest,
    });
    const pixel = try scaled.borrow().read_pixel(.{ .x = 3, .y = 1 });
    if (pixel.r != 9 or pixel.g != 8 or pixel.b != 7 or pixel.a != 255)
        return error.WrongSurfacePixel;
}

fn check_property_callbacks() !void {
    const State = struct {
        released: bool = false,
        visits: u32 = 0,
        fn cleanup(self: *@This()) void {
            self.released = true;
        }
        fn visit(self: *@This(), _: sdl.properties.PropertiesRef, _: [:0]const u8) anyerror!void {
            self.visits += 1;
        }
    };
    var state = State{};
    var properties = try sdl.properties.Properties.init();
    defer properties.deinit();
    try properties.borrow().set_owned_pointer("owned", State, &state, State.cleanup);
    try properties.borrow().visit(State, &state, State.visit);
    try properties.borrow().clear("owned");
    if (!state.released or state.visits != 1) return error.WrongPropertyCallbacks;
}

fn check_window_state() !void {
    var window = try sdl.video.Window.init(&.{
        .title = "consumer",
        .size = .{ .width = 32, .height = 32 },
        .hidden = true,
        .resizable = true,
        .borderless = true,
    });
    defer window.deinit();
    try window.borrow().set_minimum_size(.{ .width = 16 });
    try window.borrow().set_maximum_size(.{ .height = 64 });
    try window.borrow().set_aspect_limits(.{ .minimum = 1, .maximum = 2 });
    if ((try window.borrow().minimum_size()).width != 16 or
        (try window.borrow().maximum_size()).height != 64 or
        (try window.borrow().aspect_limits()).maximum != 2)
        return error.WrongWindowConstraints;
    if ((try window.borrow().safe_area()).width == 0 or
        try window.borrow().pixel_density() <= 0 or try window.borrow().opacity() != 1)
        return error.WrongWindowGeometry;
    const id = try window.borrow().id();
    if (id.resolve() == null or window.borrow().parent() != null) return error.WrongWindowLookup;
    var windows = try sdl.video.list_windows();
    defer windows.deinit();
    if (windows.count == 0) return error.MissingWindow;
    try window.borrow().set_progress_state(.normal);
    try window.borrow().set_progress_value(0.5);
    if (try window.borrow().progress_state() != .normal or
        try window.borrow().progress_value() != 0.5) return error.WrongProgress;
    {
        const surface = try window.borrow().surface();
        _ = try surface.format().details();
        _ = try window.borrow().pixel_format();
        try surface.fill(.{ .r = 10, .g = 20, .b = 30 });
        try window.borrow().present_surface();
    }
    try window.borrow().release_surface();
    if (window.borrow().has_surface()) return error.UnreleasedWindowSurface;
    try window.borrow().set_relative_mouse_mode(true);
    if (!window.borrow().relative_mouse_mode()) return error.MissingRelativeMode;
    try window.borrow().set_relative_mouse_mode(false);
    try window.borrow().set_mouse_grab(false);
    try window.borrow().set_keyboard_grab(false);
    if (window.borrow().mouse_grabbed() or window.borrow().keyboard_grabbed() or
        sdl.video.grabbed_window() != null) return error.UnexpectedGrab;
    const flags = window.borrow().flags();
    if (!flags.contains(.resizable) or !flags.contains(.borderless) or !flags.contains(.hidden))
        return error.WrongWindowState;
}

fn check_palettes() !void {
    var surface = try sdl.surface.Surface.init_format(.{ .width = 2, .height = 2 }, .index8);
    defer surface.deinit();
    {
        var palette = try sdl.pixels.Palette.init(2);
        defer palette.deinit();
        try palette.borrow().set_colors(0, &.{
            .{ .r = 0, .g = 0, .b = 0 }, .{ .r = 255, .g = 0, .b = 0 },
        });
        try surface.borrow().set_palette(palette.borrow());
    }
    const retained = surface.borrow().palette() orelse return error.MissingPalette;
    if ((try retained.get(1)).r != 255) return error.WrongPaletteColor;
    try surface.borrow().fill(.{ .r = 255, .g = 0, .b = 0 });
    var converted = try surface.borrow().to_rgba();
    defer converted.deinit();
    if ((try converted.borrow().read_pixel(.{ .x = 0, .y = 0 })).r != 255)
        return error.WrongPaletteConversion;
}
