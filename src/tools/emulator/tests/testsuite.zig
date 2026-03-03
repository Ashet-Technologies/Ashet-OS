const std = @import("std");
const emu = @import("emulator");

// Force-import peripheral unit tests
comptime {
    _ = @import("peripherals/test_debug_output.zig");
    _ = @import("peripherals/test_sysinfo.zig");
    _ = @import("peripherals/test_timer.zig");
    _ = @import("peripherals/test_video_control.zig");
    _ = @import("peripherals/test_framebuffer.zig");
    _ = @import("peripherals/test_keyboard.zig");
    _ = @import("peripherals/test_mouse.zig");
    _ = @import("peripherals/test_block_device.zig");
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Create a System loaded with the given ROM binary and a fixed-size RAM,
/// running until EBREAK or an error. Returns the CPU state for register inspection.
fn run_program(comptime rom: []const u8, ram: []align(4) u8) !emu.Cpu {
    const S = struct {
        const padded_len = (rom.len + 3) & ~@as(usize, 3);
        const padded: [padded_len]u8 align(4) = blk: {
            var p: [padded_len]u8 = [_]u8{0} ** padded_len;
            @memcpy(p[0..rom.len], rom);
            break :blk p;
        };
    };
    const aligned_rom: []align(4) const u8 = &S.padded;

    var debug_buf: [512]u8 = undefined;
    var debug_writer: std.Io.Writer = .fixed(&debug_buf);
    var debug_output = emu.DebugOutput.init(&debug_writer);

    var system = emu.System.init(aligned_rom, ram);
    system.mmio.map(0x41, debug_output.peripheral());

    const result = system.step(10000);
    if (result) |_| {
        return error.TestDidNotTerminate;
    } else |err| switch (err) {
        error.Ebreak => return system.cpu,
        else => return err,
    }
}

fn run_program_no_ram(comptime rom: []const u8) !emu.Cpu {
    var ram_backing: [4]u8 align(4) = [_]u8{0} ** 4;
    return run_program(rom, ram_backing[0..0]);
}

fn run_program_with_ram(comptime rom: []const u8, ram: []align(4) u8) !emu.Cpu {
    return run_program(rom, ram);
}

// ---------------------------------------------------------------------------
// Error handling tests
// ---------------------------------------------------------------------------

test "x0 register is always zero" {
    const rom = [_]u8{
        0x13, 0x00, 0xA0, 0x02, // addi x0, x0, 42
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    const cpu = try run_program_no_ram(&rom);
    try std.testing.expectEqual(@as(u32, 0), cpu.read_reg(0));
}

test "Bus error: write to ROM" {
    const rom = [_]u8{
        0x23, 0x20, 0x00, 0x00, // sw x0, 0(x0)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    const result = run_program_no_ram(&rom);
    try std.testing.expectError(error.StoreAccessFault, result);
}

test "Bus error: read from unmapped MMIO" {
    const rom = [_]u8{
        0x37, 0x01, 0x05, 0x40, // lui x2, 0x40050
        0x83, 0x20, 0x01, 0x00, // lw x1, 0(x2)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    const result = run_program_no_ram(&rom);
    try std.testing.expectError(error.LoadAccessFault, result);
}

test "ECALL raises error" {
    const rom = [_]u8{
        0x73, 0x00, 0x00, 0x00, // ecall
    };
    var ram_backing: [4]u8 align(4) = [_]u8{0} ** 4;
    const result = run_program(&rom, &ram_backing);
    try std.testing.expectError(error.Ecall, result);
}

test "Illegal instruction raises error" {
    const rom = [_]u8{
        0x00, 0x00, 0x00, 0x00,
    };
    var ram_backing: [4]u8 align(4) = [_]u8{0} ** 4;
    const result = run_program(&rom, &ram_backing);
    try std.testing.expectError(error.IllegalInstruction, result);
}

// ---------------------------------------------------------------------------
// Unaligned access fault tests
// ---------------------------------------------------------------------------

test "Unaligned LH faults" {
    const rom = [_]u8{
        0xB7, 0x00, 0x00, 0x80, // lui x1, 0x80000
        0x93, 0x00, 0x10, 0x00, // addi x1, x1, 1
        0x03, 0x91, 0x00, 0x00, // lh x2, 0(x1)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    var ram_backing: [16]u8 align(4) = [_]u8{0} ** 16;
    const result = run_program_with_ram(&rom, &ram_backing);
    try std.testing.expectError(error.LoadAccessFault, result);
}

test "Unaligned LW faults" {
    const rom = [_]u8{
        0xB7, 0x00, 0x00, 0x80, // lui x1, 0x80000
        0x93, 0x00, 0x20, 0x00, // addi x1, x1, 2
        0x03, 0xA1, 0x00, 0x00, // lw x2, 0(x1)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    var ram_backing: [16]u8 align(4) = [_]u8{0} ** 16;
    const result = run_program_with_ram(&rom, &ram_backing);
    try std.testing.expectError(error.LoadAccessFault, result);
}

test "Unaligned SH faults" {
    const rom = [_]u8{
        0xB7, 0x00, 0x00, 0x80, // lui x1, 0x80000
        0x93, 0x00, 0x30, 0x00, // addi x1, x1, 3
        0x23, 0x90, 0x00, 0x00, // sh x0, 0(x1)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    var ram_backing: [16]u8 align(4) = [_]u8{0} ** 16;
    const result = run_program_with_ram(&rom, &ram_backing);
    try std.testing.expectError(error.StoreAccessFault, result);
}

test "Unaligned SW faults" {
    const rom = [_]u8{
        0xB7, 0x00, 0x00, 0x80, // lui x1, 0x80000
        0x93, 0x00, 0x10, 0x00, // addi x1, x1, 1
        0x23, 0xA0, 0x00, 0x00, // sw x0, 0(x1)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    var ram_backing: [16]u8 align(4) = [_]u8{0} ** 16;
    const result = run_program_with_ram(&rom, &ram_backing);
    try std.testing.expectError(error.StoreAccessFault, result);
}
