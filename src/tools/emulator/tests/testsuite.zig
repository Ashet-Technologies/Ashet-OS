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
// RV32I base instruction tests
// All test binaries are assembled from .s files in this directory.
// See each .s file for assembly/objcopy commands and expected results.
// ---------------------------------------------------------------------------

test "ADDI: load immediate into register" {
    const system = try run_program_no_ram(@embedFile("test_addi.bin"));
    try std.testing.expectEqual(@as(u32, 42), system.cpu.read_reg(1));
}

test "ALU: register-register operations" {
    const system = try run_program_no_ram(@embedFile("test_alu.bin"));
    try std.testing.expectEqual(@as(u32, 10), system.cpu.read_reg(1)); // x1 = 10
    try std.testing.expectEqual(@as(u32, 20), system.cpu.read_reg(2)); // x2 = 20
    try std.testing.expectEqual(@as(u32, 30), system.cpu.read_reg(3)); // ADD
    try std.testing.expectEqual(@as(i32, -10), @as(i32, @bitCast(system.cpu.read_reg(4)))); // SUB
    try std.testing.expectEqual(@as(u32, 0), system.cpu.read_reg(5)); // AND(10,20)
    try std.testing.expectEqual(@as(u32, 30), system.cpu.read_reg(6)); // OR(10,20)
    try std.testing.expectEqual(@as(u32, 20), system.cpu.read_reg(7)); // XOR(10,30)
}

test "LUI and AUIPC" {
    const system = try run_program_no_ram(@embedFile("test_lui_auipc.bin"));
    try std.testing.expectEqual(@as(u32, 0x12345000), system.cpu.read_reg(1));
    try std.testing.expectEqual(@as(u32, 0x12345678), system.cpu.read_reg(2));
    // AUIPC at PC=0x0C: x3 = 0x0C + 0x1000 = 0x100C
    try std.testing.expectEqual(@as(u32, 0x100C), system.cpu.read_reg(3));
}

test "Branch instructions: BEQ, BNE, BLT" {
    const system = try run_program_no_ram(@embedFile("test_branch.bin"));
    try std.testing.expectEqual(@as(u32, 1), system.cpu.read_reg(1)); // BEQ taken
    try std.testing.expectEqual(@as(u32, 1), system.cpu.read_reg(2)); // BNE taken
    try std.testing.expectEqual(@as(u32, 1), system.cpu.read_reg(3)); // BLT taken
}

test "BLTU: unsigned comparison branch" {
    const system = try run_program_no_ram(@embedFile("test_bltu.bin"));
    try std.testing.expectEqual(@as(u32, 1), system.cpu.read_reg(3));
}

test "JAL and JALR" {
    const system = try run_program_no_ram(@embedFile("test_jal.bin"));
    // JAL at 0x00 jumps to 0x08, link = 0x04
    try std.testing.expectEqual(@as(u32, 0x04), system.cpu.read_reg(1));
    try std.testing.expectEqual(@as(u32, 99), system.cpu.read_reg(10));
    // JALR at 0x0C jumps back to ra=0x04, link = 0x10
    try std.testing.expectEqual(@as(u32, 0x10), system.cpu.read_reg(11));
}

test "Shift instructions" {
    const system = try run_program_no_ram(@embedFile("test_shifts.bin"));
    try std.testing.expectEqual(@as(u32, 40), system.cpu.read_reg(3)); // SLL 10<<2
    try std.testing.expectEqual(@as(u32, 2), system.cpu.read_reg(4)); // SRL 10>>2
    try std.testing.expectEqual(@as(u32, 0xE0000000), system.cpu.read_reg(5)); // SRA 0x80000000>>2
    try std.testing.expectEqual(@as(u32, 20), system.cpu.read_reg(6)); // SLLI 10<<1
    try std.testing.expectEqual(@as(u32, 5), system.cpu.read_reg(7)); // SRLI 10>>1
}

test "SLTI and SLTIU" {
    const system = try run_program_no_ram(@embedFile("test_slti.bin"));
    try std.testing.expectEqual(@as(i32, -5), @as(i32, @bitCast(system.cpu.read_reg(1))));
    try std.testing.expectEqual(@as(u32, 1), system.cpu.read_reg(2)); // -5 < 0 signed
    try std.testing.expectEqual(@as(u32, 0), system.cpu.read_reg(3)); // 0xFFFFFFFB > 0 unsigned
}

