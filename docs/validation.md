# Validation record

## Environment

Zig reports 0.17.0. Matching standard-library sources are installed under
`/home/mmoinvaziri/Tools/zig-x86_64-linux-0.17.0/lib`.
Native pkg-config versions: SDL 3.4.18; image 3.4.8; mixer 3.2.4; ttf 3.2.2.

## Checks

Passed on the native Linux host:

- `zig fmt --check build.zig build.zig.zon src tools build_support examples tests/consumer tests/graphics.zig`.
- Core unit tests: 8 tests; headless graphics integration: 1 test.
- System build with image, mixer, and ttf plus graphics: 12 tests in debug and 12 in safe mode.
- External provider using `/usr`: original all-extension checks plus new graphics integration pass.
- Inventory generation: 5,129 translated names, 15 wrapped, 5 partial, and 5,109 pending.
  This includes helper names emitted by translation and is not a public-API denominator.
- Shared `SDL_Surface` type identity checked between each extension and the core module.
- Expected rejection verified for the unimplemented source provider, an external provider without
  a prefix, and system-provider cross-compilation to aarch64 Linux.
- Independent consumer: core-only system, all-extension system debug/safe, and all-extension
  external `/usr` builds ran successfully; consumer explicitly calls every module's version API.
- `tests/dependencies.sh`: missing pkg-config package, missing external library, four older-header
  cases, and a wrong-major case all rejected (7 expected failures).
- Independent pinned-header audit: 3,570 declaration rows, 1,989 macro names, 125 header hashes.
  Declaration rows include separate tags and typedefs; these are not distinct public-API counts.
- The audit found 25 omitted names in application/Vulkan/TTF text-engine supplemental headers.
  Adding those headers to the shared ABI left zero missing names in this Linux audit comparison.
- Offline `header_audit.sh ... --check` matches the baseline. `tests/header_audit.sh` rejects
  deliberately changed baseline declarations and a corrupt archive without altering real inputs.
- First graphics slice: readback verifies clear/fill colors, copied RGBA texture data, bounded and
  full-target drawing. Tests reject cross-renderer texture use and invalid byte/dimension inputs.
- Bounded desktop example compiled and ran all 600 frames with dummy video/software rendering.
  This is not a visible-desktop or GPU validation result. See `graphics.md` for contracts and scope.
- Keyboard work expanded both inventory filters to include 297 `SDLK_*` macros. Reviewed baseline
  changes add only those macros; the independent comparison still reports zero missing names.
- API documentation: AST presence checks pass for all registered wrapper modules, public declarations,
  and named fields/tags. Coverage entries now include a checked documentation-source column.
- `test-docs`: four exact hover-comment examples run with dummy video, plus four documentation-tooling
  tests covering missing docs, missing import registration, and example extraction/fence rejection.
  Safe-mode checks pass; examples and the existing package checks compile with all extensions enabled.
- Generated API reference artifacts exist for `sdl`, `sdl_image`, `sdl_mixer`, and `sdl_ttf`, including
  source comments. No specific IDE's hover UI has been inspected; presentation is editor-dependent.

No cross-platform, source-provider, ABI-layout, codec-feature, or exhaustive API coverage claim
is made. The external `/usr` check is not proof of isolation from host search paths.

Contract tests cover independent subsystem reference ownership, diagnostic copy bounds and
lifetime, and enabled library version queries. Version tests require major 3 and runtime at
least as new as the compile headers; this conservative check is not a general compatibility policy.

## Remaining limitations

CI, codec dependency pins, source builds, static dependency closure, target SDKs, non-Linux AST
audits, and complete coverage dispositions remain unfinished. SDL_image provides loading/PNG saving,
SDL_ttf provides initial font/text wrappers, and mixer provides initial ownership/playback wrappers.
None of the extensions has a complete idiomatic API. External libraries use exact filenames now; their
transitive native dependencies and OS deployment remain outside the current checks.
No full Tiger Style compliance claim: accepted native dependency/allocation exceptions apply,
and build/tooling style plus assertion density require continued review.

## Surface/image slice (2026-10-18)

- Verified against installed pinned headers for surface allocation/destruction, surface-to-texture
  copying, file loading, and memory-stream decoding. Existing native allocation/dependency exceptions
  apply; decoded work/memory bounds and native allocation-failure injection remain unimplemented.
- Debug and Safe: `test test-docs test-graphics check` with all three extensions enabled passed
  (25 tests total across artifacts, including six hover examples and four tooling tests).
- Core-only `test test-docs check inventory` passed, with five core examples. Optional extension
  mappings are checked only when that library is enabled; missing mapped symbols still fail.
- Downstream `tests/consumer` build/run with extensions enabled passed. Formatting checks passed.
  Generated reference pages for all four modules rebuilt successfully.
- Surface tests cover positive dimensions, zero/oversized rejection, and zero-filled pixels.
  Image tests cover file and memory BMP loading, buffer independence, empty/malformed/truncated
  inputs, failure recovery, and texture readback after surface destruction using dummy video.
- Full inventory remains 5,129 translated names: 19 wrapped, seven partial, 5,103 pending.
  Surface allocation is partial (RGBA only); image stream loading is partial (memory only).
  The native input-stream helper remains pending as a consumer-facing API.
- No full codec matrix, hardware rendering, cross-platform behavior, leak instrumentation, or
  particular IDE hover presentation has been validated by this slice.

## Streams/PNG slice (2026-10-18)

- Added owned binary file/fixed-memory streams, borrowed seek/position views, explicit fallible
  close, and best-effort cleanup. Pinned SDL source confirms empty memory streams are supported;
  tests check their zero cursor, plus nonempty shared-cursor and clamped-seek behavior.
- Added borrowed-stream image decoding and PNG file/stream saving. Decoding and encoding preserve
  caller stream ownership on both success and failure. No wrapper storage allocation was added;
  native stream bookkeeping and codec scratch storage may allocate.
- Debug and Safe all-extension `test test-docs test-graphics check` passed: 33 tests across artifacts,
  including eight executable hover examples and four documentation-tooling tests. Generated docs
  for all four modules rebuilt, and formatting checks passed.
- PNG memory/file round trips verify decoded pixel equality; file tests use isolated temporary
  directories and cover read/create/update modes and truncation. Failure cases cover malformed
  input, missing files, short writable buffers with guard bytes, read-only output, and injected
  native close failure. Libpng prints expected diagnostics for intentional output failures.
- Core-only tests/examples/check/inventory pass independently of extensions. The downstream consumer
  imports the new stream API and completes a PNG encode/decode round trip with extensions enabled.
- Full inventory: 5,129 translated names, 27 wrapped, seven partial, 5,095 pending. File opening
  remains partial (selected binary modes). Generic stream decoding replaces memory-only coverage.
- Native allocation exhaustion, physical-disk durability, the full encoder matrix, and non-Linux
  runtime behavior remain unverified. No full Tiger Style compliance claim is made; established
  native dependency/allocation and assertion-density exceptions remain applicable.

## Font/text slice (2026-10-18)

- Added reference-counted TTF context ownership, file and borrowed-stream font owners, borrowed
  font views, checked UTF-8 measurement, and antialiased text surfaces. Native allocation/dependency
  exceptions remain in force; this is not a full Tiger Style compliance claim.
- Contracts were checked against pinned SDL_ttf headers. Font streams remain borrowed until font
  destruction. Rendered surfaces and uploaded textures outlive fonts and contexts independently.
  Empty measurement uses a safe sentinel because native length zero requests strlen; empty render
  is rejected before native work. Invalid UTF-8/NUL and nonpositive/nonfinite point sizes are checked.
- Debug and Safe module/integration/doc checks pass with all extensions enabled. The suite now has
  37 tests across artifacts, including nine exact hover examples, three TTF integration tests, and
  four documentation-tooling tests. Unchanged tests may be served from the build cache. Headless
  graphics tests pass in both modes; docs generation and formatting checks pass.
- TTF-only Debug builds/tests/examples pass without image/mixer. Core-only checks still pass.
  Downstream consumption now opens a fixture font and renders a text surface successfully.
- Tests verify reference balancing, missing/corrupt font failures and recovery, stream retention,
  nonterminated and malformed UTF-8, empty measurement, measured/rendered dimensions, pixel color
  and alpha, and text texture readback after font/context/source surface destruction.
- The original 952-byte box font has no imported glyph assets. Its optional FontTools generator
  reproduces the recorded SHA-256; normal builds/tests need no authoring tools or host fonts.
