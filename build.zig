const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "branca-zig",
        .root_source_file = b.path("src/branca.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addAnonymousImport("base-x", .{
        .root_source_file = b.path("libs/baseX/baseX.zig"),
    });
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/branca.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addAnonymousImport("base-x", .{
        .root_source_file = b.path("libs/baseX/baseX.zig"),
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
