const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libogg = b.dependency("libogg", .{
        .target = target,
        .optimize = optimize,
    });

    const ogg = b.createModule(.{
        .root_source_file = b.path("ogg.zig"),
        .target = target,
        .optimize = optimize,
    });

    ogg.linkLibrary(libogg.artifact("ogg"));

    const lib = b.addLibrary(.{
        .name = "ogg",
        .root_module = ogg,
        .linkage = .static,
    });

    b.installArtifact(lib);

    const run_all_examples_step = b.step("run", "Run all examples");

    const examples = [_][]const u8{
        "encode_decode",
        "pack_buffer",
    };

    inline for (examples) |name| {
        const example_exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
            }),
        });

        example_exe.linkLibrary(lib);
        example_exe.root_module.addImport("ogg", lib.root_module);

        b.installArtifact(example_exe);

        const run_cmd = b.addRunArtifact(example_exe);

        const run_example_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} example", .{name}));
        run_example_step.dependOn(&run_cmd.step);

        run_all_examples_step.dependOn(run_example_step);
    }
}
