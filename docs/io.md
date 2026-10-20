# Byte streams

`sdl.io.Stream` owns a native stream. `borrow()` returns a copyable `StreamRef` sharing its cursor
and status. Use one stream from only one thread at a time. File and backend operations can block
and allocate natively; the wrappers do not allocate Zig storage or retry transfers.

File streams support binary read, create/truncate, and update modes. Memory streams borrow their
storage until close. Writable memory has fixed capacity: its size includes unwritten bytes. Track
written length separately and initialize any bytes you intend to read. Read-only input must remain
alive and unchanged. Transfer buffers must not overlap the stream's backing storage.

`read(buffer)` and `write(bytes)` return `Transfer { count, status }`. Always retain `count`, even
when status reports failure or temporary unavailability. Only the first `count` bytes of a read
buffer contain newly read data. Retry a write from `bytes[count..]`, using the backend's readiness
mechanism and an application-defined work limit. A short transfer can report `ready`; do not assume
that status alone proves completion. These methods intentionally make one native transfer call.

Statuses distinguish `ready`, `failure`, `end_of_stream`, `not_ready`, `read_only`, and `write_only`.
Unknown future native values are preserved, so exhaustive consumer switches need an `else` branch.
`status()` is a snapshot, not a polling mechanism. Capture `sdl.errors.message()` or copy the error
before another native operation replaces the diagnostic. Seeking need not reset old status.

Empty transfers always return zero and preserve the previous status without invoking backend I/O.
This also applies to unsupported read/write operations: the wrapper bypasses SDL's permission checks
for empty requests. An exact final read may not report EOF until the next nonempty read.

`size()` queries the total byte size, which can be unsupported or change later. `position()` and
`seek()` operate on the shared cursor. Memory seeks clamp to capacity; file behavior differs.
`flush()` sends buffered output without closing; failure leaves the owner live and can follow partial
progress. Consult status for `not_ready` on nonblocking backends. Flushing does not promise disk
durability. Use fallible `close()` for important output: it consumes the owner even on error. Use
`deinit()` for best-effort cleanup where discarding close errors is intentional.

The `read` hover documentation contains an executable example. Tests use fixed memory plus injected
native callbacks to exercise partial failures and nonblocking status without hardware dependencies.
Custom callback backends are described below.


## Complete buffers and integer fields

`read_full(buffer)` and `write_all(bytes)` aggregate short transfers only while progress is positive
and status is `ready`. They stop when the requested length is reached, progress is zero, or status
changes. Check the returned count against the requested length and inspect status. No readiness
waiting occurs. Each call performs at most one native transfer per requested byte; this bounds the
number of calls, not their blocking time. Empty input preserves status without backend calls.

Resume a partial buffer transfer from the returned offset. There is no cursor rollback. A read's
returned prefix is initialized even when EOF or a failure prevents completion. Use single-call
`read`/`write` when your application needs a smaller per-invocation work budget.

`read_int(T, endian)` and `write_int(T, value, endian)` support signed and unsigned 8-, 16-, 32-, and
64-bit integers, with explicit `.little` or `.big` wire order. Both use at most eight stack bytes and
eight native transfers. `read_int` returns `{ value: ?T, transfer: Transfer }`; null means incomplete
input, while zero is a valid decoded value. Even a complete value can accompany a backend failure
status, so inspect both fields. Signed integers use two's-complement wire representation.

These convenience methods consume partial integer bytes without retaining them for a later call.
Never retry the whole integer after partial progress. For resumable/nonblocking protocols, retain
encoded bytes in a caller-owned buffer and resume using the buffer transfer helpers instead.

Coverage maps SDL's 28 integer read/write helpers to these generic Zig methods. Encoding is performed
with Zig's standard library over byte transfers, rather than invoking the native boolean-returning
integer functions, so byte progress remains visible. Positive short `ready` results can cause more
than one native transfer. Known-byte tests cover every supported width, signedness, and byte order.


## Growable output and detached ownership

`DynamicStream.init(.{ .chunk_size = 1024 })` owns a native growable memory stream. Its `borrow()`
view works with ordinary byte/integer operations and extension encoders such as PNG saving. Writes
copy input and can allocate/reallocate through SDL at runtime. Chunk size is allocation granularity,
not a capacity limit or reservation; zero is rejected. Use fixed-memory streams for hard capacity
bounds. Never change reserved dynamic-memory properties through raw or property APIs.

`bytes()` borrows the initialized written extent without moving the cursor. This length differs
from allocated capacity: overwriting earlier bytes does not truncate the stream. The view expires
on the next write, `finish()`, or `deinit()`. Do not write from a slice of the stream's own storage,
since growth can invalidate it. No null terminator is promised. All stream/view operations require
exclusive access, including calls made by extensions.

`finish()` consumes the stream on success **and failure**. On success it detaches the native buffer,
immediately closes the stream, and returns an `OwnedBytes` owner. On failure it closes and frees the
stream's storage. Never call stream cleanup afterward. If earlier operations can fail, guard a
surrounding deferred cleanup with a consumed flag, set immediately before calling `finish()`.
An executable hover example shows the simpler path where no fallible work precedes finishing.

The returned owner exposes immutable initialized bytes via `borrow()` and must be released exactly
once with `deinit()`, which calls SDL's allocator. Do not free it with a Zig allocator or copy the
owner. An empty stream yields an empty owner. Alternatively, `DynamicStream.deinit()` closes and
frees everything without detaching. These memory streams have no buffered output to flush on close.
Native allocation-failure injection and allocation-size instrumentation remain future validation.


## Typed custom backends

`Stream.from_callbacks(Context, &backend, .{ .read = read, .close = close })` creates an SDL stream
with a borrowed typed backend and a compile-time callback table. There is no separate adapter heap
allocation; SDL still allocates its stream. Keep the backend at a stable address until close returns.
Never copy/move its storage while the stream is alive. Opening failure leaves cleanup with the caller
and does not call the close callback.

Callbacks use ordinary Zig functions. Reads receive `[]u8`, writes receive `[]const u8`, and seeks
receive `SeekOrigin`. Read/write callbacks return `anyerror!Transfer`. Report partial progress with
a Transfer, including its status; throwing an error means zero reported progress. Reads must initialize
all bytes in the reported prefix, and neither callback may report a count larger than its slice.
Transfer slices cannot be retained. Oversized counts are rejected, but this cannot undo a backend's
out-of-bounds access or external side effects. Sizes/positions above maxInt(i64) are also rejected.

Zig errors become `SdlFailure` with their error name in `sdl.errors.message()`. A returned `.failure`
status gets a generic backend-failure diagnostic; return an error for a named zero-progress failure.
Other statuses, including EOF and temporary unavailability, retain their normal transfer meaning.
Panics are not recoverable callback errors. Callbacks execute synchronously on whichever thread invokes
the native operation; extension libraries can invoke them too. Serialize backend/stream access and
never reenter or close the same stream inside a callback. Backend allocation and blocking are its policy.

Missing read/write callbacks retain native write-only/read-only behavior. Missing seek is unsupported.
Without a size callback, SDL may seek to determine size and restore position; failures need not restore
it. Missing flush succeeds without work. A flush callback returns `.ready` for success or another
status for failure, including `.not_ready`, or throws a named error.

Close invokes the backend close callback once, then destroys the stream even if the callback fails.
Release backend resources before returning an error; no retry occurs. The adapter never frees Context
storage itself. Missing close does no backend cleanup. Explicit `close()` reports callback failure;
`deinit()` deliberately discards it. The hover example shows a write-only counting backend.
