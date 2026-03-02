const std = @import("std");
const logger = std.log.scoped(.rv32_emulator);

/// A fully emulated system combining a RV32IMC CPU core with a memory bus
/// that maps ROM, MMIO peripherals, and RAM according to the Ashet OS
/// memory map (see README.md).
pub const System = struct {
    cpu: Cpu,
    rom: []align(4) const u8,
    ram: []align(4) u8,
    debug_writer: *std.Io.Writer,

    pub fn init(rom: []align(4) const u8, ram: []align(4) u8, debug_writer: *std.Io.Writer) System {
        return .{
            .cpu = Cpu.init(),
            .rom = rom,
            .ram = ram,
            .debug_writer = debug_writer,
        };
    }

    /// Execute `count` instructions. Returns early if the CPU enters a trap
    /// state (illegal instruction, bus fault, etc.) or executes an EBREAK.
    /// The return value indicates how many instructions were actually executed,
    /// which may be less than `count` if execution was cut short.
    pub fn step(system: *System, count: usize) CpuError!usize {
        return system.cpu.execute(system, count);
    }

    /// Translate a bus address into a read of the appropriate memory region
    /// or peripheral register. The MMIO region is dispatched by page-aligned
    /// peripheral ID derived from bits [19:12] of the address.
    pub fn bus_read(system: *System, address: u32, comptime size: MemAccessSize) BusError!size.get_type() {
        if (!size.get_alignment().check(address))
            return error.UnalignedAccess;
        const bytes = comptime size.byte_count();

        if (address < 0x40000000) {
            // ROM: 0x00000000..0x3FFFFFFF
            if (address +| bytes > system.rom.len)
                return error.Unmapped;
            return std.mem.readInt(size.get_type(), system.rom[address..][0..bytes], .little);
        } else if (address < 0x80000000) {
            // MMIO: 0x40000000..0x7FFFFFFF
            return system.mmio_read(address, size);
        } else {
            // RAM: 0x80000000..0xFFFFFFFF
            const offset = address - 0x80000000;
            if (offset +| bytes > system.ram.len)
                return error.Unmapped;
            return std.mem.readInt(size.get_type(), system.ram[offset..][0..bytes], .little);
        }
    }

    /// Translate a bus address into a write to the appropriate memory region
    /// or peripheral register. ROM writes always fault with WriteProtected.
    pub fn bus_write(system: *System, address: u32, comptime size: MemAccessSize, value: size.get_type()) BusError!void {
        if (!size.get_alignment().check(address))
            return error.UnalignedAccess;
        const bytes = comptime size.byte_count();

        if (address < 0x40000000) {
            // ROM: not writable
            return error.WriteProtected;
        } else if (address < 0x80000000) {
            // MMIO: 0x40000000..0x7FFFFFFF
            return system.mmio_write(address, size, value);
        } else {
            // RAM: 0x80000000..0xFFFFFFFF
            const offset = address - 0x80000000;
            if (offset +| bytes > system.ram.len)
                return error.Unmapped;
            std.mem.writeInt(size.get_type(), system.ram[offset..][0..bytes], value, .little);
        }
    }

    /// Route an MMIO read to the correct peripheral based on the page number
    /// within the MMIO window. Bits [19:12] of the address select the
    /// peripheral, bits [11:0] become the register offset within that peripheral.
    fn mmio_read(system: *System, address: u32, comptime size: MemAccessSize) BusError!size.get_type() {
        _ = system;
        const page = (address >> 12) & 0xFF;
        switch (page) {
            // Framebuffer: pages 0x00..0x3D (250,000 bytes)
            0x00...0x3D => return error.Unmapped, // TODO: framebuffer read
            // Video Control
            0x40 => return error.Unmapped, // TODO: VCTRL
            // Debug Output (write-only)
            0x41 => return error.Unmapped,
            // Keyboard
            0x42 => return error.Unmapped, // TODO: KBD
            // Mouse
            0x43 => return error.Unmapped, // TODO: MOUSE
            // Timer / RTC
            0x44 => return error.Unmapped, // TODO: TIMER
            // System Info
            0x45 => return error.Unmapped, // TODO: SYSINFO
            // Block Device 0
            0x46 => return error.Unmapped, // TODO: BLOCK0
            // Block Device 1
            0x47 => return error.Unmapped, // TODO: BLOCK1
            else => return error.Unmapped,
        }
    }

    /// Route an MMIO write to the correct peripheral. Same page-based dispatch
    /// as mmio_read. The debug output peripheral at page 0x41 is implemented
    /// inline here — it accepts single-byte writes to offset 0x00.
    fn mmio_write(system: *System, address: u32, comptime size: MemAccessSize, value: size.get_type()) BusError!void {
        const page = (address >> 12) & 0xFF;
        const offset: u12 = @truncate(address);
        switch (page) {
            // Framebuffer: pages 0x00..0x3D
            0x00...0x3D => return error.Unmapped, // TODO: framebuffer write
            // Video Control
            0x40 => return error.Unmapped, // TODO: VCTRL
            // Debug Output: single-byte TX register at offset 0
            0x41 => {
                if (size != .u8 or offset != 0)
                    return error.InvalidSize;
                system.debug_writer.writeByte(@truncate(value)) catch |err| {
                    logger.err("failed to write debug output: {t}", .{err});
                };
            },
            // Keyboard (read-only)
            0x42 => return error.WriteProtected,
            // Mouse (read-only)
            0x43 => return error.WriteProtected,
            // Timer / RTC (read-only)
            0x44 => return error.WriteProtected,
            // System Info (read-only)
            0x45 => return error.WriteProtected,
            // Block Device 0
            0x46 => return error.Unmapped, // TODO: BLOCK0
            // Block Device 1
            0x47 => return error.Unmapped, // TODO: BLOCK1
            else => return error.Unmapped,
        }
    }
};

