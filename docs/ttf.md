# Font and text surface slice

Enable `-Dttf=true`, then import `sdl_ttf`. Acquire a `Context` with `ttf.init()`, open a font
through `context.open_font(path, .{ .size_points = 24 })`, and use `font.borrow()` to measure
or render UTF-8. Video initialization is not required for CPU text rendering. This initial
wrapper uses the main thread for initialization, font operations, and shutdown.

`FontRef.measure(text)` returns pixel dimensions. `FontRef.render(text, color)` returns an
owned `sdl.surface.Surface`, which can be uploaded with `sdl.render.Texture.from_surface`.
The generated surface owns its pixels independently of the font/context; the uploaded texture
also survives destruction of the source surface. Rendering uses antialiased ARGB surfaces,
not guaranteed RGBA byte order. Point size is not an exact pixel-height request.

Text parameters are ordinary slices without sentinel requirements. Invalid UTF-8 and embedded
NUL bytes produce `InvalidText` before native calls. Empty text is valid for measurement (zero
width) and produces `EmptyText` for rendering. A zero-length slice is passed safely even when
its backing storage is not terminated. Single-line APIs do not wrap words or lay out newlines.
Native shaping, caches, and rasterization can allocate/block; no resource budget is imposed.

Close fonts before their context. Context initialization is reference-counted; each successful
`init` needs exactly one `deinit`. Owners must not be copied, and Zig does not enforce lifetimes.
`open_font_stream` borrows the stream and its backing storage until the font closes, because
font reads can be lazy. Keep that stream exclusively available to the font; unlike image
loading, it cannot be closed or reused immediately after opening. Failure leaves the stream
open but may change its cursor. Close font, then stream, then context.

The hover example on `Context.open_font` is compiled and run with a generated test font.
Its `example_assets` import is test-only: applications substitute their own font path.
Tests cover reference balancing, bad sizes/paths/fonts, malformed and nonterminated text,
stream borrowing, pixel dimensions/colors/alpha, surface independence, and software-renderer
readback after the font/context have been destroyed.

Font properties, style changes, fallback, wrapping, glyph metrics, persistent text/text engines,
font collections, owned stream transfer, complex shaping coverage, and font caching policies
remain pending. Passing these tests does not establish typography quality, all font formats,
complex-script correctness, GPU correctness, or cross-platform support.