- Inventory remains 5,129 names: 34 wrapped, eight partial, 5,087 pending. Font stream creation is
  partial because automatic stream ownership transfer is not exposed. Advanced text engines,
  wrapping, styles, fallback, broad font/complex-script behavior, and non-Linux runtime validation
  remain pending. Native allocation failure and font memory usage are not instrumented.

## Mixer/playback slice (2026-10-18)

- Added reference-counted mixer context ownership, default-device playback, offline mono/stereo
  float32 mixing, cached file/borrowed-stream audio, track ownership, assignment, play/restart,
  immediate stop, and playing snapshots. Contracts were checked against pinned SDL_mixer headers.
- Tracks retain native audio references after the caller releases its Audio owner. Tracks still
  require their mixer, and all objects must close before final context shutdown. Stream loading
  retains neither streams nor backing memory, even with deferred decoding. All wrapper control is
  on the main thread; native callbacks/multithreaded wrapper control are not supported in this slice.
- Debug and Safe checks pass for all extensions: 43 tests across artifacts, including 11 exact
  hover examples, four mixer integration tests, and four documentation-tooling tests. Unchanged
  artifact tests can be served from cache. Core-only and mixer-only checks/examples also pass.
- Tests check waveform signal, whole-frame output validation without buffer mutation, silence,
  playback completion/restart/stop, input and owner lifetime independence in both decode modes,
  cross-mixer audio sharing, bad input recovery, and default-device lifecycle with dummy audio.
- `test-multimedia` executes the bounded all-four-module example successfully in Debug and Safe,
  using dummy video/audio and a software renderer. The downstream consumer also loads audio and
  generates offline samples alongside its existing image/font checks. Formatting and generated
  docs pass; package paths include mixer tests and the original PCM WAV fixture.
- Inventory: 5,129 translated names; 43 wrapped, 15 partial, 5,071 pending. Partial mixer entries
  retain explicit device/format, mixer-less loading, stream-transfer, playback-option, and fade
  limitations. This is not completion of core audio or SDL_mixer.
- Physical audio output, latency, compressed codecs, allocation-failure cleanup, and non-Linux
  behavior remain unverified. Native dependency/allocation exceptions and broader Tiger Style
  limitations still apply. The short fixture/example establishes integration, not audible quality.

## Typed properties and mixer loops (2026-10-18)

- Added native property group owners/views, exact tagged scalar/string/pointer values, optional
  lookup, existence/clear operations, and scoped recursive locks. Setters copy strings/names;
  getters borrow strings. Internal locks protect type/value query consistency; outer locks are
  required for borrowed string use across concurrent mutation. Pinned SDL headers and recursive
  mutex contracts were checked; multithreaded stress testing remains unperformed.
- Tests cover all value kinds, integer extremes, NaN, missing versus false/zero, replacement,
  independent groups, caller input copies, borrowed pointer storage, nested locks, invalid IDs,
  and invalid names/strings preserving state. Native OOM paths and cleanup callbacks are untested.
- Added typed one-shot/additional/forever mixer looping. Nonzero loops create temporary native
  properties; counts are bounded to signed C int because the pinned implementation narrows the
  native numeric property to int. Tests check exact repeated frame counts/data, infinite looping
  with bounded generation, upper-bound acceptance/rejection, and unchanged playback position after
  invalid options. Other playback settings remain native defaults.
- Full Debug and Safe `test test-docs test-graphics test-multimedia check` pass: 49 tests across
  artifacts, including 13 exact hover examples. Core-only and mixer-only checks pass; downstream
  use now exercises typed properties and loop options. Formatting and generated docs pass.
- Inventory remains 5,129 names: 60 wrapped, 15 partial, 5,054 pending. MIX_PlayTrack stays partial
  because only looping/default settings are exposed. Property enumeration, copy, cleanup callbacks,
  and global/object-specific property accessors remain pending.
- Native property/decoder allocation and synchronization remain allowed exceptions. No native
  allocation-freedom, full Tiger Style compliance, hardware playback, or cross-platform claim is made.

## Property copying, snapshots, and object metadata (2026-10-18)

- Added merging between property groups, caller-buffer name snapshots, borrowed global properties,
  and borrowed properties for windows, renderers, textures, surfaces, and streams. Contracts were
  checked against pinned SDL headers and implementation. Object-owned groups must not be destroyed
  by consumers, and native metadata keys retain their individual access and threading restrictions.
- Copying deep-copies strings, shares pointer values, skips source properties with cleanup callbacks,
  and may invoke cleanup when replacing destination properties. Wrapper copies acquire locks in
  group-ID order; callers must not hold other group locks and native interop must use a compatible
  lock order. Native failure can leave a partial merge.
- Name snapshots count then copy under one recursive lock. Insufficient capacity leaves both caller
  buffers untouched; copied names survive source mutation/destruction. Buffers must be disjoint.
  Enumeration visits the entire group twice, so buffer capacity does not bound execution time.
- Four new property tests cover exact/insufficient capacity, UTF-8 names, snapshot lifetimes, merge
  ownership, cleanup behavior, invalid IDs, and global sharing. A new graphics integration test
  verifies all five object accessors, independent custom values, and native texture-width metadata.
- Full Debug and Safe `test test-docs test-graphics test-multimedia check` pass: 55 tests across
  artifacts, including 14 exact hover examples. Core-only checks and the downstream consumer pass;
  the latter now exercises snapshots and copying. Documentation generation and formatting pass.
  Unchanged artifact tests may be served from the build cache.
- Inventory: 5,129 translated names; 67 wrapped, 16 partial, 5,046 pending. Enumeration remains
  partial because the wrapper exposes copied names rather than arbitrary visitor callbacks.
  Cleanup callback adapters, extension object accessors, and typed native-key conveniences remain
  pending. Native OOM and concurrent stress behavior remain unverified; allowed native allocation
  and dependency exceptions still apply.

## Stream byte transfers and status (2026-10-18)

- Added single-call byte reads/writes returning both count and typed status, size queries, status
  snapshots, and fallible flushing. Partial progress remains available on failure/nonblocking
  results; wrappers never spin or retry. Unknown future native status values remain representable.
- Pinned headers and implementation were checked. Empty wrapper transfers bypass native permission
  checks to preserve status consistently. Flush can reset status and can fail after partial progress;
  the owner remains live. Size reports fixed-memory capacity, not initialized or written length.
- Three new tests cover short reads/writes, EOF, capacity bounds, read/write permissions, untouched
  read suffixes, empty no-ops, injected partial failures/nonblocking status, absent size support, and
  use after flush failure. A compiled hover example and downstream consumer exercise the public API.
- Full Debug and Safe `test test-docs test-graphics test-multimedia check` pass: 59 tests across
  artifacts, including 15 exact hover examples. Core-only checks passed before the final additional
  permission test; all core tests subsequently passed in the complete suite. Downstream consumption,
  generated docs, inventory generation, and affected Zig formatting checks pass.
- Inventory: 5,129 translated names; 72 wrapped, 16 partial, 5,041 pending. Exact/endian helpers,
  dynamic memory ownership, and callback adapters remain pending. Tests inject native callbacks;
  they do not establish real socket readiness, disk durability, native OOM, or cross-platform behavior.
  Native allocation/dependency exceptions remain; no full Tiger Style compliance claim is made.

## Bounded full transfers and integer encoding (2026-10-18)

- Added `read_full`/`write_all`, which accumulate positive ready transfers and stop on completion,
  zero progress, or any non-ready status. Native call count is bounded by requested bytes; native
  blocking time is not. Empty inputs preserve status. Partial progress is never rolled back.
- Added generic signed/unsigned 8-, 16-, 32-, and 64-bit integer helpers using explicit byte order
  and at most eight stack bytes. Reads expose an optional value plus transfer details, preventing
  decoding of incomplete data. Partial integer operations are not resumable by calling them again;
  callers requiring resumption must retain encoded buffers. Full progress can accompany failure
  status, which remains visible. Unsupported integer types produce a compile-time diagnostic.
- Three new tests cover known wire bytes for all eight types in both byte orders, truncation,
  positive short ready transfers, zero-progress stopping, preserved suffixes, and empty transfers.
  Existing injected failure tests additionally verify immediate stopping after positive progress
  with non-ready status. No real nonblocking device or native OOM behavior is claimed.
- Full Debug and Safe `test test-docs test-graphics test-multimedia check` pass: 63 tests across
  artifacts, including 16 exact hover examples. Downstream integer round-trip consumption, docs,
  formatting, and inventory pass. Final comment/whitespace cleanup was followed by core tests,
  executable documentation checks, and core docs generation.
