//! Typed SDL property groups with explicit ownership and optional values instead of defaults.
//! No subsystem initialization is required. Native storage/locking may allocate or block.
//! Destroy groups before global SDL_Quit. Borrowed strings need synchronization across threads.
const std = @import("std");
const c = @import("sdl_abi");

/// Native failures and validation errors. Validation leaves SDL diagnostic text unchanged.
pub const Error = @import("errors.zig").Error || error{
    /// Names must be nonempty sentinel strings without embedded NUL bytes.
    InvalidName,
    /// String values cannot contain embedded NUL bytes; empty strings are allowed.
    InvalidString,
    /// A future native property kind is not represented by this wrapper.
    UnsupportedType,
    /// Name descriptors or name bytes cannot hold the entire snapshot.
    BufferTooSmall,
    /// The total number/byte length of names exceeds addressable memory.
    SizeOverflow,
};

/// Exact stored type; scalar values copy, pointer/string getters borrow their targets.
/// When setting, SDL copies a string before return. When getting, the returned string points into
/// the group and expires on replacement, clearing, destruction, or global SDL shutdown.
pub const Value = union(enum) {
    /// Boolean value, distinct from numeric zero/one.
    boolean: bool,
    /// Signed 64-bit integer, without floating-point conversion.
    number: i64,
    /// Native 32-bit float, including nonfinite values.
    float: f32,
    /// Sentinel string. Setter copies it; getter borrows it. Never free a getter's result.
    string: [:0]const u8,
    /// Nonnull pointer. Ordinary set borrows it; get also borrows cleanup-owned targets.
    pointer: *anyopaque,
};

/// Borrow process-global properties on any thread. Never destroy the returned group.
/// It lives until SDL_Quit; all views/locks must finish first. May allocate/block on first access.
/// `SdlFailure` reports native failure. Use application-specific names; native keys keep their
/// native contracts and are not made writable by this view.
pub fn global() Error!PropertiesRef {
    const handle = c.SDL_GetGlobalProperties();
    if (handle == 0) return error.SdlFailure;
    return .{ .handle = handle };
}

/// Owns a property group. Do not copy. Views/locks/borrowed strings cannot outlive this owner.
pub const Properties = struct {
    /// Native ID for interop. Never destroy separately or use after owner/global shutdown.
    handle: c.SDL_PropertiesID,

    /// Create an empty native group on any thread. May allocate; `SdlFailure` returns no owner.
    /// No initialization needed. Destroy before SDL_Quit, with no locks or active users remaining.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var properties = try sdl.properties.Properties.init();
    /// defer properties.deinit();
    /// const values = properties.borrow();
    /// try values.set("title", &.{ .string = "My window" });
    /// try values.set("width", &.{ .number = 640 });
    /// const width = (try values.get("width")).?;
    /// try @import("std").testing.expectEqual(@as(i64, 640), width.number);
    /// try @import("std").testing.expect((try values.get("missing")) == null);
    /// ```
    pub fn init() Error!Properties {
        const handle = c.SDL_CreateProperties();
        if (handle == 0) return error.SdlFailure;
        return .{ .handle = handle };
    }

    /// Destroy exactly once, on any thread with exclusive access and no outstanding locks.
    /// Invalidates views/strings. Owned-pointer cleanups run; ordinary pointer targets remain.
    /// Cleanup callbacks may run; no fallible result.
    pub fn deinit(self: *Properties) void {
        c.SDL_DestroyProperties(self.handle);
        self.* = undefined;
    }

    /// Borrow without allocation/native calls. Owner must outlive the view and any lock it creates.
    pub fn borrow(self: *const Properties) PropertiesRef {
        return .{ .handle = self.handle };
    }
};

