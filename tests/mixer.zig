const std = @import("std");
const sdl = @import("sdl");
const mix = @import("sdl_mixer");
const wave = @embedFile("fixtures/tone.wav");

test "offline output bounds and reference-balanced contexts" {
    var context = try mix.init();
    defer context.deinit();
    {
        var extra = try mix.init();
        defer extra.deinit();
    }
    try std.testing.expectError(
        error.InvalidSampleRate,
        context.create_offline(.{ .sample_rate = 0 }),
    );
    try std.testing.expectError(error.InvalidSampleRate, context.create_offline(.{
        .sample_rate = std.math.maxInt(u32),
    }));
    var offline = try context.create_offline(.{});
    defer offline.deinit();
    var bad = [_]f32{ 1, 2, 3 };
    try std.testing.expectError(error.InvalidBuffer, offline.generate(&bad));
    try std.testing.expectEqualSlices(f32, &.{ 1, 2, 3 }, &bad);
    try std.testing.expectEqual(@as(usize, 0), try offline.generate(&.{}));
    var output: [128]f32 = undefined;
    try std.testing.expectEqual(@as(usize, 0), try offline.generate(&output));
    try expect_silence(&output);
}

test "audio survives input and owner release, plays once, restarts and stops" {
    var context = try mix.init();
    defer context.deinit();
    var offline = try context.create_offline(.{});
    defer offline.deinit();
    var track = try offline.borrow().create_track();
    defer track.deinit();
    const control = track.borrow();
    try std.testing.expect(!control.is_playing());
    try std.testing.expectError(error.SdlFailure, control.play());
    for ([_]bool{ true, false }) |predecode| {
        {
            var bytes = wave.*;
            var audio = loaded: {
                var stream = try sdl.io.Stream.from_const_memory(&bytes);
                defer stream.deinit();
                break :loaded try offline.borrow().load_audio_stream(stream.borrow(), .{
                    .predecode = predecode,
                });
            };
            defer audio.deinit();
            @memset(&bytes, 0);
            try control.set_audio(audio.borrow());
        }
        try control.play();
        try std.testing.expect(control.is_playing());
        var first: [64]f32 = undefined;
        try std.testing.expectEqual(@as(usize, 32), try offline.generate(&first));
        try expect_signal(&first);
        var rest: [2048]f32 = undefined;
        const frames = try offline.generate(&rest);
        try std.testing.expect(frames > 0 and frames < rest.len / 2);
        try expect_silence(rest[frames * 2 ..]);
        try std.testing.expect(!control.is_playing());
        try control.play();
        _ = try offline.generate(&first);
        try expect_signal(&first);
        try control.stop();
        try control.stop();
        try std.testing.expect(!control.is_playing());
        try std.testing.expectEqual(@as(usize, 0), try offline.generate(&first));
        try expect_silence(&first);
    }
    try control.set_audio(null);
    try std.testing.expectError(error.SdlFailure, control.play());
}

fn expect_silence(samples: []const f32) !void {
    for (samples) |sample| try std.testing.expectEqual(@as(f32, 0), sample);
}

fn expect_signal(samples: []const f32) !void {
    var peak: f32 = 0;
    for (samples) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        peak = @max(peak, @abs(sample));
    }
    try std.testing.expect(peak > 0.1 and peak < 0.6);
}

test "file loading, bad input recovery, and sharing audio across mixers" {
    var context = try mix.init();
    defer context.deinit();
    var first = try context.create_offline(.{ .channels = .mono });
    defer first.deinit();
    var second = try context.create_offline(.{ .channels = .mono });
    defer second.deinit();
    try std.testing.expectError(error.SdlFailure, first.borrow().load_audio("", .{}));
    var bad = try sdl.io.Stream.from_const_memory("bad audio");
    defer bad.deinit();
    try std.testing.expectError(
        error.SdlFailure,
        first.borrow().load_audio_stream(bad.borrow(), .{}),
    );
    _ = try bad.borrow().seek(0, .start);
    var audio = try first.borrow().load_audio(@import("fixtures").audio_path ++ "", .{});
    defer audio.deinit();
    var track = try second.borrow().create_track();
    defer track.deinit();
    try track.borrow().set_audio(audio.borrow());
    try track.borrow().play();
    var output: [32]f32 = undefined;
    try std.testing.expectEqual(@as(usize, 32), try second.generate(&output));
    try expect_signal(&output);
}

test "default playback device lifecycle with dummy audio" {
    sdl.raw.SDL_SetMainReady();
    defer sdl.raw.SDL_Quit();
    var context = try mix.init();
    defer context.deinit();
    var playback = try context.create_playback();
    defer playback.deinit();
    var audio = try playback.borrow().load_audio(@import("fixtures").audio_path ++ "", .{});
    defer audio.deinit();
    var track = try playback.borrow().create_track();
    defer track.deinit();
    try track.borrow().set_audio(audio.borrow());
    try track.borrow().play();
    // No timing assertion: the device's audio thread may already have consumed the tiny fixture.
    try track.borrow().stop();
    try std.testing.expect(!track.borrow().is_playing());
}

test "typed loop options repeat exact frames and reject excessive counts without restarting" {
    var context = try mix.init();
    defer context.deinit();
    var offline = try context.create_offline(.{ .channels = .mono });
    defer offline.deinit();
    var audio = try offline.borrow().load_audio(@import("fixtures").audio_path ++ "", .{});
    defer audio.deinit();
    var track = try offline.borrow().create_track();
    defer track.deinit();
    const control = track.borrow();
    try control.set_audio(audio.borrow());
    var output: [1024]f32 = undefined;
    try control.play_with_options(.{});
    try std.testing.expectEqual(@as(usize, 256), try offline.generate(&output));
    try control.play_with_options(.{ .looping = .{ .additional = 0 } });
    try std.testing.expectEqual(@as(usize, 256), try offline.generate(&output));
    try control.play_with_options(.{ .looping = .{ .additional = 1 } });
    try std.testing.expectEqual(@as(usize, 512), try offline.generate(&output));
    try std.testing.expectEqualSlices(f32, output[0..256], output[256..512]);
    try expect_silence(output[512..]);
    try std.testing.expect(!control.is_playing());
    try control.play_with_options(.{ .looping = .forever });
    for (0..3) |_| {
        try std.testing.expectEqual(output.len, try offline.generate(&output));
        try expect_signal(&output);
    }
    try std.testing.expect(control.is_playing());
    try control.stop();
    try control.play_with_options(.{ .looping = .{ .additional = std.math.maxInt(c_int) } });
    try std.testing.expectEqual(@as(usize, 32), try offline.generate(output[0..32]));
    try control.stop();
    try control.play();
    _ = try offline.generate(output[0..32]);
    try std.testing.expectError(error.InvalidLoopCount, control.play_with_options(.{
        .looping = .{ .additional = std.math.maxInt(u32) },
    }));
    try std.testing.expectError(error.InvalidLoopCount, control.play_with_options(.{
        .looping = .{ .additional = @as(u32, std.math.maxInt(c_int)) + 1 },
    }));
    // Rejected configuration must not reset the existing 256-frame input to its beginning.
    try std.testing.expectEqual(@as(usize, 224), try offline.generate(&output));
}