- Inventory: 5,129 names; 100 wrapped, 16 partial, 5,013 pending. SDL's 28 integer helper symbols
  map to generic Zig encoding over byte transfers, not direct calls to native boolean-returning
  helpers. Positive short ready results may therefore be retried within the documented bound.
  Dynamic storage and callback adapters remain pending. Native dependency/allocation exceptions
  remain; these checks do not establish full Tiger Style compliance or cross-platform behavior.

## Dynamic memory stream ownership (2026-10-18)

- Added DynamicStream with configurable nonzero allocation granularity, borrowed initialized byte
  views, and a consuming finish operation returning OwnedBytes. Writes allocate/grow through SDL;
  chunk size is not a memory bound. Fixed-memory streams remain the bounded-capacity option.
- Pinned implementation confirms high-water data length, clamped seeking, property-mediated buffer
  detachment, and immediate closing after detach. finish consumes the stream even on error; successful
  detached buffers must be freed once through OwnedBytes.deinit/SDL_free. Writes invalidate borrowed
  stream slices. Reserved native memory properties must not be modified outside these operations.
- Three core tests cover zero chunk rejection, empty detachment, growth across chunk boundaries,
  overwrite/high-water behavior, source-copy independence, cleanup, and detached data surviving stream
  destruction. An image test saves PNG into dynamic storage and decodes it after detachment. The
  downstream consumer exercises integer output and detached ownership.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass across 68 tests,
  including 17 exact hover examples. Debug executed 64 tests and reused four documentation-tooling
  tests from cache; Safe executed all 68. Downstream use, generated docs, inventory, and formatting
  pass. Final documentation line wrapping was followed by core doc checks/generation.
- Inventory: 5,129 names; 103 wrapped, 16 partial, 5,010 pending. Dynamic constructor and its two
  property constants now map to typed APIs. Stream callback adapters remain pending. Native OOM,
  allocation-size instrumentation, and non-Linux execution remain unverified. Accepted native
  runtime-allocation/dependency exceptions apply; no full Tiger Style compliance claim is made.

## Typed stream callback adapters (2026-10-18)

- Added compile-time typed callback tables and Stream.from_callbacks for borrowed stable backend
  storage. The adapter adds no heap state; SDL allocates the native stream and copies its interface.
  Callback slices expire on return. Backends must serialize access and cannot reenter/close their
  own stream. Context storage remains caller-owned; opening failure does not call backend cleanup.
- Callback errors become native failures with Zig error-name diagnostics. Transfer results preserve
  partial progress/status; oversized counts and positions above signed 64-bit range are rejected.
  Rejection cannot undo backend side effects or invalid memory accesses. Close invokes cleanup once
  and consumes the stream even when cleanup reports an error. Panics are not translated.
- Three core tests cover typed read/write/seek/size/flush/close calls, partial failures, EOF, count
  and position validation, error diagnostics, not-ready flushing, close failure, and absent callbacks.
  An image integration test checks seek-based size fallback/restoration, callback-driven decoding,
  borrowed stream retention, and source survival after adapter close. The downstream consumer uses
  a typed counting sink, also shown in an executable hover example.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass: 73 tests across
  artifacts, including 18 exact hover examples. Generated docs, downstream consumption, formatting,
  and inventory pass. Final comment/test line wrapping was followed by core tests and docs checks.
- Inventory: 5,129 names; 105 wrapped, 16 partial, 5,008 pending. SDL_OpenIO and its interface now map
  to typed operations. This completes the currently listed stream callback slice, not all SDL I/O
  helpers or asynchronous I/O. Native OOM, multithreaded callback stress, and non-Linux ABI execution
  remain unverified. Native dependency/allocation exceptions remain; full Tiger Style compliance
  is not claimed.

## Checked CPU surface operations (2026-10-18)

- Added coordinate-checked pixel reads/writes with shared renderer Color values, whole clipped
  fills, independent main-pixel duplication, and RGBA32 conversion. Pinned headers/implementation
  confirm direct writes do not blend or clip, fills respect native clipping, and pixel helpers
  prioritize correctness over bulk throughput. Native precision/format limitations remain visible.
- Duplicate/conversion results own their main pixels independently of the source, but alternate
  images can retain shared native references. RGBA32 describes byte order, not tight row packing
  or a comprehensive colorspace conversion policy. These operations require exclusive surface
  access and can allocate/lock natively. No video subsystem initialization is needed.
- Three new core tests cover bounds including oversized unsigned coordinates, unchanged neighboring
  pixels, unblended alpha, clip-aware fills, unclipped single-pixel writes, padded RGB24 conversion,
  literal RGBA byte order, and copy independence after source destruction. A new image test covers
  loaded-image conversion/editing and alpha-preserving PNG round trips. Downstream use exercises
  all five new operations. A signed/unsigned test-constant mismatch was fixed before final checks.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass: 78 tests across
  artifacts, including 19 exact hover examples. Docs generation, downstream consumption, inventory,
  and formatting pass. Final test-only line wrapping was followed by core tests/doc checks.
- Inventory: 5,129 names; 108 wrapped, 19 partial, 5,002 pending. Fill rectangle, RGBA mapping, and
  format conversion entries are partial: only whole clipped fills, internal mapping, and RGBA32
  output are exposed. Bulk locks/blits, arbitrary format conversion, palette/HDR matrices, alternate
  image graphs, native OOM injection, and non-Linux execution remain pending. Existing native
  allocation/dependency exceptions apply; full Tiger Style compliance is not claimed.

## Whole-surface blitting and source blend state (2026-10-18)

- Added unscaled whole-source blits at destination origin, whole-surface scaled blits, and typed
  source blend-mode setters/getters. Unknown native blend values remain representable; native
  support is checked by SDL. Sampling includes nearest, linear, and pixel-art (the pinned CPU
  implementation treats pixel-art as nearest). Source blend/modulation/color-key state is retained.
- Both surfaces require exclusive access and must be unlocked. Same-handle aliases are rejected;
  distinct handles must not share pixel memory. Native work can allocate/block and does not promise
  rollback on failure. Source/destination ownership is unchanged, with no retained references.
- Three new core tests cover destination clipping, alpha replacement/composition, seven standard
  blend-mode round trips, unsupported modes, nearest replication and clipping transforms, all
  sampling branches, alias rejection, and locked-surface failure/recovery. An image test verifies
  native format conversion and destination survival after source destruction. Mid-alpha assertions
  allow small native integer-rounding differences; this is not a complete blend/format/filter matrix.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass: 83 tests across
  artifacts, including 20 exact hover examples. Downstream use covers both blit operations and
  blend state; documentation generation, formatting, and inventory pass.
- Inventory: 5,129 names; 110 wrapped, 21 partial, 4,998 pending. Both blit mappings are partial due
  to omitted source/destination rectangles and overlap. Positioned/rectangle blits, bulk locks,
  typed modulation/color-key controls, tiling/nine-grid operations, native OOM, and non-Linux
  validation remain pending. Existing native allocation/dependency exceptions remain; no full
  Tiger Style compliance claim is made.

## Checked cropped and positioned blits (2026-10-18)

- Added unsigned contained Region geometry, signed destination Position, and pointer-based option
  structs for unscaled/scaled region blits. Source bounds use subtraction checks; positioned blits
  intersect in 64-bit arithmetic before passing contained geometry to SDL. Extreme signed offsets
  safely become no-ops. Scaled destination regions must fit entirely within their surface.
- Invalid regions and same handles fail before mutation. Empty regions and entirely offscreen
  unscaled requests return without native calls/lock checks. Visible operations retain the existing
  unlocked, exclusive-access, nonoverlapping-storage, blend/modulation, and native clipping contracts.
  Native failures still do not promise rollback; no inputs or surface owners are retained.
- Three new tests compare positioned crops to a pixel model over 48 offsets, test signed extremes
  and oversized unsigned coordinates/extents, verify no mutation for invalid/empty requests, and
  check scaled subregion placement with all three sampling modes. Uniform-color scale tests do not
  establish general filter quality. A new hover example exercises negative destination clipping;
  downstream consumption exercises both region operations.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass: 87 tests across
  artifacts, including 21 exact hover examples. Docs generation, downstream consumption, inventory,
  and formatting pass. Final test-only line wrapping was followed by core tests/doc checks.
