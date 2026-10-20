//! Poll on the main/video thread. SDL may pump OS events and occasionally block.
//! Unknown payloads preserve native data; pointers inside remain borrowed under SDL's contracts.
//! Process them before the next poll/pump. Copying this union does not retain pointed-to data.
const std = @import("std");
const c = @import("sdl_abi");
const WindowId = @import("video.zig").WindowId;

/// Physical key position, independent of the active keyboard layout.
/// Only Escape is named so far; unnamed numeric values remain valid and must be handled by `else`.
pub const Scancode = enum(u32) {
    /// Physical Escape key position.
    escape = c.SDL_SCANCODE_ESCAPE,
    _,
};
/// Layout-dependent virtual key identity. This is not text input; use text-input events for typing.
/// Only Escape is named so far; unnamed numeric values remain valid and must be handled by `else`.
pub const Keycode = enum(u32) {
    /// Escape key, normally used for cancel/exit shortcuts.
    escape = c.SDLK_ESCAPE,
    _,
};
/// Request associated with a window. The identifier does not keep that window alive.
pub const WindowEvent = struct {
    /// Nanoseconds on SDL's monotonic tick timeline, not Unix time; not a duration.
    timestamp_ns: u64,
    /// Window to which the request belongs. It may already have been destroyed when processed.
    window: WindowId,
};
/// New window dimensions. The event tag determines window-coordinate versus pixel units.
/// Signed native data is preserved, including negative values injected by external code.
pub const ResizeEvent = struct {
    /// Nanoseconds on SDL's tick timeline. Does not establish when the event was polled.
    timestamp_ns: u64,
    /// Associated window identity; does not retain the window.
    window: WindowId,
    /// New horizontal extent; validate before converting to unsigned creation dimensions.
    width: i32,
    /// New vertical extent; zero/minimized or externally injected values must be handled.
    height: i32,
};
/// Keyboard transition, not Unicode text. Prefer scancodes for physical controls and keycodes
/// for layout-aware shortcuts. Text-input payloads currently arrive through `Event.unknown`.
pub const KeyEvent = struct {
    /// Nanoseconds on SDL's tick timeline, not a wall-clock timestamp.
    timestamp_ns: u64,
    /// Window with keyboard focus, or `.invalid` when none is associated.
    window: WindowId,
    /// Device instance ID; zero means unknown or virtual. Does not retain a device.
    keyboard_id: u32,
    /// Physical key position; unknown numeric values are preserved.
    scancode: Scancode,
    /// Layout-dependent key identity; not necessarily a Unicode character.
    keycode: Keycode,
    /// Modifier bitmask. For example, `(modifiers & sdl.raw.SDL_KMOD_CTRL) != 0` tests either
    /// Control key; SDL_KMOD_SHIFT and SDL_KMOD_ALT work the same way. Named Zig flags are pending.
    modifiers: u16,
    /// Platform-dependent hardware scan value, unsuitable for portable key bindings.
    raw_scancode: u16,
    /// True for a press, false for a release in native events; copied without normalization.
    down: bool,
    /// True for an auto-repeat transition; ignore when an action should fire once per press.
    repeat: bool,
};
/// Poll result with value-owned typed payloads and a borrowed-pointer raw fallback.
/// Switching on `unknown` must not discard application-owned user data without its cleanup.
pub const Event = union(enum) {
    /// Application shutdown request; the application decides whether and when to exit.
    quit: struct {
        /// Nanoseconds on SDL's tick timeline, not Unix time.
        timestamp_ns: u64,
    },
    /// User requested closing a particular window. The window is not destroyed automatically.
    window_close_requested: WindowEvent,
    /// Client dimensions changed in window coordinates; not necessarily framebuffer pixels.
    window_resized: ResizeEvent,
    /// Drawable pixel dimensions changed; update size-dependent rendering resources as needed.
    window_pixel_size_changed: ResizeEvent,
    /// Key press, including auto-repeat; inspect `repeat` for edge-triggered actions.
    key_down: KeyEvent,
    /// Key release. Payload values are preserved, including externally pushed metadata.
    key_up: KeyEvent,
    /// Native event not yet wrapped, with its union payload intact. Pointer targets are not copied
    /// or retained. Consume borrowed data before another poll/pump; user data ownership remains
    /// with its original owner. A raw tag alone is insufficient to infer pointer cleanup rules.
    unknown: c.SDL_Event,
};

