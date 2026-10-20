//! Native byte-stream owners for files and caller-owned memory; no subsystem initialization.
//! Streams may allocate native bookkeeping and block. Never access one stream concurrently.
//! Fixed-memory streams borrow buffers; DynamicStream instead owns growable native storage.
const c = @import("sdl_abi");
const Error = @import("errors.zig").Error;

/// Binary file access. Append, exclusive creation, and other native modes remain unwrapped.
pub const FileMode = enum {
    /// Read an existing file without modifying it.
    read,
    /// Create a file for writing; immediately truncate any existing contents.
    create,
    /// Read/write an existing file without truncating it.
    update,
};

/// Origin for a signed byte offset. Always inspect the actual returned position.
pub const SeekOrigin = enum {
    /// Relative to byte zero.
    start,
    /// Relative to the current cursor.
    current,
    /// Relative to the stream's end (capacity for fixed memory).
    end,
};

/// Outcome of the most recent stream operation. Unknown future native values are retained.
/// This is a snapshot, not a readiness notification: polling it does not perform I/O.
pub const Status = enum(c_uint) {
    /// No reported error; this does not guarantee a full transfer or future readiness.
    ready = c.SDL_IO_STATUS_READY,
    /// Backend failure; inspect `sdl.errors.message()` before another native call overwrites it.
    failure = c.SDL_IO_STATUS_ERROR,
    /// Input reached its end; an exact final read may report this only on the next read.
    end_of_stream = c.SDL_IO_STATUS_EOF,
    /// Nonblocking backend cannot currently finish; schedule a later attempt instead of spinning.
    not_ready = c.SDL_IO_STATUS_NOT_READY,
    /// Writing is unsupported by this stream.
    read_only = c.SDL_IO_STATUS_READONLY,
    /// Reading is unsupported by this stream.
    write_only = c.SDL_IO_STATUS_WRITEONLY,
    _,
};

/// One transfer's progress and status, including progress made before a backend failure.
/// Inspect both fields; even a short transfer can report `ready`. No implicit retry is performed.
pub const Transfer = struct {
    /// Bytes successfully transferred, never greater than the supplied slice length.
    count: usize,
    /// Native status immediately after the operation; empty transfers retain the previous status.
    status: Status,
};

/// Result of decoding one signed/unsigned 8-, 16-, 32-, or 64-bit integer.
/// No value is exposed until all encoded bytes arrive; transfer progress is always retained.
pub fn integer_read_result(comptime T: type) type {
    validate_integer(T);
    return struct {
        /// Decoded value, or null after an incomplete read. Zero is a valid complete value.
        value: ?T,
        /// Bytes consumed and final status, including failures after partial progress.
        transfer: Transfer,
    };
}

// Limit wire formats and stack storage to the widths supported by SDL's integer helpers.
fn validate_integer(comptime T: type) void {
    switch (T) {
        u8, i8, u16, i16, u32, i32, u64, i64 => {},
        else => @compileError("stream integers must be u8/i8/u16/i16/u32/i32/u64/i64"),
    }
}

/// Typed custom stream operations. The table is compile-time data; Context stays caller-owned.
/// Callbacks run synchronously on the invoking thread, including calls made by extension libraries.
/// Never reenter/close the same stream from a callback or retain transfer slices after returning.
/// Errors become SdlFailure with the Zig error name in SDL's diagnostic; return Transfer when
/// partial progress must be preserved. Panics cannot be translated into stream failures.
pub fn callbacks(comptime Context: type) type {
    return struct {
        /// Byte size, at most maxInt(i64). If absent, SDL tries seek-based size discovery.
        size: ?*const fn (*Context) anyerror!u64 = null,
        /// Move cursor and return position, at most maxInt(i64). Null means seeking unsupported.
        seek: ?*const fn (*Context, i64, SeekOrigin) anyerror!u64 = null,
        /// Initialize exactly the reported prefix of the slice; count must not exceed its length.
        /// Null reports write_only. Use end_of_stream/not_ready for ordinary short reads.
        read: ?*const fn (*Context, []u8) anyerror!Transfer = null,
        /// Consume the reported prefix; count must not exceed input length. Null means read_only.
        /// Errors report zero progress; use Transfer for partial writes, including failures.
        write: ?*const fn (*Context, []const u8) anyerror!Transfer = null,
        /// Return ready on success, another status on failure. Null is a no-op.
        flush: ?*const fn (*Context) anyerror!Status = null,
        /// Release backend resources even on error. Called once on close, never on opening failure.
        /// Context storage itself remains caller-owned; null performs no backend cleanup.
        close: ?*const fn (*Context) anyerror!void = null,
    };
}

// Compile-time callback tables avoid adapter heap/state lifetime issues.
fn callback_adapter(comptime Context: type, comptime functions: callbacks(Context)) type {
    return struct {
        fn context(userdata: ?*anyopaque) *Context {
            return @ptrCast(@alignCast(userdata.?));
        }

        fn report(err: anyerror) void {
            _ = c.SDL_SetError("Zig stream callback: %s", @errorName(err).ptr);
        }

        fn position_result(value: u64) i64 {
            return @import("std").math.cast(i64, value) orelse {
                report(error.PositionOverflow);
                return -1;
            };
        }

        fn size(userdata: ?*anyopaque) callconv(.c) i64 {
            const result = functions.size.?(context(userdata)) catch |err| {
                report(err);
                return -1;
            };
            return position_result(result);
        }

        fn seek(userdata: ?*anyopaque, offset: i64, native: c.SDL_IOWhence) callconv(.c) i64 {
            const origin: SeekOrigin = switch (native) {
                c.SDL_IO_SEEK_SET => .start,
                c.SDL_IO_SEEK_CUR => .current,
                c.SDL_IO_SEEK_END => .end,
                else => {
                    report(error.InvalidSeekOrigin);
                    return -1;
                },
            };
            const result = functions.seek.?(context(userdata), offset, origin) catch |err| {
                report(err);
                return -1;
            };
            return position_result(result);
        }

        fn transfer_result(result: Transfer, capacity: usize, status: [*c]c.SDL_IOStatus) usize {
            if (result.count > capacity) {
                report(error.InvalidTransferCount);
                status.* = c.SDL_IO_STATUS_ERROR;
                return 0;
            }
            status.* = @intCast(@backingInt(result.status));
            if (result.status == .failure) report(error.BackendFailure);
            return result.count;
        }

        fn read(
            userdata: ?*anyopaque,
            ptr: ?*anyopaque,
            len: usize,
            status: [*c]c.SDL_IOStatus,
        ) callconv(.c) usize {
            const bytes: [*]u8 = @ptrCast(ptr.?);
            const result = functions.read.?(context(userdata), bytes[0..len]) catch |err| {
                report(err);
                status.* = c.SDL_IO_STATUS_ERROR;
                return 0;
            };
            return transfer_result(result, len, status);
        }

        fn write(
            userdata: ?*anyopaque,
            ptr: ?*const anyopaque,
            len: usize,
            status: [*c]c.SDL_IOStatus,
        ) callconv(.c) usize {
            const bytes: [*]const u8 = @ptrCast(ptr.?);
            const result = functions.write.?(context(userdata), bytes[0..len]) catch |err| {
                report(err);
                status.* = c.SDL_IO_STATUS_ERROR;
                return 0;
            };
            return transfer_result(result, len, status);
        }

        fn flush(userdata: ?*anyopaque, status: [*c]c.SDL_IOStatus) callconv(.c) bool {
            const result = functions.flush.?(context(userdata)) catch |err| {
                report(err);
                status.* = c.SDL_IO_STATUS_ERROR;
                return false;
            };
            status.* = @intCast(@backingInt(result));
            if (result == .failure) report(error.BackendFailure);
            return result == .ready;
        }

        fn close(userdata: ?*anyopaque) callconv(.c) bool {
            functions.close.?(context(userdata)) catch |err| {
                report(err);
                return false;
            };
            return true;
        }
    };
}

