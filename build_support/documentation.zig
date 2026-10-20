//! Build-time documentation checks and extraction of executable hover examples.
const std = @import("std");
const manifest = @import("../tools/coverage/manifest.zig");

pub const Source = struct { path: []const u8, text: [:0]const u8, report: bool = true, module: []const u8 = "sdl" };
pub const sources = [_]Source{
    .{ .path = "src/core/pixels.zig", .text = @embedFile("../src/core/pixels.zig") },
    .{ .path = "src/core/display.zig", .text = @embedFile("../src/core/display.zig") },
    .{ .path = "src/core/properties.zig", .text = @embedFile("../src/core/properties.zig") },
    .{ .path = "src/core/io.zig", .text = @embedFile("../src/core/io.zig") },
    .{ .path = "src/core/surface.zig", .text = @embedFile("../src/core/surface.zig") },
    .{ .path = "src/sdl.zig", .text = @embedFile("../src/sdl.zig") },
    .{ .path = "src/image.zig", .module = "sdl_image", .text = @embedFile("../src/image.zig") },
    .{ .path = "src/mixer.zig", .module = "sdl_mixer", .text = @embedFile("../src/mixer.zig") },
    .{ .path = "src/ttf.zig", .module = "sdl_ttf", .text = @embedFile("../src/ttf.zig") },
    .{ .path = "src/core/init.zig", .text = @embedFile("../src/core/init.zig") },
    .{ .path = "src/core/errors.zig", .text = @embedFile("../src/core/errors.zig") },
    .{ .path = "src/core/video.zig", .text = @embedFile("../src/core/video.zig") },
    .{ .path = "src/core/render.zig", .text = @embedFile("../src/core/render.zig") },
    .{ .path = "src/core/events.zig", .text = @embedFile("../src/core/events.zig") },
};

pub fn add_checks(
    b: *std.Build,
    core: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    check: *std.Build.Step,
) void {
    var examples: std.Io.Writer.Allocating = .init(b.allocator);
    for (sources) |source| {
        validate_source(b.allocator, source) catch |err| {
            std.debug.panic("documentation check: {s}: {t}", .{ source.path, err });
        };
        if (b.modules.get(source.module) != null) {
            append_examples(&examples.writer, source) catch @panic("invalid doc example or OOM");
        }
    }
    for (manifest.entries) |entry| {
        if (!registered(entry.documentation)) {
            std.debug.panic("unregistered documentation for {s}", .{entry.native});
        }
    }
    const generated = b.addWriteFiles().add("doc_examples.zig", examples.written());
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = generated,
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "sdl", .module = core }},
    }) });
    for (sources) |source| {
        if (b.modules.get(source.module)) |module| tests.root_module.addImport(source.module, module);
    }
    if (b.modules.get("sdl_ttf") != null or b.modules.get("sdl_mixer") != null) {
        const assets = b.addOptions();
        assets.addOptionPath("font_path", b.path("tests/fixtures/box.ttf"));
        assets.addOptionPath("audio_path", b.path("tests/fixtures/tone.wav"));
        tests.root_module.addOptions("example_assets", assets);
    }
    check.dependOn(&tests.step);
    const run = b.addRunArtifact(tests);
    run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    const step = b.step("test-docs", "Check documentation tooling and run exact hover examples");
    step.dependOn(&run.step);
    const tooling = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("build.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    }) });
    step.dependOn(&b.addRunArtifact(tooling).step);
}

fn validate_source(allocator: std.mem.Allocator, source: Source) !void {
    var tree = try std.zig.Ast.parse(allocator, source.text, .{});
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) return error.InvalidSource;
    if (tree.tokenTag(0) != .container_doc_comment) return error.MissingModuleDocumentation;
    for (tree.tokens.items(.tag), 0..) |tag, index| {
        const token: std.zig.Ast.TokenIndex = @intCast(index);
        if (tag == .keyword_pub) try require_doc(&tree, source.path, token, source.report);
        if (tag == .builtin and std.mem.eql(u8, tree.tokenSlice(token), "@import")) {
            try validate_import(allocator, &tree, source.path, token, source.report);
        }
    }
    for (0..tree.nodes.len) |index| {
        const node: std.zig.Ast.Node.Index = @fromBackingInt(@intCast(index));
        if (tree.fullContainerField(node)) |field| {
            const token = field.firstToken();
            if (std.mem.eql(u8, tree.tokenSlice(token), "_")) continue;
            try require_doc(&tree, source.path, token, source.report);
        }
    }
}

