//! Reference-counted subsystem initialization. Acquire only what your application needs.
//! Initialization belongs on the main thread. SDL may allocate and initialize native backends.
//! Release dependent objects first, then subsystem owners, then process-global SDL shutdown.
const std = @import("std");
const c = @import("sdl_abi");
const Error = @import("errors.zig").Error;

/// Subsystems to acquire. All default to false; SDL also initializes implied dependencies.
/// This does not select drivers or guarantee that a requested device/backend exists.
pub const Options = struct {
    /// Playback/recording support; also enables events.
    audio: bool = false,
    /// Windows, rendering, and input support; also enables events.
    video: bool = false,
    /// Joystick device support; also enables events.
    joystick: bool = false,
    /// Force-feedback device support.
    haptic: bool = false,
    /// Mapped gamepad support; also enables joystick support.
    gamepad: bool = false,
    /// Event queue support, useful without opening a window.
    events: bool = false,
    /// Sensor device support; also enables events.
    sensor: bool = false,
    /// Camera capture support; also enables events.
    camera: bool = false,

    fn native(self: Options) c.SDL_InitFlags {
        var flags: c.SDL_InitFlags = 0;
        if (self.audio) flags |= c.SDL_INIT_AUDIO;
        if (self.video) flags |= c.SDL_INIT_VIDEO;
        if (self.joystick) flags |= c.SDL_INIT_JOYSTICK;
        if (self.haptic) flags |= c.SDL_INIT_HAPTIC;
        if (self.gamepad) flags |= c.SDL_INIT_GAMEPAD;
        if (self.events) flags |= c.SDL_INIT_EVENTS;
        if (self.sensor) flags |= c.SDL_INIT_SENSOR;
        if (self.camera) flags |= c.SDL_INIT_CAMERA;
        return flags;
    }
};

/// Owns one initialization reference for each requested subsystem. Do not copy.
/// Destroy dependent resources before deinit. Initialize on the main thread;
/// serialize cleanup on that thread. Does not own SDL's process-wide shutdown; call raw.SDL_Quit
/// only after all SDL users have finished, at the application's boundary.
pub const Subsystems = struct {
    /// Native acquisition mask. Internal ownership bookkeeping; do not modify or fabricate it.
    flags: c.SDL_InitFlags,

    /// Release this owner's subsystem references after destroying all dependent resources.
    /// Serialize on the main thread. Invalidates this value; call exactly once, never on copies.
    /// Other independently acquired subsystem references remain live. No fallible result.
    pub fn deinit(self: *Subsystems) void {
        c.SDL_QuitSubSystem(self.flags);
        self.* = undefined;
    }
};

/// Acquire one owner for the requested subsystem references on the main thread.
/// Options are copied; nothing supplied by the caller is retained. SDL may allocate or block
/// while initializing backends. `SdlFailure` means acquisition failed; no owner is returned.
/// Inspect `errors.message()` immediately for native diagnostics. All-false options are allowed.
///
/// ```zig
/// const sdl = @import("sdl");
/// sdl.raw.SDL_SetMainReady(); // Desktop entry-point setup, currently an explicit native call.
/// defer sdl.raw.SDL_Quit(); // Application-level shutdown, after all subsystem owners.
/// var subsystems = try sdl.init(.{ .events = true });
/// defer subsystems.deinit();
/// ```
pub fn init(options: Options) Error!Subsystems {
    const flags = options.native();
    if (!c.SDL_InitSubSystem(flags)) return error.SdlFailure;
    return .{ .flags = flags };
}

test "independent initialization references survive sibling cleanup" {
    defer c.SDL_Quit();
    var first = try init(.{ .events = true });
    var first_live = true;
    defer if (first_live) first.deinit();
    var second = try init(.{ .events = true });
    defer second.deinit();
    first.deinit();
    first_live = false;
    try std.testing.expectEqual(c.SDL_INIT_EVENTS, c.SDL_WasInit(c.SDL_INIT_EVENTS));
}
