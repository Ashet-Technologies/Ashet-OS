const std = @import("std");
const platforms = @import("../platform/all.zig");

pub const MachineSpec = struct {
    name: []const u8,
    machine_id: []const u8,
    platform: platforms.PlatformSpec,
    machine_code: []const u8,
    linker_script: []const u8,
};

pub const MachineConfig = struct {
    /// If this is set, the kernel will initialize the `.data` and `.bss` sections.
    uninitialized_memory: bool,
};

pub const all = struct {
    pub const ashet_home_computer = @import("ashet_home_computer/ashet_home_computer.zig");
    pub const rv32_virt = @import("rv32_virt/rv32_virt.zig");
    pub const bios_pc = @import("bios_pc/bios_pc.zig");
    pub const efi_pc = @import("efi_pc/efi_pc.zig");
    pub const microvm = @import("microvm/microvm.zig");
    pub const arm_virt = @import("arm_virt/arm_virt.zig");
};

pub const specs = struct {
    // RISC-V machines:
    pub const ashet_home_computer = MachineSpec{
        .name = "Ashet Home Computer",
        .machine_id = "ashet_home_computer",
        .platform = platforms.specs.riscv,
        .machine_code = "src/kernel/machine/ashet_home_computer/machine.zig",
        .linker_script = "src/kernel/machine/ashet_home_computer/linker.ld",
    };
    pub const rv32_virt = MachineSpec{
        .name = "RISC-V virt",
        .machine_id = "rv32_virt",
        .platform = platforms.specs.riscv,
        .machine_code = "src/kernel/machine/rv32_virt/machine.zig",
        .linker_script = "src/kernel/machine/rv32_virt/linker.ld",
    };

    // x86 machines:
    pub const bios_pc = MachineSpec{
        .name = "Generic PC (BIOS)",
        .machine_id = "bios_pc",
        .platform = platforms.specs.x86,
        .machine_code = "src/kernel/machine/bios_pc/machine.zig",
        .linker_script = "src/kernel/machine/bios_pc/linker.ld",
    };

    pub const efi_pc = MachineSpec{
        .name = "Generic PC (EFI)",
        .machine_id = "efi_pc",
        .platform = platforms.specs.x86,
        .machine_code = "src/kernel/machine/efi_pc/machine.zig",
        .linker_script = "src/kernel/machine/efi_pc/linker.ld",
    };

    pub const microvm = MachineSpec{
        .name = "MicroVM",
        .machine_id = "microvm",
        .platform = platforms.specs.x86,
        .machine_code = "src/kernel/machine/microvm/machine.zig",
        .linker_script = "src/kernel/machine/microvm/linker.ld",
    };

    // Arm machines:
    pub const arm_virt = MachineSpec{
        .name = "Arm virt",
        .machine_id = "arm_virt",
        .platform = platforms.specs.arm,
        .machine_code = "src/kernel/machine/arm_virt/machine.zig",
        .linker_script = "src/kernel/machine/arm_virt/linker.ld",
    };
};