// ============================================================================
// RV32IMC CPU Core
// ============================================================================

/// RV32IMC hart (hardware thread). Contains the 32 integer registers, the
/// program counter, and execution state. Register x0 is hardwired to zero
/// per the RISC-V spec — writes to it are silently discarded.
///
/// The CPU communicates with the outside world exclusively through the
/// `System` bus interface, keeping the core itself platform-independent.
pub const Cpu = struct {
    /// x0 is not stored — it is always zero. Index 0 here is x1.
    regs: [31]u32,
    pc: u32,

    pub fn init() Cpu {
        return .{
            .regs = [_]u32{0} ** 31,
            .pc = 0,
        };
    }

    /// Read a general-purpose register. Returns 0 for x0.
    pub inline fn read_reg(self: *const Cpu, reg: u5) u32 {
        if (reg == 0) return 0;
        return self.regs[reg - 1];
    }

    /// Write a general-purpose register. Writes to x0 are discarded.
    pub inline fn write_reg(self: *Cpu, reg: u5, value: u32) void {
        if (reg == 0) return;
        self.regs[reg - 1] = value;
    }

    /// Fetch, decode, and execute up to `count` instructions. Returns the
    /// number actually executed. Stops early on EBREAK or a CPU fault.
    ///
    /// Each iteration fetches either a 32-bit or 16-bit instruction based
    /// on the low two bits of the halfword at PC (the "C" extension marker).
    /// After execution, PC advances by 4 or 2 bytes accordingly unless the
    /// instruction itself modified PC (branches, jumps).
    pub fn execute(self: *Cpu, system: *System, count: usize) CpuError!usize {
        for (0..count) |_| {
            // Fetch the first halfword to determine instruction length.
            const low_hw = system.bus_read(self.pc, .u16) catch
                return error.InstructionFetchFault;

            if (low_hw & 0b11 != 0b11) {
                // Compressed 16-bit instruction (C extension).
                try self.execute_compressed(system, low_hw);
            } else {
                // Standard 32-bit instruction: fetch the upper halfword.
                const high_hw = system.bus_read(self.pc +% 2, .u16) catch
                    return error.InstructionFetchFault;
                const instruction: u32 = @as(u32, high_hw) << 16 | low_hw;
                try self.execute_32bit(system, instruction);
            }
        }
        return count;
    }

    /// Execute a single 32-bit RISC-V instruction. Dispatches on the
    /// major opcode (bits [6:2]) to the appropriate format handler.
    /// PC is advanced by 4 unless the instruction is a taken branch or jump.
    fn execute_32bit(self: *Cpu, system: *System, inst: u32) CpuError!void {
        const opcode: u7 = @truncate(inst);
        switch (opcode) {
            // LUI — Load Upper Immediate
            0b0110111 => {
                const dec = UType.decode(inst);
                self.write_reg(dec.rd, dec.imm);
                self.pc +%= 4;
            },
            // AUIPC — Add Upper Immediate to PC
            0b0010111 => {
                const dec = UType.decode(inst);
                self.write_reg(dec.rd, self.pc +% dec.imm);
                self.pc +%= 4;
            },
            // JAL — Jump and Link
            0b1101111 => {
                const dec = JType.decode(inst);
                const return_addr = self.pc +% 4;
                const target = self.pc +% dec.imm;
                self.write_reg(dec.rd, return_addr);
                self.pc = target;
            },
            // JALR — Jump and Link Register
            0b1100111 => {
                const dec = IType.decode(inst);
                if (dec.funct3 != 0b000) return error.IllegalInstruction;
                const return_addr = self.pc +% 4;
                // Target is (rs1 + imm) with bit 0 cleared.
                const target = (self.read_reg(dec.rs1) +% dec.imm) & ~@as(u32, 1);
                self.write_reg(dec.rd, return_addr);
                self.pc = target;
            },
            // Branch instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU)
            0b1100011 => {
                const dec = BType.decode(inst);
                const rs1_val = self.read_reg(dec.rs1);
                const rs2_val = self.read_reg(dec.rs2);
                const taken = switch (dec.funct3) {
                    0b000 => rs1_val == rs2_val, // BEQ
                    0b001 => rs1_val != rs2_val, // BNE
                    0b100 => @as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(rs2_val)), // BLT
                    0b101 => @as(i32, @bitCast(rs1_val)) >= @as(i32, @bitCast(rs2_val)), // BGE
                    0b110 => rs1_val < rs2_val, // BLTU
                    0b111 => rs1_val >= rs2_val, // BGEU
                    else => return error.IllegalInstruction,
                };
                if (taken) {
                    self.pc = self.pc +% dec.imm;
                } else {
                    self.pc +%= 4;
                }
            },
            // Load instructions (LB, LH, LW, LBU, LHU)
            0b0000011 => {
                const dec = IType.decode(inst);
                const addr = self.read_reg(dec.rs1) +% dec.imm;
                const value: u32 = switch (dec.funct3) {
                    // LB — sign-extended byte
                    0b000 => sign_extend(u8, system.bus_read(addr, .u8) catch return error.LoadAccessFault),
                    // LH — sign-extended halfword
                    0b001 => sign_extend(u16, system.bus_read(addr, .u16) catch return error.LoadAccessFault),
                    // LW — word
                    0b010 => system.bus_read(addr, .u32) catch return error.LoadAccessFault,
                    // LBU — zero-extended byte
                    0b100 => system.bus_read(addr, .u8) catch return error.LoadAccessFault,
                    // LHU — zero-extended halfword
                    0b101 => system.bus_read(addr, .u16) catch return error.LoadAccessFault,
                    else => return error.IllegalInstruction,
                };
                self.write_reg(dec.rd, value);
                self.pc +%= 4;
            },
            // Store instructions (SB, SH, SW)
            0b0100011 => {
                const dec = SType.decode(inst);
                const addr = self.read_reg(dec.rs1) +% dec.imm;
                const rs2_val = self.read_reg(dec.rs2);
                switch (dec.funct3) {
                    // SB
                    0b000 => system.bus_write(addr, .u8, @truncate(rs2_val)) catch return error.StoreAccessFault,
                    // SH
                    0b001 => system.bus_write(addr, .u16, @truncate(rs2_val)) catch return error.StoreAccessFault,
                    // SW
                    0b010 => system.bus_write(addr, .u32, rs2_val) catch return error.StoreAccessFault,
                    else => return error.IllegalInstruction,
                }
                self.pc +%= 4;
            },
            // Immediate ALU (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
            0b0010011 => {
                const dec = IType.decode(inst);
                const rs1_val = self.read_reg(dec.rs1);
                const shamt: u5 = @truncate(dec.imm);
                const result: u32 = switch (dec.funct3) {
                    0b000 => rs1_val +% dec.imm, // ADDI
                    0b010 => if (@as(i32, @bitCast(rs1_val)) < @as(i32, @bitCast(dec.imm))) @as(u32, 1) else 0, // SLTI
                    0b011 => if (rs1_val < dec.imm) @as(u32, 1) else 0, // SLTIU
                    0b100 => rs1_val ^ dec.imm, // XORI
                    0b110 => rs1_val | dec.imm, // ORI
                    0b111 => rs1_val & dec.imm, // ANDI
                    0b001 => blk: {
                        // SLLI — the upper 7 bits of imm must be zero.
                        if (inst >> 25 != 0) return error.IllegalInstruction;
                        break :blk rs1_val << shamt;
                    },
                    0b101 => blk: {
                        const funct7: u7 = @truncate(inst >> 25);
                        break :blk switch (funct7) {
                            0b0000000 => rs1_val >> shamt, // SRLI
                            0b0100000 => @bitCast(@as(i32, @bitCast(rs1_val)) >> shamt), // SRAI
                            else => return error.IllegalInstruction,
                        };
                    },
                };
                self.write_reg(dec.rd, result);
                self.pc +%= 4;
            },
            // Register ALU (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
            // plus M-extension (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU)
            0b0110011 => {
                const dec = RType.decode(inst);
                const rs1_val = self.read_reg(dec.rs1);
                const rs2_val = self.read_reg(dec.rs2);

                const result: u32 = if (dec.funct7 == 0b0000001)
                    // M-extension
                    try execute_m_ext(rs1_val, rs2_val, dec.funct3)
                else if (dec.funct7 == 0b0000000 or dec.funct7 == 0b0100000)
                    // Base integer register-register ops
                    try execute_base_reg(rs1_val, rs2_val, dec.funct3, dec.funct7)
                else
                    return error.IllegalInstruction;

                self.write_reg(dec.rd, result);
                self.pc +%= 4;
            },
            // FENCE — treated as a NOP in this single-hart, in-order emulator.
            0b0001111 => {
                self.pc +%= 4;
            },
            // SYSTEM (ECALL, EBREAK)
            0b1110011 => {
                const dec = IType.decode(inst);
                if (dec.funct3 != 0 or dec.rd != 0 or dec.rs1 != 0)
                    return error.IllegalInstruction;
                switch (dec.imm) {
                    0 => return error.Ecall, // ECALL
                    1 => return error.Ebreak, // EBREAK
                    else => return error.IllegalInstruction,
                }
            },
            else => return error.IllegalInstruction,
        }
    }

    /// Execute a single 16-bit compressed (RV32C) instruction. The compressed
    /// ISA encodes common operations in half the space by using restricted
    /// register fields (3-bit fields address x8–x15) and implicit operands.
    ///
    /// Dispatches on the quadrant (bits [1:0]) and funct3 (bits [15:13]).
    fn execute_compressed(self: *Cpu, system: *System, inst: u16) CpuError!void {
        const quadrant: u2 = @truncate(inst);
        const funct3: u3 = @truncate(inst >> 13);

        switch (quadrant) {
            // Quadrant 0
            0b00 => switch (funct3) {
                // C.ADDI4SPN — rd' = sp + nzuimm
                0b000 => {
                    const nzuimm = c_addi4spn_imm(inst);
                    if (nzuimm == 0) return error.IllegalInstruction; // Reserved encoding
                    const rd = c_rd_prime(inst);
                    self.write_reg(rd, self.read_reg(2) +% nzuimm);
                    self.pc +%= 2;
                },
                // C.LW — loads a 32-bit value from memory
                0b010 => {
                    const rd = c_rd_prime(inst);
                    const rs1 = c_rs1_prime(inst);
                    const offset = c_lw_sw_imm(inst);
                    const addr = self.read_reg(rs1) +% offset;
                    const value = system.bus_read(addr, .u32) catch return error.LoadAccessFault;
                    self.write_reg(rd, value);
                    self.pc +%= 2;
                },
                // C.SW — stores a 32-bit value to memory
                0b110 => {
                    const rs2 = c_rd_prime(inst); // In C.SW the rd' field is actually rs2'
                    const rs1 = c_rs1_prime(inst);
                    const offset = c_lw_sw_imm(inst);
                    const addr = self.read_reg(rs1) +% offset;
                    system.bus_write(addr, .u32, self.read_reg(rs2)) catch return error.StoreAccessFault;
                    self.pc +%= 2;
                },
                else => return error.IllegalInstruction,
            },
            // Quadrant 1
            0b01 => switch (funct3) {
                // C.ADDI / C.NOP — add sign-extended 6-bit immediate to rd
                0b000 => {
                    const rd: u5 = @truncate(inst >> 7);
                    const imm = c_ci_imm(inst);
                    // C.NOP when rd == 0 (and imm == 0, but we allow hint NOPs)
                    if (rd != 0) {
                        self.write_reg(rd, self.read_reg(rd) +% imm);
                    }
                    self.pc +%= 2;
                },
                // C.JAL — jump and link, saving return address to x1 (ra)
                0b001 => {
                    const offset = c_j_imm(inst);
                    self.write_reg(1, self.pc +% 2);
                    self.pc = self.pc +% offset;
                },
                // C.LI — load sign-extended 6-bit immediate into rd
                0b010 => {
                    const rd: u5 = @truncate(inst >> 7);
                    const imm = c_ci_imm(inst);
                    self.write_reg(rd, imm);
                    self.pc +%= 2;
                },
                // C.ADDI16SP / C.LUI
                0b011 => {
                    const rd: u5 = @truncate(inst >> 7);
                    if (rd == 2) {
                        // C.ADDI16SP — add sign-extended immediate*16 to sp
                        const imm = c_addi16sp_imm(inst);
                        if (imm == 0) return error.IllegalInstruction; // Reserved
                        self.write_reg(2, self.read_reg(2) +% imm);
                    } else {
                        // C.LUI — load upper immediate into rd
                        const imm = c_lui_imm(inst);
                        if (imm == 0) return error.IllegalInstruction; // Reserved
                        self.write_reg(rd, imm);
                    }
                    self.pc +%= 2;
                },
                // C.SRLI, C.SRAI, C.ANDI, C.SUB, C.XOR, C.OR, C.AND
                0b100 => {
                    try self.execute_c_alu(inst);
                    self.pc +%= 2;
                },
                // C.J — unconditional jump
                0b101 => {
                    const offset = c_j_imm(inst);
                    self.pc = self.pc +% offset;
                },
                // C.BEQZ — branch if rs1' == 0
                0b110 => {
                    const rs1 = c_rs1_prime(inst);
                    const offset = c_b_imm(inst);
                    if (self.read_reg(rs1) == 0) {
                        self.pc = self.pc +% offset;
                    } else {
                        self.pc +%= 2;
                    }
                },
                // C.BNEZ — branch if rs1' != 0
                0b111 => {
                    const rs1 = c_rs1_prime(inst);
                    const offset = c_b_imm(inst);
                    if (self.read_reg(rs1) != 0) {
                        self.pc = self.pc +% offset;
                    } else {
                        self.pc +%= 2;
                    }
                },
            },
            // Quadrant 2
            0b10 => switch (funct3) {
                // C.SLLI — shift rd left by shamt
                0b000 => {
                    const rd: u5 = @truncate(inst >> 7);
                    const shamt: u5 = @truncate(c_ci_imm(inst));
                    if (rd != 0) {
                        self.write_reg(rd, self.read_reg(rd) << shamt);
                    }
                    self.pc +%= 2;
                },
                // C.LWSP — load word from sp + offset into rd
                0b010 => {
                    const rd: u5 = @truncate(inst >> 7);
                    if (rd == 0) return error.IllegalInstruction; // Reserved
                    const offset = c_lwsp_imm(inst);
                    const addr = self.read_reg(2) +% offset;
                    const value = system.bus_read(addr, .u32) catch return error.LoadAccessFault;
                    self.write_reg(rd, value);
                    self.pc +%= 2;
                },
                // C.JR, C.MV, C.JALR, C.ADD, C.EBREAK
                0b100 => {
                    const bit12: u1 = @truncate(inst >> 12);
                    const rd: u5 = @truncate(inst >> 7);
                    const rs2: u5 = @truncate(inst >> 2);
                    if (bit12 == 0) {
                        if (rs2 == 0) {
                            // C.JR — jump to address in rs1
                            if (rd == 0) return error.IllegalInstruction; // Reserved
                            self.pc = self.read_reg(rd) & ~@as(u32, 1);
                        } else {
                            // C.MV — rd = rs2
                            self.write_reg(rd, self.read_reg(rs2));
                            self.pc +%= 2;
                        }
                    } else {
                        if (rs2 == 0 and rd == 0) {
                            // C.EBREAK
                            return error.Ebreak;
                        } else if (rs2 == 0) {
                            // C.JALR — jump to rs1, link to ra
                            self.write_reg(1, self.pc +% 2);
                            self.pc = self.read_reg(rd) & ~@as(u32, 1);
                        } else {
                            // C.ADD — rd = rd + rs2
                            self.write_reg(rd, self.read_reg(rd) +% self.read_reg(rs2));
                            self.pc +%= 2;
                        }
                    }
                },
                // C.SWSP — store word to sp + offset
                0b110 => {
                    const rs2: u5 = @truncate(inst >> 2);
                    const offset = c_swsp_imm(inst);
                    const addr = self.read_reg(2) +% offset;
                    system.bus_write(addr, .u32, self.read_reg(rs2)) catch return error.StoreAccessFault;
                    self.pc +%= 2;
                },
                else => return error.IllegalInstruction,
            },
            // Quadrant 3 would be 32-bit instructions; should never reach here.
            0b11 => unreachable,
        }
    }

    /// Handle the C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND
    /// subgroup. These all share funct3=0b100 in quadrant 1 and are further
    /// distinguished by bits [11:10] and, for register-register ops, bits [6:5].
    fn execute_c_alu(self: *Cpu, inst: u16) CpuError!void {
        const rd = c_rs1_prime(inst); // rd' is in the rs1' position for these
        const rd_val = self.read_reg(rd);
        const sub_funct: u2 = @truncate(inst >> 10);

        switch (sub_funct) {
            // C.SRLI
            0b00 => {
                const shamt: u5 = @truncate(c_ci_imm(inst));
                self.write_reg(rd, rd_val >> shamt);
            },
            // C.SRAI
            0b01 => {
                const shamt: u5 = @truncate(c_ci_imm(inst));
                self.write_reg(rd, @bitCast(@as(i32, @bitCast(rd_val)) >> shamt));
            },
            // C.ANDI
            0b10 => {
                const imm = c_ci_imm(inst);
                self.write_reg(rd, rd_val & imm);
            },
            // Register-register: C.SUB, C.XOR, C.OR, C.AND
            0b11 => {
                const rs2 = c_rd_prime(inst);
                const rs2_val = self.read_reg(rs2);
                const op: u2 = @truncate(inst >> 5);
                const result: u32 = switch (op) {
                    0b00 => rd_val -% rs2_val, // C.SUB
                    0b01 => rd_val ^ rs2_val, // C.XOR
                    0b10 => rd_val | rs2_val, // C.OR
                    0b11 => rd_val & rs2_val, // C.AND
                };
                self.write_reg(rd, result);
            },
        }
    }
};

