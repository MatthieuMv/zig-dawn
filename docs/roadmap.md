# Work plan

Work in reviewable vertical slices. For each slice: read pinned headers and contracts, record
ownership and failure rules, implement, compile public uses, exercise success/failure paths,
reconcile coverage, and update validation. Never mark a phase complete from scaffolding alone.
Documentation is part of completion: each public API needs a consumer-facing Zig contract;
examples compile, mapped operations reference checked documentation sources, and limitations stay
explicit. See `documentation.md` for the automated gate and required semantic review.

## Phase 0: foundation (in progress)

- [x] Verify Zig 0.17.0 and discover installed native versions.
- [x] Record accepted architecture and Tiger Style exceptions.
- [x] Introduce optional public modules and shared ABI translation.
- [x] Implement reference-counted subsystem ownership and diagnostic copying.
- [x] Bootstrap translated-symbol inventory with pending dispositions.
- [x] Pin upstream source releases, archive hashes, and top-level license notices.
- [ ] Pin codec/font dependency configurations and their license closure for source builds.
- [x] Enforce baseline header versions and strict linkage selection in ordinary builds.
- [x] Exercise missing-package, missing-external-library, old-header and wrong-major diagnostics.
- [ ] Implement cached source provider and hermetic external target installations.
- [x] Extract independent Linux declarations/macros; hash and scan all shipped headers/branches.
- [ ] Compile remaining platform branches and classify candidate/private/test/GL declarations.
- [ ] Enforce explicit inventory dispositions and drift checks in CI.
- [x] Test downstream package consumption and cross-module resource type identity.
- [x] Document the current public Zig surface, generate reference pages, and execute hover examples.
- [x] Require declaration/field documentation and documentation paths in mapped coverage entries.

## Phase 1: graphics foundation

Properties, application entry points, windows/displays, surfaces, renderer, textures, events.
Completion: bounded event-loop example drawing a texture; lifecycle and error-path tests.