/// Non-owning group view. Operations can run on any thread while the owner remains alive.
/// String/pointer targets require lifetime coordination beyond individual getter calls.
pub const PropertiesRef = struct {
    /// Valid live native property group ID. Never destroy through this borrowed view.
    handle: c.SDL_PropertiesID,

    /// Set/replace an exact typed value. Names are borrowed only for the call; SDL copies names
    /// and string values. Pointer targets remain caller-owned. May allocate/block.
    /// `InvalidName`/`InvalidString` precede mutation. `SdlFailure` does not guarantee rollback;
    /// native interop cleanup on the previous value may run. Clear explicitly to remove a key.
    pub fn set(self: PropertiesRef, name: [:0]const u8, value: *const Value) Error!void {
        try validate_name(name);
        const success = switch (value.*) {
            .boolean => |v| c.SDL_SetBooleanProperty(self.handle, name.ptr, v),
            .number => |v| c.SDL_SetNumberProperty(self.handle, name.ptr, v),
            .float => |v| c.SDL_SetFloatProperty(self.handle, name.ptr, v),
            .pointer => |v| c.SDL_SetPointerProperty(self.handle, name.ptr, v),
            .string => |v| string: {
                if (std.mem.indexOfScalar(u8, v, 0) != null) return error.InvalidString;
                break :string c.SDL_SetStringProperty(self.handle, name.ptr, v.ptr);
            },
        };
        if (!success) return error.SdlFailure;
    }

    /// Read the exact stored type, or null if absent. No implicit conversions/defaults.
    /// Locks across type/value queries; may block. Scalars copy; strings borrow group storage.
    /// Keep an outer `lock` alive while using a string if other threads may mutate the group.
    /// The internal lock is released before return. Pointer pointees require their own lifetime
    /// coordination. Errors: `InvalidName`, `SdlFailure` (invalid/unlockable group),
    /// `UnsupportedType` for future native types.
    pub fn get(self: PropertiesRef, name: [:0]const u8) Error!?Value {
        try validate_name(name);
        var guard = try self.lock();
        defer guard.deinit();
        const value: Value = switch (c.SDL_GetPropertyType(self.handle, name.ptr)) {
            c.SDL_PROPERTY_TYPE_INVALID => return null,
            c.SDL_PROPERTY_TYPE_BOOLEAN => .{
                .boolean = c.SDL_GetBooleanProperty(self.handle, name.ptr, false),
            },
            c.SDL_PROPERTY_TYPE_NUMBER => .{
                .number = c.SDL_GetNumberProperty(self.handle, name.ptr, 0),
            },
            c.SDL_PROPERTY_TYPE_FLOAT => .{
                .float = c.SDL_GetFloatProperty(self.handle, name.ptr, 0),
            },
            c.SDL_PROPERTY_TYPE_POINTER => .{
                .pointer = c.SDL_GetPointerProperty(self.handle, name.ptr, null) orelse
                    return error.SdlFailure,
            },
            c.SDL_PROPERTY_TYPE_STRING => string: {
                const text = c.SDL_GetStringProperty(self.handle, name.ptr, null);
                if (text == null) return error.SdlFailure;
                break :string .{ .string = std.mem.span(text) };
            },
            else => return error.UnsupportedType,
        };
        return value;
    }

    /// Query key existence under a group lock, without reading or converting the value.
    /// May block. `InvalidName` precedes lookup; `SdlFailure` reports an invalid/unlockable group.
    pub fn contains(self: PropertiesRef, name: [:0]const u8) Error!bool {
        try validate_name(name);
        var guard = try self.lock();
        defer guard.deinit();
        return c.SDL_HasProperty(self.handle, name.ptr);
    }

    /// Remove a key; an absent key succeeds. Invalidates any borrowed string for that key.
    /// `InvalidName` precedes mutation; `SdlFailure` reports native failure. May block or invoke
    /// installed pointer cleanup callbacks.
    pub fn clear(self: PropertiesRef, name: [:0]const u8) Error!void {
        try validate_name(name);
        if (!c.SDL_ClearProperty(self.handle, name.ptr)) return error.SdlFailure;
    }

    /// Transfer a typed pointer and its cleanup obligation into this group. Consumes the value
    /// on EVERY outcome: validation/native failure calls cleanup immediately, success installs it
    /// for replacement, clear, or group destruction. Never clean it up again after this call.
    /// The target must stay at its address until cleanup and must not already be owned by a key.
    /// Native names/state may allocate; the wrapper allocates no adapter storage. Cleanup code
    /// must remain loaded, release resources even on adverse conditions, and not panic or reenter
    /// the same group. It can run on the mutating/destroying thread, with or without native locks.
    /// Getter pointers are borrowed; copy_to skips cleanup-owned properties. Store any cleanup
    /// context inside T. Cleanup can change diagnostics; InvalidName precedes group mutation.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// const Resource = struct {
    ///     released: bool = false,
    ///     fn cleanup(self: *@This()) void { self.released = true; }
    /// };
    /// var value = Resource{};
    /// var properties = try sdl.properties.Properties.init();
    /// defer properties.deinit();
    /// try properties.borrow().set_owned_pointer("resource", Resource, &value, Resource.cleanup);
    /// try properties.borrow().clear("resource");
    /// try @import("std").testing.expect(value.released);
    /// ```
    pub fn set_owned_pointer(
        self: PropertiesRef,
        name: [:0]const u8,
        comptime T: type,
        value: *T,
        comptime cleanup: *const fn (*T) void,
    ) Error!void {
        validate_name(name) catch |err| {
            cleanup(value);
            return err;
        };
        const Adapter = struct {
            fn release(_: ?*anyopaque, pointer: ?*anyopaque) callconv(.c) void {
                cleanup(@ptrCast(@alignCast(pointer.?)));
            }
        };
        if (!c.SDL_SetPointerPropertyWithCleanup(
            self.handle,
            name.ptr,
            value,
            Adapter.release,
            null,
        )) return error.SdlFailure;
    }

    /// Visit each property name in unspecified order while SDL holds the group lock. Any thread;
    /// lookups are allowed, but callbacks must not mutate/destroy this group or acquire conflicting
    /// group locks. Names borrow native storage only for the callback; retain copies if needed.
    /// Context is borrowed synchronously; no adapter allocation. Callback errors propagate and
    /// suppress later callback invocations, but native enumeration still traverses remaining keys.
    /// Runtime therefore depends on group size even after failure. Native failure is SdlFailure.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// const View = sdl.properties.PropertiesRef;
    /// const Counter = struct {
    ///     count: usize = 0,
    ///     fn visit(self: *@This(), _: View, _: [:0]const u8) anyerror!void {
    ///         self.count += 1;
    ///     }
    /// };
    /// var properties = try sdl.properties.Properties.init();
    /// defer properties.deinit();
    /// try properties.borrow().set("visible", &.{ .boolean = true });
    /// var counter = Counter{};
    /// try properties.borrow().visit(Counter, &counter, Counter.visit);
    /// try @import("std").testing.expectEqual(@as(usize, 1), counter.count);
    /// ```
    pub fn visit(
        self: PropertiesRef,
        comptime Context: type,
        context: *Context,
        comptime callback: *const fn (*Context, PropertiesRef, [:0]const u8) anyerror!void,
    ) anyerror!void {
        const Adapter = struct {
            /// Borrowed caller state, only used during synchronous enumeration.
            context: *Context,
            /// First callback failure; later user callbacks are skipped.
            failure: ?anyerror = null,

            fn invoke(
                userdata: ?*anyopaque,
                props: c.SDL_PropertiesID,
                name: [*c]const u8,
            ) callconv(.c) void {
                const state: *@This() = @ptrCast(@alignCast(userdata.?));
                if (state.failure != null) return;
                callback(state.context, .{ .handle = props }, std.mem.span(name)) catch |err| {
                    state.failure = err;
                };
            }
        };
        var state = Adapter{ .context = context };
        if (!c.SDL_EnumerateProperties(self.handle, Adapter.invoke, &state))
            return error.SdlFailure;
        if (state.failure) |err| return err;
    }

    /// Copy values into another live group, overwriting matching keys and retaining other keys.
    /// Strings/names are copied; pointer targets remain shared. Native properties with cleanup
    /// callbacks are skipped, leaving any matching destination value unchanged. Self-copy is a
    /// validated no-op. May allocate/block; `SdlFailure` can leave partial destination changes.
    /// Overwritten destination strings expire and native cleanup callbacks may run.
    /// Acquires locks in ID order. Call without other group locks held; native interop/callbacks
    /// must follow compatible lock ordering. Both owners must outlive the call.
    pub fn copy_to(self: PropertiesRef, destination: PropertiesRef) Error!void {
        var first = try (PropertiesRef{ .handle = @min(self.handle, destination.handle) }).lock();
        defer first.deinit();
        if (self.handle == destination.handle) return;
        var second = try (PropertiesRef{ .handle = @max(self.handle, destination.handle) }).lock();
        defer second.deinit();
        if (!c.SDL_CopyProperties(self.handle, destination.handle)) return error.SdlFailure;
    }

    /// Snapshot property NAMES into caller storage, in unspecified order. Values are not copied.
    /// `names` holds descriptors; `bytes` holds names plus one NUL byte each. Returned descriptors
    /// borrow `bytes`, surviving group mutation/destruction until that storage is reused or freed.
    /// Both buffers must be disjoint from each other and from the group's native storage.
    /// No wrapper allocation; traverses the group twice under one recursive lock (may block).
    /// `BufferTooSmall`/`SizeOverflow` leave buffers untouched. Empty groups accept empty buffers.
    /// `SdlFailure` reports native failure; the second pass may leave partially filled buffers.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var properties = try sdl.properties.Properties.init();
    /// defer properties.deinit();
    /// try properties.borrow().set("width", &.{ .number = 640 });
    /// var names: [1][:0]const u8 = undefined;
    /// var bytes: [6]u8 = undefined; // Five characters and the terminating zero.
    /// const snapshot = try properties.borrow().copy_names(&names, &bytes);
    /// try properties.borrow().clear("width");
    /// try @import("std").testing.expectEqualStrings("width", snapshot[0]);
    /// ```
    pub fn copy_names(
        self: PropertiesRef,
        names: [][:0]const u8,
        bytes: []u8,
    ) Error![][:0]const u8 {
        var guard = try self.lock();
        defer guard.deinit();
        var state = NameCopy{};
        if (!c.SDL_EnumerateProperties(self.handle, collect_name, &state)) return error.SdlFailure;
        if (state.overflow) return error.SizeOverflow;
        if (state.count > names.len or state.used > bytes.len) return error.BufferTooSmall;
        state = .{ .names = names, .bytes = bytes, .copy = true };
        if (!c.SDL_EnumerateProperties(self.handle, collect_name, &state)) return error.SdlFailure;
        return names[0..state.count];
    }

    /// Acquire a recursive native lock for compound operations or borrowed string use.
    /// Any thread; may block. `SdlFailure` returns no guard. Release on the acquiring thread
    /// before destroying the owner. Group getters/setters can run while this guard is held.
    ///
    /// ```zig
    /// const sdl = @import("sdl");
    /// var properties = try sdl.properties.Properties.init();
    /// defer properties.deinit();
    /// const values = properties.borrow();
    /// var guard = try values.lock();
    /// defer guard.deinit();
    /// try values.set("label", &.{ .string = "ready" });
    /// const value = (try values.get("label")).?;
    /// // Consume the borrowed string before releasing the lock or replacing the value.
    /// try @import("std").testing.expectEqualStrings("ready", value.string);
    /// ```
    pub fn lock(self: PropertiesRef) Error!Lock {
        if (!c.SDL_LockProperties(self.handle)) return error.SdlFailure;
        return .{ .handle = self.handle };
    }
};