- Inventory remains 5,129 names: 110 wrapped, 21 partial, 4,998 pending. Both existing blit mappings
  now include the region APIs and remain partial: source regions must fit, scaled destination
  regions must fit, and overlap is excluded. Bulk locks, typed clipping state, unrestricted scaled
  clipping, overlap, native OOM injection, and non-Linux validation remain pending. Accepted native
  dependency/allocation exceptions remain; full Tiger Style compliance is not claimed.

## Typed surface clipping and rectangle fills (2026-10-18)

- Added signed ClipRect geometry, effective clip queries/setters, reset via null, and rectangular
  RGBA fills. Rectangles intersect using 64-bit arithmetic before native calls. Empty/offscreen
  clip requests return a canonical empty Region and suppress fills/blits; SDL's false intersection
  result is not translated into an error. Getter failures still return SdlFailure.
- Rectangle fills preserve clip state and do not blend. Empty/offscreen fills do no native work;
  nonempty operations retain native format/color approximation and failure behavior. Single-pixel
  writes continue to ignore clipping. Exclusive surface access is required; no inputs are retained.
- Three new tests cover initial/reset and empty state, stale diagnostics, extreme signed/unsigned
  geometry, independent pixel-intersection models, unchanged clip state after fills, and clipped
  blit suppression/recovery. The new hover example and downstream consumer exercise the public API.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass: 91 tests across
  artifacts, including 22 exact hover examples. Documentation generation, downstream consumption,
  formatting, and inventory pass.
- Inventory: 5,129 names; 112 wrapped, 21 partial, 4,996 pending. Both native clip operations are
  mapped; fill coverage now includes signed rectangles but remains partial because input is RGBA,
  not arbitrary native encoded pixel values. Bulk pixel locks, unrestricted scaled clipping,
  raw pixel mapping, native OOM injection, and non-Linux validation remain pending. Existing native
  allocation/dependency exceptions remain; no full Tiger Style compliance claim is made.

## Scoped RGBA row access (2026-10-18)

- Added lock_rgba and noncopyable RgbaLock guards with checked mutable row slices. RGBA32 and
  positive dimensions are required; pitch and final-row spans are validated with checked arithmetic.
  Rows expose width*4 bytes, excluding padding, and expire on unlock. Unsupported formats, existing
  locks, unavailable/empty layouts, and out-of-range rows report explicit errors.
- Native locking is not a mutex. The owner must remain alive with exclusive access until cleanup;
  all other surface use, encoding, upload, and blitting must wait. Native locking can allocate or
  decompress pixels. Locking initializes no pixel bytes and cannot validate arbitrary raw backing
  allocation capacity. Failure after acquiring a lock unwinds it automatically.
- Three new core tests cover row edits, metadata, nested guards, invalid rows, reacquisition,
  borrowed storage with row padding and guard bytes, format rejection/conversion, missing storage,
  and empty surfaces. Image integration verifies edits survive PNG encoding after unlock; downstream
  consumption uses scoped row access. The executable example caught and corrected a Zig array-type
  inference issue before final validation.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass: 96 tests across
  artifacts, including 23 exact hover examples. Docs generation, downstream consumption, formatting,
  and inventory pass.
- Inventory: 5,129 names; 112 wrapped, 23 partial, 4,994 pending. Lock/unlock mappings remain partial
  because only positive RGBA32 surfaces and nonnested scoped locks are exposed. Other formats,
  planar layouts, native recursive locks, RLE-specific stress, native OOM injection, and non-Linux
  execution remain pending. Native allocation/dependency exceptions remain; these checks do not
  establish full Tiger Style compliance.

## Surface tint and opacity controls (2026-10-18)

- Added typed RGB Tint with identity defaults, independent tint setters/getters, and alpha-opacity
  setters/getters. These modify source blit state without changing stored pixels or blend mode.
  Multipliers use channel/255 and native rounding; opacity does not automatically enable blending
  or guarantee correct premultiplied fading. Native formats/blend modes still determine output.
- Two new tests cover default/selected/reset state, channel multiplication, unchanged source pixels
  and blend mode, independent controls, and scaled alpha composition at zero/partial/full opacity.
  Midpoint assertions permit small native integer-rounding differences. The hover example and
  downstream consumer exercise all four public methods. Native rejection paths are forwarded;
  no invalid-handle or native allocation-failure injection is claimed.
- Full Debug and Safe test/test-docs/test-graphics/test-multimedia/check pass: 99 tests across
  artifacts, including 24 exact hover examples. Documentation generation, downstream consumption,
  formatting, and inventory pass.
- Inventory: 5,129 names; 116 wrapped, 23 partial, 4,990 pending. All four native color/alpha
  modulation functions now have typed mappings. Color keys, complete blend/format combinations,
  general-format pixel locks, native OOM injection, and non-Linux execution remain pending.
  Accepted native allocation/dependency exceptions remain; no full Tiger Style compliance claim.


## Property callbacks and display discovery (2026-10-18)

- Typed property pointer insertion consumes the cleanup obligation on success and failure;
  tests cover replacement, clear, destruction, invalid names/groups, and copy exclusion.
  Typed enumeration uses a stack adapter, preserves callback errors, and suppresses later user
  callbacks after failure while native traversal finishes. Recursive reads are covered.
- Display discovery owns its native ID array and exposes borrowed names/properties, signed desktop
  bounds, orientation, content scale, and window display/scale queries. Dummy-video tests cover
  valid and invalid IDs; real hotplug and mixed-DPI/multi-monitor behavior remain unverified.
- Full Debug and Safe suites passed: 106 tests across artifacts, including 27 exact hover examples.
  Debug executed 102 with four documentation-tool tests cached; Safe executed all 106.
  Reference docs, inventory generation, and downstream all-extension consumption passed.
- Inventory: 5,129 symbols; 132 wrapped, 22 partial, 4,975 pending. Native allocations,
  platform coverage, property cleanup concurrency, and native OOM injection remain limitations.


## Window requests and visibility (2026-10-18)

- Added borrowed/copied title access, validated client resize, tagged per-axis placement,
  position queries, show/hide, and explicit native state synchronization. Position encoding rejects
  reserved-coordinate collisions and unrepresentable display hints before either axis mutates.
  Documentation distinguishes successful requests from actual window-manager state.
- Pure encoding tests and dummy-driver integration cover title copying, empty titles, resizing,
  rejection without mutation, positioning, centering, synchronization, and visibility flags.
  The existing executable window example also exercises title, size, placement, and synchronization.
- Full Debug and Safe suites pass with 108 tests, including 27 executable hover examples;
  documentation generation, inventory, and downstream all-extension consumption pass.
- Inventory: 5,129 symbols; 140 wrapped, 22 partial, 4,967 pending. Actual desktop asynchronous
  transitions, denial policies, synchronization timeouts, and other platform backends remain pending.
  Native dependency/allocation exceptions remain; no full Tiger Style compliance claim is made.


## Display modes and fullscreen selection (2026-10-18)

- Added native-owned mode snapshots with checked indexing, copied desktop/current tokens, closest
  searches with validated dimensions/refresh, and copied measurements retaining exact refresh
  fractions. Window APIs select exclusive/desktop mode separately from entering/exiting fullscreen.
  IDE docs distinguish allocation lifetime, historical scalar data, and live mode applicability.
- Tests cover invalid requests, fractional measurement preservation, negative native dimensions,
  invalid IDs, empty lists, absent matches, and desktop fullscreen entry/exit. The dummy backend
  was independently queried and exposes zero exclusive modes: conditional nonempty-mode integration
  branches are not evidence of exclusive switching coverage. Real hardware/mode hotplug remains pending.
- An initial compile exposed Zig's explicit cast requirement when freeing a C double-pointer
  allocation; the owner cleanup and failure unwind now use the required pointer casts.
- Full Debug and Safe suites pass: 112 tests, including 28 executable IDE examples. Docs generation,
  formatting, inventory, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 147 wrapped, 22 partial, 4,960 pending. Mode pixel formats remain native
  numeric identifiers until the general pixel-format API is implemented. Native allocations and
  platform dependencies remain accepted exceptions; no full Tiger Style compliance is claimed.


## Window state and native graphics capabilities (2026-10-18)

- Added all 26 named pinned window-state bits and snapshots retaining unknown future bits.
  Creation options now cover borderless, desktop fullscreen, always-on-top, utility, transparency,
  focus eligibility, and mutually exclusive OpenGL/Vulkan/Metal capability requests.
  No native context/surface/view is implicitly owned by these creation options.
