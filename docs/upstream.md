# Upstream baseline and independent audit

`upstream.lock.tsv` pins official source archive URLs and SHA-256 digests. The archives were
downloaded and hashed on 2026-10-18; the audit verifies their digests before extraction.
This establishes repeatable input identity, not an independently authenticated signature chain.

| Library | Pinned API baseline / minimum headers |
| --- | --- |
| SDL3 | 3.4.18 |
| SDL_image | 3.4.8 |
| SDL_mixer | 3.2.4 |
| SDL_ttf | 3.2.2 |

Header checks require major 3 and an encoded version at least the baseline. These deliberately
conservative minimums define the API surface we intend to cover; they are not a claim that the
initial wrappers require every feature in these releases. Newer major-3 headers may build, but
only the locked releases currently define the reviewed coverage baseline. Runtime version tests
are separate; ordinary builds cannot prove which shared library a deployed process will load.

All four archives include zlib-style LICENSE.txt files, preserved under `upstream-licenses`.
Codec/font dependencies can carry other licenses. Their configuration and dependency closure are
not pinned yet: the source provider remains disabled. System-provider codec support depends on
the selected installation. Source archive pins do not imply codec availability or a reproducible
native binary build.

## Reproduce offline

Download the four URLs in the lock file to an archive directory, retaining their basenames.
No normal build or audit command performs a network download.

```sh
zig build inventory -Dimage=true -Dmixer=true -Dttf=true
sh tools/coverage/header_audit.sh /path/to/archives zig-out/header-audit --check
```

The maintainer audit uses Zig 0.17.0's bundled C compiler, POSIX shell/awk/sort, tar, find,
sha256sum, and ordinary text utilities. It adds no runtime dependency or external Clang package.
The declaration/preprocessor target is explicitly `x86_64-linux-gnu`; the lexical scan covers
all headers, regardless of platform, without pretending those branches have been compiled.

Outputs:

- `declarations.tsv`: SDL-prefixed C declaration names and kinds extracted from the compiler AST.
- `macros.tsv`: active SDL-prefixed macro names, including function-like macros.
- `native.ast.txt`, `native.macros.txt`: full intermediate evidence, including fields/signatures
  and macro definitions; AST addresses and temporary paths are intentionally not baselined.
- `header-sha256.tsv`: digests for every shipped include header. This detects signature, field,
  macro-body, documentation, and inactive-branch changes even when symbol names stay unchanged.
- `conditional-directives.tsv`: file/line records for conditional branches requiring matrix review.
- `candidates.tsv`: conservative names from every header, including comments, GL/test helper
  headers, and inactive branches. These are candidates to classify, not public-API counts.
- `not-translated.txt`: independent names absent from the latest `zig-out/coverage/symbols.tsv`,
  if that file exists. Regenerate that report with all extensions first; disabled modules or
  different targets/versions can otherwise appear as apparent gaps.

`--check` compares declarations, macro names, and header hashes with the checked-in baseline.
It fails on drift without updating files. Review changes before deliberately replacing a baseline.
The snapshot is an input/translation audit; complete per-symbol dispositions, callback and field
contracts, additional platform ASTs, CI enforcement, and exhaustive behavior review remain pending.

The first comparison found 25 absent names in supplemental application, Vulkan, and TTF text-engine
headers (including header guards). Those headers are now included in the canonical ABI, and the
comparison is empty for this baseline/target. Name presence does not prove declaration usability,
native symbol availability on every platform, or idiomatic wrapper completion.

Run `sh tests/header_audit.sh /path/to/archives` to verify baseline-drift and corrupt-input rejection
in an isolated temporary workspace; it does not modify the repository baseline or original archives.
