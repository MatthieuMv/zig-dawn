//! Bootstrap inventory of translated declarations, not a complete header audit.
const std = @import("std");
const c = @import("sdl_abi");
const manifest = @import("manifest.zig");

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var output: std.Io.File.Writer = .init(.stdout(), init.io, &buffer);
    try output.interface.writeAll("symbol\tstatus\tzig_api\tdocumentation\n");
    for (symbols) |name| {
        const entry = manifest.lookup(name);
        try output.interface.print("{s}\t{s}\t{s}\t{s}\n", .{
            name,
            if (entry) |value| @tagName(value.status) else "pending",
            if (entry) |value| value.api else "",
            if (entry) |value| value.documentation else "",
        });
    }
    try output.interface.flush();
}

const symbols = blk: {
    @setEvalBranchQuota(1_000_000);
    const declarations = @typeInfo(c).@"struct".decl_names;
    var names: [declarations.len][]const u8 = undefined;
    var count: usize = 0;
    for (declarations) |name| {
        if (std.mem.startsWith(u8, name, "SDL_") or
            std.mem.startsWith(u8, name, "SDLK_") or
            std.mem.startsWith(u8, name, "IMG_") or
            std.mem.startsWith(u8, name, "MIX_") or
            std.mem.startsWith(u8, name, "TTF_"))
        {
            names[count] = name;
            count += 1;
        }
    }
    for (manifest.entries) |entry| {
        if (!@import("libraries").enabled[@backingInt(entry.library)]) continue;
        if (!@hasDecl(c, entry.native)) @compileError("missing mapped symbol: " ++ entry.native);
    }
    break :blk names[0..count].*;
};
