const std = @import("std");
const builtin = @import("builtin");

const libraries = @import("build_support/dependencies.zig").libraries;

const Provider = enum { system, source, external };

test "documentation tooling" {
    _ = @import("build_support/documentation.zig");
}

pub fn build(b: *std.Build) void {
    if (!std.mem.eql(u8, builtin.zig_version_string, "0.17.0")) {
        @panic("zig-sdl3 requires exactly Zig 0.17.0");
    }
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const provider = b.option(Provider, "sdl-provider", "Dependency provider") orelse .system;
    const prefix = b.option([]const u8, "sdl-prefix", "External installation prefix");
    if (provider == .source) {
        @panic("source provider is not implemented; use system or external");
    }
    if (provider == .external and prefix == null) @panic("external requires -Dsdl-prefix");
    if (provider == .system and prefix != null) @panic("sdl-prefix requires external provider");
    if (provider == .system and !target.query.isNative()) {
        @panic("cross-compilation requires an explicit target installation via external provider");
    }
    const enabled = [_]bool{
        true,
        b.option(bool, "image", "Enable SDL_image") orelse false,
        b.option(bool, "mixer", "Enable SDL_mixer") orelse false,
        b.option(bool, "ttf", "Enable SDL_ttf") orelse false,
    };
    const linkage = b.option(std.builtin.LinkMode, "sdl-linkage", "Native linkage") orelse .dynamic;
    const headers = b.addWriteFiles();
    var includes: std.Io.Writer.Allocating = .init(b.allocator);
    includes.writer.writeAll("#define SDL_MAIN_HANDLED 1\n") catch @panic("OOM");
    for (libraries, enabled) |library, enable| {
        if (enable) {
            write_header_check(b, &includes.writer, library, prefix);
        }
    }
    const translation = b.addTranslateC(.{
        .root_source_file = headers.add("sdl_abi.h", includes.written()),
        .target = target,
        .optimize = optimize,
    });
    if (prefix) |path| {
        translation.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ path, "include" }) });
    }
    for (libraries, enabled) |library, enable| {
        if (!enable) continue;
        if (provider == .external) continue;
        translation.linkSystemLibrary(library.pkg, .{
            .use_pkg_config = .force,
            .preferred_link_mode = linkage,
            .search_strategy = .no_fallback,
        });
    }
    const abi = translation.createModule();
    if (prefix) |path| add_external_libraries(b, abi, path, target, linkage, enabled);
    add_modules(b, abi, target, optimize, enabled);
    add_inventory(b, abi, enabled);
}

fn add_modules(
    b: *std.Build,
    abi: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    enabled: [4]bool,
) void {
    const test_step = b.step("test", "Run enabled module contract tests");
    const check_step = b.step("check", "Compile enabled module tests without running");
    const docs = b.step("docs", "Generate API reference for enabled modules");
    var core: ?*std.Build.Module = null;
    for (libraries, enabled) |library, enable| {
        if (!enable) continue;
        const module = b.addModule(library.module, .{
            .root_source_file = b.path(library.root),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "sdl_abi", .module = abi }},
        });
        if (core) |module_core| module.addImport("sdl", module_core) else core = module;
        const reference = b.addObject(.{ .name = library.module, .root_module = module });
        docs.dependOn(&b.addInstallDirectory(.{
            .source_dir = reference.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = b.fmt("docs/{s}", .{library.module}),
        }).step);
        const tests = b.addTest(.{ .root_module = module });
        check_step.dependOn(&tests.step);
        test_step.dependOn(&b.addRunArtifact(tests).step);
    }
    b.default_step.dependOn(check_step);
    add_graphics_steps(b, core.?, target, optimize, check_step);
    if (b.modules.get("sdl_image")) |image| {
        add_image_tests(b, core.?, image, target, optimize, check_step, test_step);
    }
    if (b.modules.get("sdl_ttf")) |ttf| {
        add_ttf_tests(b, core.?, ttf, target, optimize, check_step, test_step);
    }
    if (b.modules.get("sdl_mixer")) |mixer| {
        add_mixer_tests(b, core.?, mixer, target, optimize, check_step, test_step);
    }
    if (enabled[1] and enabled[2] and enabled[3]) {
        add_multimedia_example(b, target, optimize, check_step);
    }
    @import("build_support/documentation.zig").add_checks(b, core.?, target, optimize, check_step);
}

fn add_graphics_steps(
    b: *std.Build,
    core: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    check: *std.Build.Step,
) void {
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/graphics.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "sdl", .module = core }},
    }) });
    const run = b.addRunArtifact(tests);
    run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    b.step("test-graphics", "Run headless software-renderer integration tests").dependOn(&run.step);
    check.dependOn(&tests.step);
    const example = b.addExecutable(.{
        .name = "sdl-window",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/window.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "sdl", .module = core }},
        }),
    });
    check.dependOn(&example.step);
    b.step("example", "Install the bounded desktop window example")
        .dependOn(&b.addInstallArtifact(example, .{}).step);
    b.step("run-window", "Run desktop example (close/Escape, or exits after 600 frames)")
        .dependOn(&b.addRunArtifact(example).step);
}

fn add_image_tests(
    b: *std.Build,
    core: *std.Build.Module,
    image: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const options = b.addOptions();
    options.addOptionPath("image_path", b.path("tests/fixtures/orange.bmp"));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/image.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sdl", .module = core },
            .{ .name = "sdl_image", .module = image },
        },
    }) });
    tests.root_module.addOptions("fixtures", options);
    const run = b.addRunArtifact(tests);
    run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    test_step.dependOn(&run.step);
    check.dependOn(&tests.step);
}