/// Owns a native stream, not its borrowed memory buffer. Do not copy.
/// Close exactly once with `close` when errors matter, or `deinit` for best-effort cleanup.
pub const Stream = struct {
    /// Native interop handle. Do not close elsewhere or install memory-free callbacks.
    handle: *c.SDL_IOStream,

    /// Open a binary file on any thread. UTF-8 sentinel path is borrowed only for this call;
    /// relative paths use the working directory. `create` truncates immediately, without rollback.
    /// May allocate/block. `SdlFailure` returns no owner; read `sdl.errors.message()` for detail.
    pub fn open(path: [:0]const u8, mode: FileMode) Error!Stream {
        const native_mode: [:0]const u8 = switch (mode) {
            .read => "rb",
            .create => "wb",
            .update => "r+b",
        };
        const handle = c.SDL_IOFromFile(path.ptr, native_mode.ptr) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Open a stream borrowing a stable typed backend until close. Any thread; SDL may allocate.
    /// Callback code and backend resources must remain live across all stream/extension operations.
    /// No wrapper allocation or backend copy. Opening failure leaves backend ownership unchanged
    /// and does not invoke close. Serialize access; callbacks may block/allocate by backend policy.
    /// Backend cleanup runs once on close, even on error; caller frees Context storage.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// const Sink = struct {
    ///     total: usize = 0,
    ///     fn write(self: *@This(), bytes: []const u8) anyerror!sdl.io.Transfer {
    ///         self.total += bytes.len;
    ///         return .{ .count = bytes.len, .status = .ready };
    ///     }
    /// };
    /// var sink = Sink{};
    /// var stream = try sdl.io.Stream.from_callbacks(Sink, &sink, .{ .write = Sink.write });
    /// defer stream.deinit();
    /// const result = stream.borrow().write_all("abc");
    /// try @import("std").testing.expectEqual(@as(usize, 3), result.count);
    /// try @import("std").testing.expectEqual(@as(usize, 3), sink.total);
    /// ```
    pub fn from_callbacks(
        comptime Context: type,
        context: *Context,
        comptime functions: callbacks(Context),
    ) Error!Stream {
        const Adapter = callback_adapter(Context, functions);
        var interface = @import("std").mem.zeroes(c.SDL_IOStreamInterface);
        interface.version = @sizeOf(c.SDL_IOStreamInterface);
        interface.size = if (functions.size != null) Adapter.size else null;
        interface.seek = if (functions.seek != null) Adapter.seek else null;
        interface.read = if (functions.read != null) Adapter.read else null;
        interface.write = if (functions.write != null) Adapter.write else null;
        interface.flush = if (functions.flush != null) Adapter.flush else null;
        interface.close = if (functions.close != null) Adapter.close else null;
        const handle = c.SDL_OpenIO(&interface, context) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Borrow bytes as a read-only fixed-capacity stream with initial cursor zero.
    /// Any thread; native bookkeeping may allocate. Bytes must remain alive and unchanged until
    /// close, including across image loads. Empty input creates an empty stream. `SdlFailure`
    /// returns no owner. No copy or ownership transfer of the bytes occurs.
    pub fn from_const_memory(bytes: []const u8) Error!Stream {
        const handle = c.SDL_IOFromConstMem(bytes.ptr, bytes.len) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Borrow writable storage as a fixed-capacity stream with initial cursor zero.
    /// Any thread; native bookkeeping may allocate. Buffer must outlive the stream. Synchronize
    /// direct buffer access with stream operations; never free it through native stream properties.
    /// No bytes are initialized, copied, or grown. Reads can include unwritten bytes: keep track of
    /// the written length yourself. Empty buffers are allowed. `SdlFailure` returns no owner.
    pub fn from_memory(buffer: []u8) Error!Stream {
        const handle = c.SDL_IOFromMem(buffer.ptr, buffer.len) orelse return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Close and report buffered output failure as `SdlFailure`. Any thread with exclusive access.
    /// Invalidates the owner and every view even on error; never retry or call deinit afterward.
    /// Releases native resources but leaves caller-owned memory intact. May block; does not promise
    /// physical-disk durability. Prefer this operation when output success matters.
    pub fn close(self: *Stream) Error!void {
        const success = c.SDL_CloseIO(self.handle);
        self.* = undefined;
        if (!success) return error.SdlFailure;
    }

    /// Best-effort close for defer/error cleanup; deliberately discards close/flush failures.
    /// Any thread with exclusive access; may block. Invalidates owner/views. Retains caller memory.
    /// Call exactly once. Use `close` instead when a write must report final flush failure.
    pub fn deinit(self: *Stream) void {
        self.close() catch {};
    }

    /// Borrow without allocation or ownership transfer. Owner and any buffer must outlive the view.
    pub fn borrow(self: *const Stream) StreamRef {
        return .{ .handle = self.handle };
    }
};

/// Dynamic stream configuration. Growth uses SDL's allocator, not a Zig allocator.
pub const DynamicOptions = struct {
    /// Native allocation granularity in bytes, not a capacity limit. Must be nonzero.
    chunk_size: u32 = 1024,
};

/// Failures specific to creating or inspecting dynamic streams.
pub const DynamicError = Error || error{
    /// Allocation granularity was zero; no native owner was created.
    InvalidChunkSize,
    /// Native byte length cannot be represented as a slice on this target.
    SizeOverflow,
};

/// Owns a detached SDL allocation. Do not copy; call deinit exactly once.
/// No Zig allocator may free this storage. Bytes remain valid independently of any stream.
pub const OwnedBytes = struct {
    /// Allocation base, or null for an empty unallocated buffer. Never replace or free separately.
    allocation: ?*anyopaque,
    /// Initialized data length, excluding unused native capacity. Never change independently.
    len: usize,

    /// Borrow immutable initialized bytes until deinit. Any thread with synchronized owner access.
    /// No allocation; empty owners return an empty slice. No sentinel termination is promised.
    pub fn borrow(self: *const OwnedBytes) []const u8 {
        if (self.len == 0) return &.{};
        const pointer: [*]const u8 = @ptrCast(self.allocation.?);
        return pointer[0..self.len];
    }

    /// Free through SDL, invalidating this owner and all slices. Any thread with exclusive access.
    /// Native allocator hooks may run; do not also free through a Zig allocator.
    pub fn deinit(self: *OwnedBytes) void {
        c.SDL_free(self.allocation);
        self.* = undefined;
    }
};

/// Owns a growable native memory stream and its allocation. Do not copy.
/// Writes may allocate/reallocate at runtime. No hard memory limit is enforced; use fixed memory
/// for bounded capacity. Never mutate reserved memory properties through native interop.
pub const DynamicStream = struct {
    /// Native stream handle. Never close elsewhere or transfer its buffer through raw properties.
    handle: *c.SDL_IOStream,

    /// Create an empty stream with cursor zero. Any thread; may allocate native bookkeeping.
    /// Zero chunk size returns InvalidChunkSize before allocation. Native failure returns no owner.
    pub fn init(options: DynamicOptions) DynamicError!DynamicStream {
        if (options.chunk_size == 0) return error.InvalidChunkSize;
        const handle = c.SDL_IOFromDynamicMem() orelse return error.SdlFailure;
        errdefer _ = c.SDL_CloseIO(handle);
        const properties = c.SDL_GetIOProperties(handle);
        if (properties == 0) return error.SdlFailure;
        if (!c.SDL_SetNumberProperty(
            properties,
            c.SDL_PROP_IOSTREAM_DYNAMIC_CHUNKSIZE_NUMBER,
            options.chunk_size,
        )) return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Borrow the shared cursor for reads, writes, seeks, or extension encoders. No allocation.
    /// Owner must outlive views; never pass a view to an API that closes or detaches its stream.
    /// Exclusive access is required across all views. Do not modify reserved dynamic properties.
    pub fn borrow(self: *const DynamicStream) StreamRef {
        return .{ .handle = self.handle };
    }

    /// Borrow initialized bytes without moving the cursor. Any thread with exclusive stream access.
    /// Valid until the next write, finish, or deinit; never use as input to this stream's writes.
    /// Length is the high-water written extent, not capacity or cursor. No sentinel is promised.
    /// Native property access may allocate/block; native query failure returns SdlFailure.
    pub fn bytes(self: *const DynamicStream) DynamicError![]const u8 {
        const length = try self.borrow().size();
        const len = @import("std").math.cast(usize, length) orelse return error.SizeOverflow;
        if (len == 0) return &.{};
        const properties = c.SDL_GetIOProperties(self.handle);
        if (properties == 0) return error.SdlFailure;
        const allocation = c.SDL_GetPointerProperty(
            properties,
            c.SDL_PROP_IOSTREAM_DYNAMIC_MEMORY_POINTER,
            null,
        ) orelse return error.SdlFailure;
        const pointer: [*]const u8 = @ptrCast(allocation);
        return pointer[0..len];
    }

    /// Consume this stream and transfer its native buffer without copying. Any thread, exclusive.
    /// Invalidates owner/views on both success and failure; never deinit afterward. On failure,
    /// native storage is freed. On success, call the returned owner's deinit exactly once.
    /// Pending borrowed byte slices expire; borrow from the returned owner instead. May block in
    /// native property/cleanup code. This memory backend has no buffered close failure.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var stream = try sdl.io.DynamicStream.init(.{});
    /// const written = stream.borrow().write_all("hello");
    /// var bytes = try stream.finish();
    /// defer bytes.deinit();
    /// try @import("std").testing.expectEqual(@as(usize, 5), written.count);
    /// try @import("std").testing.expectEqualStrings("hello", bytes.borrow());
    /// ```
    pub fn finish(self: *DynamicStream) DynamicError!OwnedBytes {
        defer self.deinit();
        const data = try self.bytes();
        const properties = c.SDL_GetIOProperties(self.handle);
        if (properties == 0) return error.SdlFailure;
        const allocation = c.SDL_GetPointerProperty(
            properties,
            c.SDL_PROP_IOSTREAM_DYNAMIC_MEMORY_POINTER,
            null,
        );
        if (!c.SDL_SetPointerProperty(
            properties,
            c.SDL_PROP_IOSTREAM_DYNAMIC_MEMORY_POINTER,
            null,
        )) return error.SdlFailure;
        // SDL requires closing immediately after detachment; defer performs that next native call.
        return .{ .allocation = allocation, .len = data.len };
    }

    /// Close and free native storage, invalidating every view and byte slice. Call exactly once.
    /// Any thread with exclusive access; may run native cleanup. Use finish to retain the bytes.
    pub fn deinit(self: *DynamicStream) void {
        _ = c.SDL_CloseIO(self.handle);
        self.* = undefined;
    }
};

/// Copyable borrowed cursor shared by every view of this stream. No concurrent access.
/// Asynchronous streams remain separate native operations.
pub const StreamRef = struct {
    /// Live native handle. Never close it through this view or transfer it to a native close flag.
    handle: *c.SDL_IOStream,

    /// Borrow this object's native property group. Any thread with exclusive access to the stream.
    /// May allocate/block; `SdlFailure` returns no view. The object owns the group: never destroy
    /// it separately. Finish all views/locks before object destruction. Use application-specific
    /// keys for custom data; native keys retain their individual read/write and lifetime contracts.
    pub fn properties(
        self: StreamRef,
    ) @import("errors.zig").Error!@import("properties.zig").PropertiesRef {
        const handle = c.SDL_GetIOProperties(self.handle);
        if (handle == 0) return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Read at most `buffer.len` bytes in one native call. Any thread with exclusive stream access.
    /// Only `buffer[0..result.count]` contains newly read bytes; preserve progress even on failure.
    /// Buffer is borrowed for this call and must not overlap memory backing the stream. May block
    /// or allocate in the backend; no wrapper allocation. Empty buffers do no I/O or status reset.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var stream = try sdl.io.Stream.from_const_memory("abc");
    /// defer stream.deinit();
    /// var buffer: [8]u8 = undefined;
    /// const result = stream.borrow().read(&buffer);
    /// try @import("std").testing.expectEqualStrings("abc", buffer[0..result.count]);
    /// const end = stream.borrow().read(&buffer);
    /// try @import("std").testing.expectEqual(.end_of_stream, end.status);
    /// ```
    pub fn read(self: StreamRef, buffer: []u8) Transfer {
        const count = if (buffer.len == 0) 0 else c.SDL_ReadIO(self.handle, buffer.ptr, buffer.len);
        return .{ .count = count, .status = self.status() };
    }

    /// Write from `bytes` in one native call; `count` bytes were consumed even on failure.
    /// Retry only the remaining suffix, according to status and the backend's readiness mechanism.
    /// Any thread with exclusive stream access; backend work may block/allocate. Input is borrowed
    /// for this call and must not overlap stream backing memory. No wrapper allocation or retries.
    /// Empty input does no I/O and preserves status. Flush/close can still fail after a full write.
    pub fn write(self: StreamRef, bytes: []const u8) Transfer {
        const count = if (bytes.len == 0) 0 else c.SDL_WriteIO(self.handle, bytes.ptr, bytes.len);
        return .{ .count = count, .status = self.status() };
    }

    /// Fill a buffer while reads make progress and report `ready`; return total progress/status.
    /// Completion means `count == buffer.len`; a short result is not an error union and must be
    /// checked. Stop on zero progress or any non-ready status, without waiting for readiness.
    /// At most buffer.len native reads; each can block/allocate. Empty buffers preserve status.
    /// Any thread with exclusive stream access; buffer lifetime/nonoverlap rules match `read`.
    /// A partial result leaves the cursor advanced and only its returned prefix initialized.
    pub fn read_full(self: StreamRef, buffer: []u8) Transfer {
        var result = Transfer{ .count = 0, .status = self.status() };
        while (result.count < buffer.len) {
            const part = self.read(buffer[result.count..]);
            result.count += part.count;
            result.status = part.status;
            if (part.count == 0 or part.status != .ready) break;
        }
        return result;
    }

    /// Write a complete slice while progress continues with `ready` status; return total progress.
    /// Always check `count == bytes.len` and status. Stop on zero progress or non-ready status;
    /// resume from the returned count if appropriate. At most bytes.len native writes, without
    /// readiness waiting. Each call can block/allocate; empty input preserves status. Any thread
    /// with exclusive access; input lifetime/nonoverlap rules match `write`. No rollback or flush.
    pub fn write_all(self: StreamRef, bytes: []const u8) Transfer {
        var result = Transfer{ .count = 0, .status = self.status() };
        while (result.count < bytes.len) {
            const part = self.write(bytes[result.count..]);
            result.count += part.count;
            result.status = part.status;
            if (part.count == 0 or part.status != .ready) break;
        }
        return result;
    }

    /// Decode one u8/i8/u16/i16/u32/i32/u64/i64 using explicit wire byte order.
    /// Uses `read_full` with at most eight stack bytes/native reads; other types fail compilation.
    /// Any thread with exclusive access; backend calls may block/allocate. On incomplete input,
    /// value is null and consumed bytes are not rolled back. Do not retry the integer operation
    /// after partial input: use a caller-owned byte buffer and `read_full` for resumable parsing.
    /// Inspect transfer status even with a value: a backend may report failure with full progress.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var stream = try sdl.io.Stream.from_const_memory(&.{ 0x12, 0x34 });
    /// defer stream.deinit();
    /// const result = stream.borrow().read_int(u16, .big);
    /// try @import("std").testing.expectEqual(@as(u16, 0x1234), result.value.?);
    /// ```
    pub fn read_int(
        self: StreamRef,
        comptime T: type,
        endian: @import("std").lang.Endian,
    ) integer_read_result(T) {
        var bytes: [@sizeOf(T)]u8 = undefined;
        const transfer = self.read_full(&bytes);
        return .{
            .value = if (transfer.count == bytes.len)
                @import("std").mem.readInt(T, &bytes, endian)
            else
                null,
            .transfer = transfer,
        };
    }

    /// Encode one u8/i8/u16/i16/u32/i32/u64/i64 in explicit wire byte order, then `write_all`.
    /// Uses at most eight stack bytes/native writes; unsupported types fail compilation.
    /// Any thread with exclusive access; backend work may block/allocate. Inspect count and status;
    /// partial output remains written. Do not retry the whole integer after partial output. For
    /// resumable output, encode into caller-owned bytes and `write_all` the remaining suffix.
    /// A full write still requires fallible flush/close when output success matters.
    pub fn write_int(
        self: StreamRef,
        comptime T: type,
        value: T,
        endian: @import("std").lang.Endian,
    ) Transfer {
        comptime validate_integer(T);
        var bytes: [@sizeOf(T)]u8 = undefined;
        @import("std").mem.writeInt(T, &bytes, value, endian);
        return self.write_all(&bytes);
    }

    /// Snapshot native status without I/O or allocation. Any thread with exclusive stream access.
    /// Read/write and flush can change it; seeking need not clear an earlier EOF or failure.
    pub fn status(self: StreamRef) Status {
        return @fromBackingInt(@intCast(c.SDL_GetIOStatus(self.handle)));
    }

    /// Query size in bytes; fixed-memory streams report capacity, including unwritten bytes.
    /// Any thread with exclusive stream access; backend work may block/allocate. `SdlFailure`
    /// includes unsupported size queries. Size can change later and is not a remaining-byte count.
    pub fn size(self: StreamRef) Error!u64 {
        const result = c.SDL_GetIOSize(self.handle);
        if (result < 0) return error.SdlFailure;
        return @intCast(result);
    }

    /// Flush buffered output without closing the stream. May block/allocate in the backend.
    /// Any thread with exclusive access. `SdlFailure` can follow partial flushing; inspect status
    /// for a nonblocking backend's `not_ready`. Owner remains live on failure. No disk-durability
    /// guarantee; still check `close` when output matters. Unbuffered backends may do nothing.
    pub fn flush(self: StreamRef) Error!void {
        if (!c.SDL_FlushIO(self.handle)) return error.SdlFailure;
    }

    /// Return the byte cursor on any thread with exclusive access; may invoke backend I/O.
    /// `SdlFailure` means position is unavailable. No wrapper allocation or ownership change.
    pub fn position(self: StreamRef) Error!u64 {
        const result = c.SDL_TellIO(self.handle);
        if (result < 0) return error.SdlFailure;
        return @intCast(result);
    }

    /// Move the shared cursor by signed bytes and return its actual position from the start.
    /// Any thread with exclusive access; may block. Memory streams clamp to their buffer bounds;
    /// file behavior differs. `SdlFailure` covers unsupported/failed seeks; do not assume rollback.
    /// No wrapper allocation or ownership transfer.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var stream = try sdl.io.Stream.from_const_memory("abc");
    /// defer stream.deinit();
    /// const view = stream.borrow();
    /// try @import("std").testing.expectEqual(@as(u64, 2), try view.seek(-1, .end));
    /// try @import("std").testing.expectEqual(@as(u64, 2), try view.position());
    /// ```
    pub fn seek(self: StreamRef, offset: i64, origin: SeekOrigin) Error!u64 {
        const native_origin: c.SDL_IOWhence = switch (origin) {
            .start => c.SDL_IO_SEEK_SET,
            .current => c.SDL_IO_SEEK_CUR,
            .end => c.SDL_IO_SEEK_END,
        };
        const result = c.SDL_SeekIO(self.handle, offset, native_origin);
        if (result < 0) return error.SdlFailure;
        return @intCast(result);
    }
};

test "memory stream bounds and shared cursors" {
    const std = @import("std");
    var empty_input = try Stream.from_const_memory(&.{});
    defer empty_input.deinit();
    var empty_output = try Stream.from_memory(&.{});
    defer empty_output.deinit();
    try std.testing.expectEqual(@as(u64, 0), try empty_input.borrow().position());
    try std.testing.expectEqual(@as(u64, 0), try empty_output.borrow().seek(0, .end));
    var bytes = [_]u8{ 1, 2, 3 };
    var stream = try Stream.from_memory(&bytes);
    defer stream.deinit();
    const view = stream.borrow();
    try std.testing.expectEqual(@as(u64, 0), try view.position());
    try std.testing.expectEqual(@as(u64, 2), try view.seek(2, .start));
    try std.testing.expectEqual(@as(u64, 1), try stream.borrow().seek(-1, .current));
    try std.testing.expectEqual(@as(u64, 3), try view.seek(100, .start));
    try std.testing.expectEqual(@as(u64, 0), try view.seek(-100, .start));
}

test "explicit close retains borrowed memory" {
    const std = @import("std");
    var bytes = [_]u8{ 1, 2, 3 };
    var stream = try Stream.from_memory(&bytes);
    try stream.close();
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, &bytes);
}

test "close errors are reported once and best effort cleanup consumes the stream" {
    const std = @import("std");
    const Backend = struct {
        fn fail_close(userdata: ?*anyopaque) callconv(.c) bool {
            const calls: *u32 = @ptrCast(@alignCast(userdata.?));
            calls.* += 1;
            return c.SDL_SetError("injected close failure");
        }
    };
    var interface = std.mem.zeroes(c.SDL_IOStreamInterface);
    interface.version = @sizeOf(c.SDL_IOStreamInterface);
    interface.close = Backend.fail_close;
    var calls: u32 = 0;
    var stream = Stream{
        .handle = c.SDL_OpenIO(&interface, &calls) orelse return error.SdlFailure,
    };
    try std.testing.expectError(error.SdlFailure, stream.close());
    try std.testing.expectEqual(@as(u32, 1), calls);
    var cleanup = Stream{
        .handle = c.SDL_OpenIO(&interface, &calls) orelse return error.SdlFailure,
    };
    cleanup.deinit();
    try std.testing.expectEqual(@as(u32, 2), calls);
}

test "byte transfers preserve bounds, EOF, permissions, and empty status" {
    const std = @import("std");
    var storage = [_]u8{ 9, 9, 9 };
    var output = try Stream.from_memory(&storage);
    defer output.deinit();
    const view = output.borrow();
    try std.testing.expectEqual(@as(u64, 3), try view.size());
    try std.testing.expectEqual(@as(usize, 3), view.write("abcd").count);
    try std.testing.expectEqualStrings("abc", &storage);
    try std.testing.expectEqual(@as(usize, 0), view.write("d").count);
    try std.testing.expectEqual(Status.failure, view.status());
    try std.testing.expectEqual(Status.failure, view.write("").status);
    try view.flush();
    _ = try view.seek(0, .start);
    var buffer = [_]u8{ 9, 9, 9, 9 };
    const result = view.read(&buffer);
    try std.testing.expectEqual(@as(usize, 3), result.count);
    try std.testing.expectEqualStrings("abc", buffer[0..result.count]);
    try std.testing.expectEqual(@as(u8, 9), buffer[3]);
    try std.testing.expectEqual(Status.end_of_stream, view.read(&buffer).status);
    try std.testing.expectEqual(Status.end_of_stream, view.read(buffer[0..0]).status);
    var input = try Stream.from_const_memory("x");
    defer input.deinit();
    try std.testing.expectEqual(Status.ready, input.borrow().write("").status);
    try std.testing.expectEqual(Status.read_only, input.borrow().write("x").status);
    try std.testing.expectEqual(Status.read_only, input.borrow().read(buffer[0..0]).status);
    try std.testing.expectEqual(@as(usize, 1), input.borrow().read(&buffer).count);
}

test "partial backend failures retain progress without retries and flush leaves owner live" {
    const std = @import("std");
    const Backend = struct {
        fn write(
            userdata: ?*anyopaque,
            _: ?*const anyopaque,
            size_bytes: usize,
            status_ptr: [*c]c.SDL_IOStatus,
        ) callconv(.c) usize {
            const calls: *u32 = @ptrCast(@alignCast(userdata.?));
            calls.* += 1;
            status_ptr.* = c.SDL_IO_STATUS_NOT_READY;
            return @min(size_bytes, 1);
        }
        fn read(
            _: ?*anyopaque,
            ptr: ?*anyopaque,
            _: usize,
            status_ptr: [*c]c.SDL_IOStatus,
        ) callconv(.c) usize {
            const bytes: [*]u8 = @ptrCast(ptr.?);
            bytes[0] = 42;
            status_ptr.* = c.SDL_IO_STATUS_ERROR;
            _ = c.SDL_SetError("injected partial read failure");
            return 1;
        }
        fn flush(_: ?*anyopaque, status_ptr: [*c]c.SDL_IOStatus) callconv(.c) bool {
            status_ptr.* = c.SDL_IO_STATUS_NOT_READY;
            return false;
        }
    };
    var interface = std.mem.zeroes(c.SDL_IOStreamInterface);
    interface.version = @sizeOf(c.SDL_IOStreamInterface);
    interface.write = Backend.write;
    interface.read = Backend.read;
    interface.flush = Backend.flush;
    var calls: u32 = 0;
    var stream = Stream{
        .handle = c.SDL_OpenIO(&interface, &calls) orelse return error.SdlFailure,
    };
    defer stream.deinit();
    const result = stream.borrow().write("abc");
    try std.testing.expectEqual(@as(usize, 1), result.count);
    try std.testing.expectEqual(Status.not_ready, result.status);
    try std.testing.expectEqual(@as(u32, 1), calls);
    try std.testing.expectEqual(Status.not_ready, stream.borrow().write("").status);
    try std.testing.expectEqual(@as(u32, 1), calls);
    var bytes = [_]u8{ 9, 9 };
    const read_result = stream.borrow().read(&bytes);
    try std.testing.expectEqual(@as(usize, 1), read_result.count);
    try std.testing.expectEqual(Status.failure, read_result.status);
    try std.testing.expectEqualSlices(u8, &.{ 42, 9 }, &bytes);
    try std.testing.expectError(error.SdlFailure, stream.borrow().flush());
    try std.testing.expectEqual(Status.not_ready, stream.borrow().status());
    try std.testing.expectError(error.SdlFailure, stream.borrow().size());
    try std.testing.expectEqual(@as(usize, 1), stream.borrow().write("z").count);
    calls = 0;
    const partial_write = stream.borrow().write_all("abc");
    try std.testing.expectEqual(@as(usize, 1), partial_write.count);
    try std.testing.expectEqual(Status.not_ready, partial_write.status);
    try std.testing.expectEqual(@as(u32, 1), calls);
    const partial_read = stream.borrow().read_full(&bytes);
    try std.testing.expectEqual(@as(usize, 1), partial_read.count);
    try std.testing.expectEqual(Status.failure, partial_read.status);
}

test "write-only backend and empty transfers preserve status" {
    const std = @import("std");
    var interface = std.mem.zeroes(c.SDL_IOStreamInterface);
    interface.version = @sizeOf(c.SDL_IOStreamInterface);
    var stream = Stream{ .handle = c.SDL_OpenIO(&interface, null) orelse return error.SdlFailure };
    defer stream.deinit();
    var byte: [1]u8 = undefined;
    try std.testing.expectEqual(Status.ready, stream.borrow().read(byte[0..0]).status);
    try std.testing.expectEqual(Status.write_only, stream.borrow().read(&byte).status);
    try std.testing.expectEqual(Status.write_only, stream.borrow().write("").status);
    try std.testing.expectEqual(@as(usize, 0), stream.borrow().read(&byte).count);
}

test "integer wire vectors cover every width signedness and endian" {
    const std = @import("std");
    inline for (.{ u8, i8, u16, i16, u32, i32, u64, i64 }) |T| {
        inline for (.{ std.lang.Endian.little, std.lang.Endian.big }) |endian| {
            const signed = @typeInfo(T).int.signedness == .signed;
            const value: T = if (signed) -2 else @truncate(@as(u64, 0x0807060504030201));
            var expected: [@sizeOf(T)]u8 = undefined;
            for (&expected, 0..) |*byte, i| {
                const significance = if (endian == .little) i else expected.len - 1 - i;
                byte.* = if (signed)
                    (if (significance == 0) 0xfe else 0xff)
                else
                    @intCast(significance + 1);
            }
            var storage: [@sizeOf(T)]u8 = undefined;
            var stream = try Stream.from_memory(&storage);
            defer stream.deinit();
            const written = stream.borrow().write_int(T, value, endian);
            try std.testing.expectEqual(storage.len, written.count);
            try std.testing.expectEqual(Status.ready, written.status);
            try std.testing.expectEqualSlices(u8, &expected, &storage);
            _ = try stream.borrow().seek(0, .start);
            const decoded = stream.borrow().read_int(T, endian);
            try std.testing.expectEqual(value, decoded.value.?);
            try std.testing.expectEqual(storage.len, decoded.transfer.count);
            const end = stream.borrow().read_int(T, endian);
            try std.testing.expectEqual(@as(?T, null), end.value);
            try std.testing.expectEqual(Status.end_of_stream, end.transfer.status);
        }
    }
}

test "truncated integer preserves progress and never exposes a value" {
    const std = @import("std");
    var input = try Stream.from_const_memory(&.{ 0x12, 0x34, 0x56 });
    defer input.deinit();
    const result = input.borrow().read_int(u32, .big);
    try std.testing.expectEqual(@as(?u32, null), result.value);
    try std.testing.expectEqual(@as(usize, 3), result.transfer.count);
    try std.testing.expectEqual(Status.end_of_stream, result.transfer.status);
    try std.testing.expectEqual(@as(u64, 3), try input.borrow().position());
    var storage: [3]u8 = undefined;
    var output = try Stream.from_memory(&storage);
    defer output.deinit();
    const written = output.borrow().write_int(u32, 0x12345678, .big);
    try std.testing.expectEqual(@as(usize, 3), written.count);
    try std.testing.expectEqual(Status.failure, written.status);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56 }, &storage);
}

// Deterministic one-byte backend: test aggregation and stopping without OS timing dependencies.
const TransferBackend = struct {
    /// Number of invoked transfer callbacks.
    calls: usize = 0,
    /// Number of one-byte transfers allowed before no-progress results.
    stop_after: usize = 3,
    /// Status reported when progress stops.
    stop_status: c.SDL_IOStatus = c.SDL_IO_STATUS_READY,
    /// Captured output for order/offset checks; tests never write more than four bytes.
    output: [4]u8 = .{ 0, 0, 0, 0 },

    fn read(
        userdata: ?*anyopaque,
        ptr: ?*anyopaque,
        _: usize,
        status_ptr: [*c]c.SDL_IOStatus,
    ) callconv(.c) usize {
        const self: *TransferBackend = @ptrCast(@alignCast(userdata.?));
        self.calls += 1;
        if (self.calls > self.stop_after) {
            status_ptr.* = self.stop_status;
            return 0;
        }
        const bytes: [*]u8 = @ptrCast(ptr.?);
        bytes[0] = @intCast(self.calls);
        return 1;
    }

    fn write(
        userdata: ?*anyopaque,
        ptr: ?*const anyopaque,
        _: usize,
        status_ptr: [*c]c.SDL_IOStatus,
    ) callconv(.c) usize {
        const self: *TransferBackend = @ptrCast(@alignCast(userdata.?));
        self.calls += 1;
        if (self.calls > self.stop_after) {
            status_ptr.* = self.stop_status;
            return 0;
        }
        const bytes: [*]const u8 = @ptrCast(ptr.?);
        self.output[self.calls - 1] = bytes[0];
        return 1;
    }
};

test "full transfers aggregate short ready results and stop on zero progress" {
    const std = @import("std");
    var backend = TransferBackend{};
    var interface = std.mem.zeroes(c.SDL_IOStreamInterface);
    interface.version = @sizeOf(c.SDL_IOStreamInterface);
    interface.read = TransferBackend.read;
    interface.write = TransferBackend.write;
    var stream = Stream{
        .handle = c.SDL_OpenIO(&interface, &backend) orelse return error.SdlFailure,
    };
    defer stream.deinit();
    var bytes = [_]u8{ 9, 9, 9, 9 };
    const read = stream.borrow().read_full(&bytes);
    try std.testing.expectEqual(@as(usize, 3), read.count);
    try std.testing.expectEqual(Status.ready, read.status);
    try std.testing.expectEqual(@as(usize, 4), backend.calls);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 9 }, &bytes);
    backend.calls = 0;
    const written = stream.borrow().write_all("abc");
    try std.testing.expectEqual(@as(usize, 3), written.count);
    try std.testing.expectEqual(@as(usize, 3), backend.calls);
    try std.testing.expectEqualStrings("abc", backend.output[0..3]);
    backend.calls = 0;
    backend.stop_after = 1;
    backend.stop_status = c.SDL_IO_STATUS_NOT_READY;
    const blocked = stream.borrow().write_all("abcd");
    try std.testing.expectEqual(@as(usize, 1), blocked.count);
    try std.testing.expectEqual(Status.not_ready, blocked.status);
    try std.testing.expectEqual(@as(usize, 2), backend.calls);
    const empty = stream.borrow().read_full(bytes[0..0]);
    try std.testing.expectEqual(@as(usize, 0), empty.count);
    try std.testing.expectEqual(Status.not_ready, empty.status);
    try std.testing.expectEqual(Status.not_ready, stream.borrow().write_all("").status);
    try std.testing.expectEqual(@as(usize, 2), backend.calls);
}

test "dynamic streams validate options and detach empty storage" {
    const std = @import("std");
    try std.testing.expectError(error.InvalidChunkSize, DynamicStream.init(.{ .chunk_size = 0 }));
    var stream = try DynamicStream.init(.{});
    try std.testing.expectEqual(@as(u64, 0), try stream.borrow().size());
    try std.testing.expectEqual(@as(usize, 0), (try stream.bytes()).len);
    try std.testing.expectEqual(@as(u64, 0), try stream.borrow().seek(100, .start));
    var bytes = try stream.finish();
    defer bytes.deinit();
    try std.testing.expectEqual(@as(usize, 0), bytes.borrow().len);
    try std.testing.expectEqual(@as(?*anyopaque, null), bytes.allocation);
}

test "dynamic storage grows preserves high-water length and transfers ownership" {
    const std = @import("std");
    var stream = try DynamicStream.init(.{ .chunk_size = 16 });
    var consumed = false;
    defer if (!consumed) stream.deinit();
    var payload: [4097]u8 = undefined;
    @memset(&payload, 0x5a);
    try std.testing.expectEqual(@as(usize, 3), stream.borrow().write_all("abc").count);
    try std.testing.expectEqualStrings("abc", try stream.bytes());
    try std.testing.expectEqual(payload.len, stream.borrow().write_all(&payload).count);
    try std.testing.expectEqual(@as(u64, 4100), try stream.borrow().size());
    _ = try stream.borrow().seek(1, .start);
    try std.testing.expectEqual(@as(usize, 1), stream.borrow().write("X").count);
    const snapshot = try stream.bytes();
    try std.testing.expectEqualStrings("aXc", snapshot[0..3]);
    try std.testing.expectEqualSlices(u8, &payload, snapshot[3..]);
    try std.testing.expectEqual(@as(u64, 2), try stream.borrow().position());
    try std.testing.expectEqual(@as(usize, 4100), snapshot.len);
    consumed = true;
    var bytes = try stream.finish();
    defer bytes.deinit();
    try std.testing.expectEqualStrings("aXc", bytes.borrow()[0..3]);
    try std.testing.expectEqualSlices(u8, &payload, bytes.borrow()[3..]);
    var input = try Stream.from_const_memory(bytes.borrow());
    defer input.deinit();
    var prefix: [3]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 3), input.borrow().read_full(&prefix).count);
    try std.testing.expectEqualStrings("aXc", &prefix);
}