- [x] First window/renderer/static RGBA texture ownership slice with borrowed views.
- [x] Typed quit/window/keyboard events with raw fallback and future numeric values retained.
- [x] Bounded desktop example and headless drawing verified by pixel readback.
- [x] CPU surface owners, dimension views, and static texture upload from surfaces.
- [x] Typed property owners/views, scalar/string/pointer values, and scoped recursive locks.
- [x] Property merging, copied-name snapshots, and borrowed global/core-object property access.
- [x] Checked surface pixels, whole clipped fills, duplication, and RGBA conversion.
- [x] Whole-source unscaled/scaled blits and typed source blend modes.
- [x] Contained source regions, signed positioned blits, and contained scaled region blits.
- [x] Typed surface clip state and checked signed rectangle fills.
- [x] Scoped RGBA pixel locks with checked row slices and explicit padding/lifetime contracts.
- [x] Typed RGB tint and alpha opacity controls for surface blits.
- [x] Typed property cleanup ownership and enumeration visitor adapters.
- [x] Owned display ID snapshots, desktop bounds, orientation, scale, and window display queries.
- [x] Window title, typed placement, client resize, visibility, and explicit synchronization.
- [x] Display mode snapshots/search and explicit desktop/exclusive fullscreen selection APIs.
- [x] Complete named window-state bits, native graphics creation selection, and window-manager requests.
- [x] Optional per-axis client-size limits and validated aspect-ratio intervals.
- [x] Safe-area/density/decoration queries, opacity/focus controls, icon copying, and attention requests.
- [x] Borrowed window discovery/ID resolution and independent typed taskbar progress state/value.
- [x] Common popup creation, bounded hierarchy validation, and explicit child-first ownership contracts.
- [x] Borrowed software window surfaces, presentation/release, resize invalidation, and VSync requests.
- [x] Window grab/relative-mode requests, active-grab queries, and validated mouse confinement.
- [x] All pinned pixel-format identities/byte aliases, classification, integer masks, and copied details.
- [x] Typed general surface allocation and direct format conversion for native-supported pairs.
- [x] Owned/shared indexed palettes, checked color updates, and borrowed surface palette access.
- [x] Optional RGB/exact indexed color keys and native RLE acceleration controls.
- [x] Locked in-place reflections and independently owned positive-size scaled surfaces.
- [x] Owned clockwise/counter-clockwise rotation with audited native arithmetic bounds.
- [x] Floating RGBA pixel access and whole-surface clears with documented conversion behavior.
- [x] Explicit sRGB/linear-sRGB surface alpha premultiplication with locked storage access.
- [x] Named colorspaces, metadata relabeling, and explicit format/colorspace/palette conversion.
- [x] Typed colorspace components, lossless identity construction, and native classification predicates.
- [x] Retained alternate images, owned pointer snapshots, removal, and bounded cycle prevention.
- [x] Repeated surface tiles with signed clipped regions and documented tile-phase behavior.
- [x] Scaled tiled blits with explicit sampling and prevalidated native rounding/edge arithmetic.
- [x] Nine-grid surfaces with typed borders, corner scale, and prevalidated contained geometry.
- [x] Renderer backend discovery, borrowed associations, output-size queries, and software surface owners.
- [x] Renderer byte/float drawing-color queries and explicit primitive blend state.
- [x] Typed logical presentation modes, positive resolution configuration, and mapping queries.
- [x] Finite main-window/drawing coordinate conversion with DPI/presentation semantics.
- [x] Typed renderer VSync intervals/queries and explicit native-interop command flushing.
- [x] Texture byte/float tint and opacity, safe rounded queries, and independent blend state.
- [x] Texture dimensions, sampling policies, and renderer defaults for newly created textures.
- [x] General texture format/access allocation, exact metadata, and checked contained RGBA updates.
- [x] Scoped initialized RGBA streaming locks with checked rows and explicit alias lifetimes.
- [x] Borrowed render-target selection/query and rejection of active-target feedback/uploads.
- [x] Contained source-region texture drawing with tested per-target presentation persistence.
- [x] Checked padded byte-addressable uploads and retained shared indexed texture palettes.
- [ ] Complete display/window options, general surface formats/events.
- [ ] Implement portable application entry-point adapters and real desktop/GPU/DPI validation.

## Phase 2: extension vertical slices

Image loading/saving, font/text rendering, mixer playback. Completion: example combining all
four modules, with explicit lifetimes and native resources cleaned up on failures.

- [x] File/memory image loading into owned surfaces, with documented lifetimes and headless tests.
- [x] Borrowed-stream image loading and PNG file/stream saving with round-trip tests.
- [x] Font/context owners, borrowed-stream fonts, UTF-8 measurement and text surface rendering.
- [x] Mixer/context/audio/track owners, default-device playback, and offline float mixing.
- [x] Typed finite/infinite mixer loop options backed by temporary native properties.
- [x] Bounded all-four-module example with dummy audio/video execution.
- [ ] Other image encoders, hinted formats/animation, advanced text APIs, mixer controls/callbacks.

## Phase 3: remaining services and devices

Input, devices, audio, streams, filesystem, storage, process and platform integration.

- [x] File/fixed-memory stream ownership, borrowed cursors, seeking, and fallible close.
- [x] Stream byte transfers with preserved partial progress, status, size queries, and flushing.
- [x] Bounded full-transfer helpers and signed/unsigned integer wire encoding.
- [x] Dynamic memory stream ownership, borrowed initialized bytes, and detached SDL buffer owners.
- [x] Typed borrowed-backend stream callbacks, diagnostics, and close/error adapters.

## Phase 4: advanced APIs

GPU lifecycle types, asynchronous I/O, callback adapters, threading, complete extension APIs.

## Phase 5: release readiness

Platform entry points and runtime matrix; system/source CI; consumer documentation;
all pinned public symbols accounted for with zero pending items and explicit exceptions.