/// Owns one recursive lock acquisition, not the property group. Do not copy or transfer threads.
/// Other threads cannot mutate this group until all its locks are released. Same-thread mutation
/// can still invalidate borrowed values. Pointer targets are not protected by the group mutex.
pub const Lock = struct {
    /// Locked group ID. Do not unlock separately or destroy while this guard is live.
    handle: c.SDL_PropertiesID,

    /// Unlock exactly once on the acquiring thread. Owner must still be alive. No fallible result.
    pub fn deinit(self: *Lock) void {
        c.SDL_UnlockProperties(self.handle);
        self.* = undefined;
    }
};

const NameCopy = struct {
    /// Descriptor output, used only during the second pass.
    names: [][:0]const u8 = &.{},
    /// Name-byte output, used only during the second pass.
    bytes: []u8 = &.{},
    /// Number of names visited in this pass.
    count: usize = 0,
    /// Total bytes, including terminators, visited in this pass.
    used: usize = 0,
    /// True after capacities were validated under the group lock.
    copy: bool = false,
    /// Stops counting after checked arithmetic fails; native traversal still finishes.
    overflow: bool = false,
};

fn collect_name(
    userdata: ?*anyopaque,
    _: c.SDL_PropertiesID,
    name: [*c]const u8,
) callconv(.c) void {
    const state: *NameCopy = @ptrCast(@alignCast(userdata.?));
    if (state.overflow) return;
    const text = std.mem.span(name);
    const length = std.math.add(usize, text.len, 1) catch {
        state.overflow = true;
        return;
    };
    const used = std.math.add(usize, state.used, length) catch {
        state.overflow = true;
        return;
    };
    const count = std.math.add(usize, state.count, 1) catch {
        state.overflow = true;
        return;
    };
    if (state.copy) {
        // The outer lock keeps names stable; caller buffers cannot alias native storage.
        const end = used - 1;
        @memcpy(state.bytes[state.used..end], text);
        state.bytes[end] = 0;
        state.names[state.count] = state.bytes[state.used..end :0];
    }
    state.count = count;
    state.used = used;
}