- Added runtime border/resize/stacking setters and raise/maximize/minimize/restore requests.
  Pinned native source and initial tests exposed dummy-driver unsupported operations; tests now
  verify native errors and unchanged state, rather than assuming these requests succeed everywhere.
  Typed creation/query paths, snapshot independence, and unavailable graphics-backend failures pass.
- Full Debug and Safe suites pass: 115 tests across artifacts, including 29 executable IDE examples.
  Debug ran 111 with four unchanged documentation-tool tests cached; Safe ran all 115.
  Documentation generation, formatting, inventory, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 182 wrapped, 22 partial, 4,925 pending. Successful desktop runtime setters,
  physical window-manager actions, native graphics creation, transparency, and platform behavior
  remain unverified. Native allocation/dependency exceptions remain; no full Tiger Style claim.


## Window size and aspect limits (2026-10-18)

- Added per-axis optional minimum/maximum client sizes and optional aspect-ratio endpoints.
  Null expresses unrestricted values. Supplied size limits must be positive C ints; aspect limits
  must be finite/positive and ordered. Validation runs before native calls. Getters convert native
  zero back to null and validate native results, preserving stored-request versus actual-size semantics.
- Tests cover default limits, per-axis clearing, round trips, fixed/interval ratios, oversized/zero
  and nonfinite inputs, reversed ratios, and native minimum/maximum conflicts without mutation.
  The executable hover example and downstream consumer use these APIs.
- Pinned SDL source confirms that setters store constraints before attempting a resize. Documentation
  therefore makes no rollback promise for native failures; failure-after-mutation injection and
  window-manager enforcement remain unverified. Native size limits take precedence when aspect
  and size constraints conflict.
- Full Debug and Safe suites pass: 118 tests, including 30 executable hover examples. Reference
  generation, formatting, downstream all-extension consumption, and inventory pass.
- Inventory: 5,129 names; 188 wrapped, 22 partial, 4,919 pending. Native allocations/dependencies
  remain accepted exceptions; no full Tiger Style compliance or cross-platform completion claim.


## Window geometry and presentation controls (2026-10-18)

- Added client safe-area snapshots, pixel density distinct from UI scale, decoration extents,
  validated whole-window opacity, focus eligibility, copied icons, and typed attention requests.
  Native icon conversion can replace the prior icon before backend rejection; focus setters can
  succeed without changes or fail after flags change. These contracts are explicit in IDE docs.
- Dummy tests cover resized safe areas, density, unsupported decoration/opacity/icon/attention,
  invalid opacity, opaque fallback, focus no-op acceptance, and source-icon lifetime after native
  copying on a rejected request. They do not establish successful physical presentation behavior.
- Full Debug and Safe suites pass: 121 tests, including 31 executable IDE examples. Documentation
  generation, inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 200 wrapped, 22 partial, 4,907 pending. Physical notch/overscan geometry,
  successful decoration/opacity/icon/notification/focus behavior, and other platforms remain pending.
  Native allocation/dependency exceptions remain; no full Tiger Style compliance claim.


## Window discovery and taskbar progress (2026-10-18)

- Added native-owned pointer snapshots of borrowed windows, checked indexing, optional ID resolution,
  and borrowed parent queries. Array ownership never extends a window lifetime. Tests cover empty
  and multi-window snapshots, unknown/stale IDs, and array cleanup after an entry's owner is gone.
- Added typed taskbar progress states with unknown-value preservation and independent validated
  completion fractions. Tests cover every known state, endpoints, invalid values/states, preserved
  values when hiding the indicator, and unchanged state after wrapper/native validation rejection.
  Native apply failures can still leave new state stored; docs make no rollback guarantee.
- Full Debug and Safe suites pass: 125 tests, including 33 executable IDE examples. Reference docs,
  formatting, inventory, and downstream all-extension consumption pass. The final documentation
  formatting change was re-executed through the Debug hover-example gate.
- Inventory: 5,129 names; 214 wrapped, 22 partial, 4,893 pending. Real taskbar presentation, native
  failure-after-mutation, parented windows, and platform validation remain pending. Native allocator
  and dependency exceptions remain; no full Tiger Style compliance claim.


## Popup ownership and hierarchy validation (2026-10-18)

- Added common tooltip/menu popup creation with signed parent-relative offsets and shared graphics
  capability selection. Explicit child-before-parent owner cleanup is required because native parent
  destruction recursively destroys descendants. Added modal requests and bounded regular-window
  reparenting validation: self/sibling/descendant links are rejected; traversal stops after 256 links.
- Dummy SDL rejects popup creation/runtime reparenting/modal operations. Native creation-property
  fixtures build regular-window hierarchies for positive parent lookup, invalid-link rejection,
  257-level traversal-bound checks, and reverse-order cleanup. These tests do not establish successful
  popup creation, desktop focus behavior, native reparenting, or modal interaction.
- Full Debug and Safe suites pass: 128 tests, including 34 executable IDE examples. Reference docs,
  formatting, downstream all-extension consumption, and inventory pass.
- Inventory: 5,129 names; 215 wrapped, 24 partial, 4,890 pending. Popup creation is partial because
  property-specific policy/Emscripten flags are absent; reparenting is partial because validation
  deliberately bounds hierarchy depth. Native backend failures can detach parents or change modal
  flags; failure-after-mutation tests remain pending. Native allocation/dependency exceptions remain;
  no full Tiger Style compliance claim.


## Software window surfaces (2026-10-18)

- Added borrowed optimal-format window surfaces, whole-buffer presentation, explicit release,
  existence queries, and typed disabled/adaptive/positive-interval VSync. Window-owned SurfaceRef
  documentation carries the main-thread and resize-invalidation exception into IDE hovers.
  No surface owner is returned; window cleanup owns the final framebuffer.
- Tests cover missing-surface rejection, fill/readback, presentation, resize invalidation and
  reacquisition, explicit release/recreation, and native cleanup. VSync encoding tests preserve
  intervals and reject zero/oversized inputs/invalid native results. Dummy VSync requests/queries
  are unsupported; no real display timing or acceleration evidence is claimed.
- Full Debug and Safe suites pass: 131 tests, including 35 executable IDE examples. Reference docs,
  inventory, formatting, and downstream all-extension consumption pass. Final owner-thread hover
  qualifications were regenerated and rechecked through the documentation gate.
- Inventory: 5,129 names; 223 wrapped, 24 partial, 4,882 pending. Partial-region presentation,
  framebuffer acceleration, real synchronization, and platform behavior remain pending. Native
  allocation/dependency exceptions remain; no full Tiger Style compliance claim.


## Window input confinement and relative mode (2026-10-18)

- Added mouse/keyboard grab requests and active-grab queries, borrowed grabbed-window lookup,
  copied optional client-coordinate barriers with checked native geometry, and relative-mode
  enablement/query. Documentation distinguishes pending requests, focus, active SDL state, and
  actual OS enforcement; relative-mode updates flush pending motion and disable warp emulation.
- Tests cover empty/overflowing confinement geometry, hidden pending grabs without active capture,
  relative enablement/flags without focus, native unsupported barriers, and unchanged barrier absence
  after validation/backend rejection. The executable example and downstream consumer exercise relative
  mode; no physical cursor motion or OS shortcut capture is claimed.
- Full Debug and Safe suites pass: 134 tests, including 36 executable IDE examples. Reference docs,
  formatting, inventory, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 232 wrapped, 24 partial, 4,873 pending. Supported confinement rectangle
  round trips, focus transitions, motion flushing/delivery, native failure-after-mutation, and
  cross-platform physical input behavior remain pending. Accepted native allocation/dependency
  exceptions remain; no full Tiger Style compliance claim.


## General pixel-format identities and metadata (2026-10-18)

- Added sdl.pixels with all 65 distinct pinned format identities, eight endian-aware byte aliases,
  unknown-value preservation, classification, encoded/storage hints, copied channel metadata,
  integer-mask lookup, and FourCC construction. Surfaces, windows, and display modes expose typed
  queries; the existing numeric display-mode info field remains compatible.
- Zig 0.17 translation of nested SDL pixel predicates generates invalid bool/integer comparisons.
  Direct Zig bit rules avoid those macros. An independent C-generated 76-row fixture covers all
  73 named identities/aliases plus three custom values; regeneration compiles the pinned native
  macros and reproduced the fixture exactly. Native metadata tests additionally cover masks,
  endian byte layout, malformed formats, unknown identity preservation, and zero-layout behavior.