fn require_doc(
    tree: *const std.zig.Ast,
    path: []const u8,
    token: std.zig.Ast.TokenIndex,
    report: bool,
) !void {
    var preceding = token;
    while (preceding > 0) {
        preceding -= 1;
        if (tree.tokenTag(preceding) != .doc_comment) break;
        const comment = tree.tokenSlice(preceding);
        if (std.mem.trim(u8, comment[3..], " \t\r\n").len > 0) return;
    }
    const location = tree.tokenLocation(0, token);
    if (report) std.debug.print(
        "{s}:{d}: missing /// documentation for {s}\n",
        .{ path, location.line + 1, tree.tokenSlice(token) },
    );
    return error.MissingDeclarationDocumentation;
}

fn validate_import(
    allocator: std.mem.Allocator,
    tree: *const std.zig.Ast,
    path: []const u8,
    token: std.zig.Ast.TokenIndex,
    report: bool,
) !void {
    if (tree.tokenTag(token + 2) != .string_literal) return error.NonLiteralImport;
    const import = try std.zig.string_literal.parseAlloc(allocator, tree.tokenSlice(token + 2));
    defer allocator.free(import);
    if (!std.mem.endsWith(u8, import, ".zig")) return;
    const resolved = try std.fs.path.resolve(
        allocator,
        &.{ "/", std.fs.path.dirname(path).?, import },
    );
    defer allocator.free(resolved);
    for (sources) |source| {
        const candidate = try std.fs.path.resolve(allocator, &.{ "/", source.path });
        defer allocator.free(candidate);
        if (std.mem.eql(u8, candidate, resolved)) return;
    }
    if (report) std.debug.print(
        "{s}: register imported source {s} in documentation.sources\n",
        .{ path, import },
    );
    return error.UnregisteredSource;
}

fn registered(path: []const u8) bool {
    for (sources) |source| {
        if (std.mem.eql(u8, source.path, path)) return true;
    }
    return false;
}

fn append_examples(writer: *std.Io.Writer, source: Source) !void {
    var lines = std.mem.splitScalar(u8, source.text, '\n');
    var in_example = false;
    var line_number: u32 = 0;
    while (lines.next()) |line| {
        line_number += 1;
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, "///")) {
            if (in_example) return error.UnclosedExample;
            continue;
        }
        const content = std.mem.trimStart(u8, trimmed[3..], " ");
        if (std.mem.eql(u8, content, "```zig")) {
            if (in_example) return error.NestedExample;
            in_example = true;
            try writer.print("test \"{s}:{d}\" {{\n", .{ source.path, line_number });
        } else if (in_example and std.mem.eql(u8, content, "```")) {
            in_example = false;
            try writer.writeAll("}\n");
        } else if (in_example) {
            try writer.print("{s}\n", .{content});
        }
    }
    if (in_example) return error.UnclosedExample;
}

test "doc gate rejects undocumented exports and fields, but accepts documented counterparts" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(
        error.MissingDeclarationDocumentation,
        validate_source(allocator, .{
            .path = "fixture.zig",
            .report = false,
            .text = "//! Module\npub const x = 1;",
        }),
    );
    try std.testing.expectError(error.MissingDeclarationDocumentation, validate_source(allocator, .{
        .path = "fixture.zig",
        .report = false,
        .text = "//! Module\n/// Type\npub const T = struct { value: u32 };",
    }));
    try validate_source(allocator, .{
        .path = "fixture.zig",
        .report = false,
        .text = "//! Module\n/// Type\npub const T = struct {\n/// Value\nvalue: u32,\n};",
    });
}

test "examples come from exact comment content and unclosed fences fail" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try append_examples(&output.writer, .{
        .path = "fixture.zig",
        .report = false,
        .text = "/// ```zig\n/// try work();\n/// ```\n",
    });
    try std.testing.expectEqualStrings(
        "test \"fixture.zig:1\" {\ntry work();\n}\n",
        output.written(),
    );
    try std.testing.expectError(
        error.UnclosedExample,
        append_examples(&output.writer, .{
            .path = "fixture.zig",
            .report = false,
            .text = "/// ```zig\n",
        }),
    );
}

test "module docs, enum docs and local import registration are enforced" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingModuleDocumentation, validate_source(allocator, .{
        .path = "fixture.zig",
        .text = "/// Value\npub const x = 1;",
        .report = false,
    }));
    try std.testing.expectError(error.MissingDeclarationDocumentation, validate_source(allocator, .{
        .path = "fixture.zig",
        .text = "//! Module\n/// Kind\npub const Kind = enum { undocumented };",
        .report = false,
    }));
    try std.testing.expectError(error.UnregisteredSource, validate_source(allocator, .{
        .path = "src/fixture.zig",
        .text = "//! Module\nconst extra = @import(\"undocumented.zig\");",
        .report = false,
    }));
}
