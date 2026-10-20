# Architecture decisions

## Scope

Cover the entire public core SDL3 API plus SDL_image, SDL_mixer, and SDL_ttf for pinned releases.
Track platform-dependent declarations and public macros, not only exported functions.
Full API coverage and supported runtime platforms are separate promises.

Four public modules share a canonical target-specific translated C module. Extensions use core
resource types. Idiomatic interfaces are handwritten; raw declarations remain an escape hatch.
Use options structs, checked conversions, slices, sentinel strings, optionals, error unions,
typed IDs, tagged event unions, and explicit resource ownership.

## Ownership and execution

Owning structs must not be copied. Borrowed views do not expose destruction. Document parent
lifetimes, invalidation, ownership transfer, callback context stability, and teardown order.
Native allocations use the matching native deallocator. Wrapper allocation requires explicit
caller storage or an allocator. Error diagnostics must be copied before native cleanup if retained.

Subsystem initialization owns reference-counted acquisitions; it does not own process-global quit.
Application entry-point integration and global shutdown belong at an explicit application boundary.
No hidden global runtime manager. No claim of compile-time lifetime enforcement.

Native callbacks retain their thread and reentrancy restrictions. Zig adapters must not silently
change SDL asynchronous operations into std.Io tasks. Bounded event processing belongs in helpers;
raw single-operation wrappers preserve native semantics.

## Accepted Tiger Style exceptions

The user explicitly accepts SDL and its native dependencies and their runtime allocation behavior.
Whole-stack allocation freedom is not promised. Avoid implicit wrapper allocation; document native
behavior and measure sensitive paths. Build tools may allocate during their bounded build work.
Meaningful assertions are required; artificial assertions do not establish compliance with an
assertion-count target. Blocking native operations retain documented behavior.

## Dependencies

Default to compatible system installations. Never silently fall back to source builds.
Provide explicit source and external providers; provider and linkage are independent decisions.
Source caching must include revision, target, toolchain, configuration, and dependency identities.
Cross-compilation must not accidentally discover host libraries. CI must eventually cover both
system discovery and pinned source builds. Packaging shared libraries is the application's policy.

## Subsystem map

- Foundation: init, app, errors, version, hints, properties, logging, assertions.
- Graphics: video, renderer, surfaces, pixels, blend, rectangles, GPU, OpenGL/Vulkan/Metal/OpenXR.
- Input/devices: events, keyboard, mouse, joystick, gamepad, touch, pen, sensor, haptic, HID, camera.
- Services: audio, streams, async I/O, filesystem, storage, threads, synchronization, atomics,
  timers, time, processes, shared objects.
- Platform: clipboard, dialogs, messages, tray, notifications, locale, power, CPU, GUIDs, system,
  platform-specific APIs, standard-library helpers and remaining public utilities.
- Image: load/save, surfaces/textures/GPU integration, animations and codecs.
- Mixer: audio assets, decoding, mixers, tracks, groups, tags, callbacks and positional audio.
- TTF: fonts, metrics, shaping, fallback, surface rendering, persistent text and text engines.

## Coverage contract

Every upstream item eventually needs an explicit disposition: wrapped, covered by another
abstraction, justified raw-only, platform-gated, or pending. Missing entries fail the final audit;
pending entries block completion. Raw-only availability does not count as idiomatic coverage.
Record ownership, nullability, failures, encoding, units, allocations, thread/callback contracts,
version, implementation, and validation for each operation.
Public Zig declaration documentation is required before completion. Coverage entries must identify
a documentation source checked by the build; examples are extracted from the actual hover comments
and compiled/run. Semantic contract review remains mandatory even when automated checks pass.

The translated inventory only enumerates names surviving C translation for enabled headers and the
active target. It does not identify hidden conditionals, omitted macros, fields, or changed semantic
contracts. Independent header/preprocessor extraction and configuration-matrix reconciliation are
required before completeness claims. The independent pinned-header audit now covers Linux ASTs,
active macros, every header hash, and lexical candidates/conditional directives across platforms;
see `upstream.md`. New symbols currently appear as pending, not silently wrapped.
