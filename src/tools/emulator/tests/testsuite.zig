const std = @import("std");
const emu = @import("emulator");

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// Create a System loaded with the given ROM binary and a fixed-size RAM,
/// running until EBREAK or an error. Returns the system for register inspection.
fn run_program(comptime rom: []const u8, ram: []align(4) u8, debug: *std.Io.Writer) !emu.System {
    // Pad the ROM to 4-byte alignment at compile time. Using a const struct
    // field so the address is available at runtime (comptime vars cannot be
    // referenced at runtime in Zig 0.15+).
    const S = struct {
        const padded_len = (rom.len + 3) & ~@as(usize, 3);
        const padded: [padded_len]u8 align(4) = blk: {
            var p: [padded_len]u8 = [_]u8{0} ** padded_len;
            @memcpy(p[0..rom.len], rom);
            break :blk p;
        };
    };
    const aligned_rom: []align(4) const u8 = &S.padded;

    var system = emu.System.init(aligned_rom, ram, debug);

    // Run up to 10000 instructions — any test should complete well within that.
    const result = system.step(10000);
    if (result) |_| {
        return error.TestDidNotTerminate;
    } else |err| switch (err) {
        error.Ebreak => return system,
        else => return err,
    }
}

fn run_program_no_ram(comptime rom: []const u8) !emu.System {
    var debug_output: [512]u8 = undefined;
    var debug: std.Io.Writer = .fixed(&debug_output);
    var ram_backing: [4]u8 align(4) = [_]u8{0} ** 4;
    return run_program(rom, ram_backing[0..0], &debug);
}

fn run_program_with_ram(comptime rom: []const u8, ram: []align(4) u8) !emu.System {
    var debug_output: [512]u8 = undefined;
    var debug: std.Io.Writer = .fixed(&debug_output);
    return run_program(rom, ram, &debug);
}

// ---------------------------------------------------------------------------
// Error handling tests
// ---------------------------------------------------------------------------

test "x0 register is always zero" {
    // addi x0, x0, 42; ebreak — verified against assembler output
    const rom = [_]u8{
        0x13, 0x00, 0xA0, 0x02, // addi x0, x0, 42
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    const system = try run_program_no_ram(&rom);
    try std.testing.expectEqual(@as(u32, 0), system.cpu.read_reg(0));
}

test "Bus error: write to ROM" {
    // sw x0, 0(x0) — store to address 0 (ROM region)
    const rom = [_]u8{
        0x23, 0x20, 0x00, 0x00, // sw x0, 0(x0)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    const system = run_program_no_ram(&rom);
    try std.testing.expectError(error.StoreAccessFault, system);
}

test "Bus error: read from unmapped MMIO" {
    // lui x2, 0x40050; lw x1, 0(x2) — unmapped MMIO page
    const rom = [_]u8{
        0x37, 0x01, 0x05, 0x40, // lui x2, 0x40050
        0x83, 0x20, 0x01, 0x00, // lw x1, 0(x2)
        0x73, 0x00, 0x10, 0x00, // ebreak
    };
    const system = run_program_no_ram(&rom);
    try std.testing.expectError(error.LoadAccessFault, system);
}

test "ECALL raises error" {
    const rom = [_]u8{
        0x73, 0x00, 0x00, 0x00, // ecall
    };
    var debug_output: [512]u8 = undefined;
    var debug: std.Io.Writer = .fixed(&debug_output);
    var ram_backing: [4]u8 align(4) = [_]u8{0} ** 4;
    const result = run_program(&rom, &ram_backing, &debug);
    try std.testing.expectError(error.Ecall, result);
}

test "Illegal instruction raises error" {
    // All-zeros is the permanently reserved illegal instruction encoding
    const rom = [_]u8{
        0x00, 0x00, 0x00, 0x00,
    };
    var debug_output: [512]u8 = undefined;
    var debug: std.Io.Writer = .fixed(&debug_output);
    var ram_backing: [4]u8 align(4) = [_]u8{0} ** 4;
    const result = run_program(&rom, &ram_backing, &debug);
    try std.testing.expectError(error.IllegalInstruction, result);
}