test "dynamic stream cleanup retains no caller storage" {
    const std = @import("std");
    var source = [_]u8{ 1, 2, 3 };
    var stream = try DynamicStream.init(.{ .chunk_size = 1 });
    try std.testing.expectEqual(@as(usize, 3), stream.borrow().write_all(&source).count);
    source[0] = 9;
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, try stream.bytes());
    stream.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 9, 2, 3 }, &source);
}

test "typed callbacks forward slices positions flush and close exactly once" {
    const std = @import("std");
    const Backend = struct {
        /// Underlying memory stream, owned until callback close.
        inner: Stream,
        /// Number of close callbacks observed.
        closes: u32 = 0,
        fn size(self: *@This()) anyerror!u64 {
            return self.inner.borrow().size();
        }
        fn seek(self: *@This(), offset: i64, origin: SeekOrigin) anyerror!u64 {
            return self.inner.borrow().seek(offset, origin);
        }
        fn read(self: *@This(), bytes: []u8) anyerror!Transfer {
            return self.inner.borrow().read(bytes);
        }
        fn write(self: *@This(), bytes: []const u8) anyerror!Transfer {
            return self.inner.borrow().write(bytes);
        }
        fn flush(self: *@This()) anyerror!Status {
            try self.inner.borrow().flush();
            return .ready;
        }
        fn close(self: *@This()) anyerror!void {
            self.closes += 1;
            try self.inner.close();
        }
    };
    var storage: [3]u8 = undefined;
    var backend = Backend{ .inner = try Stream.from_memory(&storage) };
    var stream = Stream.from_callbacks(Backend, &backend, .{
        .size = Backend.size,
        .seek = Backend.seek,
        .read = Backend.read,
        .write = Backend.write,
        .flush = Backend.flush,
        .close = Backend.close,
    }) catch |err| {
        backend.inner.deinit();
        return err;
    };
    var closed = false;
    defer if (!closed) stream.deinit();
    try std.testing.expectEqual(@as(u64, 3), try stream.borrow().size());
    const written = stream.borrow().write_all("abcd");
    try std.testing.expectEqual(@as(usize, 3), written.count);
    try std.testing.expectEqual(Status.failure, written.status);
    try stream.borrow().flush();
    try std.testing.expectEqual(@as(u64, 3), try stream.borrow().position());
    _ = try stream.borrow().seek(-2, .end);
    _ = try stream.borrow().seek(-1, .current);
    var buffer: [4]u8 = undefined;
    const read = stream.borrow().read_full(&buffer);
    try std.testing.expectEqualStrings("abc", buffer[0..read.count]);
    try std.testing.expectEqual(Status.end_of_stream, read.status);
    closed = true;
    try stream.close();
    try std.testing.expectEqual(@as(u32, 1), backend.closes);
}

