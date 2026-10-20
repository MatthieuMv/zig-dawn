# Mixer ownership and playback slice

Enable `-Dmixer=true` and import `sdl_mixer`. Acquire a `Context` with `init()`, create a
mixer, load audio, create a track, assign its input, then play. The wrapper uses the main thread
for all operations and does not support calls from native audio callbacks. Native codec work,
mixing, and device synchronization may allocate or block; no real-time guarantee is made.

`context.create_playback()` opens the default playback device with the system-selected format.
It acquires its own SDL audio subsystem reference and releases it when the mixer closes.
`context.create_offline(options)` opens no device. It produces mono or interleaved stereo
native-endian float32 samples at the requested sample rate, only when `generate` is called.

`offline.generate(buffer)` initializes the whole buffer on success and returns the number of
mixed **frames**, excluding appended silence. Stereo has two samples per frame. The output
slice must contain whole frames, and its byte count must fit a signed C integer. Empty output
returns zero without advancing playback. No tracks produces zero mixed frames and silence.
Errors can leave the buffer and playback cursor partially advanced. Floating-point mixing
should not be assumed to clip every output to [-1, 1].

`mixer.borrow().load_audio(path, options)` caches file audio. `load_audio_stream` exclusively
borrows a seekable stream for the call, never closes it, and retains no backing-buffer borrow.
The stream/buffer can be released afterward, including with deferred decoding. `predecode`
defaults to true, trading increased startup memory/work for less decoding during playback.
False retains encoded data and decodes when playing. Codec availability is installation-dependent.

`track.borrow().set_audio(audio.borrow())` retains an independent native reference. The caller
can release its Audio owner immediately; playback still works. Its old borrowed AudioRef is
nevertheless invalid after owner release. Loaded audio is shareable across mixers and can outlive
its loading mixer, but must remain within the initialization context lifetime.

Tracks belong to exactly one mixer. Destroy track owners before their mixer; destroy all mixers
and Audio owners before the context. Never copy an owner. Final native shutdown destroys leftover
resources, making later owner cleanup invalid. Context initialization/shutdown must be globally
serialized, including with any raw interop. Zig does not enforce these lifetime rules.

`play()` starts/restarts once from the beginning with native defaults. `play_with_options` adds
`.once`, `.additional = count`, and `.forever` loop policies; nonzero loops allocate temporary native
properties. See `properties.md` for validation and allocation details. `stop()` stops immediately,
retaining the input for replay. `set_audio(null)` removes input; a playing track notices during
its next mix. `is_playing()` is a snapshot, false for paused/stopped tracks and native errors;
it is not a validity check. Device playback can advance between any two calls.

The exact hover examples demonstrate offline generation and assigning audio with explicit lifetimes.
The test-only `example_assets` path is replaced by an application's own asset path in consumer code.
Tests cover cached and deferred decoding of an original PCM WAV, buffer bounds/silence, replay,
stop, input/owner release, cross-mixer sharing, bad input recovery, and dummy-device lifecycle.

## Combined example

```sh
zig build run-multimedia -Dimage=true -Dmixer=true -Dttf=true
zig build test-multimedia -Dimage=true -Dmixer=true -Dttf=true
```

`examples/multimedia.zig` uses all four modules. It runs for at most 120 frames with 64 event polls
per frame and exits on close/Escape. The headless step selects dummy audio/video. Fixture paths
are build-provided absolute paths, suitable for this repository example rather than an installed
asset/deployment scheme. The tiny box font and 5.33-ms WAV test integration, not visual quality
or perceptible audio playback. Software-renderer and offline audio tests separately check outputs.

Specific devices/formats, fades, seeking, gain/pan, groups/tags, callbacks, streaming input,
decoder APIs, and multithreaded control remain pending. Physical speakers, real-time latency,
compressed codec coverage, native OOM cleanup, and non-Linux behavior have not been validated.
