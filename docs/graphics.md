# First graphics and event slice

This slice adds usable window/renderer ownership, static RGBA textures, drawing operations, and
typed polling for quit, close, resize, pixel-size, and keyboard events. It is not completion of
the video, rendering, or event subsystems. General surface locks/unrestricted scaled clipping and explicit colorspace conversion,
advanced window relationships/constraints, texture access/format
variants, and additional typed events remain pending.

## Consumer workflow

```sh
zig build example       # installs zig-out/bin/sdl-window
zig build run-window    # visible desktop example, Escape/close or 600-frame limit
zig build test-graphics # dummy video driver, software renderer, pixel readback assertions
zig build test test-graphics -Doptimize=safe
```

The example is in `examples/window.zig`. It polls at most 64 events per frame and renders a
procedural texture for at most 600 frames, delaying 16 milliseconds between frames. SDL's event
pumping and rendering can still block internally; these bounds are not a frame-time guarantee.
It uses the desktop main entry point with `SDL_SetMainReady`; mobile/web entry-point adapters
remain pending. No desktop display is needed for `test-graphics`.

## Resource and failure contracts

| Resource / operation | Contract |
| --- | --- |
| `Window.init` | Main thread; video initialized; UTF-8 sentinel title borrowed for the call; positive dimensions fitting C int; SDL may allocate |
| `Window.borrow` | Non-owning view; owner outlives view and dependent resources |
| `Renderer.init` | Borrows window; optional sentinel driver name is borrowed for the call |
| `Texture.init_rgba` | Borrows renderer; exact tightly packed RGBA byte count; checked pitch/length arithmetic; SDL copies pixels before return |
| `deinit` | Main thread; destroy texture, renderer, window, then subsystem references; never copy owners or destroy twice |
| `draw_texture` | Rejects a texture from another renderer; null destination covers target; currently draws the entire source |
| `fill_rect` | Null covers target; finite coordinates, nonnegative extent; zero area accepted |
| `WindowRef.size` | Window coordinates; `pixel_size` separately returns drawable pixel dimensions |
| `events.poll` | Main/video thread; optional result, empty queue is not an error; no wrapper allocation |

Native failures return `SdlFailure`; validation errors are normal error unions. Validation runs
before native resource creation/upload. Texture upload failure releases the newly created native
texture. Cleanup can affect SDL's ephemeral diagnostic text; error identity is preserved, but
there is no guaranteed diagnostic snapshot across cleanup. Explicit caller buffers are available
through `sdl.errors.copy_message` when a diagnostic needs to be retained before further SDL calls.

All handle fields are explicit native interoperability escape hatches. Do not fabricate handles,
destroy a native object behind an owner, or use a borrowed view after destruction. Zig does not
enforce these lifetime contracts. The renderer association check prevents ordinary cross-renderer
texture mistakes; it cannot detect use-after-free or native pointer reuse.

## Events and forward compatibility

Window IDs, keycodes, and scancodes are non-exhaustive enums. Only Escape currently has a named
key/scancode tag; all other numeric values are retained. Keyboard metadata and nanosecond timestamps
are preserved. Resize payloads remain signed, including malformed values pushed by external code.

Events without typed wrappers use `.unknown` with the native union intact. Copying an event does
not copy or retain pointer-backed payloads. Process borrowed payloads before subsequent polling or
pumping, and obey each native event's ownership contract. The wrapper does not free user data.
`from_native` is an explicit interop operation requiring an initialized union consistent with its tag.

## Validation and coverage

Pure tests exercise size/pitch bounds, exact upload byte counts, invalid rectangles, future key
values, unknown payload preservation, and signed resize data. Headless integration tests exercise
window queries, renderer creation failure/recovery, texture copying, drawing verified through pixel
readback, cross-renderer rejection, presentation, queued quit events, and ordered teardown.

The coverage manifest distinguishes `partial` from `wrapped`. Limited window flags, static RGBA
texture creation/upload, whole-source drawing, and the typed event subset remain partial entries.
Keyboard work exposed 297 `SDLK_*` macros omitted by the earlier `SDL_*` inventory filter. Both
inventory paths now include them; the macro baseline update contains only those added names.

Dummy-driver results do not establish GPU correctness, DPI behavior on real monitors, native window
interaction, allocation freedom, or failure-path leak freedom for every backend. Those need later
platform tests and instrumentation. Native dependencies/allocation and meaningful-assertion rather
than artificial assertion-count choices remain the documented Tiger Style limitations.

## CPU surfaces and image loading

Enable `-Dimage=true` and import `sdl_image`. `image.load(path)` reads a sentinel-terminated
UTF-8 file path; `image.load_memory(bytes)` detects the format of encoded bytes. Both return
`sdl.surface.Surface` owners. The encoded bytes are no longer borrowed when decoding returns.
Inspect dimensions with `surface.borrow().size()`; do not assume RGBA output or tight row packing.

With a live renderer, use `sdl.render.Texture.from_surface(renderer.borrow(), surface.borrow())`.
The resulting static texture does not retain the surface, which can be destroyed immediately
after upload. The renderer must still outlive the texture. `Surface.init_rgba(size)` also creates
zero-filled CPU storage without video initialization; it can be destroyed on any thread with
exclusive access. Image decoding uses the main thread under the current wrapper contract.

Loading may allocate, block, and request large decoded buffers. No decode budget or codec
availability guarantee is imposed by the wrapper. Failures return `SdlFailure`; read the SDL
error immediately. `load_memory` closes its temporary native stream on either outcome.
PNG saving and borrowed streams are available; other encoders, hinted formats, animation, and
direct image-to-texture helpers are pending.

`zig build test -Dimage=true` includes deterministic file/memory BMP decoding, malformed and
truncated input, recovery, input-buffer independence, and software-renderer readback after the
source surface is destroyed. The original 1x1 orange BMP fixture is generated from a BITMAPINFOHEADER
and one BGR pixel with row padding; it has no external asset/license dependency. This tests the
BMP path; PNG round trips are covered by the stream tests below. This is not the full codec
matrix or native allocation-failure cleanup instrumentation.

## Streams and PNG saving