fn validate_name(name: [:0]const u8) Error!void {
    if (name.len == 0 or std.mem.indexOfScalar(u8, name, 0) != null) return error.InvalidName;
}

test "exact values, replacement, absence, and independent groups" {
    var properties = try Properties.init();
    defer properties.deinit();
    var other = try Properties.init();
    defer other.deinit();
    const values = properties.borrow();
    try std.testing.expect((try values.get("missing")) == null);
    try std.testing.expect(!try values.contains("missing"));
    try values.clear("missing");
    try values.set("key", &.{ .boolean = false });
    try std.testing.expect(try values.contains("key"));
    try std.testing.expectEqual(false, (try values.get("key")).?.boolean);
    try std.testing.expect((try other.borrow().get("key")) == null);
    for ([_]i64{ std.math.minInt(i64), 0, std.math.maxInt(i64) }) |number| {
        try values.set("key", &.{ .number = number });
        try std.testing.expectEqual(number, (try values.get("key")).?.number);
    }
    try values.set("key", &.{ .float = 1.25 });
    try std.testing.expectEqual(@as(f32, 1.25), (try values.get("key")).?.float);
    try values.set("key", &.{ .float = std.math.nan(f32) });
    try std.testing.expect(std.math.isNan((try values.get("key")).?.float));
    try values.clear("key");
    try std.testing.expect((try values.get("key")) == null);
}