/// Remove and decode one event on the main/video thread; null means no event is available.
/// Requires event support (also enabled by video). No wrapper allocation or error union.
/// May pump OS events, so a non-waiting poll is not a guarantee of bounded latency.
/// Typed payloads can be retained by value. Consume borrowed `unknown` pointer data before
/// polling/pumping again. Bound the number of polls per frame so input cannot starve drawing.
///
/// ```zig
/// const sdl = @import("sdl");
/// sdl.raw.SDL_SetMainReady();
/// defer sdl.raw.SDL_Quit();
/// var subsystems = try sdl.init(.{ .events = true });
/// defer subsystems.deinit();
/// var quit_requested = false;
/// for (0..64) |_| {
///     const event = sdl.events.poll() orelse break;
///     switch (event) {
///         .quit => quit_requested = true,
///         .key_down => |key| if (key.keycode == .escape and !key.repeat) {
///             quit_requested = true;
///         },
///         else => {}, // This example does not register pointer-owning user events.
///     }
/// }
/// if (quit_requested) return;
/// ```
pub fn poll() ?Event {
    var native = std.mem.zeroes(c.SDL_Event);
    if (!c.SDL_PollEvent(&native)) return null;
    return from_native(&native);
}

/// Decode an initialized native event whose union member matches its type tag.
/// Performs no native calls, allocation, ownership transfer, or fallible validation. Callable
/// on any thread with exclusive/stable access to the input. Unknown numeric keys/tags survive.
/// Copies native unknown events by value but does not retain pointer data. The source union
/// may expire after this call; pointed-to storage still follows its original lifetime.
/// This is an interop contract, not a parser for arbitrary/uninitialized bytes.
pub fn from_native(native: *const c.SDL_Event) Event {
    return switch (native.type) {
        c.SDL_EVENT_QUIT => .{ .quit = .{ .timestamp_ns = native.common.timestamp } },
        c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => .{ .window_close_requested = .{
            .timestamp_ns = native.window.timestamp,
            .window = @fromBackingInt(@intCast(native.window.windowID)),
        } },
        c.SDL_EVENT_WINDOW_RESIZED => .{ .window_resized = resize_event(native) },
        c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => .{
            .window_pixel_size_changed = resize_event(native),
        },
        c.SDL_EVENT_KEY_DOWN => .{ .key_down = key_event(native) },
        c.SDL_EVENT_KEY_UP => .{ .key_up = key_event(native) },
        else => .{ .unknown = native.* },
    };
}

fn resize_event(native: *const c.SDL_Event) ResizeEvent {
    return .{
        .timestamp_ns = native.window.timestamp,
        .window = @fromBackingInt(@intCast(native.window.windowID)),
        .width = native.window.data1,
        .height = native.window.data2,
    };
}

fn key_event(native: *const c.SDL_Event) KeyEvent {
    return .{
        .timestamp_ns = native.key.timestamp,
        .window = @fromBackingInt(@intCast(native.key.windowID)),
        .keyboard_id = native.key.which,
        .scancode = @fromBackingInt(@intCast(native.key.scancode)),
        .keycode = @fromBackingInt(@intCast(native.key.key)),
        .modifiers = native.key.mod,
        .raw_scancode = native.key.raw,
        .down = native.key.down,
        .repeat = native.key.repeat,
    };
}

test "future key values and metadata survive decoding" {
    var native = std.mem.zeroes(c.SDL_Event);
    native.key.type = c.SDL_EVENT_KEY_DOWN;
    native.key.key = 0xf0000001;
    native.key.scancode = 0x12345;
    native.key.windowID = 42;
    native.key.timestamp = 1234;
    native.key.repeat = true;
    const event = from_native(&native).key_down;
    try std.testing.expectEqual(@as(u32, 0xf0000001), @backingInt(event.keycode));
    try std.testing.expectEqual(@as(u32, 0x12345), @backingInt(event.scancode));
    try std.testing.expectEqual(@as(u32, 42), @backingInt(event.window));
    try std.testing.expectEqual(@as(u64, 1234), event.timestamp_ns);
    try std.testing.expect(event.repeat);
}

test "unknown events preserve native payload and resize dimensions stay signed" {
    var native = std.mem.zeroes(c.SDL_Event);
    native.user.type = c.SDL_EVENT_USER;
    native.user.code = -123;
    var context: u8 = 9;
    native.user.data1 = &context;
    const unknown = from_native(&native).unknown;
    try std.testing.expectEqual(@as(c_int, -123), unknown.user.code);
    try std.testing.expectEqual(native.user.data1, unknown.user.data1);
    native = std.mem.zeroes(c.SDL_Event);
    native.window.type = c.SDL_EVENT_WINDOW_RESIZED;
    native.window.data1 = -1;
    try std.testing.expectEqual(@as(i32, -1), from_native(&native).window_resized.width);
}
