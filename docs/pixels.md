# Pixel formats

`sdl.pixels.Format` names all 65 distinct pinned native format identities and retains unknown future
numeric values. Packed names such as `rgba8888` describe channel significance within native-endian
integers. Array formats describe component order. `Format.rgba32` and seven related `*32` constants
are aliases chosen for byte order in memory on the target; they are not distinct enum tags. Use
`Format.rgba32` explicitly when passing the alias. X channels are unused, not alpha. Float components
do not imply a particular colorspace or linear-light encoding.

`SurfaceRef.format()`, `WindowRef.pixel_format()`, and `display.Mode.format()` provide typed identities.
The window query can fail and does not create a surface. The existing numeric display-mode info
field remains available. Identity alone does not establish renderer/codec/platform support.

Classification predicates distinguish FourCC, indexed, packed, array, float, 2/10/10/10, and explicit
alpha layouts. Palette alpha and surface color keys are separate. FourCC P010 is not classified as
packed 10-bit. `bits_per_pixel()` returns the encoded bit count; `storage_bytes_per_pixel()` returns
SDL's storage hint. Sub-byte indices return zero bytes, and planar/compressed FourCC hints are not
complete image sizes. Never allocate a general image with width*height*bytes: pitch, planes, padding,
and compression need separate handling.

`details()` copies cached native metadata, so no native pointer or cleanup escapes. Native lookup
may allocate/cache and returns `SdlFailure` on rejection. It can also accept unknown/FourCC identities
with zero metadata. `masks()` copies the native bit-count/masks result, and `Masks.format()` returns
an optional canonical match. Metadata bit counts can differ from encoded counts: XRGB8888 encodes
24 bits but native mask/details queries report 32 storage bits. Zero metadata is not proof that a
format has usable CPU storage. `name()` borrows a static native name; unknown identities use SDL's
unknown label. `from_fourcc([4]u8)` constructs an identity without guaranteeing support/classification.
All these operations require no SDL subsystem initialization and may run on any thread.

Zig 0.17's translated nested classification macros contain invalid bool/integer comparisons.
The wrapper implements their pinned bit rules directly. An independent C-generated reference covers
all 73 named formats/aliases plus three custom/unknown inputs. Regenerate on the pinned development
host with:

```sh
python3 tools/coverage/pixel_macros.py > src/core/fixtures/pixel-formats.tsv
```

The script compiles the actual public C macros and rejects headers other than SDL 3.4.18. Zig tests
compare every reference row and separately verify packed masks, byte aliases using native integer
layout, unknown identities, zero metadata, and malformed-format failure. Typed surface allocation
and conversion use these identities. Raw-buffer conversion, colorspace components, row-layout computation,
and other-platform execution remain pending.

## Indexed palettes

`pixels.Palette.init(count)` owns a native reference with opaque-white entries. Defer `deinit`;
`borrow()` gives a view without retaining it. `PaletteRef.get(index)` copies a color, and
`set_colors(first, colors)` copies a complete checked range. Invalid ranges leave every entry
unchanged; empty input is valid through the end boundary. The shared `pixels.Color` (also exposed
by render/surface) has C-compatible RGBA field layout, checked against SDL at compile time.

`SurfaceRef.set_palette(view)` retains a reference on success, so the original palette owner can
be released. Reacquire a view with `surface.palette()` after releasing the original owner. Multiple
surfaces may share one palette; edits affect all of them. Synchronize reads and writes with every
sharing surface. Window-related operations retain their main-thread restriction.

`create_palette()` installs a compatible palette and returns a borrowed view owned by the surface.
One-bit palettes start white/black; other entries start opaque white. Never deinitialize this view.
Replacement, removal with `set_palette(null)`, or surface destruction ends that association's borrow.
Nonindexed surfaces reject attached palettes; oversized palettes fail without replacing the old one.
Smaller palettes are permitted by SDL. Indexed-to-RGBA conversion resolves the current colors into
independent pixels. General indexed row access remains pending. Explicit conversion palettes are supported below.


## Colorspace identities

`pixels.Colorspace` names every pinned encoding and the RGB/YUV default aliases, retaining future
or custom numeric values. A format describes component storage; a colorspace describes how those
components represent color. Neither identity alone proves conversion or output-device support.
`srgb` is the common nonlinear RGB encoding; `srgb_linear` is the floating-point default; `hdr10`
uses PQ transfer and BT.2020 primaries. Named YCbCr encodings distinguish limited/full range.
Transfer-function evaluation and explicit HDR property helpers remain pending.

`SurfaceRef.colorspace()` queries metadata. `set_colorspace()` relabels existing numbers without
converting them; even custom identities can be stored, so success is not validation. Use it only
when you know the original encoding. `converted(.{ .format = ..., .colorspace = ... })` instead
returns independently owned converted pixels. Optional destination palette and color properties
are borrowed through the call; the result can retain a shared palette reference. Copied pointer
properties and alternate images retain their native sharing/lifetime requirements. A new surface
is not necessarily a deep copy of all associated resources. Source and options require synchronized
exclusive access during conversion, and source pixel locks must be released first.


`Colorspace.components()` separates the component model, range, primaries, transfer, matrix, and
chroma siting into typed identities. Each enum accepts every value of its packed field width.
`from_components()` assembles those fields without native calls or allocations. The five reserved
bits are exposed separately and retained, so arbitrary 32-bit identities round-trip losslessly.
The field-width types prevent values from spilling into neighboring fields; the original C macro
accepts unchecked integers. Construction validates representation only, not color science or backend
support. Every pinned named component identity is exposed with hover documentation.

Matrix predicates match SDL's classification; BT.601 includes BT.470BG. The native-compatible
`is_limited_range()` means *not full*, so it returns true for unknown/custom ranges as well. To
require a known limited range, compare `components().range == .limited`. Tests compare component
extraction and predicates with translated native macros and preserve custom/reserved-bit identities.