// ============================================================================
// 32-bit Instruction Format Decoders
// ============================================================================

/// R-type format: register-register operations.
/// Layout: [funct7 | rs2 | rs1 | funct3 | rd | opcode]
const RType = struct {
    rd: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    funct7: u7,

    fn decode(inst: u32) RType {
        return .{
            .rd = @truncate(inst >> 7),
            .funct3 = @truncate(inst >> 12),
            .rs1 = @truncate(inst >> 15),
            .rs2 = @truncate(inst >> 20),
            .funct7 = @truncate(inst >> 25),
        };
    }
};

/// I-type format: immediates with one source register.
/// Layout: [imm[11:0] | rs1 | funct3 | rd | opcode]
/// The 12-bit immediate is sign-extended to 32 bits.
const IType = struct {
    rd: u5,
    funct3: u3,
    rs1: u5,
    imm: u32,

    fn decode(inst: u32) IType {
        return .{
            .rd = @truncate(inst >> 7),
            .funct3 = @truncate(inst >> 12),
            .rs1 = @truncate(inst >> 15),
            .imm = sign_extend_bits(inst >> 20, 12),
        };
    }
};

/// S-type format: stores (immediate split across two fields).
/// Layout: [imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode]
const SType = struct {
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm: u32,

    fn decode(inst: u32) SType {
        const low: u32 = (inst >> 7) & 0x1F;
        const high: u32 = (inst >> 25) & 0x7F;
        return .{
            .funct3 = @truncate(inst >> 12),
            .rs1 = @truncate(inst >> 15),
            .rs2 = @truncate(inst >> 20),
            .imm = sign_extend_bits(high << 5 | low, 12),
        };
    }
};