test "strings copy on set, pointers borrow, and recursive locks protect reads" {
    var target: u32 = 42;
    {
        var properties = try Properties.init();
        defer properties.deinit();
        const values = properties.borrow();
        var guard = try values.lock();
        defer guard.deinit();
        var text: [3:0]u8 = .{ 'a', 'b', 'c' };
        var name: [3:0]u8 = .{ 'k', 'e', 'y' };
        try values.set(&name, &.{ .string = &text });
        text[0] = 'x';
        name[0] = 'x';
        try std.testing.expectEqualStrings("abc", (try values.get("key")).?.string);
        try values.set("key", &.{ .string = "" });
        try std.testing.expectEqualStrings("", (try values.get("key")).?.string);
        try values.set("pointer", &.{ .pointer = &target });
        const result: *u32 = @ptrCast(@alignCast((try values.get("pointer")).?.pointer));
        try std.testing.expect(result == &target);
        result.* = 99;
        try values.clear("pointer");
    }
    try std.testing.expectEqual(@as(u32, 99), target);
}

test "invalid names and strings are rejected before mutation" {
    var properties = try Properties.init();
    defer properties.deinit();
    const values = properties.borrow();
    try values.set("key", &.{ .number = 7 });
    try std.testing.expectError(error.InvalidName, values.set("", &.{ .number = 1 }));
    try std.testing.expectError(error.InvalidName, values.set("key\x00suffix", &.{ .number = 1 }));
    try std.testing.expectError(error.InvalidName, values.get(""));
    try std.testing.expectError(error.InvalidName, values.clear("key\x00suffix"));
    try std.testing.expectError(error.InvalidName, values.contains(""));
    try std.testing.expectError(error.InvalidString, values.set("key", &.{ .string = "a\x00b" }));
    try std.testing.expectEqual(@as(i64, 7), (try values.get("key")).?.number);
    const invalid = PropertiesRef{ .handle = 0 };
    try std.testing.expectError(error.SdlFailure, invalid.get("key"));
    try std.testing.expectError(error.SdlFailure, invalid.contains("key"));
    try std.testing.expectError(error.SdlFailure, invalid.set("key", &.{ .number = 1 }));
    try std.testing.expectError(error.SdlFailure, invalid.clear("key"));
}

