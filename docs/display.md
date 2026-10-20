# Display discovery

`sdl.display.list()` returns an owned `Displays` snapshot. Defer `deinit()` exactly once;
its `items` slice expires on cleanup. SDL allocates the array; the wrapper adds no allocation.
IDs do not own monitors. Hotplug can invalidate an ID even while its snapshot remains alive.
All display and window display queries require initialized video and the main thread.

`primary()` selects the primary display. `for_point()` delegates desktop-point selection to SDL.
`DisplayId` exposes borrowed UTF-8 `name()`, signed-origin `bounds()` and `usable_bounds()`,
`content_scale()`, natural/current orientation, and borrowed `properties()`. Bounds have unsigned
extents; negative desktop coordinates are valid. Names and property views expire when their display
is removed or video shuts down. Copy names before retaining them across such changes. Do not destroy
borrowed property groups. An unavailable orientation returns `.unknown`; other failed queries
return `SdlFailure`, with SDL diagnostics available through `sdl.errors`.

`WindowRef.display()` identifies the window's current display. `display_scale()` reports the
window's effective content scale. It can differ from the display base scale and the ratio of window
pixels to window coordinates. Requery after display/scale changes; cached values are snapshots.

Dummy-driver tests cover discovery, bounds, properties, invalid IDs, and window association.
Physical hotplug, multiple monitors, desktop work areas, and mixed-DPI transitions still require
platform testing. Exclusive fullscreen selection still requires a backend exposing real modes.


## Modes and fullscreen

`DisplayId.modes()` owns a native fullscreen-mode snapshot. Its `count` excludes the sentinel;
`get(index)` checks bounds and returns a copied `Mode`. Defer `deinit()` on the list once.
SDL orders modes by dimensions, pixel format, refresh, and density. An empty list is valid.
`desktop_mode()` describes the original desktop configuration during exclusive fullscreen;
`current_mode()` describes current scanout. `Mode.info()` copies dimensions, display ID, native
pixel-format number (retained for compatibility), density, approximate Hz, and the exact refresh fraction. Zero refresh means
unspecified; check the denominator before division. These scalar copies remain historical data
when a monitor disappears. `Mode.format()` returns the typed `sdl.pixels.Format` identity. Mode tokens retain native internal data: requery before application
after hotplug/configuration changes or video shutdown; never fabricate their internal pointers.

`closest_mode(.{ .size = ..., .refresh_rate = ..., .include_high_density = ... })` searches without
changing the display. Sizes must be positive C ints; Hz must be finite/nonnegative (zero means
desktop refresh). Invalid inputs return `InvalidModeRequest`; no match or native failure returns
`SdlFailure`. Native enumeration may allocate or block.

`WindowRef.set_fullscreen_mode(mode)` selects an exclusive mode; null selects borderless desktop
fullscreen. SDL copies the request, so the list/token need not remain alive afterward.
`fullscreen_mode()` returns a copied selection or null for desktop mode; SDL also returns null
for unsupported popup windows. `set_fullscreen(true/false)` requests entry/exit separately. Calls
require the main thread and initialized video. Transitions may be asynchronous; use events or
explicit `sync()` and requery actual state. The wrapper does not promise instant switching.

The Linux dummy driver exposes zero exclusive modes. Tests exercise empty lists, absent matches,
desktop/current data, invalid searches/IDs, and borderless entry/exit. Exclusive mode selection,
physical refresh changes, and mode-token invalidation across real hotplug remain unverified.
