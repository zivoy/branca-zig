const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const baseX = b.dependency("base_x", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("branca", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("branca.zig"),
    });
    mod.addImport("base-x", baseX.module("baseX"));

    const lib = b.addLibrary(.{
        .name = "branca",
        .root_module = b.createModule(.{
            .root_source_file = b.path("abi.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),

        .linkage = .static,
    });
    lib.root_module.addImport("branca", mod);
    b.installArtifact(lib);

    const mod_unit_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_unit_tests = b.addRunArtifact(mod_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_unit_tests.step);
}