`image.load_stream(stream.borrow())` decodes from a shared cursor and leaves the stream open.
`image.save_png(surface.borrow(), path)` overwrites a file; a failure can leave a partial file.
`image.save_png_stream(surface.borrow(), stream.borrow())` writes at the current cursor without
closing or retaining either argument. Decode output owns its pixels independently of the stream.
The executable hover example on `save_png_stream` shows encoding into a caller-provided buffer.

`Stream.from_const_memory(bytes)` borrows immutable input; `Stream.from_memory(buffer)` borrows
fixed writable storage. Both buffers must outlive their streams. Memory capacity does not grow;
only the written prefix is valid encoded output. Native encoder scratch storage can still allocate.
`Stream.open(path, .read / .create / .update)` opens binary files; `create` truncates immediately.
Byte transfers, flushing, dynamic storage, and typed callback backends are now available; see
[stream contracts](io.md). Append/exclusive file modes remain pending.

Use `defer stream.deinit()` for best-effort cleanup, accepting that close errors are discarded.
For output where final close errors matter, call `try stream.close()` exactly once instead.
A close attempt consumes the owner even when it fails: never leave a `defer` or `errdefer` that
would close it again. Scope error cleanup around the work before the final close:

```zig
var output = try sdl.io.Stream.open(path, .create);
{
    errdefer output.deinit();
    try image.save_png_stream(surface.borrow(), output.borrow());
}
try output.close();
```

Tests exercise PNG signatures and decoded pixel equality, file truncation, cursor sharing, memory
seek bounds, empty buffers, injected close failure, and exhausted/read-only output. Guard bytes
surrounding a short writable buffer remain intact. Intentional PNG write failures may print libpng
diagnostics to stderr even when tests pass. Tests use an isolated temporary directory for file output.


## Checked surface operations

`SurfaceRef.read_pixel(.{ .x = x, .y = y })` returns `surface.Color`, the same eight-bit RGBA type
used by the renderer. `write_pixel(point, color)` replaces one pixel without blending or clipping.
Unsigned coordinates outside the dimensions return `OutOfBounds` before native access. These native
helpers account for pixel format and pitch, but prioritize convenience over speed. They can lock or
convert storage internally; do not use them as a fast bulk-pixel loop. Low-depth formats quantize
colors, formats without alpha discard it, and unsupported native formats can fail.

`fill(color)` fills the surface within its current native clipping rectangle, with no blending.
It maps RGBA to the closest native representation. Rectangular fills and typed clip state are described below. RGBA row locks are described below; raw pixel mapping and other-format locks remain pending.

`duplicate()` returns a new owner with independent main pixel storage and the same format.
`to_rgba()` returns independent main pixels in R,G,B,A byte order on either host endian. Row pitch
can still include padding. These operations allocate natively, can fail, and leave source ownership
with the caller. Alternate images can retain shared references, so this is not a deep-copy API for
an entire image graph. SDL controls palette, color-key, and colorspace conversion; eight-bit RGBA
conversion can lose HDR precision and does not provide explicit color-profile controls.

No video initialization is needed for these operations. Use any thread with exclusive access to the
surface, including for reads and copies. Tests cover unblended alpha, coordinate bounds, clipping,
padded RGB24 conversion, copy independence after source destruction, and edited PNG round trips.


## Surface composition

`source.blit_to(destination)` copies the whole source at destination (0,0), without scaling.
`source.blit_scaled_to(destination, .nearest / .linear / .pixel_art)` scales to the destination's
full dimensions. Both clip writes to destination bounds and its native clip rectangle. Clipping
restricts writes without redefining the scaling transform. Nearest sampling replicates pixels;
linear filtering interpolates. The pinned CPU blitter currently treats pixel_art as nearest.

Blending is source state: explicitly call `source.set_blend_mode(.none)` for replacement or `.alpha`
for straight-alpha composition. `blend_mode()` queries it. Premultiplied alpha/addition, addition,
modulation, and multiplication are also represented; premultiplied modes require premultiplied
source pixels. Blend state does not change pixel bytes. Separate color/alpha modulation and color-key state still affect results and are not reset.
Tint/opacity controls are described below; typed color-key controls remain pending.

Both surfaces must stay alive and unlocked, with exclusive access during each operation. The
wrappers retain neither surface; source destruction after success leaves destination pixels valid.
Same-handle blits return `AliasedSurface` before mutation. Distinct native handles must not share
pixel storage. SDL can convert pixel formats, allocate, or block; native failure does not guarantee
rollback. No video initialization is needed. Contained subrectangles and positioned blits are described below. Unrestricted scaled clipping,
in-place overlap, tiling, and nine-grid composition remain pending.

Tests cover clipped copies, explicit replacement versus alpha blending, nearest scaling and clipping
coordinates, supported blend-mode round trips, all sampling branches, locked-surface errors/recovery,
and loaded-image conversion with source lifetime independence. Mid-alpha comparisons allow native
integer rounding differences. These tests do not validate every blend/format/filter combination.


## Cropped and positioned blits

`blit_region_to(destination, &.{ .source = region, .destination = position })` selects a contained
source region and an unscaled signed destination position. Null source means the whole source;
omitted position means (0,0). `Region` uses unsigned x/y/width/height and must fit entirely within
its surface. Zero-sized regions are permitted at the edges. Bounds are checked using subtraction,
so oversized coordinates/extents return `InvalidRegion` without overflow or destination mutation.

Destination `Position` uses signed 32-bit x/y. Negative positions clip the source's leading pixels;
fully offscreen positions, including the extreme signed values, do no work. The wrapper computes
intersections using 64-bit arithmetic before handing bounded geometry to SDL. Destination native
clipping still applies. These operations do not change source blend or destination clip state.

`blit_scaled_region_to(destination, &.{ .source = source_region, .destination = target_region,
.mode = .nearest })` scales between contained regions. Null regions select whole surfaces. Both
regions must fit; out-of-bounds scaled destination rectangles are deliberately not supported yet.
Native clipping restricts writes while preserving the selected transform.

Same-handle alias rejection occurs before geometry checks. Both region APIs treat zero extents as
successful no-ops; entirely offscreen unscaled blits also return without native lock checks. For
nonempty visible work, the existing unlocked/exclusive-access and nonoverlapping-storage contracts
apply. Native failures may partially modify output. Neither owners nor option pointers are retained.