/// B-type format: conditional branches (immediate encodes a signed PC offset).
/// The offset is always a multiple of 2. Layout scatters the immediate bits
/// to keep the sign bit at position 31 (matching S-type) for simpler hardware.
const BType = struct {
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm: u32,

    fn decode(inst: u32) BType {
        // imm[12|10:5] from bits [31|30:25], imm[4:1|11] from bits [11:8|7]
        const bit_11: u32 = (inst >> 7) & 1;
        const bits_4_1: u32 = (inst >> 8) & 0xF;
        const bits_10_5: u32 = (inst >> 25) & 0x3F;
        const bit_12: u32 = (inst >> 31) & 1;
        const raw = bit_12 << 12 | bit_11 << 11 | bits_10_5 << 5 | bits_4_1 << 1;
        return .{
            .funct3 = @truncate(inst >> 12),
            .rs1 = @truncate(inst >> 15),
            .rs2 = @truncate(inst >> 20),
            .imm = sign_extend_bits(raw, 13),
        };
    }
};

/// U-type format: upper-immediate instructions (LUI, AUIPC).
/// The 20-bit immediate occupies bits [31:12] and is placed in the upper
/// 20 bits of the result with the lower 12 bits zeroed.
const UType = struct {
    rd: u5,
    imm: u32,

    fn decode(inst: u32) UType {
        return .{
            .rd = @truncate(inst >> 7),
            .imm = inst & 0xFFFFF000,
        };
    }
};

