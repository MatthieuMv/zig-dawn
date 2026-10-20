const sdl = @import("sdl");

pub fn main() !void {
    // Desktop Zig entry point. Other platform entry-point adapters are still pending.
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var subsystems = try sdl.init(.{ .video = true });
    defer subsystems.deinit();
    var window = try sdl.video.Window.init(&.{
        .title = "zig-sdl3: Escape or close to exit",
        .size = .{ .width = 640, .height = 480 },
        .resizable = true,
    });
    defer window.deinit();
    var renderer = try sdl.render.Renderer.init(window.borrow(), .{});
    defer renderer.deinit();
    const pixels = [_]u8{ 240, 160, 40, 255 };
    var texture = try sdl.render.Texture.init_rgba(
        renderer.borrow(),
        .{ .width = 1, .height = 1 },
        &pixels,
    );
    defer texture.deinit();
    const window_id = try window.borrow().id();
    // Bounded demonstration: roughly ten seconds, at most 64 events per frame.
    for (0..600) |_| {
        for (0..64) |_| {
            const event = sdl.events.poll() orelse break;
            switch (event) {
                .quit => return,
                .window_close_requested => |close| if (close.window == window_id) return,
                .key_down => |key| if (key.window == window_id and key.keycode == .escape) return,
                else => {},
            }
        }
        const drawing = renderer.borrow();
        try drawing.set_color(.{ .r = 22, .g = 28, .b = 38 });
        try drawing.clear();
        try drawing.draw_texture(texture.borrow(), .{
            .x = 220,
            .y = 160,
            .width = 200,
            .height = 160,
        });
        try drawing.present();
        sdl.raw.SDL_Delay(16);
    }
}
