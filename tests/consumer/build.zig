const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const extensions = b.option(bool, "extensions", "Import all extensions") orelse false;
    const provider = b.option([]const u8, "sdl-provider", "Dependency provider") orelse "system";
    const prefix = b.option([]const u8, "sdl-prefix", "External prefix");
    const dependency = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
        .image = extensions,
        .mixer = extensions,
        .ttf = extensions,
        .@"sdl-provider" = provider,
        .@"sdl-prefix" = prefix,
    });
    const options = b.addOptions();
    options.addOption(bool, "extensions", extensions);
    if (extensions) {
        options.addOptionPath("font_path", dependency.path("tests/fixtures/box.ttf"));
        options.addOptionPath("audio_path", dependency.path("tests/fixtures/tone.wav"));
    }
    const module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addOptions("options", options);
    module.addImport("sdl", dependency.module("sdl"));
    if (extensions) {
        for ([_][]const u8{ "sdl_image", "sdl_mixer", "sdl_ttf" }) |name| {
            module.addImport(name, dependency.module(name));
        }
    }
    const executable = b.addExecutable(.{ .name = "consumer", .root_module = module });
    b.installArtifact(executable);
    const run = b.addRunArtifact(executable);
    run.setEnvironmentVariable("SDL_VIDEODRIVER", "dummy");
    b.step("run", "Run downstream smoke test").dependOn(&run.step);
}