/// J-type format: unconditional jumps (JAL). Encodes a 20-bit signed
/// PC-relative offset (always a multiple of 2). The bits are scattered
/// similarly to B-type to keep the sign at bit 31.
const JType = struct {
    rd: u5,
    imm: u32,

    fn decode(inst: u32) JType {
        // imm[20|10:1|11|19:12]
        const bits_19_12: u32 = (inst >> 12) & 0xFF;
        const bit_11: u32 = (inst >> 20) & 1;
        const bits_10_1: u32 = (inst >> 21) & 0x3FF;
        const bit_20: u32 = (inst >> 31) & 1;
        const raw = bit_20 << 20 | bits_19_12 << 12 | bit_11 << 11 | bits_10_1 << 1;
        return .{
            .rd = @truncate(inst >> 7),
            .imm = sign_extend_bits(raw, 21),
        };
    }
};

// ============================================================================
// 16-bit Compressed Instruction Immediate Extractors
// ============================================================================

/// Map the 3-bit rd' field (bits [4:2]) to the actual register number x8–x15.
/// The compressed ISA uses a restricted register set for its small encodings.
inline fn c_rd_prime(inst: u16) u5 {
    return @as(u5, @truncate(inst >> 2)) & 0b111 | 0b01000;
}

/// Map the 3-bit rs1' field (bits [9:7]) to register x8–x15.
inline fn c_rs1_prime(inst: u16) u5 {
    return @as(u5, @truncate(inst >> 7)) & 0b111 | 0b01000;
}

