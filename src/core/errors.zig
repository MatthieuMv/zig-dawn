//! Native failures use a stable Zig error; diagnostic text stays in thread-local SDL storage.
//! Read text only after a native call reports failure. A nonempty message does not prove failure:
//! successful calls need not clear a previous message. Wrapper validation errors do not set it.
const std = @import("std");
const c = @import("sdl_abi");

/// Shared native failure error set. Specific operations may add wrapper validation errors.
pub const Error = error{
    /// A native operation reported failure; inspect `message` before another SDL call.
    SdlFailure,
};

/// Borrow the last native diagnostic on the calling thread as a zero-terminated byte slice.
/// Valid until that thread's diagnostic changes. Copy before subsequent SDL calls or cleanup
/// if the text must survive; do not free it. No wrapper allocation and no initialization needed.
/// An empty string is valid. Do not use this function to decide whether an operation failed.
pub fn message() [:0]const u8 {
    return std.mem.span(c.SDL_GetError());
}

/// Copy the calling thread's diagnostic into caller-owned storage without allocation/truncation.
/// Returns a slice of `buffer`; no terminating zero is appended or counted. An empty message
/// accepts an empty buffer. `BufferTooSmall` leaves every destination byte unchanged.
/// Buffer must not overlap SDL's diagnostic storage. The result survives later SDL calls but
/// expires when the caller reuses/frees the buffer. No initialization or main-thread requirement.
pub fn copy_message(buffer: []u8) error{BufferTooSmall}![]const u8 {
    const source = message();
    if (source.len > buffer.len) return error.BufferTooSmall;
    @memcpy(buffer[0..source.len], source);
    return buffer[0..source.len];
}

test "diagnostics copy preserves destination on insufficient capacity" {
    _ = c.SDL_SetError("binding diagnostic");
    defer _ = c.SDL_ClearError();
    var small = [_]u8{ 0xaa, 0xaa };
    try std.testing.expectError(error.BufferTooSmall, copy_message(&small));
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa }, &small);
    var buffer: [18]u8 = undefined;
    try std.testing.expectEqualStrings("binding diagnostic", try copy_message(&buffer));
    _ = c.SDL_ClearError();
    try std.testing.expectEqualStrings("binding diagnostic", &buffer);
    try std.testing.expectEqualStrings("", try copy_message(&.{}));
}
