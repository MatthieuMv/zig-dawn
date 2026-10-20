//! SDL_mixer: audio decoding/mixing. Requires the corresponding optional build dependency.
//! Own a Context, create a playback or offline mixer, then load audio and play it on tracks.
//! All wrapper operations use the main thread; no calls from native audio callbacks are supported.
//! Native decoding, mixing, and device synchronization may allocate or block.
/// Native C declarations sharing core SDL type identity. No Zig ownership or validation layer.
/// Native resources must use their matching native destroy function and documented lifetime.
pub const raw = @import("sdl_abi");

/// Return the linked SDL_mixer runtime version, without initializing the library.
/// Encoding: `major * 1_000_000 + minor * 1_000 + patch`. Callable from any thread.
/// No wrapper allocation or fallible result; the value does not establish codec availability.
pub fn version() u32 {
    return @intCast(raw.MIX_Version());
}

test "native version matches header major and meets header version" {
    try std.testing.expect(@import("sdl").raw.SDL_Surface == raw.SDL_Surface);
    try std.testing.expectEqual(@as(u32, 3), version() / 1_000_000);
    try std.testing.expect(version() >= raw.SDL_MIXER_VERSION);
}

const std = @import("std");
const sdl = @import("sdl");

/// Native failures plus invalid output/playback configuration. Validation does not set SDL errors.
pub const Error = sdl.errors.Error || error{
    /// Sample rate must be positive and fit a signed C integer.
    InvalidSampleRate,
    /// Output must contain whole frames and its byte count must fit a signed C integer.
    InvalidBuffer,
    /// Additional playback repetitions must fit the native signed C integer.
    InvalidLoopCount,
};

/// Interleaved output channel count. Surround channel layouts remain unwrapped.
pub const Channels = enum(u8) {
    /// One sample per frame.
    mono = 1,
    /// Left then right sample for each frame.
    stereo = 2,
};

/// Offline native-endian float32 output. No hardware device is opened.
pub const OfflineOptions = struct {
    /// Frames per second; positive and at most maxInt(c_int).
    sample_rate: u32 = 48_000,
    /// Interleaved channel layout; stereo by default.
    channels: Channels = .stereo,
};

/// Audio loading tradeoff; data is always cached in native memory.
pub const LoadOptions = struct {
    /// Decode to PCM during loading (default), increasing memory to reduce later decoding work.
    /// False retains compressed data and decodes during playback. Neither promises allocation-free
    /// playback. Native codec availability depends on the installed library.
    predecode: bool = true,
};

/// Number of repetitions after the initial playback. No negative sentinel values are needed.
pub const Looping = union(enum) {
    /// Play the input once (default).
    once,
    /// Repeat this many additional times; zero is equivalent to once. At most maxInt(c_int).
    additional: u32,
    /// Repeat indefinitely; explicitly stop or clear input to end playback.
    forever,
};

/// Playback settings. Seeking, fades, limits, and other native playback properties remain default.
pub const PlayOptions = struct {
    /// Repeat policy; once by default. Assigned cached Audio inputs support rewinding.
    looping: Looping = .once,
};

/// Acquire one mixer initialization reference on the main thread; native code may allocate.
/// `SdlFailure` returns no owner. Release every track/mixer/audio owner before this context.
/// No SDL audio initialization is needed for offline work; device creation initializes it itself.
pub fn init() sdl.errors.Error!Context {
    if (!raw.MIX_Init()) return error.SdlFailure;
    return .{};
}

