const sdl = @import("sdl");
const image = @import("sdl_image");
const ttf = @import("sdl_ttf");
const mix = @import("sdl_mixer");
const assets = @import("example_assets");

pub fn main() !void {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .video = true });
    defer subsystems.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "zig-sdl3: image, text, audio",
        .size = .{ .width = 320, .height = 240 },
    });
    defer window.deinit();
    var renderer = try sdl.render.Renderer.init(window.borrow(), .{ .driver = "software" });
    defer renderer.deinit();
    var picture = uploaded: {
        var surface = try image.load(assets.image_path ++ "");
        defer surface.deinit();
        break :uploaded try sdl.render.Texture.from_surface(renderer.borrow(), surface.borrow());
    };
    defer picture.deinit();
    var label = uploaded: {
        var context = try ttf.init();
        defer context.deinit();
        var font = try context.open_font(assets.font_path ++ "", .{ .size_points = 32 });
        defer font.deinit();
        var surface = try font.borrow().render("Aé", .{ .r = 255, .g = 255, .b = 255 });
        defer surface.deinit();
        break :uploaded try sdl.render.Texture.from_surface(renderer.borrow(), surface.borrow());
    };
    defer label.deinit();
    var context = try mix.init();
    defer context.deinit();
    var playback = try context.create_playback();
    defer playback.deinit();
    var track = try playback.borrow().create_track();
    defer track.deinit();
    {
        var audio = try playback.borrow().load_audio(assets.audio_path ++ "", .{});
        defer audio.deinit();
        try track.borrow().set_audio(audio.borrow());
    }
    try track.borrow().play();
    try draw_frames(renderer.borrow(), picture.borrow(), label.borrow());
}

fn draw_frames(
    drawing: sdl.render.RendererRef,
    picture: sdl.render.TextureRef,
    label: sdl.render.TextureRef,
) !void {
    // About two seconds, with bounded event work. Fixtures test integration, not typography/audio.
    for (0..120) |_| {
        for (0..64) |_| {
            const event = sdl.events.poll() orelse break;
            switch (event) {
                .quit, .window_close_requested => return,
                .key_down => |key| if (key.keycode == .escape) return,
                else => {},
            }
        }
        try drawing.set_color(.{ .r = 20, .g = 30, .b = 40 });
        try drawing.clear();
        try drawing.draw_texture(picture, .{ .x = 20, .y = 20, .width = 280, .height = 140 });
        try drawing.draw_texture(label, .{ .x = 20, .y = 180, .width = 80, .height = 40 });
        try drawing.present();
        sdl.raw.SDL_Delay(16);
    }
}
