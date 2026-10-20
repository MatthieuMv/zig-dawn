//! SDL3 for Zig: explicit initialization, owned resources, borrowed views, and error unions.
//! Import `sdl`, acquire the subsystems you need, then destroy children before their parents.
//! Owners must not be copied; Zig does not enforce their lifetimes. Native calls may allocate.
//! Video, renderer, and event-polling operations belong on the application's main thread.
//!
//! Desktop entry points currently call `raw.SDL_SetMainReady()` before initialization and
//! `raw.SDL_Quit()` after every SDL user has finished. Mobile/web entry-point adapters are pending.
//! Start with `init`, `video.Window`, `render.Renderer`, and `events.poll`.

/// Native C interoperability namespace. Bypasses Zig validation and ownership conventions.
/// Do not destroy a native object behind a Zig owner or retain borrowed native data blindly.
pub const raw = @import("sdl_abi");
/// Acquire subsystem references on the main thread; pair the returned `deinit` with `defer`.
/// Options default to false. Native backends may allocate/block; `SdlFailure` returns no owner.
/// Destroy dependent resources before releasing references. This does not own global shutdown.
/// See `InitOptions` for implied dependencies and `Subsystems` for cleanup rules.
pub const init = @import("core/init.zig").init;
/// Select required subsystems. Every option defaults to false; dependencies are enabled by SDL.
pub const InitOptions = @import("core/init.zig").Options;
/// Owner of initialization references, not of global process shutdown. Do not copy.
pub const Subsystems = @import("core/init.zig").Subsystems;
/// Native failure identity and borrowed/caller-buffer diagnostic text.
pub const errors = @import("core/errors.zig");
/// Window owners, borrowed views, identifiers, and coordinate/pixel size queries.
pub const video = @import("core/video.zig");
/// Display identity snapshots, desktop layout, scaling, and orientation queries.
pub const display = @import("core/display.zig");
/// Renderer and texture owners, borrowed drawing views, colors, and rectangles.
pub const render = @import("core/render.zig");
/// Pixel-format identities, classification, integer masks, and copied native metadata.
pub const pixels = @import("core/pixels.zig");
/// Owned CPU surfaces and borrowed pixel-dimension views; independent of video initialization.
pub const surface = @import("core/surface.zig");
/// Owned native file/memory streams and borrowed cursors with explicit cleanup.
pub const io = @import("core/io.zig");
/// Owned typed property groups, borrowed values, and scoped recursive locks.
pub const properties = @import("core/properties.zig");
/// Main-thread event polling, typed payloads, and a lossless raw fallback.
pub const events = @import("core/events.zig");

/// Return the linked SDL runtime version, not the version of the compile-time headers.
/// Encoded as `major * 1_000_000 + minor * 1_000 + patch`; 3.4.18 becomes 3_004_018.
/// Callable on any thread without initialization. No wrapper allocation or fallible result.
/// This reports version identity, not backend or codec availability.
pub fn version() u32 {
    return @intCast(raw.SDL_GetVersion());
}

test {
    _ = @import("core/init.zig");
    _ = errors;
    _ = video;
    _ = display;
    _ = render;
    _ = events;
    _ = surface;
    _ = pixels;
    _ = io;
    _ = properties;
    const std = @import("std");
    try std.testing.expectEqual(@as(u32, 3), version() / 1_000_000);
    try std.testing.expect(version() >= raw.SDL_VERSION);
}
