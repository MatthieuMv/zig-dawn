# zig-sdl3

Idiomatic SDL3 bindings for **exactly Zig 0.17.0**. Early foundation, not a complete binding.

The default provider uses installed development headers and libraries through pkg-config.
SDL_image, SDL_mixer, and SDL_ttf are optional. No native libraries are downloaded or rebuilt.

```sh
zig build test
zig build test -Dimage=true -Dmixer=true -Dttf=true
zig build test -Dimage=true -Dmixer=true -Dttf=true -Doptimize=safe
zig build inventory -Dimage=true -Dmixer=true -Dttf=true
zig build run --build-file tests/consumer/build.zig -Dextensions=true
zig build test-graphics
zig build run-window
zig build test-multimedia -Dimage=true -Dmixer=true -Dttf=true
zig build test-docs
zig build docs -Dimage=true -Dmixer=true -Dttf=true
```

`zig build check` compiles tests without executing them. Inventory output is
`zig-out/coverage/symbols.tsv`; it is a bootstrap report, not proof of complete API coverage.

Indexed surfaces support owned/shared palettes with checked color updates; see
[pixel formats and palettes](docs/pixels.md).

Exports: `sdl`, and enabled `sdl_image`, `sdl_mixer`, `sdl_ttf` modules. All share one translated
ABI module. SDL_image provides owned surface loading from files, encoded bytes, or streams,
and PNG saving to files or borrowed streams. `sdl.io` owns file/fixed-memory streams with explicit
close, borrowed cursors, byte transfers, status, size, flushing, dynamic buffer owners, and typed custom backends; see [stream contracts](docs/io.md).
SDL_ttf provides initialization/font owners, UTF-8 measurement, and text surface rendering;
see [font contracts](docs/ttf.md). SDL_mixer provides default-device playback, offline float mixing,
and audio/track owners; see [mixer contracts and combined example](docs/mixer.md).
Core includes the initial `pixels`, `display`, `video`, `surface`, `render`, `io`, `properties`, and `events` APIs. See [graphics contracts and example](docs/graphics.md).
See [pixel-format contracts](docs/pixels.md) for endian aliases, classification, masks, and metadata.
See [display discovery](docs/display.md) for snapshots, desktop coordinates, and scale queries.
See [typed properties and mixer looping](docs/properties.md) for ownership, locking, copying, name snapshots, and borrowed object metadata.
Public Zig declarations include IDE-hover contracts. `zig build docs` generates reference pages
under `zig-out/docs`; `test-docs` runs the exact usage examples embedded in those comments.
See the [documentation contract](docs/documentation.md) for contribution and review requirements.

Provider options:

- `-Dsdl-provider=system` (default): pkg-config discovery; native targets only for now.
- `-Dsdl-provider=external -Dsdl-prefix=/installation`: absolute installation prefix, with explicit
  `include` headers and `lib/libSDL3*.so` (Linux) or `.dylib` (macOS) paths; `.a` for static linkage.
- `-Dsdl-provider=source`: reserved; fails explicitly until pinned source builds are implemented.
- `-Dsdl-linkage=dynamic|static`: native linkage with fallback disabled.

External installations must supply matching target headers and libraries. Static transitive
dependencies, SDK/framework layouts, runtime deployment, and cross-platform support remain pending.
Selected external libraries cannot fall back to host search paths. This is still not a hermetic
sysroot: transitive system headers and native runtime dependencies require separate configuration.

Minimum headers are SDL 3.4.18, image 3.4.8, mixer 3.2.4, ttf 3.2.2, all major 3. These are also
the pinned source/API baselines in [upstream.lock.tsv](upstream.lock.tsv). Header checks run during
ordinary builds, including downstream consumption. See [upstream audit](docs/upstream.md) for
offline reproduction, licensing, compatibility policy, and remaining platform/codec gaps.

On the development Linux host, `sh tests/dependencies.sh` verifies missing dependencies and rejected
header versions. Its fixtures use `/usr/include` and `/usr/lib`; it is not a portable CI matrix.

See [architecture](docs/architecture.md), [work plan](docs/roadmap.md), and
[validation](docs/validation.md) before contributing.
