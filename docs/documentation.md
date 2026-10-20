# Consumer API documentation contract

The handwritten Zig API is the consumer's primary reference. Document behavior in `//!` module
comments and `///` declaration comments so IDE hovers and generated reference pages share the
same source. Native links are supplementary; a user should not need C API knowledge for normal
wrapped operations. The `raw` namespace is an explicitly documented interoperability exception.

## Completion criteria

Every public module, alias, function, type, named field, option, enum/union tag, and error set needs
documentation. Explain the purpose before implementation details. Review the following where relevant:

- A concrete use case and a short example for non-obvious resource or control-flow patterns.
- Ownership, borrowing, copying, transfer, invalidation, parent lifetime, and destruction order.
- Units, coordinate systems, encoding, sentinel requirements, bounds, defaults, and null semantics.
- Actual errors that can occur, failure-side effects, cleanup, and diagnostic lifetime.
- Initialization, thread affinity, blocking behavior, and native/wrapper allocation behavior.
- Unsupported variants and raw escape hatches, without implying partial wrappers are complete.

Do not mechanically copy C comments. For example, `Texture.init_rgba` documents exact RGBA byte
layout and caller-buffer lifetime, while `RendererRef.present` explains that backbuffer contents
must be redrawn. Native failure does not imply rollback unless the implementation guarantees it.
Keep meaningful details close to each declaration; module-wide rules supplement hover text.

## Automated checks

```sh
zig build check
zig build test-docs -Dimage=true -Dmixer=true -Dttf=true
zig build docs -Dimage=true -Dmixer=true -Dttf=true
```

During build configuration, `build_support/documentation.zig` parses registered wrapper sources
with Zig's AST parser. It requires module docs, nonempty declaration docs before `pub`, and docs
for named container fields (including enum/union tags). `_` enum catch-all markers are exempt.
For simplicity, all container fields in those sources are checked, including private containers.
Named error members and semantic completeness remain manual review items.

Every local `.zig` import from those files must also be registered, preventing an imported new
submodule from silently escaping the check. Register new public module roots explicitly too.
Generated native declarations, standard-library imports, and build-tool internals are outside this
consumer documentation gate. A nonempty comment is not evidence that its contract is correct.

The source registry records each owning public module. All sources are checked for documentation,
including disabled extensions; examples are extracted and imported only for enabled modules.

Each `///` fenced `zig` block is extracted directly into a named test body. Write self-contained
statements with imports and setup/cleanup; use hidden windows and the software renderer for examples
that need graphics. Avoid placeholder code, unbounded loops, hardware-specific assumptions, or
context that only exists outside the snippet. Do not use a `main` declaration inside these blocks.
Examples that require assets may import the test-only `example_assets` module, currently providing
deterministic font/audio paths; clearly tell consumers to substitute their application asset path.
This module is only added to the documentation-test artifact when TTF or mixer is enabled.
Doc examples currently live in declaration comments; module comments describe navigation/contracts.

`zig build check` compiles the extracted examples. `zig build test-docs` runs them with the dummy
video driver and runs the documentation checker's own rejection/extraction tests. It does not run
the visible desktop example. Build-time parsing/extraction allocates through the build allocator;
this is tooling work, not a new consumer runtime allocation.

The coverage manifest requires a `documentation` path for every mapped operation, and the inventory
exports that path. Only paths registered with the documentation gate are accepted. A reviewer must
still verify that the referenced declaration describes that operation and that any limitations are
reflected by its coverage status. A mapped or compiled declaration alone is not complete.

## Generated reference and IDE use

Generated references are installed at `zig-out/docs/sdl/index.html` and corresponding
`sdl_image`, `sdl_mixer`, and `sdl_ttf` directories when enabled. Serve `zig-out/docs` through a
local static HTTP server to view the JavaScript/Wasm reference application. These generated files
are build artifacts and are not committed.

The same comments are present on public declarations for language-server hover/completion help.
Actual IDE presentation depends on the consumer's Zig language-server/editor integration; this
workflow verifies source comments, generated reference artifacts, and executable examples, not a
particular editor's hover rendering.