/// C.ADDI4SPN immediate: zero-extended, scaled by 4.
/// Bits: nzuimm[5:4|9:6|2|3] from inst[12:5].
inline fn c_addi4spn_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    return ((w >> 6) & 1) << 2 |
        ((w >> 5) & 1) << 3 |
        ((w >> 11) & 0b11) << 4 |
        ((w >> 7) & 0b1111) << 6;
}

/// C.LW / C.SW offset: zero-extended, word-aligned (multiple of 4).
/// Bits: offset[5:3|2|6] from inst[12:10|6|5].
inline fn c_lw_sw_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    return ((w >> 6) & 1) << 2 |
        ((w >> 10) & 0b111) << 3 |
        ((w >> 5) & 1) << 6;
}

/// CI-format sign-extended 6-bit immediate.
/// Bits: imm[5] from inst[12], imm[4:0] from inst[6:2].
inline fn c_ci_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    const low5 = (w >> 2) & 0x1F;
    const bit5 = (w >> 12) & 1;
    return sign_extend_bits(bit5 << 5 | low5, 6);
}

/// C.J / C.JAL offset: sign-extended, always a multiple of 2.
/// Bits scattered across inst[12:2] encoding an 11-bit signed offset.
inline fn c_j_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    const bit_5 = (w >> 2) & 1;
    const bits_3_1 = (w >> 3) & 0b111;
    const bit_7 = (w >> 6) & 1;
    const bit_6 = (w >> 7) & 1;
    const bit_10 = (w >> 8) & 1;
    const bits_9_8 = (w >> 9) & 0b11;
    const bit_4 = (w >> 11) & 1;
    const bit_11 = (w >> 12) & 1;
    const raw = bits_3_1 << 1 | bit_4 << 4 | bit_5 << 5 | bit_6 << 6 |
        bit_7 << 7 | bits_9_8 << 8 | bit_10 << 10 | bit_11 << 11;
    return sign_extend_bits(raw, 12);
}