Tests compare positioned crops against an independent bounded pixel model across 48 offsets,
exercise signed extremes and oversized unsigned regions, and check scaled subregions with every
sampling mode. Their uniform-color scale cases validate region placement, not general filter quality.


## Clip state and rectangular fills

`set_clip(?ClipRect)` replaces the destination clip and returns its effective contained `Region`.
Null resets it to the whole surface. `clip()` queries current state. `ClipRect` permits signed x/y
and unsigned extents; intersections use 64-bit arithmetic, including extreme values. Empty or wholly
offscreen rectangles are valid: they return a canonical zero region and suppress subsequent fills
and blits. SDL's setter returns false for an empty intersection, which this wrapper deliberately
does not interpret as failure. Native getter failure still returns `SdlFailure`.

`fill_rect(rect, color)` intersects its rectangle with the surface bounds and current clip, then
writes the mapped color without blending. It does not change clip state. Empty/offscreen input does
no work. Color approximation, unsupported formats, and native allocation/locking limits match
`fill`. Single-pixel writes continue to ignore clipping. Clip changes and queries require exclusive
surface access; they do not retain inputs or mutate pixel storage.

Tests cover initial/reset state, empty clips despite stale native diagnostics, extreme signed/unsigned
geometry, pixel-model rectangle intersections, clip preservation, disabled fills/blits, and resumed
drawing after reset. Raw encoded-pixel fills and unrestricted scaled clipping remain unwrapped.


## Scoped RGBA rows

`var pixels = try surface.borrow().lock_rgba(); defer pixels.deinit();` acquires a scoped row view.
`try pixels.row(y)` returns exactly `width * 4` mutable bytes in R,G,B,A order, excluding padding.
The guard exposes read-only width/height/pitch metadata; do not change its fields or copy the guard.
Use existing bytes only when initialized; locking itself does not initialize storage. Writes directly
change pixels and ignore blend/clip state. Repeated row calls can alias the same bytes.

This API accepts positive-sized RGBA32 surfaces only. Use `to_rgba()` explicitly for loaded images
in other formats. `UnsupportedPixelFormat` rejects incompatible storage; `AlreadyLocked` rejects
existing native/wrapper locks. `InvalidPixelLayout` covers empty dimensions, missing storage,
insufficient pitch, and row-span arithmetic overflow. Failure after acquiring a native lock releases
it automatically. Row indices outside height return `OutOfBounds` without accessing pixels.

Keep the surface alive and exclude every other access until guard cleanup. SDL pixel locking makes
storage accessible; it is **not a mutex**. Do not blit, encode, upload, destroy, or use other surface
views while the guard is live. Deinitialize it exactly once on the accessing thread; all row slices
expire immediately. Native locking may allocate/decompress storage; the wrapper does not allocate.
Native interop must still supply valid backing allocations; geometry checks cannot prove ownership
or capacity of arbitrary raw pointers.

Tests cover row edits, nested-lock rejection, out-of-range rows, unlock/reacquisition, padded borrowed
storage with guard bytes, incompatible formats, missing storage, empty surfaces, and PNG encoding
after unlock. Other pixel formats, recursive locks, planar layouts, RLE-specific stress, and native
allocation-failure injection remain unverified or unwrapped.


## Blit tint and opacity

`set_tint(Tint)` sets per-channel RGB multipliers. Each channel uses `source * multiplier / 255`,
with native integer rounding. Defaults are all 255, so `set_tint(.{})` restores identity. `tint()`
returns this state, not a pixel color. `set_opacity(u8)` multiplies source alpha by value/255;
`opacity()` queries that multiplier. A value of 255 preserves source alpha; zero removes it.

These independent controls modify source blit state without modifying stored pixels or changing
blend mode. Use `.alpha` blending for ordinary straight-alpha composition. With `.none`, lowering
opacity can replace destination pixels with reduced-alpha data rather than leave them unchanged.
Premultiplied modes require suitable pixel data/channel factors; opacity alone is not a promise of
correct premultiplied fading. Native format, modulation, color key, and blend state determine the
result. Modulation is not a colorspace/profile correction API.

Setters and getters require exclusive surface access. They allocate no Zig storage and report native
failures as `SdlFailure`. Setters can invalidate native blit caches; neither setters nor getters retain
inputs. Tests cover independent state/defaults/reset, unchanged source pixels and blend mode,
channel multiplication, and scaled alpha composition at zero/partial/full opacity. Midpoint checks
allow small native rounding differences; this is not an exhaustive format/blend-mode matrix.


## Window controls

`WindowRef.set_title` copies a sentinel UTF-8 title through SDL. `title()` borrows SDL's string until
replacement or window destruction; copy it before retaining it. Embedded zeros truncate titles.
`set_size` validates positive client dimensions before requesting a resize. Framebuffer pixels may
differ; query `pixel_size()` separately.

`set_position` takes independent tagged axes: `.coordinate = signed_value`, `.centered = display`,
or `.unspecified = display`. A null display means primary. `.{}` centers both axes on primary.
Display hints require nonzero IDs fitting 16 bits. Coordinates colliding with native sentinel ranges
return `InvalidPosition`; both axes validate before SDL is called. `position()` returns the most
recent desktop coordinates reported by the backend.

`show()` and `hide()` retain the window and its children. Showing does not guarantee focus or that
another window will not cover it. Size/position requests may be asynchronous, denied, constrained,
or ignored in fullscreen/maximized states. `sync()` waits for pending native state and reports
failure including timeout, but provides no caller-controlled deadline. Requery actual state after
synchronization; success does not promise the exact requested size/position. All calls require the
main thread and initialized video. Native calls may allocate or block.

Dummy-driver tests check copying, state changes, and validation atomicity. Desktop window-manager
policies, asynchronous transitions, and synchronization timeouts remain unverified.


## Window state and creation capabilities

`WindowRef.flags()` returns a copied bitset with `contains(.hidden)`, `contains(.resizable)`, and
other named `WindowFlag` queries. All 26 pinned native window bits have names; `bits` also retains
unknown future bits. A flag snapshot can become stale immediately and may describe a pending
request. It owns no window and does not extend its lifetime.

