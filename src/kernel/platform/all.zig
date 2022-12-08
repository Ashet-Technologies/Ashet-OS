const std = @import("std");
const ashet = @import("../main.zig");

pub const PlatformSpec = struct {
    name: []const u8,
    platform_id: []const u8,
    platform_code: []const u8,
    target: std.zig.CrossTarget,
};

pub const all = struct {
    pub const riscv = @import("riscv.zig");
    pub const arm = @import("arm.zig");
    pub const x86 = @import("x86.zig");
};

pub const specs = struct {
    pub const riscv = PlatformSpec{
        .name = "RISC-V",
        .platform_id = "riscv",
        .platform_code = "src/kernel/platform/riscv.zig",
        .target = std.zig.CrossTarget{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .eabi,
            .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
            .cpu_features_add = std.Target.riscv.featureSet(&[_]std.Target.riscv.Feature{
                .c,
                .m,
                .reserve_x4, // Don't allow LLVM to use the "tp" register. We want that for our own purposes
            }),
        },
    };

    pub const arm = PlatformSpec{
        .name = "Arm",
        .platform_id = "arm",
        .platform_code = "src/kernel/platform/arm.zig",
        .target = std.zig.CrossTarget{
            .cpu_arch = .arm,
            .os_tag = .freestanding,
            .abi = .eabi,
            .cpu_model = .{ .explicit = &std.Target.arm.cpu.generic },
        },
    };

    pub const x86 = PlatformSpec{
        .name = "x86",
        .platform_id = "x86",
        .platform_code = "src/kernel/platform/x86.zig",
        .target = std.zig.CrossTarget{
            .cpu_arch = .x86,
            .os_tag = .freestanding,
            .abi = .eabi,
            .cpu_model = .{ .explicit = &std.Target.x86.cpu.i486 },
        },
    };
};