test "callback errors invalid counts and overflowing positions become native failures" {
    const std = @import("std");
    const Backend = struct {
        /// Calls observed despite a close error.
        closes: u32 = 0,
        /// Controls flush error versus temporary unavailability.
        fail_flush: bool = false,
        fn size(_: *@This()) anyerror!u64 {
            return std.math.maxInt(u64);
        }
        fn seek(_: *@This(), _: i64, _: SeekOrigin) anyerror!u64 {
            return error.SeekDenied;
        }
        fn read(_: *@This(), bytes: []u8) anyerror!Transfer {
            return .{ .count = bytes.len + 1, .status = .ready };
        }
        fn write(_: *@This(), _: []const u8) anyerror!Transfer {
            return error.WriteDenied;
        }
        fn flush(self: *@This()) anyerror!Status {
            if (self.fail_flush) return error.FlushDenied;
            return .not_ready;
        }
        fn close(self: *@This()) anyerror!void {
            self.closes += 1;
            return error.CloseDenied;
        }
    };
    var backend = Backend{};
    var stream = try Stream.from_callbacks(Backend, &backend, .{
        .size = Backend.size,
        .seek = Backend.seek,
        .read = Backend.read,
        .write = Backend.write,
        .flush = Backend.flush,
        .close = Backend.close,
    });
    var closed = false;
    defer if (!closed) stream.deinit();
    try std.testing.expectError(error.SdlFailure, stream.borrow().size());
    try std.testing.expectEqualStrings(
        "Zig stream callback: PositionOverflow",
        @import("errors.zig").message(),
    );
    try std.testing.expectError(error.SdlFailure, stream.borrow().seek(0, .start));
    var bytes = [_]u8{ 9, 9 };
    const read = stream.borrow().read(&bytes);
    try std.testing.expectEqual(@as(usize, 0), read.count);
    try std.testing.expectEqual(Status.failure, read.status);
    const written = stream.borrow().write("x");
    try std.testing.expectEqual(@as(usize, 0), written.count);
    try std.testing.expectEqual(Status.failure, written.status);
    try std.testing.expectEqualStrings(
        "Zig stream callback: WriteDenied",
        @import("errors.zig").message(),
    );
    try std.testing.expectError(error.SdlFailure, stream.borrow().flush());
    try std.testing.expectEqual(Status.not_ready, stream.borrow().status());
    backend.fail_flush = true;
    try std.testing.expectError(error.SdlFailure, stream.borrow().flush());
    try std.testing.expectEqual(Status.failure, stream.borrow().status());
    closed = true;
    try std.testing.expectError(error.SdlFailure, stream.close());
    try std.testing.expectEqual(@as(u32, 1), backend.closes);
    try std.testing.expectEqualStrings(
        "Zig stream callback: CloseDenied",
        @import("errors.zig").message(),
    );
}

test "absent callbacks preserve native unsupported semantics" {
    const std = @import("std");
    var backend: u8 = 0;
    var stream = try Stream.from_callbacks(u8, &backend, .{});
    defer stream.deinit();
    try std.testing.expectError(error.SdlFailure, stream.borrow().size());
    try std.testing.expectError(error.SdlFailure, stream.borrow().seek(0, .start));
    var byte: [1]u8 = undefined;
    try std.testing.expectEqual(Status.write_only, stream.borrow().read(&byte).status);
    try std.testing.expectEqual(Status.read_only, stream.borrow().write("x").status);
    try stream.borrow().flush();
    try std.testing.expectEqual(@as(u8, 0), backend);
}