`WindowOptions` now exposes borderless, fullscreen desktop, always-on-top, utility, transparency,
and focus eligibility settings. `graphics_backend` selects `.none`, `.opengl`, `.vulkan`, or `.metal`
mutually exclusively. It requests window capability only: contexts, surfaces, and views are separate
resources. Unsupported native backends return `SdlFailure`; transparency and native graphics support
require actual platform testing. Typed popup/parent relationships are available; property-based creation remains pending.

Runtime `set_bordered`, `set_resizable`, and `set_always_on_top` forward native requests, including
unsupported-backend errors. `raise` requests focus/stacking subject to desktop policy. `maximize`,
`minimize`, and `restore` request window-manager actions; they can fail or complete asynchronously.
Maximization requires a resizable window. Fullscreen may defer the intended restored/minimized state
until exit. All operations require the main thread and may allocate/block. Use events or explicit
`sync()` then query state; a successful call does not override window-manager policy.

The dummy backend verifies creation flags, snapshot independence, graphics-backend rejection, and
runtime unsupported-operation failures without state mutation. It has no successful native runtime
border/resize/stacking or maximize/minimize/restore implementation. Those success paths and physical
window appearance/focus remain platform-validation work.


## Client-size and aspect constraints

`set_minimum_size` and `set_maximum_size` take `SizeLimits`, with independent optional width/height
in window coordinates. Null removes an axis limit; supplied values must be positive C ints.
Their getters return the stored limits, with native zero represented as null. A minimum exceeding
an existing maximum (or the reverse) produces `SdlFailure`. Change or remove conflicting existing
limits before applying a new interval; the two setters are separate native operations.

`set_aspect_limits` takes optional minimum/maximum width-to-height ratios. Values must be finite
and positive; a present minimum cannot exceed a present maximum. Equal endpoints request a fixed
ratio. `.{}` removes both limits. `aspect_limits()` returns the stored request, not the current
window's ratio. Invalid wrapper inputs return `InvalidConstraint` without calling SDL. Size limits
can take precedence over aspect constraints when both cannot be satisfied.

SDL may store constraints before a subsequent resize fails, so native `SdlFailure` does not promise
rollback. Requery stored constraints on failure. All operations require the main thread and initialized
video. Setters may allocate/block or produce asynchronous resizing; maximized/fullscreen enforcement
and actual dimensions remain subject to the backend and desktop policy. Dummy tests establish stored
state, per-axis removal, input validation, and native conflicting-limit rejection. They do not establish
window-manager enforcement or native failure-after-mutation behavior.


## Safe areas, density, and presentation requests

`safe_area()` returns a copied client-coordinate rectangle for important/interactable content.
Background rendering can continue outside it. Requery after size/safe-area changes. `pixel_density()`
reports drawable pixels per window-coordinate unit; it differs from recommended UI `display_scale()`.
`border_sizes()` reports native decoration extents and preserves query failure: unsupported or
not-yet-decorated windows return `SdlFailure`, rather than pretending to have zero borders.

Window `set_opacity()` takes a finite 0..1 value (zero transparent, one opaque); other inputs return
`InvalidOpacity` before native calls. The wrapper rejects rather than silently clamps out-of-range
values. Whole-window opacity is separate from per-pixel framebuffer alpha and surface blit opacity.
`opacity()` returning one does not prove support: SDL also returns one on unsupported platforms.
`set_focusable()` changes eligibility, not focus itself. A backend can accept it without changing
flags; requery `.not_focusable`. Native rejection can also leave changed flags.

`set_icon(surface)` borrows a live unlocked source only for the call and retains no source ownership.
SDL allocates a converted copy. The caller can release the source afterward, even on failure.
SDL can replace/discard its previous icon before returning `SdlFailure`; no rollback is promised.
`request_attention(.briefly/.until_focused/.cancel)` forwards native attention policy without
promising focus, appearance, or duration. All operations require the main thread and initialized
video; native mutations may allocate/block.

Dummy-driver tests cover safe-area resizing, unit density, opaque fallback, invalid opacity,
unsupported border/opacity/icon/attention operations, and focus requests accepted without change.
The source surface remains usable and is released before the window's converted icon. Physical
safe-area insets, decoration sizes, opacity effects, focus changes, icon appearance, and native
notifications remain platform-validation work.


## Window discovery and taskbar progress

`video.list_windows()` owns an allocated pointer array, not its windows. Defer snapshot `deinit()`;
use checked `get(index)` only while the corresponding window owner is still alive. The array retains
its recorded count even if windows disappear; cleanup remains safe without dereferencing entries.
For IDs kept across possible destruction, `WindowId.resolve()` returns an optional borrowed view:
null means no matching window. Neither discovery method retains windows. `WindowRef.parent()` is
also borrowed; reparenting/destruction invalidates assumptions about cached relationships.

`set_progress_state` selects `.none`, `.indeterminate`, `.normal`, `.paused`, or `.failed`.
The last is an error-style taskbar indicator, not an API failure. Unknown query states are retained;
native invalid-state results become `SdlFailure`. `set_progress_value` independently sets a finite
0..1 completion fraction; invalid inputs return `InvalidProgress` without native mutation. Hiding
with `.none` does not reset the fraction. Setters may store new state before backend rejection, so
native failure does not promise rollback. Querying stored state does not prove visible presentation.

Discovery and progress calls require the main thread and initialized video. Enumeration allocates
native storage; progress updates may allocate/block. Dummy tests cover empty/multi-window lists,
stale IDs, independent array cleanup, all progress states, value endpoints, and rejected input.
Real taskbar indicators, backend failure-after-mutation, and desktop parented-window behavior
still require platform tests.


## Parented windows and popups

`Window.init_popup(parent, options)` creates an owned tooltip or menu popup with parent-relative
signed offsets. Size validation and reserved-position rejection run before creation. The options
expose relevant common graphics/visibility/focus settings without incompatible modal/utility flags.
Native support is required; dummy video returns `SdlFailure`. Popup size/position may be constrained
by desktop bounds. General property-based popup policy and Emscripten fill-document flags remain
outside this creation API.