/// Owns one initialization reference. Do not copy; close all dependent resources first.
/// Serialize initialization/shutdown globally, even when using native interop from other threads.
pub const Context = struct {
    /// Release this reference on the main thread, after all owned mixer resources. Exactly once.
    /// Final native shutdown destroys remaining resources; later owner cleanup would be invalid.
    pub fn deinit(self: *Context) void {
        raw.MIX_Quit();
        self.* = undefined;
    }

    /// Open default playback using the system-selected format on the main thread.
    /// Native code acquires an audio subsystem reference and opens a device; may block/allocate.
    /// `SdlFailure` returns no mixer. Context outlives the returned owner and its tracks.
    /// Device selection and preferred format are not wrapped yet. Caller owns global SDL shutdown.
    pub fn create_playback(self: *const Context) sdl.errors.Error!Mixer {
        _ = self;
        const handle = raw.MIX_CreateMixerDevice(raw.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, null) orelse
            return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Create a float32 offline mixer on the main thread; context must outlive it and its tracks.
    /// `InvalidSampleRate` rejects bad input before allocation; `SdlFailure` returns no owner.
    /// Generates only when requested: no device, wall-clock timing, or audio subsystem is required.
    /// Native format conversion and mixing can allocate even after creation.
    ///
    /// ```zig
    /// const mixer = @import("sdl_mixer");
    /// var context = try mixer.init();
    /// defer context.deinit();
    /// var offline = try context.create_offline(.{ .channels = .mono });
    /// defer offline.deinit();
    /// var output: [64]f32 = undefined;
    /// // No tracks: initializes the whole buffer to silence and returns zero mixed frames.
    /// try @import("std").testing.expectEqual(@as(usize, 0), try offline.generate(&output));
    /// for (output) |sample| try @import("std").testing.expectEqual(@as(f32, 0), sample);
    /// ```
    pub fn create_offline(self: *const Context, options: OfflineOptions) Error!OfflineMixer {
        _ = self;
        if (options.sample_rate == 0 or options.sample_rate > std.math.maxInt(c_int)) {
            return error.InvalidSampleRate;
        }
        const spec = raw.SDL_AudioSpec{
            .format = raw.SDL_AUDIO_F32,
            .channels = @backingInt(options.channels),
            .freq = @intCast(options.sample_rate),
        };
        const handle = raw.MIX_CreateMixer(&spec) orelse return error.SdlFailure;
        return .{ .mixer = .{ .handle = handle }, .channels = options.channels };
    }
};

/// Owns a mixer. Do not copy; destroy its track owners before deinit and its context afterward.
pub const Mixer = struct {
    /// Native interop handle. Never destroy separately or let native shutdown invalidate it.
    handle: *raw.MIX_Mixer,

    /// Destroy on the main thread after all tracks. Closes an attached device and releases its
    /// audio subsystem reference. Does not destroy caller-owned Audio objects. May block.
    /// Exactly once; invalidates owner/views. No fallible result.
    pub fn deinit(self: *Mixer) void {
        raw.MIX_DestroyMixer(self.handle);
        self.* = undefined;
    }

    /// Borrow without allocation or native calls. Owner/context must outlive the view.
    pub fn borrow(self: *const Mixer) MixerRef {
        return .{ .handle = self.handle };
    }
};

/// Owns an offline float32 mixer. Do not copy; all tracks must close before deinit.
pub const OfflineMixer = struct {
    /// Embedded owner. Use this object's deinit, never destroy the embedded owner separately.
    mixer: Mixer,
    /// Output layout fixed at creation; do not mutate or change native format behind this owner.
    channels: Channels,

    /// Destroy on the main thread, after tracks and before context. Exactly once; no error result.
    pub fn deinit(self: *OfflineMixer) void {
        self.mixer.deinit();
        self.* = undefined;
    }

    /// Borrow shared loading/track operations without allocation. Owner/context outlive the view.
    pub fn borrow(self: *const OfflineMixer) MixerRef {
        return self.mixer.borrow();
    }

    /// Fill interleaved native-endian float samples and return mixed FRAME count, excluding any
    /// appended silence. The entire buffer is initialized on success. No tracks produces silence.
    /// Main thread; advances playback immediately, independent of wall-clock time. Empty output
    /// returns zero without advancing. Native mixing may allocate/block; wrapper storage does not.
    /// `InvalidBuffer` rejects partial frames/oversized byte lengths before mixing. `SdlFailure`
    /// may leave output partially changed and playback advanced. Float mixing may exceed [-1, 1].
    pub fn generate(self: *OfflineMixer, output: []f32) Error!usize {
        const channels: usize = @backingInt(self.channels);
        if (output.len % channels != 0 or output.len > std.math.maxInt(c_int) / @sizeOf(f32)) {
            return error.InvalidBuffer;
        }
        if (output.len == 0) return 0;
        const result = raw.MIX_Generate(self.mixer.handle, output.ptr, @intCast(output.len * 4));
        if (result < 0) return error.SdlFailure;
        const bytes: usize = @intCast(result);
        if (bytes > output.len * 4 or bytes % (channels * 4) != 0) return error.SdlFailure;
        return bytes / (channels * 4);
    }
};

/// Borrowed mixer operations, main thread only. Native work may allocate/block.
pub const MixerRef = struct {
    /// Live mixer handle. Never destroy through this view.
    handle: *raw.MIX_Mixer,

    /// Load a UTF-8 sentinel file path, borrowed only for this call; relative paths use the cwd.
    /// `SdlFailure` returns no owner. Audio is cached and may be shared with other mixers; it
    /// requires a live Context, but does not borrow this mixer. Read SDL errors on failure.
    pub fn load_audio(self: MixerRef, path: [:0]const u8, options: LoadOptions) Error!Audio {
        const handle = raw.MIX_LoadAudio(self.handle, path.ptr, options.predecode) orelse
            return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Cache audio at a seekable stream cursor, borrowed exclusively for this call.
    /// Never closes the stream on success/failure. Audio retains no stream/backing-buffer borrow;
    /// these may be released immediately after return. Failure can change the cursor.
    /// `SdlFailure` returns no owner. Native load/decode has no wrapper memory or work budget.
    pub fn load_audio_stream(
        self: MixerRef,
        stream: sdl.io.StreamRef,
        options: LoadOptions,
    ) Error!Audio {
        const handle = raw.MIX_LoadAudio_IO(
            self.handle,
            stream.handle,
            options.predecode,
            false,
        ) orelse
            return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Create an initially stopped track without input. Mixer/context must outlive the track.
    /// Native code may allocate; `SdlFailure` returns no owner. Tracks cannot move between mixers.
    pub fn create_track(self: MixerRef) Error!Track {
        const handle = raw.MIX_CreateTrack(self.handle) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }
};

/// Owns one native audio reference. Do not copy. Context must outlive it; mixers need not.
pub const Audio = struct {
    /// Native handle; never destroy separately or use after this owner is released.
    handle: *raw.MIX_Audio,

    /// Release on the main thread, exactly once. Tracks retain independent native references,
    /// so playback can continue after this owner closes. Invalidates this owner and all its views.
    pub fn deinit(self: *Audio) void {
        raw.MIX_DestroyAudio(self.handle);
        self.* = undefined;
    }

    /// Borrow without allocation/native calls. This owner must outlive the view, even if tracks
    /// still retain the audio after deinit. Passing a view to a track lets that track retain audio.
    pub fn borrow(self: *const Audio) AudioRef {
        return .{ .handle = self.handle };
    }
};

/// Non-owning audio view, valid only while its owner lives. No copy of sample/encoded data.
pub const AudioRef = struct {
    /// Native reference; never destroy through this borrowed view.
    handle: *raw.MIX_Audio,
};

/// Owns a track belonging to one mixer. Do not copy; destroy before mixer/context.
pub const Track = struct {
    /// Native interop handle. Do not destroy separately, including through mixer shutdown.
    handle: *raw.MIX_Track,

    /// Stop immediately and destroy on the main thread. May block on native mixing work.
    /// Releases retained input audio. Call exactly once; invalidates owner/views.
    pub fn deinit(self: *Track) void {
        raw.MIX_DestroyTrack(self.handle);
        self.* = undefined;
    }

    /// Borrow without allocation/native calls. Track, mixer, and context must remain alive.
    pub fn borrow(self: *const Track) TrackRef {
        return .{ .handle = self.handle };
    }
};

/// Borrowed main-thread track control. Native operations may allocate or synchronize/block.
pub const TrackRef = struct {
    /// Live track handle. Never destroy through this view.
    handle: *raw.MIX_Track,

    /// Assign input and retain a native audio reference. Caller may release its Audio afterward.
    /// Null clears input; a playing track becomes stopped on the next mix. Assignment does not
    /// start playback. `SdlFailure` does not promise unchanged input/playback state.
    ///
    /// ```zig
    /// const mix = @import("sdl_mixer");
    /// var context = try mix.init();
    /// defer context.deinit();
    /// var offline = try context.create_offline(.{ .channels = .mono });
    /// defer offline.deinit();
    /// var track = try offline.borrow().create_track();
    /// defer track.deinit();
    /// {
    ///     // Documentation fixture; replace with your application's audio path.
    ///     const path = @import("example_assets").audio_path ++ "";
    ///     var audio = try offline.borrow().load_audio(path, .{});
    ///     defer audio.deinit();
    ///     try track.borrow().set_audio(audio.borrow());
    /// }
    /// // Track retains its input after Audio.deinit. Play twice in total.
    /// try track.borrow().play_with_options(.{ .looping = .{ .additional = 1 } });
    /// var output: [32]f32 = undefined;
    /// try @import("std").testing.expectEqual(@as(usize, 32), try offline.generate(&output));
    /// try track.borrow().stop();
    /// ```
    pub fn set_audio(self: TrackRef, audio: ?AudioRef) Error!void {
        if (!raw.MIX_SetTrackAudio(self.handle, if (audio) |value| value.handle else null)) {
            return error.SdlFailure;
        }
    }

    /// Start/restart from the beginning, once, with default playback settings (no loop/fade).
    /// An input must be assigned first. `SdlFailure` reports native failure; no rollback guarantee.
    pub fn play(self: TrackRef) Error!void {
        if (!raw.MIX_PlayTrack(self.handle, 0)) return error.SdlFailure;
    }

    /// Start/restart with a typed loop policy on the main thread. Requires an assigned input.
    /// Additional repetitions count after the first play: one means two plays in total.
    /// `InvalidLoopCount` rejects an excessive count before allocation or playback changes.
    /// Non-default options allocate a temporary native property group, released before return.
    /// `SdlFailure` covers property setup/playback; no rollback guarantee after native play.
    /// Cleanup may replace native diagnostics. Native interop nonseekable inputs cannot loop.
    pub fn play_with_options(self: TrackRef, options: PlayOptions) Error!void {
        const loops: i64 = switch (options.looping) {
            .once => 0,
            .forever => -1,
            .additional => |count| loops: {
                if (count > std.math.maxInt(c_int)) return error.InvalidLoopCount;
                break :loops @intCast(count);
            },
        };
        if (loops == 0) return self.play();
        var properties = sdl.properties.Properties.init() catch return error.SdlFailure;
        defer properties.deinit();
        properties.borrow().set(raw.MIX_PROP_PLAY_LOOPS_NUMBER, &.{ .number = loops }) catch
            return error.SdlFailure;
        if (!raw.MIX_PlayTrack(self.handle, properties.handle)) return error.SdlFailure;
    }

    /// Stop immediately without fading. Stopping an already stopped track succeeds.
    /// Retains assigned input for later replay. `SdlFailure` reports a native failure.
    pub fn stop(self: TrackRef) Error!void {
        if (!raw.MIX_StopTrack(self.handle, 0)) return error.SdlFailure;
    }

    /// Snapshot whether playing, excluding paused/stopped tracks. Device state can change at once.
    /// Native errors also return false; this is not a handle-validity check. No wrapper allocation.
    pub fn is_playing(self: TrackRef) bool {
        return raw.MIX_TrackPlaying(self.handle);
    }
};