/// C.BEQZ / C.BNEZ offset: sign-extended, multiple of 2.
/// Bits: offset[8|4:3] from inst[12:10], offset[7:6|2:1|5] from inst[6:2].
inline fn c_b_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    const bit_5 = (w >> 2) & 1;
    const bits_2_1 = (w >> 3) & 0b11;
    const bits_7_6 = (w >> 5) & 0b11;
    const bits_4_3 = (w >> 10) & 0b11;
    const bit_8 = (w >> 12) & 1;
    const raw = bits_2_1 << 1 | bits_4_3 << 3 | bit_5 << 5 | bits_7_6 << 6 | bit_8 << 8;
    return sign_extend_bits(raw, 9);
}

/// C.ADDI16SP immediate: sign-extended, always a multiple of 16.
/// Bits: nzimm[9] from inst[12], nzimm[4|6|8:7|5] from inst[6:2].
inline fn c_addi16sp_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    const bit_5 = (w >> 2) & 1;
    const bits_8_7 = (w >> 3) & 0b11;
    const bit_6 = (w >> 5) & 1;
    const bit_4 = (w >> 6) & 1;
    const bit_9 = (w >> 12) & 1;
    const raw = bit_4 << 4 | bit_5 << 5 | bit_6 << 6 | bits_8_7 << 7 | bit_9 << 9;
    return sign_extend_bits(raw, 10);
}

/// C.LUI immediate: sign-extended, placed in bits [17:12].
/// Bits: nzimm[17] from inst[12], nzimm[16:12] from inst[6:2].
inline fn c_lui_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    const low5 = (w >> 2) & 0x1F;
    const bit17 = (w >> 12) & 1;
    const raw = bit17 << 17 | low5 << 12;
    return sign_extend_bits(raw, 18);
}

/// C.LWSP offset: zero-extended, word-aligned.
/// Bits: offset[5] from inst[12], offset[4:2|7:6] from inst[6:2].
inline fn c_lwsp_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    const bits_4_2 = (w >> 4) & 0b111;
    const bits_7_6 = (w >> 2) & 0b11;
    const bit_5 = (w >> 12) & 1;
    return bits_4_2 << 2 | bit_5 << 5 | bits_7_6 << 6;
}

/// C.SWSP offset: zero-extended, word-aligned.
/// Bits: offset[5:2|7:6] from inst[12:7].
inline fn c_swsp_imm(inst: u16) u32 {
    const w = @as(u32, inst);
    const bits_5_2 = (w >> 9) & 0b1111;
    const bits_7_6 = (w >> 7) & 0b11;
    return bits_5_2 << 2 | bits_7_6 << 6;
}

// ============================================================================
// ALU Helpers
// ============================================================================

/// Execute base RV32I register-register operations. Funct7 distinguishes
/// ADD from SUB and SRL from SRA; all other ops ignore funct7.
fn execute_base_reg(rs1: u32, rs2: u32, funct3: u3, funct7: u7) CpuError!u32 {
    const shamt: u5 = @truncate(rs2);
    return switch (funct3) {
        0b000 => if (funct7 == 0b0100000) rs1 -% rs2 else rs1 +% rs2, // ADD/SUB
        0b001 => rs1 << shamt, // SLL
        0b010 => if (@as(i32, @bitCast(rs1)) < @as(i32, @bitCast(rs2))) @as(u32, 1) else 0, // SLT
        0b011 => if (rs1 < rs2) @as(u32, 1) else 0, // SLTU
        0b100 => rs1 ^ rs2, // XOR
        0b101 => if (funct7 == 0b0100000) @bitCast(@as(i32, @bitCast(rs1)) >> shamt) else rs1 >> shamt, // SRL/SRA
        0b110 => rs1 | rs2, // OR
        0b111 => rs1 & rs2, // AND
    };
}