- Initial assumptions that unknown/FourCC metadata must fail were disproved by native tests/source:
  SDL can return zero-filled metadata, and YUV-disabled builds may reject FourCC masks. Contracts
  and tests now preserve those distinctions. Metadata success never proves backend/storage support.
- Full Debug and Safe suites pass: 137 tests, including 37 executable IDE examples. Reference docs,
  formatting, inventory, independent C-reference regeneration, and downstream consumption pass.
- Inventory: 5,129 names; 322 wrapped, 24 partial, 4,783 pending. General pixel conversion, palettes,
  colorspaces/layout helpers, and non-Linux execution remain pending. Native allocation/dependency
  exceptions remain; no full Tiger Style compliance claim.


## Typed surface allocation and conversion (2026-10-18)

- Added Surface.init_format and SurfaceRef.to_format using typed pixel identities. Existing RGBA
  helpers delegate to them without changing consumer behavior. Native-supported conversion pairs
  retain source ownership and return independent main pixels; palette/colorspace/alternate-image
  behavior remains native. Positive-size allocation policy remains explicit.
- Tests cover zero-filled RGB24, RGB565 and RGBA32 conversion, source/destination independence,
  native unknown-format failures, pre-call dimension validation, and source usability after a
  rejected conversion. Initial compile checks caught a reserved identifier and a shadowed method
  name; both were corrected before runtime validation.
- Full Debug and Safe suites pass: 139 tests, including 38 executable IDE examples. Reference docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 323 wrapped, 23 partial, 4,783 pending. SDL_ConvertSurface now has general
  format coverage; SDL_CreateSurface remains partial because zero-sized native surfaces are outside
  the positive-size constructor contract. All-format-pair testing, palettes, explicit colorspace
  conversion, general row locks, and OOM injection remain pending. Accepted native allocations and
  dependencies remain; no full Tiger Style compliance claim.


## Shared indexed palettes (2026-10-18)

- Added Palette owners, borrowed PaletteRef color access, and surface palette creation, attachment,
  removal, and lookup. SDL retains attached palettes; releasing the initial owner leaves surface
  references usable. Public documentation distinguishes owner borrows from surface associations.
- Range checks reject an entire invalid update before SDL can apply a truncated partial write.
  Tests cover copied input, empty boundaries, extreme indices/counts, unchanged colors on failure,
  retained/shared edits, incompatible attachment, removal/replacement, one-bit defaults, and RGBA
  conversion. The shared Color now has extern layout with compile-time native size/offset checks.
- Full Debug and Safe suites pass: 143 tests, including 39 executable IDE examples. Generated
  reference documentation, inventory, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 331 wrapped, 23 partial, 4,775 pending. General indexed row locks,
  explicit conversion palettes/colorspaces, OOM injection, and other-platform runs remain pending.
  Native allocation/dependency exceptions remain; no full Tiger Style compliance claim.

## Surface color keys and RLE controls (2026-10-18)

- Added optional RGB/exact encoded color-key setters, optional key queries, and RLE hint controls.
  Indexed keys preserve exact palette indices; absence does not generate a native query error.
  RGB mapping rejects FourCC/float/wide storage and missing indexed palettes before mutation.
- Tests verify transparent pixels leave the destination unchanged, disabling the key restores
  copying, invalid palette indices preserve the prior key, and RGBA locks preserve/read/edit pixels
  after an RLE-enabled blit. A test compilation issue with an untyped memcpy tuple was corrected
  to an explicit byte array before runtime verification. No acceleration benchmark is claimed.
- Full Debug and Safe suites pass: 146 tests, including 40 executable IDE examples. Reference docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 336 wrapped, 23 partial, 4,770 pending. RGB mapping is a convenience
  subset; exact encoded keys expose native values. All-format blitter combinations, allocation
  failure injection, and non-Linux execution remain pending. Native allocation/dependency exceptions
  remain; no full Tiger Style compliance claim.

## Surface reflection and scaling (2026-10-18)

- Added typed horizontal/vertical/both reflection and owned scaled copies. Flip locks native storage
  internally because pinned SDL directly accesses its pixel pointer; existing locks are rejected.
  FourCC plane layouts remain excluded from reflection. Scaling validates positive native-sized
  output dimensions and rejects locked sources. Shared palettes and native sampling are documented.
- Tests verify reflection pixel order, all replicated nearest-neighbor output pixels, source tint
  restoration/bypass, destination independence, existing-lock failures, and invalid size rejection.
  RLE hint preservation/access is exercised; no performance claim or exhaustive format claim.
- Full Debug and Safe suites pass: 148 tests, including 41 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 336 wrapped, 25 partial, 4,768 pending. Reflection and scaling are marked
  partial for FourCC exclusion and positive-only output sizes. Rotation remains pending while its
  native integer/fixed-point geometry bounds are audited. Other-platform/hardware validation and
  allocation failure injection remain incomplete. Accepted native allocations/dependencies remain;
  no full Tiger Style compliance claim.

## Audited surface rotation (2026-10-18)

- Added owned clockwise/counter-clockwise rotation preserving the original angle. Guards reject
  nonfinite or unrepresentable quarter-turn conversions, existing source locks, nonpositive layout,
  width+height above 8192, and pitch*height above signed native int. The conservative geometry bound
  protects pinned SDL's signed 16.16 coordinate and row-offset intermediates; larger sizes remain
  partial coverage. Native format/state/conversion behavior is explicitly documented.
- Tests cover positive/negative right-angle pixel order, independent output pixels, non-right-angle
  square bounds, nonfinite inputs, locked sources, and arithmetic rejection boundaries. An initial
  assumption that every fractional rotation enlarges a thin image failed; the corrected test uses
  a square and documentation now reflects SDL's pixel-center bounding behavior.
- Full Debug and Safe suites pass: 151 tests, including 42 executable IDE examples. Reference docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 336 wrapped, 26 partial, 4,767 pending. Large rotation geometry, complete
  indexed/float/YUV rotation combinations, metadata fidelity across native conversion paths, OOM
  injection, and non-Linux execution remain incomplete. Native allocation/dependency exceptions
  remain; no full Tiger Style compliance claim.

## Floating-point surface colors (2026-10-18)

- Added shared FloatColor, checked float pixel reads/writes, and whole-surface clears that ignore
  and restore clipping. Nonfinite writes/clears are rejected before mutation; finite HDR/negative
  values reach native conversion unchanged. Unlocked clear precondition is enforced.
- Tests verify RGBA128_FLOAT precision/HDR/negative values, unclipped writes, whole-image clear,
  clip restoration, unchanged values after validation errors, integer clamping/quantization,
  out-of-bounds rejection, and locked clear failure. Native small-format eight-bit intermediates,
  YUV read conversion/write rejection, and colorspace limitations are documented.
- Full Debug and Safe suites pass: 154 tests, including 43 executable IDE examples. Reference docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 338 wrapped, 28 partial, 4,763 pending. Float writes/clears are partial
  because the wrapper accepts finite input only; read results preserve native values. Exhaustive
  format/colorspace combinations, allocation failure injection, and other-platform execution remain
  incomplete. Native allocation/dependency exceptions remain; no full Tiger Style compliance claim.

## Explicit alpha premultiplication (2026-10-18)

- Added in-place premultiply_alpha with named sRGB and linear-sRGB working encodings. The wrapper
  locks/unlocks native storage and rejects outstanding locks. Documentation distinguishes pixel
  mutation from blend-mode selection, repeats from idempotent conversion, and native conversion
  from allocation-free processing.
- Tests verify unchanged alpha, tint/opacity/blend/clip state, full-image multiplication despite
  clipping, differing linear-light output, repeated multiplication, and lock rejection. Native
  quantization is tested on RGBA32; exhaustive format/colorspace combinations remain incomplete.
- Full Debug and Safe suites pass: 156 tests, including 44 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 339 wrapped, 28 partial, 4,762 pending. Raw-buffer premultiplication,
  explicit colorspace metadata/conversion, allocation failure injection, and other-platform checks
  remain pending. Native allocations/dependencies remain accepted; no full Tiger Style claim.

## Colorspace identities and explicit conversion (2026-10-18)

- Added every named pinned colorspace and default alias with custom numeric identity preservation.
  Surface colorspace queries/relabeling explicitly leave pixel numbers unchanged; converted returns
  owned pixels with selected format, encoding, optional indexed palette, and color properties.
  Shared palette/alternate-image and pointer-property lifetime limits are documented.
