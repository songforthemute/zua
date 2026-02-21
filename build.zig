const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 실행 파일 빌드
    const exe = b.addExecutable(.{
        .name = "zua",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    // run 스텝
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the Zua interpreter");
    run_step.dependOn(&run_cmd.step);

    // 테스트 빌드 — 모든 소스 파일의 test 블록을 실행
    const test_targets = [_][]const u8{
        "src/token.zig",
        "src/lexer.zig",
        "src/value.zig",
        "src/ast.zig",
        "src/parser.zig",
        "src/opcode.zig",
        "src/compiler.zig",
        "src/vm.zig",
    };

    const test_step = b.step("test", "Run unit tests");
    for (test_targets) |path| {
        const unit_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_unit_test = b.addRunArtifact(unit_test);
        test_step.dependOn(&run_unit_test.step);
    }
}