Every parented owner must be explicitly destroyed before its parent. Register child `defer deinit()`
after parent cleanup so it executes first. SDL destroys/hides native descendants recursively with
their parent; destroying the parent early leaves child Zig owners invalid and makes later cleanup
unsafe. Borrowed parent views do not retain owners. This obligation also applies after reparenting.

`set_parent(optional_parent)` handles regular windows; null detaches. The wrapper rejects self,
sibling, and descendant relationships before SDL can encounter undefined hierarchy behavior.
Ancestor validation is bounded to 256 links; deeper requests return `HierarchyTooDeep` without
mutation. `InvalidParent` indicates an unsafe link. Popups cannot be reparented or parent top-level
windows. `set_modal(true)` requires a current parent; clear modal status before reparenting.
Calls require the main thread and initialized video and may allocate/block. Backend reparenting
failure can detach the old parent, and modal failure can leave updated flags. Requery on failure.

Tests create regular-window hierarchy fixtures through native creation properties, which dummy
SDL supports, and verify invalid links, traversal bounds, and cleanup order. This does not establish
successful runtime reparenting, modal interaction, popup focus, or popup desktop behavior.


## Software window surfaces

`WindowRef.surface()` creates or borrows SDL's optimal-format window surface. Use this workflow
without a renderer/3D API on the same window. The window owns the buffer; do not create a Surface
owner from it or free it separately. General surface operations such as fill, pixel access, and
blits work without assuming RGBA32. All use of this window-owned view requires the main thread,
including otherwise thread-independent SurfaceRef methods.

`present_surface()` presents the full buffer. Finish pixel locks first and retain no raw pixel
pointers/rows across presentation. Resize invalidates borrowed surfaces; reacquire with `surface()`
before drawing/presenting again. `has_surface()` reports existence, not freshness. Calling present
with no valid surface returns `SdlFailure`. Presentation may allocate/block and does not guarantee
physical visibility. Partial-region presentation remains pending.

`release_surface()` explicitly frees the window's surface/framebuffer while leaving the window alive.
Finish all surface/property/pixel views first. Calling it with no surface is valid, and a later
`surface()` can create a new buffer. Window destruction also cleans up the final surface.
`set_surface_vsync` takes `.disabled`, `.adaptive`, or `.{ .interval = N }` for positive refresh
intervals fitting C int. Invalid intervals return `InvalidVSync`; unsupported modes/query backends
return `SdlFailure`. No requested interval guarantees a frame rate.

Dummy tests verify fills/readback, presentation calls, resize invalidation/reacquisition, release,
recreation, and native cleanup. Dummy VSync is unsupported; actual display refresh, adaptive timing,
framebuffer acceleration, and platform presentation behavior remain unverified.


## Window input policy

`set_mouse_grab` requests confinement to the window; `set_keyboard_grab` requests capture of system
shortcuts for specialized VM/remote-desktop workflows. OS-reserved shortcuts may remain unavailable.
Both require focus for active grabs, and hidden-window requests can remain pending until shown.
`mouse_grabbed()` and `keyboard_grabbed()` report SDL's active grab, not merely the request flag.
`video.grabbed_window()` returns a borrowed active-grab window or null. Enabling grabs can displace
another window's grab; popup restrictions and native failure are forwarded.

`set_mouse_confinement(optional_client_area)` defines a mouse-focus barrier without enabling a grab;
null removes it. Positive extents must fit C int and signed end coordinates must not overflow.
Invalid requests return `InvalidRegion` before native calls. `mouse_confinement()` copies the stored
rectangle, returning null when absent/empty. Backend clipping/enforcement is separate. A native
setter failure may leave the requested rectangle stored; no rollback is promised.

`set_relative_mouse_mode(true)` requests hidden/constrained cursor behavior and continuous relative
motion while focused. Toggling flushes pending motion and disables warp-emulation fallback.
`relative_mouse_mode()` reports enablement, which can remain true while unfocused; it does not prove
physical mode activation. These calls all require the main thread and initialized video. Setters
may allocate/block; borrowed lookup results never retain windows.

Dummy tests cover pending hidden grabs, active-grab absence, relative-mode state toggles, confinement
input validation, and unsupported barrier calls. Actual focus transitions, physical cursor barriers,
system shortcut capture, motion delivery/flushing, and supported rectangle round trips remain pending.


## Typed surface creation and conversion

`Surface.init_format(size, format)` allocates zero-initialized native storage using a typed pixel
identity. Dimensions must be positive C ints. Unknown/unsupported formats and native allocation
failures return `SdlFailure` without an owner. Format identity does not promise every pixel operation
supports that surface. Pitch, planes, and palette availability follow SDL; zero-filled YUV or indexed
storage does not necessarily mean transparent black. `init_rgba` remains a byte-order convenience.

