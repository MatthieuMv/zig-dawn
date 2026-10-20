# Typed property groups

`sdl.properties.Properties.init()` creates an owned native group without subsystem initialization.
Destroy it before global SDL shutdown, with all views and locks finished. `borrow()` returns a
copyable `PropertiesRef`; it does not extend the group lifetime. Native property storage can
allocate and operations may block on locks. No Zig wrapper allocator is used.

Use `set(name, &value)` with a tagged `Value`: boolean, signed 64-bit number, float32, sentinel
string, or nonnull pointer. Scalar kinds stay distinct. `get(name)` returns an optional tagged
value rather than conflating absence with false, zero, or an empty string. It does not implicitly
convert between kinds. Names must be nonempty and contain no embedded NUL; string values may be
empty but cannot contain embedded NUL. Validation failures precede mutation.

Native storage copies names and string values during `set`; caller input can be reused afterward.
Strings returned by `get` borrow native storage until their key is replaced/cleared or the group
is destroyed. Never free them. Ordinary pointer values passed through set never transfer ownership, copy pointees, or install
cleanup callbacks. Use set_owned_pointer for the separate consuming path. `clear` removes a key and succeeds if it was already absent; `contains` queries
existence without interpreting the value. Native setter failure does not guarantee rollback.

## Synchronization

Each typed `get` holds a native recursive lock across its type and value queries. This prevents
another thread from changing the kind between those queries. Scalars are snapshots. The internal
lock is released before return, so a borrowed string still needs external lifetime coordination.

Acquire an outer `var guard = try view.lock()` and `defer guard.deinit()` when performing compound
operations or using a borrowed string while other threads may mutate the group. The exact hover
example demonstrates a nested getter while this lock is held. Release each guard exactly once on
its acquiring thread; do not copy/transfer it or destroy the group while locked. Same-thread
mutation can still invalidate the string, and group locks do not protect pointer pointees.

Tests cover all value types, integer extremes, NaN, missing versus false/zero, replacement, clear,
independent groups, input name/string copies, borrowed pointers, nested locking, invalid native IDs,
and validation preserving existing values. Native concurrency contracts underpin the implementation;
these tests do not constitute multithreaded stress testing or allocation-failure injection.

Known current native types are supported; a future unknown type returns UnsupportedType rather
than being guessed. Extension-object accessors and typed convenience APIs for native property keys
remain pending. Typed cleanup and visitor adapters are described below.

## Copying and enumerating names

`source.copy_to(destination)` merges into an existing group. It replaces matching keys and leaves
other destination keys alone. Strings/names are independently copied; pointer targets remain shared.
Source properties with native cleanup callbacks are skipped, preserving any corresponding destination
value. Overwriting other destination properties can run their native cleanup callbacks and invalidate
borrowed strings. Copying a group to itself is a validated no-op.

Copying may allocate and can fail after partial destination changes. It acquires both group locks
in ID order. Do not call it with other group locks already held; native interop and cleanup callbacks
must obey compatible locking rules. Native OOM and concurrent lock-order stress testing are pending.

`view.copy_names(descriptors, bytes)` snapshots names into caller-provided storage. Each descriptor
is a sentinel slice into `bytes`; names remain valid after source mutation/destruction until these
buffers are reused or freed. Enumeration order is unspecified. Descriptor storage and byte storage
must be disjoint from each other and from the group's native storage. Values are not copied.

The wrapper counts names/bytes, checks capacity, then copies under the same lock. Byte capacity
includes one terminating NUL per name. Empty groups accept empty buffers. Insufficient capacity or
size overflow leaves both caller buffers untouched. A native failure during the copy pass can leave
partial output. This uses stack callback state and no wrapper allocator; it traverses the whole
group twice on success, so caller buffer size is not a bound on work or time spent holding the lock.

## Borrowed object and global groups

`properties.global()` returns a borrowed process-global group, valid until SDL_Quit. Never destroy
it separately. `WindowRef`, `RendererRef`, `TextureRef`, `SurfaceRef`, and `StreamRef` now provide
`properties()` accessors whose groups remain owned by those objects. Finish all property views,
locks, and borrowed-string use before the parent object is destroyed. Access can allocate native
storage. Graphics accessors use the main thread under the wrapper contract; surface access is allowed
on any thread while alive, and stream access requires exclusive use of the stream.

Use application-specific names for custom data. Native keys retain their native read/write, thread,
and lifetime restrictions; obtaining a generic view does not turn read-only backend metadata into
configurable settings. A raw native property ID may also be wrapped as PropertiesRef only while its
native owner stays alive. The borrowed view never exposes a destruction operation.

## Typed mixer looping

`track.borrow().play_with_options(.{ .looping = .{ .additional = 2 } })` plays three times in total.
`.once` (default) and `.additional = 0` use the existing one-shot path. `.forever` repeats until
stopped or input is removed. Nonzero looping builds a temporary native property group and destroys
it before return; it therefore may allocate. Consumers do not need native property names or
negative loop sentinels. Input and track lifetime rules remain those in `mixer.md`.

Additional counts are bounded by the native signed C integer. Rejection occurs before changing
playback. Tests verify finite repeat length/waveforms, bounded output from infinite looping,
accepted/rejected count boundaries, and preserved playback position after invalid options.
Other native playback properties remain unwrapped; raw nonseekable inputs cannot loop reliably.


## Cleanup ownership and typed visitors

`set_owned_pointer(name, T, pointer, cleanup)` consumes the cleanup obligation on **every outcome**.
Validation or native failure calls cleanup immediately; success installs it for replacement, clearing,
or destruction. Do not retain an error defer that would clean up again. The target remains at a stable
address until cleanup, and cannot already be owned by another key. Embed allocator/user context in T
if needed; the adapter allocates no state. Getters borrow the pointer and do not transfer ownership.
Copies of property groups skip cleanup-owned values, matching native behavior.

Cleanup uses an ordinary Zig `fn (*T) void`, not a C callback. It can run on whichever thread mutates
or destroys the property, with or without native locks. Release resources unconditionally, do not
panic or reenter the same group, and keep callback code alive until all registrations are gone.
A cleanup can change SDL diagnostics, so error identity does not guarantee diagnostic preservation.

`visit(Context, &context, callback)` synchronously enumerates sentinel names in unspecified order.
The callback receives typed context, a group view, and a borrowed name. Lookups are allowed under the
recursive group lock; mutation/destruction of the enumerated group is forbidden. Do not acquire
conflicting group locks or retain a name after its callback. Return a Zig error to suppress later user
callbacks: it propagates after SDL finishes its traversal. Native enumeration has no early-stop API,
so work still scales with the full group size even after a callback error. Use copy_names to retain
names safely outside the lock. Neither adapter provides thread synchronization for pointer targets.