/// Execute M-extension operations (multiply/divide). RISC-V specifies that
/// division by zero does not trap — it returns a defined result instead
/// (all-ones for DIV, the dividend for REM). Signed overflow (INT32_MIN / -1)
/// similarly returns defined results without trapping.
fn execute_m_ext(rs1: u32, rs2: u32, funct3: u3) CpuError!u32 {
    const s1: i32 = @bitCast(rs1);
    const s2: i32 = @bitCast(rs2);
    return switch (funct3) {
        // MUL — lower 32 bits of signed × signed
        0b000 => rs1 *% rs2,
        // MULH — upper 32 bits of signed × signed
        0b001 => mulh(s1, s2),
        // MULHSU — upper 32 bits of signed × unsigned
        0b010 => mulhsu(s1, rs2),
        // MULHU — upper 32 bits of unsigned × unsigned
        0b011 => mulhu(rs1, rs2),
        // DIV — signed division, with defined results for /0 and overflow
        0b100 => blk: {
            if (s2 == 0) break :blk @as(u32, 0xFFFFFFFF); // div by zero → all ones
            if (s1 == std.math.minInt(i32) and s2 == -1) break :blk @bitCast(s1); // overflow → dividend
            break :blk @bitCast(@divTrunc(s1, s2));
        },
        // DIVU — unsigned division
        0b101 => blk: {
            if (rs2 == 0) break :blk @as(u32, 0xFFFFFFFF);
            break :blk rs1 / rs2;
        },
        // REM — signed remainder
        0b110 => blk: {
            if (s2 == 0) break :blk rs1; // rem by zero → dividend
            if (s1 == std.math.minInt(i32) and s2 == -1) break :blk @as(u32, 0); // overflow → 0
            break :blk @bitCast(@rem(s1, s2));
        },
        // REMU — unsigned remainder
        0b111 => blk: {
            if (rs2 == 0) break :blk rs1;
            break :blk rs1 % rs2;
        },
    };
}

/// Upper 32 bits of a full signed 32×32→64 multiplication.
fn mulh(a: i32, b: i32) u32 {
    const product: i64 = @as(i64, a) * @as(i64, b);
    return @truncate(@as(u64, @bitCast(product)) >> 32);
}

/// Upper 32 bits of a signed×unsigned 32×32→64 multiplication.
/// The first operand is treated as signed, the second as unsigned.
fn mulhsu(a: i32, b: u32) u32 {
    const product: i64 = @as(i64, a) * @as(i64, @as(u32, b));
    return @truncate(@as(u64, @bitCast(product)) >> 32);
}

/// Upper 32 bits of a full unsigned 32×32→64 multiplication.
fn mulhu(a: u32, b: u32) u32 {
    const product: u64 = @as(u64, a) * @as(u64, b);
    return @truncate(product >> 32);
}

// ============================================================================
// Utility
// ============================================================================

/// Sign-extend a value of `width` bits (stored in the low bits of a u32)
/// to fill all 32 bits. Uses arithmetic right-shift to replicate the sign bit.
inline fn sign_extend_bits(value: u32, comptime width: u6) u32 {
    const shift = 32 - width;
    return @bitCast(@as(i32, @bitCast(value << shift)) >> shift);
}

/// Sign-extend a narrow unsigned integer type to u32 by first bitcasting
/// to the corresponding signed type, then widening (which replicates the
/// sign bit into the upper positions).
inline fn sign_extend(comptime T: type, value: T) u32 {
    const S = std.meta.Int(.signed, @bitSizeOf(T));
    return @bitCast(@as(i32, @as(S, @bitCast(value))));
}

// ============================================================================
// Error Types
// ============================================================================

pub const CpuError = error{
    /// Fetching the next instruction failed (bus fault at PC).
    InstructionFetchFault,

    /// The instruction word does not correspond to any valid RV32IMC encoding.
    IllegalInstruction,

    /// A load instruction triggered a bus fault.
    LoadAccessFault,

    /// A store instruction triggered a bus fault.
    StoreAccessFault,

    /// The program executed an ECALL instruction.
    Ecall,

    /// The program executed an EBREAK instruction (or C.EBREAK).
    Ebreak,
};

pub const MemAccessSize = enum(u8) {
    u8 = 0,
    u16 = 1,
    u32 = 2,

    pub inline fn get_alignment(mas: MemAccessSize) std.mem.Alignment {
        return @enumFromInt(@intFromEnum(mas));
    }

    /// Number of bytes for this access size (1, 2, or 4). Comptime-known
    /// so it can be used to index into slices as a fixed-length array bound.
    pub fn byte_count(comptime mas: MemAccessSize) comptime_int {
        return @as(comptime_int, 1) << @intFromEnum(mas);
    }

    pub fn get_type(comptime mas: MemAccessSize) type {
        return switch (mas) {
            .u8 => u8,
            .u16 => u16,
            .u32 => u32,
        };
    }
};

pub const BusError = error{
    /// The address does not correspond to any mapped region.
    Unmapped,

    /// Access size does not match the register's expected width.
    InvalidSize,

    /// Address is not aligned to the access size boundary.
    UnalignedAccess,

    /// Attempted write to a read-only region (ROM or read-only peripheral).
    WriteProtected,
};

pub const Peripheral = struct {
    /// Bus function access
    vtable: *const VTable,

    /// Size of the peripheral in bytes.
    size: u32,

    pub const VTable = struct {
        read8_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u8,
        read16_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u16,
        read32_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u32,

        write8_fn: *const fn (peri: *Peripheral, offset: u32, value: u8) BusError!void,
        write16_fn: *const fn (peri: *Peripheral, offset: u32, value: u16) BusError!void,
        write32_fn: *const fn (peri: *Peripheral, offset: u32, value: u32) BusError!void,
    };
};