- Tests distinguish unchanged bytes after metadata relabeling from sRGB-to-linear conversion
  (mid-gray approximately 0.216), preserve custom identities, verify independent destination pixels,
  reject locked/invalid-format conversion, and release the palette owner before reading indexed
  converted output. No exhaustive HDR/format-pair claim is made.
- Full Debug and Safe suites pass: 159 tests, including 45 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 356 wrapped, 28 partial, 4,745 pending. Colorspace components/construction,
  HDR property-specific helpers, allocation failure injection, and non-Linux execution remain pending.
  Native allocations/dependencies remain accepted; no full Tiger Style compliance claim.

## Colorspace components and construction (2026-10-18)

- Added all pinned component-model, range, primaries, transfer, matrix, and chroma-location names.
  Field-width enums retain unknown packed values; components/from_components preserve the five
  reserved bits for lossless numeric round trips. Representation does not validate native support.
- Extraction/construction and classification tests compare against translated native macros for
  named, custom, zero, and all-bits-set identities. Documentation explicitly records that SDL's
  limited-range predicate means non-full, including unknown values. Direct range comparison remains
  available when the caller requires the specifically named limited range.
- Debug and Safe suites pass: 161 tests including 46 executable IDE examples (Debug reused four
  cached tooling tests). Generated docs, inventory, formatting, and downstream consumption pass.
- Inventory: 5,129 names; 432 wrapped, 28 partial, 4,669 pending. Transfer-function evaluation,
  HDR property helpers, exhaustive native conversion compatibility, and non-Linux execution remain
  incomplete. Native allocation/dependency exceptions remain; no full Tiger Style compliance claim.

## Alternate surface representations (2026-10-18)

- Added retained alternate attachment/removal, presence query, and owned pointer-list snapshots
  with borrowed entries. Attachment accepts an existing surface owner without consuming it; native
  references keep images alive after that owner is released. Lists do not retain their entries.
- A bounded iterative traversal rejects reference cycles before mutation; limits are 256 pending
  nodes and 4096 visits. Tests cover retained pixels after owner release, base-first enumeration,
  out-of-range access, self/indirect cycle rejection, removal, and unchanged destination after
  a 257-child candidate exceeds the breadth bound. Duplicate attachments retain native references.
- Full Debug and Safe suites pass: 164 tests, including 47 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 435 wrapped, 29 partial, 4,665 pending. Attachment remains partial due
  to graph limits; large-graph support, allocation failure injection, and platform-specific high-DPI
  icon/cursor behavior remain incomplete. Native allocations/dependencies remain accepted; no full
  Tiger Style compliance claim.

## Repeated surface tiles (2026-10-18)

- Added blit_tiled_to with signed source/destination selection, bounded intersections, empty no-ops,
  and explicit alias/lock rejection. Native blend/modulation/key semantics apply. Documentation
  explains that destination clipping restarts tile phase rather than preserving offscreen offsets.
- Tests verify every pixel of a repeated pattern with partial edge tiles, clip-origin restart,
  untouched pixels outside the clip, empty source intersections, same-handle rejection, and locked
  destination rejection. Scaled tiling/nine-grid paths remain separate pending work.
- Full Debug and Safe suites pass: 166 tests, including 48 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 436 wrapped, 29 partial, 4,664 pending. Scaled tile arithmetic, nine-grid,
  allocation failure injection, and non-Linux execution remain incomplete. Native allocation and
  dependency exceptions remain; no full Tiger Style compliance claim.

## Scaled tiled blits (2026-10-18)

- Added scaled tiling with explicit sampling, finite/nonnegative scale checks, native-equivalent
  rounded tile-size checks, and effective-clip edge validation. Zero scale/rounded-zero dimensions
  produce no writes. Partial edge spans mapping to zero source pixels or exceeding source bounds
  are rejected before writes; a full-support fallback remains pending and coverage stays partial.
- Tests verify enlarged repeating pixels with a representable partial edge, rejected zero-source
  edge, NaN/infinity/negative/overflow scales, and zero/tiny-scale no-ops. An initial local name
  shadowed the clip method; renamed before successful runtime validation.
- Full Debug and Safe suites pass: 167 tests, including 48 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 436 wrapped, 30 partial, 4,663 pending. Complete scaled-edge handling,
  nine-grid drawing, allocation failure injection, and non-Linux execution remain incomplete.
  Native allocation/dependency exceptions remain; no full Tiger Style compliance claim.

## Scaled tile edge fallback (2026-10-18)

- Replaced zero/excessive source-edge rejection with a clipped full-tile fallback. Destination clip
  is restored on exit; endpoint arithmetic is checked before writes. RLE-requested sources use a
  temporary uncompressed native copy to isolate SDL's clipped-scaler source-pointer adjustment.
  Temporary native allocation and fallback edge-sampling differences are documented.
- Existing scaled-tiling tests now verify the formerly rejected one-pixel right/bottom edges,
  pixels outside the target, restored clipping, and RLE-requested source processing. Source/target
  lifetime and no-alias contracts remain. Nonfinite/overflow scales still fail before mutation.
- Debug and Safe full suites, generated docs, inventory, formatting, and downstream consumption
  pass; suite remains 167 tests including 48 executable IDE examples. Checks were repeated after
  adding the RLE isolation path because that changed native allocation and source handling.
- Inventory remains 436 wrapped, 30 partial, 4,663 pending. Scaled tiling remains partial for
  finite/representable arithmetic constraints. Exhaustive format/filter/RLE combinations, native
  allocation-failure injection, nine-grid, and non-Linux execution remain incomplete. Accepted native
  allocations/dependencies remain; no full Tiger Style compliance claim.

## Nine-grid surface drawing (2026-10-18)

- Added typed border sizes and corner scale with explicit sampling and contained source/destination
  regions. Validation rejects oversized source borders, destination border overlap, nonfinite/negative
  scale, and empty source bands stretched into nonempty target bands before writes. Native zero
  scale semantics (unscaled corners) are retained. RLE sources use an isolated native copy.
- Pixel-readback tests verify every corner/edge/center pixel of a scaled grid, invalid geometry
  leaves output unchanged, and zero scale behaves as unscaled. Native failure after validation can
  still partially write; format/filter/backend coverage is not exhaustive.
- Full Debug and Safe suites pass: 169 tests, including 49 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 436 wrapped, 31 partial, 4,662 pending. Nine-grid remains partial for
  offscreen regions and overlapping-border layouts. Native allocation failure injection and
  non-Linux execution remain incomplete. Native allocations/dependencies remain accepted; no full
  Tiger Style compliance claim.

## Renderer discovery and CPU destinations (2026-10-18)

- Added compiled-in driver count/name discovery, borrowed window/renderer association lookup,
  selected backend names, physical/current output queries, and software renderer creation over
  borrowed CPU surfaces. Updated owner/view lifetimes to include backing surfaces, with explicit
  main-thread wrapper contracts and texture-before-renderer-before-backing-resource cleanup.
- Tests validate driver index bounds, selected software backend, window associations, physical
  window output, software output sizes, absent software window association, drawing into a CPU
  surface, and surface survival after renderer destruction. Enumeration is not runtime capability
  proof; logical-presentation/texture-target size distinctions await those control APIs.
- Full Debug and Safe suites pass: 172 tests, including 50 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 444 wrapped, 31 partial, 4,654 pending. Other backend/hardware validation,
  logical presentation, target textures, and allocation failure injection remain incomplete.
  Native allocations/dependencies remain accepted; no full Tiger Style compliance claim.

## Renderer drawing colors and primitive blending (2026-10-18)

- Added floating color state, byte/float queries, and primitive blend controls. Float setters reject
  nonfinite input. Byte reads deliberately query float state, clamp finite components to 0..1,
  and truncate component*255; raw-installed NaN/infinity is rejected without native integer casts.
- Initial tests disproved an assumption that SDL's native byte getter clamps: HDR red 2 became 254
  because pinned SDL directly casts float*255. The wrapper now implements explicit safe conversion.
  A parameter shadowing the new color method was also renamed before successful validation.
- Tests preserve HDR float state, reject nonfinite setters/reads, verify unchanged state on validation
  failure, check alpha compositing with pixel readback, and distinguish replacement blend mode.
- Full Debug and Safe suites pass: 174 tests, including 51 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 448 wrapped, 32 partial, 4,649 pending. Float setter coverage is partial
  for finite-only input. GPU/HDR display behavior, exhaustive blend modes, allocation failure
  injection, and non-Linux execution remain incomplete. Native allocations/dependencies remain
  accepted; no full Tiger Style compliance claim.