fn add_ttf_tests(
    b: *std.Build,
    core: *std.Build.Module,
    ttf: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const options = b.addOptions();
    options.addOptionPath("font_path", b.path("tests/fixtures/box.ttf"));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/ttf.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sdl", .module = core },
            .{ .name = "sdl_ttf", .module = ttf },
        },
    }) });
    tests.root_module.addOptions("fixtures", options);
    const run = b.addRunArtifact(tests);
    run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    test_step.dependOn(&run.step);
    check.dependOn(&tests.step);
}

fn add_mixer_tests(
    b: *std.Build,
    core: *std.Build.Module,
    mixer: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const options = b.addOptions();
    options.addOptionPath("audio_path", b.path("tests/fixtures/tone.wav"));
    const tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("tests/mixer.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sdl", .module = core },
            .{ .name = "sdl_mixer", .module = mixer },
        },
    }) });
    tests.root_module.addOptions("fixtures", options);
    const run = b.addRunArtifact(tests);
    run.setEnvironmentVariable("SDL_AUDIODRIVER", "dummy");
    test_step.dependOn(&run.step);
    check.dependOn(&tests.step);
}

fn add_multimedia_example(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Optimize,
    check: *std.Build.Step,
) void {
    const assets = b.addOptions();
    assets.addOptionPath("image_path", b.path("tests/fixtures/orange.bmp"));
    assets.addOptionPath("font_path", b.path("tests/fixtures/box.ttf"));
    assets.addOptionPath("audio_path", b.path("tests/fixtures/tone.wav"));
    const module = b.createModule(.{
        .root_source_file = b.path("examples/multimedia.zig"),
        .target = target,
        .optimize = optimize,
    });
    for (libraries) |library| module.addImport(library.module, b.modules.get(library.module).?);
    module.addOptions("example_assets", assets);
    const example = b.addExecutable(.{ .name = "sdl-multimedia", .root_module = module });
    check.dependOn(&example.step);
    b.step("run-multimedia", "Run bounded image/text/audio example (all extensions required)")
        .dependOn(&b.addRunArtifact(example).step);
    const headless = b.addRunArtifact(example);
    headless.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    headless.setEnvironmentVariable("SDL_AUDIODRIVER", "dummy");
    b.step("test-multimedia", "Run all-extension example with dummy audio/video")
        .dependOn(&headless.step);
}

fn add_inventory(b: *std.Build, abi: *std.Build.Module, enabled: [4]bool) void {
    const options = b.addOptions();
    options.addOption([4]bool, "enabled", enabled);
    const executable = b.addExecutable(.{
        .name = "sdl-inventory",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/coverage/main.zig"),
            .target = b.graph.host,
            .imports = &.{.{ .name = "sdl_abi", .module = abi }},
        }),
    });
    executable.root_module.addOptions("libraries", options);
    const run = b.addRunArtifact(executable);
    const output = run.captureStdOut(.{});
    const install = b.addInstallFile(output, "coverage/symbols.tsv");
    b.step("inventory", "Write native translated-symbol inventory (native builds only)")
        .dependOn(&install.step);
}

fn write_header_check(
    b: *std.Build,
    writer: *std.Io.Writer,
    library: anytype,
    prefix: ?[]const u8,
) void {
    write_include(b, writer, library.header, prefix);
    writer.print(
        "#if {s}_MAJOR_VERSION != 3 || {s}_VERSION < {d}\n" ++
            "#error zig-sdl3 requires {s} headers >= {s} with major version 3\n" ++
            "#endif\n",
        .{ library.macro, library.macro, library.minimum, library.native, library.version },
    ) catch @panic("OOM");
    for (library.extra_headers) |header| write_include(b, writer, header, prefix);
}

fn write_include(
    b: *std.Build,
    writer: *std.Io.Writer,
    name: []const u8,
    prefix: ?[]const u8,
) void {
    if (prefix) |path| {
        const header = b.pathJoin(&.{ path, "include", name });
        if (std.mem.indexOfAny(u8, header, "\\\"\n\r") != null) {
            @panic("external prefix must not contain backslashes, quotes or newlines");
        }
        writer.print("#include \"{s}\"\n", .{header}) catch @panic("OOM");
    } else {
        writer.print("#include <{s}>\n", .{name}) catch @panic("OOM");
    }
}

fn add_external_libraries(
    b: *std.Build,
    abi: *std.Build.Module,
    prefix: []const u8,
    target: std.Build.ResolvedTarget,
    linkage: std.builtin.LinkMode,
    enabled: [4]bool,
) void {
    if (!std.fs.path.isAbsolute(prefix)) @panic("external prefix must be an absolute path");
    const suffix: []const u8 = if (linkage == .static) ".a" else switch (target.result.os.tag) {
        .linux => ".so",
        .macos => ".dylib",
        else => @panic("external shared-library layout currently supports Linux and macOS"),
    };
    for (libraries, enabled) |library, enable| {
        if (!enable) continue;
        const filename = b.fmt("lib{s}{s}", .{ library.native, suffix });
        abi.addObjectFile(.{ .cwd_relative = b.pathJoin(&.{ prefix, "lib", filename }) });
    }
}