test "Load/store with RAM" {
    var ram_backing: [1024]u8 align(4) = [_]u8{0} ** 1024;
    const system = try run_program_with_ram(@embedFile("test_mem.bin"), &ram_backing);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), system.cpu.read_reg(3)); // LW
    try std.testing.expectEqual(@as(i32, @bitCast(@as(u32, 0xFFFFFFEF))), @as(i32, @bitCast(system.cpu.read_reg(4)))); // LB sign-extended
    try std.testing.expectEqual(@as(u32, 0xEF), system.cpu.read_reg(5)); // LBU zero-extended
}

test "Half-word store and load" {
    var ram_backing: [1024]u8 align(4) = [_]u8{0} ** 1024;
    const system = try run_program_with_ram(@embedFile("test_halfword.bin"), &ram_backing);
    try std.testing.expectEqual(@as(i32, -1), @as(i32, @bitCast(system.cpu.read_reg(3)))); // LH sign-extend
    try std.testing.expectEqual(@as(u32, 0xFFFF), system.cpu.read_reg(4)); // LHU zero-extend
}

// ---------------------------------------------------------------------------
// M-extension tests
// ---------------------------------------------------------------------------

test "M-extension: multiply and divide" {
    const system = try run_program_no_ram(@embedFile("test_mul.bin"));
    try std.testing.expectEqual(@as(u32, 200), system.cpu.read_reg(3)); // MUL 10*20
    try std.testing.expectEqual(@as(u32, 2), system.cpu.read_reg(4)); // DIVU 20/10
    try std.testing.expectEqual(@as(u32, 0), system.cpu.read_reg(5)); // REMU 20%10
    try std.testing.expectEqual(@as(u32, 5), system.cpu.read_reg(6)); // DIVU 50/10
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), system.cpu.read_reg(7)); // DIVU by zero
}

test "M-extension: signed division edge cases" {
    const system = try run_program_no_ram(@embedFile("test_div_edge.bin"));
    try std.testing.expectEqual(@as(u32, 0x80000000), system.cpu.read_reg(3)); // INT32_MIN / -1
    try std.testing.expectEqual(@as(u32, 0), system.cpu.read_reg(4)); // INT32_MIN % -1
    try std.testing.expectEqual(@as(u32, 0x80000000), system.cpu.read_reg(5)); // INT32_MIN % 0
}

test "M-extension: MULH, MULHU, MULHSU" {
    const system = try run_program_no_ram(@embedFile("test_mulh.bin"));
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), system.cpu.read_reg(3)); // mulh
    try std.testing.expectEqual(@as(u32, 0x00000001), system.cpu.read_reg(4)); // mulhu
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), system.cpu.read_reg(5)); // mulhsu
}

// ---------------------------------------------------------------------------
// C-extension (compressed) tests
// ---------------------------------------------------------------------------

test "Compressed: c.li, c.mv, c.add, c.slli, c.ebreak" {
    const system = try run_program_no_ram(@embedFile("test_compressed.bin"));
    try std.testing.expectEqual(@as(u32, 7), system.cpu.read_reg(10)); // c.li 7
    try std.testing.expectEqual(@as(i32, -3), @as(i32, @bitCast(system.cpu.read_reg(11)))); // c.li -3
    try std.testing.expectEqual(@as(u32, 7), system.cpu.read_reg(12)); // c.mv from x10
    try std.testing.expectEqual(@as(u32, 14), system.cpu.read_reg(13)); // c.add 7+7
    try std.testing.expectEqual(@as(u32, 28), system.cpu.read_reg(14)); // c.slli 14<<1
}

// ---------------------------------------------------------------------------
// Debug output peripheral test
// ---------------------------------------------------------------------------

test "Debug output: write bytes to serial" {
    var debug_output: [512]u8 = undefined;
    var debug: std.Io.Writer = .fixed(&debug_output);
    var ram_backing: [4]u8 align(4) = [_]u8{0} ** 4;

    const rom_data = @embedFile("test_debug.bin");
    const S = struct {
        const padded_len = (rom_data.len + 3) & ~@as(usize, 3);
        const padded: [padded_len]u8 align(4) = blk: {
            var p: [padded_len]u8 = [_]u8{0} ** padded_len;
            @memcpy(p[0..rom_data.len], rom_data);
            break :blk p;
        };
    };

    var system = emu.System.init(@as([]align(4) const u8, &S.padded), &ram_backing, &debug);

    const result = system.step(10000);
    if (result) |_| {
        return error.TestDidNotTerminate;
    } else |err| switch (err) {
        error.Ebreak => {},
        else => return err,
    }
    try std.testing.expectEqualStrings("Hi\n", debug.buffered());
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