test "name snapshots use exact capacity and survive source destruction" {
    var names: [2][:0]const u8 = undefined;
    var bytes: [9]u8 = undefined;
    const snapshot = copied: {
        var properties = try Properties.init();
        defer properties.deinit();
        try std.testing.expectEqual(
            @as(usize, 0),
            (try properties.borrow().copy_names(&.{}, &.{})).len,
        );
        try properties.borrow().set("alpha", &.{ .number = 1 });
        try properties.borrow().set("é", &.{ .boolean = true });
        const result = try properties.borrow().copy_names(&names, &bytes);
        try properties.borrow().clear("alpha");
        break :copied result;
    };
    try std.testing.expectEqual(@as(usize, 2), snapshot.len);
    var found_alpha = false;
    var found_unicode = false;
    for (snapshot) |name| {
        if (std.mem.eql(u8, name, "alpha")) found_alpha = true;
        if (std.mem.eql(u8, name, "é")) found_unicode = true;
        try std.testing.expectEqual(@as(u8, 0), name[name.len]);
    }
    try std.testing.expect(found_alpha and found_unicode);
}

test "name snapshot capacity failures preserve both caller buffers" {
    var properties = try Properties.init();
    defer properties.deinit();
    try properties.borrow().set("name", &.{ .number = 1 });
    var names = [_][:0]const u8{"untouched"};
    var bytes = [_]u8{ 1, 2, 3, 4, 5 };
    try std.testing.expectError(
        error.BufferTooSmall,
        properties.borrow().copy_names(&names, bytes[0..4]),
    );
    try std.testing.expectEqualStrings("untouched", names[0]);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, &bytes);
    try std.testing.expectError(
        error.BufferTooSmall,
        properties.borrow().copy_names(names[0..0], &bytes),
    );
    try std.testing.expectEqualStrings("untouched", names[0]);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5 }, &bytes);
    const invalid = PropertiesRef{ .handle = 0 };
    try std.testing.expectError(error.SdlFailure, invalid.copy_names(&names, &bytes));
    try std.testing.expectEqualStrings(
        "name",
        (try properties.borrow().copy_names(&names, &bytes))[0],
    );
}

test "copy merges deep strings and shallow pointers but skips cleanup properties" {
    const Callback = struct {
        fn cleanup(userdata: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
            const count: *u32 = @ptrCast(@alignCast(userdata.?));
            count.* += 1;
        }
    };
    var destination = try Properties.init();
    defer destination.deinit();
    const dst = destination.borrow();
    try dst.set("text", &.{ .string = "old" });
    try dst.set("retained", &.{ .number = 5 });
    try dst.set("cleanup", &.{ .number = 99 });
    var target: u32 = 42;
    var cleanups: u32 = 0;
    try std.testing.expect(c.SDL_SetPointerPropertyWithCleanup(
        destination.handle,
        "text",
        &target,
        Callback.cleanup,
        &cleanups,
    ));
    {
        var source = try Properties.init();
        defer source.deinit();
        const src = source.borrow();
        try src.set("text", &.{ .string = "new" });
        try src.set("pointer", &.{ .pointer = &target });
        try std.testing.expect(c.SDL_SetPointerPropertyWithCleanup(
            source.handle,
            "cleanup",
            &target,
            Callback.cleanup,
            &cleanups,
        ));
        const before = (try src.get("text")).?.string;
        try src.copy_to(src);
        try std.testing.expect(before.ptr == (try src.get("text")).?.string.ptr);
        try src.copy_to(dst);
        try std.testing.expectEqual(@as(u32, 1), cleanups);
        try src.set("text", &.{ .string = "changed" });
        try std.testing.expectError(error.SdlFailure, src.copy_to(.{ .handle = 0 }));
    }
    try std.testing.expectEqual(@as(u32, 2), cleanups);
    try std.testing.expectEqualStrings("new", (try dst.get("text")).?.string);
    try std.testing.expectEqual(@as(i64, 5), (try dst.get("retained")).?.number);
    try std.testing.expectEqual(@as(i64, 99), (try dst.get("cleanup")).?.number);
    try std.testing.expect((try dst.get("pointer")).?.pointer == @as(*anyopaque, &target));
}