`SurfaceRef.to_format(format)` allocates independent main pixels in the requested native-supported
format. The source stays owned by its caller and can be modified or destroyed independently afterward.
Unsupported conversion pairs or missing palettes can fail even for known format identities.
Finish source locks before conversion and follow source-owner thread restrictions. Row padding,
colorspace handling, precision/alpha loss, palette/color-key/modulation state, and alternate-image
sharing follow SDL. `to_rgba` remains the RGBA32 convenience; explicit color-profile conversion,
explicit conversion palettes and general-format row locks remain pending.
See [pixel palettes](pixels.md#indexed-palettes) for owned/shared indexed-surface palettes.

Tests verify zero-filled RGB24, RGB565/RGBA conversion, source/destination independence, and source
usability after a rejected conversion. Native-supported pairs remain runtime-dependent; these tests
do not establish every format pair or allocation-failure path.


## Transparent keys and run-length acceleration

`SurfaceRef.set_color_key(color)` selects an RGB color to skip during source blits; null disables
keying. Alpha is ignored by the mapping, and native quantization or palette matching can make
multiple RGB inputs share one key. `set_color_key_pixel(?u32)` supports exact encoded values,
including palette indices. `color_key_pixel()` returns null when disabled without generating a
native missing-key error. Palette edits change the displayed color of an indexed key; the key
remains the same index. Blend/alpha interactions follow the selected native blitter.

RGB convenience mapping rejects FourCC, floating-point, storage wider than 32 bits, and indexed
surfaces without palettes. Exact keys remain available for native interop. Neither setter changes
stored pixels. Invalid palette indices fail without replacing the previous key.

`set_rle(bool)` requests native run-length acceleration; `rle()` queries the request, not whether
pixels are currently compressed. Native encoding/decoding and allocation may occur lazily. There
is no speed guarantee. Use `lock_rgba()` for direct RGBA access and finish the lock before changing
blit state or blitting. Synchronize surface access and obey owner thread restrictions, including
the main thread for window surfaces.


## Surface reflections and scaled copies

`SurfaceRef.flip(.horizontal/.vertical/.both)` changes pixels in place. Both axes are a half turn,
not a transpose. The wrapper locks/unlocks native storage to support RLE and rejects existing locks.
FourCC layouts are rejected because native row reversal does not handle their plane layouts.
Sub-byte horizontal reflection may fail in SDL; a combined-axis failure may still modify pixels.
Clipping, tint, opacity, and blending do not constrain the reflection.

`scaled(size, mode)` returns a new owner with independent pixels. Defer `deinit`. Positive dimensions
must fit native integers. SDL bypasses source tint/opacity/blend state while scaling and restores it;
the source must be exclusively accessed and unlocked. Indexed input uses nearest sampling even
when linear is requested. Palettes can remain shared; a new pixel buffer is not a deep copy of every
associated native resource. Format support, color conversion, allocation, and rounding remain native.
Window-owned source operations require the main thread and a view valid for the current window size.

`rotated(degrees)` returns an owned clockwise rotated copy; negative angles rotate counter-clockwise.
It preserves the caller's angle without normalization. Nonfinite angles and angles whose quotient
by 90 cannot fit a native signed integer are rejected. The current audited geometry requires positive
dimensions/pitch, width+height at most 8192, and source pitch*height fitting a signed native integer.
These conservative limits protect native 16.16 coordinate and integer row calculations; larger
rotations remain partial coverage until audited. Existing locks are rejected.

Output dimensions use SDL's pixel-center bounds; a non-right-angle rotation does not invariably
enlarge a thin image. Native interpolation, padding, conversion, blend/key state, palette sharing,
and rotation-property adjustment are preserved without promising deep metadata copying. The pinned
implementation has format-dependent state behavior; consumers should explicitly set output blit
state when they require a particular mode. No allocation-free guarantee applies.


## Floating-point surface colors

`pixels.FloatColor` (also `surface.FloatColor`) carries RGBA floats with opaque default alpha.
It does not imply a colorspace. `read_pixel_float(point)` copies a pixel; `write_pixel_float(point,
color)` replaces one pixel, ignoring clip and blend state. Both check coordinates first. Writes
reject NaN/infinity before mutation but pass finite HDR and negative components to SDL unchanged.
The destination may clamp, quantize, or discard alpha. Reads can return nonfinite native values.

`clear(color)` replaces the whole image while ignoring and restoring its clip rectangle. It requires
an unlocked surface and rejects nonfinite input. RGB is interpreted in the surface's colorspace;
for YUV it is sRGB. This differs from the clipped, eight-bit `fill` operation. Native allocation or
conversion can fail, with no guarantee that pixels remain unchanged after native failure.

These APIs preserve RGBA128_FLOAT values, but the pinned native implementation uses eight-bit
intermediates for small integer formats, including packed high-bit formats. Float pixel reads of
YUV can convert the entire image; float YUV pixel writes are unsupported. Other wide formats may
undergo colorspace conversion, so floating-point input/output is not a universal promise of exact
component identity. These per-pixel methods suit inspection/tests, not rendering loops. Synchronize
access and follow source ownership/thread rules, including main-thread access for window surfaces.


## Alpha premultiplication

`premultiply_alpha(.srgb/.linear_srgb)` modifies RGB in place while preserving alpha, subject to
native format conversion and quantization. The choice selects encoded sRGB or linear sRGB as the
working colorspace; SDL converts back to the surface's encoding afterward. Linear-light
multiplication can produce different encoded bytes from sRGB multiplication.

This operation ignores clipping and leaves blend mode, tint, and opacity unchanged. Repeating it
multiplies again. Set `.premultiplied_alpha` explicitly when the destination compositor expects
premultiplied input. The wrapper locks/unlocks storage for RLE and rejects an outstanding pixel lock.
Native conversion may allocate and native failure may leave partial writes. Access must be exclusive
and obey owner thread rules, including main-thread use for window surfaces.


## Alternate surface representations

`add_alternate(&owner)` retains another owned surface without consuming its owner. Its size,
format, and contents can differ; edits to one representation do not update others. The original
owner may deinitialize after successful attachment. Duplicate attachments retain duplicate native
references. `remove_alternates()` releases all direct alternate references, destroying surfaces
whose last reference is released. The base image remains usable.

`images()` allocates an owned pointer-list snapshot, with the base at index zero. Defer list cleanup.
The entries returned by `get(index)` are borrowed, not retained. Finish using them before graph
mutation or surface destruction; keeping the list allocation does not keep its entries alive.
`has_alternates()` checks whether direct alternatives exist without allocation.

Attachment traverses the candidate graph before mutation and rejects a path back to the destination.
Traversal allows at most 256 pending nodes and 4096 visits (shared nodes may be visited repeatedly).
Exceeding these bounds returns `AlternateGraphTooLarge`; enumeration/native append failures return
`SdlFailure`. No attachment occurs on failure. Entire reachable graphs require exclusive access
through validation and attachment, with all owner thread restrictions respected. Existing raw-interop
cycles are outside the ownership contract and may exhaust the traversal budget. Large-graph support
remains partial coverage; no graph-deep-copy or allocation-free guarantee applies.


## Repeated surface tiles

`blit_tiled_to(destination, &options)` repeats source pixels, cropping the rightmost/bottommost tiles
to fill the target. Optional signed source/destination rectangles are intersected with their surface
bounds; null selects the whole surface. Empty intersections are no-ops. Source blend/modulation/key
state applies, and the destination's clip limits writes. SDL restarts the pattern at the clipped
destination origin; offscreen positions do not preserve an earlier tile phase.

Both surfaces require exclusive unlocked access, must have distinct handles, and must not alias
backing pixels through raw interop. Native failure can leave partial output. Window-owned surfaces
retain their main-thread/lifetime requirements. Nine-grid drawing is described below.


`blit_tiled_scaled_to(destination, &options)` adds explicit scale and sampling. Nonfinite/negative
scales and rounded tile sizes that cannot fit native integers fail before writing. Zero scale or a
rounded zero tile dimension is a no-op. SDL rounds tile dimensions but truncates the source span
for a partial edge tile. When that maps a nonempty edge to zero or excessive source pixels, the
wrapper draws complete scaled tiles through the effective destination clip. The original clip is
restored on success or native failure. RLE-requested sources use a temporary uncompressed copy
so native clipped scaling does not offset compressed storage. This fallback may allocate native surfaces;
its edge pixels come from cropping a full tile rather than stretching a truncated source strip.
Fallback tile endpoints are checked before any writes. Native errors after validation can still
leave partial output; source state, clipping phase, threading, and alias rules match tiling.
Nonfinite/overflowing native arithmetic remains outside the wrapper contract.


## Nine-grid surface drawing

`blit_nine_grid_to(destination, &options)` divides a contained source region into three rows and
columns. Border sizes are source pixels; corners use the requested corner scale, edges stretch in
one direction, and the center stretches in both. Zero corner scale means unscaled, matching SDL.
Destination clipping limits writes without shifting the grid geometry. Source blend/modulation/key
state applies; RLE-requested sources use an isolated uncompressed copy for native clipped scaling.

Opposite source borders must fit, and rounded scaled borders must fit the destination. Empty source
bands cannot be stretched into nonempty destination bands. Invalid geometry, nonfinite/negative
scale, aliased handles, and locked surfaces fail before writing. Native failures after validation
may leave partial output. Both regions must be contained; offscreen destination grids and overlapping
borders remain partial coverage. Native allocation and owner thread restrictions still apply.


## Renderer discovery and software destinations

`render.driver_count()` and `driver_name(index)` enumerate compiled-in backend identifiers in SDL's
preference order. Names are static borrowed ASCII strings and can be passed to renderer creation.
Enumeration needs no initialization and does not prove a backend will initialize on the current
machine. The list can be empty. Out-of-range indices fail before native calls.

`RendererRef.name()` reports the actual selected backend. `render.for_window(window)` and
`RendererRef.window()` return borrowed associations; neither creates nor retains an owner. Missing
associations return `SdlFailure`, including window lookup on a surface-backed software renderer.
`output_size()` gives physical pixels, ignoring texture targets/logical presentation;
`current_output_size()` reports the mapped presentation extent in pixels in the pinned implementation.
This differs from logical drawing dimensions; use `presentation().size` for logical resolution.
Both pixel-size queries preserve zero dimensions.

`Renderer.for_surface(surface)` creates a software renderer borrowing CPU storage without a window
or video subsystem. Destroy textures first, then the renderer, then its backing surface. Keep the
surface layout stable and synchronize renderer operations with direct pixel access. Follow the
wrapper's main-thread renderer contract even though some native software operations permit other
threads. Window surfaces have additional resize invalidation, so an ordinary owned surface is the
recommended durable backing resource. Native renderer creation may allocate/fail.


## Renderer drawing color and blending

`set_color`/`color` use byte RGBA; `set_color_float`/`color_float` preserve floating-point state.
Finite HDR and negative components can be stored, but target/backend conversion may clamp or
quantize during rendering. Float setters reject NaN/infinity before changing state. The byte getter
explicitly clamps finite components to 0..1 and truncates component*255; it rejects raw-installed
NaN/infinity. This avoids the pinned native byte getter's unchecked out-of-range float casts. A draw color does not select a colorspace or guarantee HDR display output.

`set_blend_mode` selects primitive compositing, independently of texture blend state. Alpha in a
color alone does not enable blending. Unsupported requests can fall back or fail; query
`blend_mode()` when the actual selection matters. Premultiplied modes require premultiplied colors.
Clear ignores blend mode; drawing operations apply it. All operations follow the main-thread
renderer contract, and native failures do not promise untouched state/output.


## Logical renderer presentation

`set_presentation(.{ .size = ..., .mode = ... })` enables a logical drawing resolution; null disables
it. Modes are stretch, letterbox, overscan, and integer scale. Enabled dimensions must be positive
native integers. Queries preserve unknown native modes. Presentation belongs to the current target;
it does not configure viewport state or convert event coordinates.

`presentation()` copies the logical dimensions and mode. `presentation_rect()` reports where content
maps in physical output coordinates, including letterbox placement or overscan extents. For example,
a 4x2 logical image letterboxed into 8x6 output occupies x=0, y=1, width=8, height=4. The physical
output stays 8x6, while current_output_size is 8x4 and the logical resolution is 4x2. All operations require the main
thread; native setter failure need not leave state unchanged. Texture-target switching and event
coordinate conversion remain separate roadmap work.


## Window and drawing coordinate conversion

`from_window_point(point)` and `to_window_point(point)` convert finite floating positions using
DPI, logical presentation, viewport, and scale. They use the renderer's main-window state even when
a texture target is active. For a 32x32 window letterboxing 16x8 logical content, window position
(8,12) maps to drawing position (4,2). Points in letterbox bars can become negative; these methods
perform no clamping or hit testing. Use window-coordinate input, not physical framebuffer pixels.

Nonfinite input/output returns `InvalidCoordinate`; degenerate native state can cause invalid
results even from finite input. Round trips can lose floating precision. Calls require the main
thread and a live renderer/window association. They neither mutate events nor retain resources.
Event-wide coordinate conversion and typed viewport/scale controls remain separate roadmap work.


## Renderer synchronization and flushing

`set_vsync(.disabled/.adaptive/.every_refresh)` requests presentation timing. `VSync.interval(n)`
constructs a positive refresh-cycle interval; zero is rejected in favor of explicit `.disabled`.
Not every backend supports every request, and SDL can simulate one-refresh synchronization with
software delays. Surface-backed software renderers support disabling it but reject enabling it.
A failed native request can change internal state; `vsync()` reports stored metadata, not measured
timing or every failed-set side effect. Future integer values remain representable in queries.

`flush()` submits queued SDL commands before native graphics interop. It neither presents nor
waits for GPU completion and is normally unnecessary for SDL-only drawing. Native API users must
still obey backend context/state/lifetime rules. Both controls require the main thread and can
perform native work; there is no allocation-free or untouched-state-on-failure guarantee.

## Texture tint, opacity, and blending

Texture views provide `set_tint`/`tint`, `set_opacity`/`opacity`, and independent
`set_blend_mode`/`blend_mode`. RGB tint and alpha opacity multiply source components during texture
copies without changing stored pixels. White tint and opacity 255 reset modulation. Opacity alone
does not enable blending: select `.alpha` when compositing translucent copies. Renderer drawing
color/blend state does not control texture copies. Native geometry uses vertex colors instead of
texture tint/opacity. Premultiplied blend modes require premultiplied source pixels.

Float variants retain finite HDR/negative values, with actual output depending on the backend.
Byte queries clamp to 0..1 and round to the nearest byte: 0.5 becomes 128. This differs from the
renderer drawing-color byte query, which truncates. Float setters reject nonfinite input before
mutation; byte getters reject raw-installed nonfinite state instead of casting it to integers.
Float getters preserve native state verbatim. All operations require the main thread and live
texture/renderer owners. Native failures need not preserve state; wrappers allocate no storage.

## Texture sampling and dimensions

`TextureRef.size()` returns floating source-pixel dimensions, independent of destination scaling
or logical presentation. Preserve integer creation dimensions for byte-buffer sizing: native float
conversion can lose precision for large dimensions.

`set_scale_mode(.nearest/.linear/.pixel_art)` selects sampling for one texture. The getter reports
stored policy, not proof of backend filtering quality. `RendererRef.set_default_texture_scale_mode`
changes only the policy inherited by new textures; existing textures keep their own state. Both
setters reject invalid/unknown identities before mutation, while queries preserve future native
values. The default is linear. Surface CPU sampling uses its separate `surface.ScaleMode` type.
These operations require the main thread and live owners, and allocate no wrapper storage.

## General texture creation and RGBA updates

`Texture.init(renderer, options)` allocates storage with explicit size, format, and
`.static`, `.streaming`, or `.target` access. Backend support determines valid combinations.
Storage starts undefined: initialize it before sampling. Access selection does not itself lock
pixels or switch the renderer's destination. The renderer must outlive the texture.

`pixel_size()` reads exact integer dimensions; `format()` reads the public upload format, which
can differ from internal GPU storage. `update_rgba(region, bytes)` updates RGBA32 textures from
exactly sized, tightly packed RGBA rows. Null selects the whole texture; a contained integer region
updates only that rectangle. Bounds checks use subtraction to avoid overflow. Empty regions require
empty input and perform no upload. Unsupported formats, invalid lengths, and out-of-bounds regions
fail before mutation. Native failures can leave partial updates; native work can allocate/block.

Finish locks and deselect texture render targets before uploading. Streaming uploads are available,
but later write-only locks do not preserve uploaded pixels. Planar/compressed updates, fractional
source crops, and other-format locks remain roadmap work.

## Streaming locks, render targets, and source regions

`TextureRef.lock_rgba(region)` returns a `TextureRgbaLock` for nonempty contained RGBA32 streaming
storage. Use a block with `defer pixels.deinit()`, then write `try pixels.row(y)`. Rows are relative
to the selected region and omit pitch padding. Unlike a surface pixel lock, this texture operation
**discards prior contents**. The wrapper initializes visible bytes to transparent black before
returning, so unwritten bytes and error-path releases remain initialized. That initialization is
linear in the region size. Other pixels are unaffected. There is no Zig allocation; native locks
and unlocks may allocate or block. SDL's void unlock cannot report whether an upload succeeded.

Only one exclusive use of a texture may exist while locked. Do not copy the guard, nest locks,
draw/upload/destroy the texture, or retain row slices after release. SDL has no portable lock-state
query, so alias exclusion is a caller responsibility. Wrong format, empty/out-of-bounds region,
non-streaming access, and malformed native layout produce errors with no live guard returned.

`RendererRef.set_target(texture.borrow())` directs drawing into a target-access texture;
`set_target(null)` restores the original window or software surface. `target()` borrows the current
texture or returns null for the original destination. Target changes can flush commands, allocate,
and fail after changing native state. Recovery must not assume rollback. No target reference is
retained: keep owners alive and explicitly switch away before sampling or destroying a target.
Viewport, clipping, scale, and logical presentation remain separate persistent state per target.
Drawing color/blending is renderer state, not saved/restored by this target API.

`draw_texture_region(texture, source, destination)` maps a contained integer source-pixel region
onto a floating destination in current renderer coordinates. Null source means the whole texture;
null destination fills the current viewport. Empty sources do nothing. Source bounds are checked
without implicit clipping. Fractional/clipped native source rectangles remain unwrapped. Both
whole-texture and region drawing reject different renderer owners and sampling the active target.
Uploads and locks also reject the active target. Native drawing and errors may still change pixels.

## Padded uploads and shared texture palettes

`update_pixels(region, .{ .bytes = data, .pitch = row_stride })` accepts byte-addressable native
texture formats, including RGB24/RGB565, RGBA arrays, and index8. The bytes must already use the
texture's public format; this API does not reinterpret them as RGBA. Pitch must fit a positive C
integer and cover each visible row. The slice must reach the last row's visible bytes; final-row
padding is optional and extra trailing bytes are ignored. Planar/FourCC/compressed and sub-byte
indexed formats are explicitly rejected. All bounds, pitch, and slice checks precede native upload.

`set_palette(palette.borrow())` retains a shared native palette reference for indexed textures.
After success, releasing the caller's Palette owner is safe. `palette()` returns a borrowed view
that expires when the association changes or dies; `set_palette(null)` removes it. Shared edits
affect subsequent texture draws. Use the main thread and coordinate with every sharing texture or
surface. Native failures can change associations, and allocation/backend failure is not atomic.
