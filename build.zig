const std = @import("std");

pub const pico_rv32 = std.Target.Cpu.Model{
    .name = "pico_rv32",
    .llvm_name = null,
    .features = std.Target.riscv.featureSet(&[_]std.Target.riscv.Feature{
        .c,
        .m,
    }),
};

pub fn build(b: *std.build.Builder) void {
    const target = std.zig.CrossTarget{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .eabi,
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
        .cpu_features_add = std.Target.riscv.featureSet(&[_]std.Target.riscv.Feature{
            .c,
            .m,
        }),
    };

    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("ashet-os", "src/kernel/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackage(.{
        .name = "hal",
        .source = .{ .path = "src/kernel/hal/virt/hal.zig" },
    });
    exe.setLinkerScriptPath(.{ .path = "src/kernel/hal/virt/linker.ld" });
    exe.install();

    const raw_step = exe.installRaw("ashet-os.bin", .{
        .format = .bin,
        .pad_to_size = 0x200_0000,
    });

    b.getInstallStep().dependOn(&raw_step.step);

    const run_cmd = b.addSystemCommand(&.{"qemu-system-riscv32"});
    run_cmd.addArgs(&.{
        "-M",      "virt",
        "-m",      "16M",
        "-device", "virtio-gpu-device,xres=400,yres=300",
        "-d",      "guest_errors",
        "-bios",   "none",
        "-drive",  "if=pflash,index=0,file=zig-out/bin/ashet-os.bin,format=raw",
    });

    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