test "global access borrows one shared process group" {
    const first = try global();
    const second = try global();
    try std.testing.expectEqual(first.handle, second.handle);
    try first.set("zig-sdl3.test.global", &.{ .number = 42 });
    defer first.clear("zig-sdl3.test.global") catch {};
    try std.testing.expectEqual(@as(i64, 42), (try second.get("zig-sdl3.test.global")).?.number);
}

test "owned pointers clean up exactly once on replacement clear destruction and rejection" {
    const Resource = struct {
        /// Test resource-release notifications, remaining alive until cleanup.
        count: *u32,
        fn cleanup(self: *@This()) void {
            self.count.* += 1;
        }
    };
    var releases: u32 = 0;
    var resources = [_]Resource{
        .{ .count = &releases }, .{ .count = &releases }, .{ .count = &releases },
        .{ .count = &releases }, .{ .count = &releases },
    };
    {
        var properties = try Properties.init();
        defer properties.deinit();
        const view = properties.borrow();
        try view.set_owned_pointer("resource", Resource, &resources[0], Resource.cleanup);
        try std.testing.expectEqual(@as(u32, 0), releases);
        try std.testing.expectEqual(
            @as(*anyopaque, &resources[0]),
            (try view.get("resource")).?.pointer,
        );
        try view.set_owned_pointer("resource", Resource, &resources[1], Resource.cleanup);
        try std.testing.expectEqual(@as(u32, 1), releases);
        try view.clear("resource");
        try std.testing.expectEqual(@as(u32, 2), releases);
        try view.set_owned_pointer("resource", Resource, &resources[2], Resource.cleanup);
        var copied = try Properties.init();
        defer copied.deinit();
        try view.copy_to(copied.borrow());
        try std.testing.expect((try copied.borrow().get("resource")) == null);
        try std.testing.expectError(
            error.InvalidName,
            view.set_owned_pointer("", Resource, &resources[3], Resource.cleanup),
        );
        try std.testing.expectEqual(@as(u32, 3), releases);
        try std.testing.expectError(
            error.SdlFailure,
            (PropertiesRef{ .handle = 0 }).set_owned_pointer(
                "resource",
                Resource,
                &resources[4],
                Resource.cleanup,
            ),
        );
        try std.testing.expectEqual(@as(u32, 4), releases);
    }
    try std.testing.expectEqual(@as(u32, 5), releases);
}

test "typed visitors allow lookups and propagate failures without later callbacks" {
    const Visitor = struct {
        /// Number of observed names.
        count: u32 = 0,
        /// Whether to stop accepting names with a callback error.
        fail: bool = false,
        fn invoke(self: *@This(), view: PropertiesRef, name: [:0]const u8) anyerror!void {
            self.count += 1;
            try std.testing.expect(try view.contains(name));
            try std.testing.expect((try view.get(name)) != null);
            if (self.fail) return error.VisitorStopped;
        }
    };
    var properties = try Properties.init();
    defer properties.deinit();
    var visitor = Visitor{};
    try properties.borrow().visit(Visitor, &visitor, Visitor.invoke);
    try std.testing.expectEqual(@as(u32, 0), visitor.count);
    try properties.borrow().set("a", &.{ .boolean = true });
    try properties.borrow().set("é", &.{ .number = 2 });
    try properties.borrow().visit(Visitor, &visitor, Visitor.invoke);
    try std.testing.expectEqual(@as(u32, 2), visitor.count);
    visitor = .{ .fail = true };
    try std.testing.expectError(
        error.VisitorStopped,
        properties.borrow().visit(Visitor, &visitor, Visitor.invoke),
    );
    try std.testing.expectEqual(@as(u32, 1), visitor.count);
    try properties.borrow().set("after", &.{ .number = 3 });
    try std.testing.expectError(
        error.SdlFailure,
        (PropertiesRef{ .handle = 0 }).visit(Visitor, &visitor, Visitor.invoke),
    );
    try std.testing.expectEqual(@as(u32, 1), visitor.count);
}