## Logical renderer presentation (2026-10-18)

- Added typed presentation modes, positive logical size configuration/null disable, state queries,
  and physical mapping rectangles. Enabled size validation precedes native changes; target-specific
  state and input conversion remain separate contracts.
- Tests distinguish a 4x2 logical resolution, 8x4 letterboxed mapping, and 8x6 physical output,
  verify the y=1 letterbox offset, reject zero enabled dimensions without changing state, and reset
  to disabled presentation. Initial assumptions about current_output_size were disproved: pinned
  SDL assigns it the mapped destination extent, not logical resolution or full physical output.
  Corrected API documentation and tests preserve that observed native behavior.
- Full Debug and Safe suites pass: 176 tests, including 52 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 456 wrapped, 33 partial, 4,640 pending. Presentation configuration is partial
  for positive enabled dimensions. Texture-target state, coordinate/event conversion, full mode/
  hardware validation, and non-Linux execution remain incomplete. Native allocations/dependencies
  remain accepted; no full Tiger Style compliance claim.

## Renderer/window coordinate mapping (2026-10-18)

- Added typed floating points and bidirectional window/drawing conversion, validating finite input
  and output. Documentation distinguishes window units from framebuffer pixels, main-window state
  from texture-target state, and coordinate conversion from event mutation/hit testing.
- Expanded the headless window test with letterbox coordinate round trips, outside-bar negative
  coordinates, and NaN/infinity rejection. Pinned source confirms viewport/scale/DPI participation;
  non-unit physical DPI and texture-target interactions remain unexecuted validation items.
- Full Debug and Safe suites pass: 176 tests, including 52 executable IDE examples. Existing graphics
  coverage was expanded without adding a test declaration. Generated docs, inventory, formatting,
  and downstream all-extension consumption pass.
- Inventory: 5,129 names; 456 wrapped, 35 partial, 4,638 pending. Coordinate functions are partial
  for finite-only input/output. Typed viewport/scale, event-wide conversion, hardware DPI, and
  non-Linux execution remain incomplete. Native allocations/dependencies remain accepted; no full
  Tiger Style compliance claim.

## Renderer synchronization and flush (2026-10-18)

- Added typed disabled/adaptive/positive VSync intervals, stored-configuration queries, and explicit
  command flushing. Documents failed-set side effects, possible simulated synchronization, and
  the distinction between submission, presentation, and GPU completion.
- Surface-renderer tests cover disabled success, unsupported enabled synchronization, invalid
  interval rejection, and pixel visibility after flush.
- Full Debug and Safe suites pass: 177 tests, including 52 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 460 wrapped, 36 partial, 4,633 pending. Native hardware refresh timing,
  adaptive synchronization, and non-Linux execution remain unverified. Native allocations and
  dependencies remain accepted; no full Tiger Style compliance claim.

## Texture modulation and compositing (2026-10-18)

- Added byte/float RGB tint and alpha opacity, plus independent texture blend state. Float setters
  reject nonfinite input before mutation; byte getters safely clamp and round finite state, while
  float getters preserve native values. Texture conversion rounds, unlike draw-color truncation.
- Tests cover HDR/negative state, half-byte rounding, unchanged state on invalid setters, safe
  rejection of raw-installed NaN, alpha compositing over blue, renderer/texture state independence,
  and resetting modulation without changing stored white pixels. Added an executable IDE example.
- Full Debug and Safe suites pass: 180 tests, including 53 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 468 wrapped, 38 partial, 4,623 pending. Float setters are partial for
  finite-only inputs. Hardware/HDR rendering, native geometry, all blend modes, allocation failure
  injection, and non-Linux execution remain incomplete. Native allocations/dependencies remain
  accepted; no full Tiger Style compliance claim.

## Texture sampling and dimensions (2026-10-18)

- Added floating source-size queries, named texture sampling policies, and renderer defaults that
  affect only subsequently created textures. Queries preserve unknown identities; setters reject
  invalid/unknown policies. Size documentation warns against deriving allocation lengths from
  potentially rounded native floating dimensions.
- Tests verify default inheritance without changing existing textures, all named mode metadata,
  unchanged state on invalid requests, source dimensions, and exact nearest-neighbor pixel
  replication. Metadata checks do not establish hardware filtering quality.
- Debug and Safe validation pass: 181 tests, including 53 executable IDE examples (Debug full
  validation reused focused-test results). Generated docs, inventory, formatting, and downstream
  all-extension consumption pass.
- Inventory: 5,129 names; 477 wrapped, 39 partial, 4,613 pending. The default setter is partial
  because native SDL accepts arbitrary identities while this wrapper requires named valid modes.
  Hardware filtering, source-provider builds, non-Linux execution, and the remaining roadmap are
  incomplete. Native allocations/dependencies remain accepted; no full Tiger Style claim.

## General texture allocation and contained RGBA uploads (2026-10-18)

- Added explicit format/access creation, exact integer dimensions/public format queries, and
  checked tightly packed RGBA32 updates for whole textures or contained regions. Initial RGBA
  creation now reuses general allocation. Ownership, undefined initial storage, lock restrictions,
  source-buffer lifetimes, and partial native failures are documented.
- Software pixel readback verifies static/streaming/target texture updates and unchanged surrounding
  pixels. Tests cover zero-size creation, invalid byte counts, extreme out-of-bounds coordinates,
  empty regions, and rejection of RGBA updates to RGB565 textures. Added an executable IDE example.
- Initial test syntax used the removed array repetition operator; replaced it with explicit bytes
  before successful validation on the exact Zig 0.17.0 toolchain.
- Full Debug and Safe suites pass: 183 tests, including 54 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 481 wrapped, 39 partial, 4,609 pending. Creation remains partial for
  positive dimensions and named access modes; uploads remain partial for tightly packed contained
  RGBA32 data. Native locking, target selection, general/padded/planar uploads, hardware backends,
  and non-Linux execution remain incomplete. Native allocations/dependencies remain accepted;
  no full Tiger Style compliance claim.

## Streaming texture workflows, render targets, and indexed uploads (2026-10-18)

- Added contained RGBA32 streaming locks with scoped row views. Acquisitions explicitly zero visible
  pixels, discarding prior region contents and making early/error-path releases initialized. Bounds,
  pitch, and row-offset arithmetic are checked. Padding stays hidden; native unlock has no error
  result. Nested/aliased use remains a documented caller lifetime responsibility, not a mutex or
  runtime borrow checker. No Zig allocation; native allocations/blocking remain possible.
- Added explicit target selection/query, cross-renderer validation, and active-target rejection for
  draws/uploads/locks. Pinned SDL source confirms failed target changes can mutate state and that
  logical presentation/viewport/clip/scale persist per target. No rollback guarantee is claimed.
- Added contained integer source-region draws, byte-addressable padded uploads, and retained shared
  texture palettes. Updated shared palette lifetime/thread documentation to cover texture owners.
  Uploads validate native pitch limits and the final visible byte without requiring last-row padding.
- Tests exercise subregion lock initialization, pitch-independent rows, outside-pixel preservation,
  error-path unlock/reacquisition, unsupported lock access/format, malformed layout validation,
  target presentation restoration, feedback/foreign-owner rejection, and the complete streaming
  source -> cropped offscreen target -> scaled output path with pixel readback.
- Additional tests cover padded RGB24 upload, short/invalid rows, empty regions, native pitch bounds,
  indexed drawing after releasing the palette owner, shared palette edits, incompatible counts,
  removal, and continued drawing through a second retained texture association. Two executable IDE
  examples demonstrate the full offscreen workflow and indexed texture uploads.
- Initial compile errors from untyped memcpy literals were corrected to explicit byte arrays. Row
  validation now rejects rows exceeding native pitch capacity consistently before length checks.
- Full Debug and Safe suites pass: 191 tests, including 56 executable IDE examples. Generated docs,
  inventory, formatting, and downstream all-extension consumption pass.
- Inventory: 5,129 names; 486 wrapped, 40 partial, 4,603 pending. Locking remains partial for nonempty
  contained RGBA32 with explicit initialization; draw sources remain contained integers; generic
  uploads exclude FourCC/planar/compressed and sub-byte formats. Lock-to-surface, fractional source
  rectangles, exhaustive transformed-coordinate arithmetic, allocation/backend failure injection,
  hardware filtering/targets, and non-Linux execution remain incomplete. Native dependencies and
  allocations remain accepted; no full Tiger Style compliance claim.
