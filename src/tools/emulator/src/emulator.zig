const std = @import("std");

/// A fully emulated system combining a RV32IMC CPU core with a memory bus
/// that maps ROM, MMIO peripherals, and RAM according to the Ashet OS
/// memory map (see README.md).
pub const System = struct {
    cpu: Cpu,
    rom: []align(4) const u8,
    ram: []align(4) u8,
    mmio: MmioPageTable,

    pub fn init(rom: []align(4) const u8, ram: []align(4) u8) System {
        return .{
            .cpu = .{},
            .rom = rom,
            .ram = ram,
            .mmio = .{},
        };
    }

    /// Execute `count` instructions. Returns early if the CPU enters a trap
    /// (illegal instruction, bus fault, ecall, ebreak) or encounters a host
    /// I/O error. The result indicates how many instructions were executed
    /// and the trap that stopped execution, if any.
    pub fn step(system: *System, count: usize) StepError!StepResult {
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

    /// Route an MMIO read to the correct peripheral via the page table.
    fn mmio_read(system: *System, address: u32, comptime size: MemAccessSize) BusError!size.get_type() {
        const page: u8 = @truncate((address >> 12) & 0xFF);
        const entry = system.mmio.pages[page] orelse return error.Unmapped;
        const offset: u32 = (@as(u32, page) - @as(u32, entry.base_page)) << 12 | (address & 0xFFF);
        return entry.peri.read(offset, size);
    }

    /// Route an MMIO write to the correct peripheral via the page table.
    fn mmio_write(system: *System, address: u32, comptime size: MemAccessSize, value: size.get_type()) BusError!void {
        const page: u8 = @truncate((address >> 12) & 0xFF);
        const entry = system.mmio.pages[page] orelse return error.Unmapped;
        const offset: u32 = (@as(u32, page) - @as(u32, entry.base_page)) << 12 | (address & 0xFFF);
        return entry.peri.write(offset, size, value);
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
    regs: [31]u32 = [_]u32{0} ** 31,
    pc: u32 = 0,
    total_instructions: u64 = 0,

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

    /// Fetch, decode, and execute up to `count` instructions. Returns a
    /// `StepResult` indicating how many instructions ran and whether a
    /// trap stopped execution early.
    ///
    /// Each iteration fetches either a 32-bit or 16-bit instruction based
    /// on the low two bits of the halfword at PC (the "C" extension marker).
    /// After execution, PC advances by 4 or 2 bytes accordingly unless the
    /// instruction itself modified PC (branches, jumps).
    pub fn execute(self: *Cpu, system: *System, count: usize) StepError!StepResult {
        for (0..count) |i| {
            // Fetch the first halfword to determine instruction length.
            const low_hw = system.bus_read(self.pc, .u16) catch |err| {
                self.total_instructions += i;
                return .{ .instructions_executed = i, .trap = .{ .instruction_fetch_fault = .{
                    .cause = err,
                    .address = self.pc,
                    .size = .u16,
                } } };
            };

            const maybe_trap = if (low_hw & 0b11 != 0b11)
                // Compressed 16-bit instruction (C extension).
                try self.execute_compressed(system, low_hw)
            else blk: {
                // Standard 32-bit instruction: fetch the upper halfword.
                const high_hw = system.bus_read(self.pc +% 2, .u16) catch |err| {
                    self.total_instructions += i;
                    return .{ .instructions_executed = i, .trap = .{ .instruction_fetch_fault = .{
                        .cause = err,
                        .address = self.pc +% 2,
                        .size = .u16,
                    } } };
                };
                const instruction: u32 = @as(u32, high_hw) << 16 | low_hw;
                break :blk try self.execute_32bit(system, instruction);
            };

            if (maybe_trap) |trap| {
                self.total_instructions += i;
                return .{ .instructions_executed = i, .trap = trap };
            }
        }
        self.total_instructions += count;
        return .{ .instructions_executed = count };
    }

    /// Execute a single 32-bit RISC-V instruction. Dispatches on the
    /// major opcode (bits [6:2]) to the appropriate format handler.
    /// PC is advanced by 4 unless the instruction is a taken branch or jump.
    /// Returns null on success, or a CpuTrap if the instruction caused a trap.
    fn execute_32bit(self: *Cpu, system: *System, inst: u32) StepError!?CpuTrap {
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
                if (dec.funct3 != 0b000) return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
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
                    else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
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
                    0b000 => sign_extend(u8, system.bus_read(addr, .u8) catch |err| return CpuTrap{ .load_access_fault = .{ .cause = err, .address = addr, .size = .u8 } }),
                    // LH — sign-extended halfword
                    0b001 => sign_extend(u16, system.bus_read(addr, .u16) catch |err| return CpuTrap{ .load_access_fault = .{ .cause = err, .address = addr, .size = .u16 } }),
                    // LW — word
                    0b010 => system.bus_read(addr, .u32) catch |err| return CpuTrap{ .load_access_fault = .{ .cause = err, .address = addr, .size = .u32 } },
                    // LBU — zero-extended byte
                    0b100 => system.bus_read(addr, .u8) catch |err| return CpuTrap{ .load_access_fault = .{ .cause = err, .address = addr, .size = .u8 } },
                    // LHU — zero-extended halfword
                    0b101 => system.bus_read(addr, .u16) catch |err| return CpuTrap{ .load_access_fault = .{ .cause = err, .address = addr, .size = .u16 } },
                    else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
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
                    0b000 => system.bus_write(addr, .u8, @truncate(rs2_val)) catch |err| return CpuTrap{ .store_access_fault = .{ .cause = err, .address = addr, .size = .u8 } },
                    // SH
                    0b001 => system.bus_write(addr, .u16, @truncate(rs2_val)) catch |err| return CpuTrap{ .store_access_fault = .{ .cause = err, .address = addr, .size = .u16 } },
                    // SW
                    0b010 => system.bus_write(addr, .u32, rs2_val) catch |err| return CpuTrap{ .store_access_fault = .{ .cause = err, .address = addr, .size = .u32 } },
                    else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
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
                        if (inst >> 25 != 0) return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
                        break :blk rs1_val << shamt;
                    },
                    0b101 => blk: {
                        const funct7: u7 = @truncate(inst >> 25);
                        break :blk switch (funct7) {
                            0b0000000 => rs1_val >> shamt, // SRLI
                            0b0100000 => @bitCast(@as(i32, @bitCast(rs1_val)) >> shamt), // SRAI
                            else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
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
                    execute_m_ext(rs1_val, rs2_val, dec.funct3)
                else if (dec.funct7 == 0b0000000 or dec.funct7 == 0b0100000)
                    // Base integer register-register ops
                    execute_base_reg(rs1_val, rs2_val, dec.funct3, dec.funct7)
                else
                    return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };

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
                    return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
                switch (dec.imm) {
                    0 => return .ecall,
                    1 => return .ebreak,
                    else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
                }
            },
            else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
        }
        return null;
    }

    /// Execute a single 16-bit compressed (RV32C) instruction. The compressed
    /// ISA encodes common operations in half the space by using restricted
    /// register fields (3-bit fields address x8–x15) and implicit operands.
    ///
    /// Dispatches on the quadrant (bits [1:0]) and funct3 (bits [15:13]).
    /// Returns null on success, or a CpuTrap if the instruction caused a trap.
    fn execute_compressed(self: *Cpu, system: *System, inst: u16) StepError!?CpuTrap {
        const quadrant: u2 = @truncate(inst);
        const funct3: u3 = @truncate(inst >> 13);

        switch (quadrant) {
            // Quadrant 0
            0b00 => switch (funct3) {
                // C.ADDI4SPN — rd' = sp + nzuimm
                0b000 => {
                    const nzuimm = c_addi4spn_imm(inst);
                    if (nzuimm == 0) return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
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
                    const value = system.bus_read(addr, .u32) catch |err| return CpuTrap{ .load_access_fault = .{ .cause = err, .address = addr, .size = .u32 } };
                    self.write_reg(rd, value);
                    self.pc +%= 2;
                },
                // C.SW — stores a 32-bit value to memory
                0b110 => {
                    const rs2 = c_rd_prime(inst); // In C.SW the rd' field is actually rs2'
                    const rs1 = c_rs1_prime(inst);
                    const offset = c_lw_sw_imm(inst);
                    const addr = self.read_reg(rs1) +% offset;
                    system.bus_write(addr, .u32, self.read_reg(rs2)) catch |err| return CpuTrap{ .store_access_fault = .{ .cause = err, .address = addr, .size = .u32 } };
                    self.pc +%= 2;
                },
                else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
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
                        if (imm == 0) return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
                        self.write_reg(2, self.read_reg(2) +% imm);
                    } else {
                        // C.LUI — load upper immediate into rd
                        const imm = c_lui_imm(inst);
                        if (imm == 0) return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
                        self.write_reg(rd, imm);
                    }
                    self.pc +%= 2;
                },
                // C.SRLI, C.SRAI, C.ANDI, C.SUB, C.XOR, C.OR, C.AND
                0b100 => {
                    self.execute_c_alu(inst);
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
                    if (rd == 0) return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
                    const offset = c_lwsp_imm(inst);
                    const addr = self.read_reg(2) +% offset;
                    const value = system.bus_read(addr, .u32) catch |err| return CpuTrap{ .load_access_fault = .{ .cause = err, .address = addr, .size = .u32 } };
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
                            if (rd == 0) return CpuTrap{ .illegal_instruction = .{ .address = self.pc } };
                            self.pc = self.read_reg(rd) & ~@as(u32, 1);
                        } else {
                            // C.MV — rd = rs2
                            self.write_reg(rd, self.read_reg(rs2));
                            self.pc +%= 2;
                        }
                    } else {
                        if (rs2 == 0 and rd == 0) {
                            // C.EBREAK
                            return .ebreak;
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
                    system.bus_write(addr, .u32, self.read_reg(rs2)) catch |err| return CpuTrap{ .store_access_fault = .{ .cause = err, .address = addr, .size = .u32 } };
                    self.pc +%= 2;
                },
                else => return CpuTrap{ .illegal_instruction = .{ .address = self.pc } },
            },
            // Quadrant 3 would be 32-bit instructions; should never reach here.
            0b11 => unreachable,
        }
        return null;
    }

    /// Handle the C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND
    /// subgroup. These all share funct3=0b100 in quadrant 1 and are further
    /// distinguished by bits [11:10] and, for register-register ops, bits [6:5].
    fn execute_c_alu(self: *Cpu, inst: u16) void {
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
fn execute_base_reg(rs1: u32, rs2: u32, funct3: u3, funct7: u7) u32 {
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
fn execute_m_ext(rs1: u32, rs2: u32, funct3: u3) u32 {
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
// Step Result and Trap Types
// ============================================================================

/// Host-level errors that indicate a real emulator/environment failure,
/// not a CPU trap. Reserved for future use (e.g. block device I/O errors
/// surfaced through the bus).
pub const StepError = error{IoError};

/// Result of executing instructions.
pub const StepResult = struct {
    /// Number of instructions successfully executed.
    instructions_executed: usize,
    /// Why execution stopped. Null if the full requested count was reached.
    trap: ?CpuTrap = null,
};

/// A CPU trap — an expected event that stops instruction execution.
/// These are normal CPU behavior, not emulator errors.
pub const CpuTrap = union(enum) {
    /// The program executed an EBREAK instruction (or C.EBREAK).
    ebreak,
    /// The program executed an ECALL instruction.
    ecall,
    /// The instruction word does not correspond to any valid RV32IMC encoding.
    illegal_instruction: IllegalInstructionFault,
    /// Fetching the next instruction failed (bus fault at PC).
    instruction_fetch_fault: BusFault,
    /// A load instruction triggered a bus fault.
    load_access_fault: BusFault,
    /// A store instruction triggered a bus fault.
    store_access_fault: BusFault,
};

pub const IllegalInstructionFault = struct {
    address: u32,
};

pub const BusFault = struct {
    cause: BusError,
    address: u32,
    size: MemAccessSize,
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

// ============================================================================
// Peripheral Interface
// ============================================================================

pub const Peripheral = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        read8_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u8,
        read16_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u16,
        read32_fn: *const fn (peri: *Peripheral, offset: u32) BusError!u32,

        write8_fn: *const fn (peri: *Peripheral, offset: u32, value: u8) BusError!void,
        write16_fn: *const fn (peri: *Peripheral, offset: u32, value: u16) BusError!void,
        write32_fn: *const fn (peri: *Peripheral, offset: u32, value: u32) BusError!void,
    };

    /// Bridge from comptime MemAccessSize to runtime vtable dispatch.
    pub fn read(self: *Peripheral, offset: u32, comptime size: MemAccessSize) BusError!size.get_type() {
        return switch (size) {
            .u8 => self.vtable.read8_fn(self, offset),
            .u16 => self.vtable.read16_fn(self, offset),
            .u32 => self.vtable.read32_fn(self, offset),
        };
    }

    pub fn write(self: *Peripheral, offset: u32, comptime size: MemAccessSize, value: size.get_type()) BusError!void {
        return switch (size) {
            .u8 => self.vtable.write8_fn(self, offset, value),
            .u16 => self.vtable.write16_fn(self, offset, value),
            .u32 => self.vtable.write32_fn(self, offset, value),
        };
    }

    /// Generate a VTable for a concrete peripheral type T.
    /// T must embed a `peri: Peripheral` field and implement:
    ///   fn busRead(self: *T, comptime size: MemAccessSize, offset: u32) BusError!size.get_type()
    ///   fn busWrite(self: *T, comptime size: MemAccessSize, offset: u32, value: size.get_type()) BusError!void
    pub fn makeVTable(comptime T: type) VTable {
        return .{
            .read8_fn = &struct {
                fn f(p: *Peripheral, offset: u32) BusError!u8 {
                    const self: *T = @fieldParentPtr("peri", p);
                    return self.busRead(.u8, offset);
                }
            }.f,
            .read16_fn = &struct {
                fn f(p: *Peripheral, offset: u32) BusError!u16 {
                    const self: *T = @fieldParentPtr("peri", p);
                    return self.busRead(.u16, offset);
                }
            }.f,
            .read32_fn = &struct {
                fn f(p: *Peripheral, offset: u32) BusError!u32 {
                    const self: *T = @fieldParentPtr("peri", p);
                    return self.busRead(.u32, offset);
                }
            }.f,
            .write8_fn = &struct {
                fn f(p: *Peripheral, offset: u32, value: u8) BusError!void {
                    const self: *T = @fieldParentPtr("peri", p);
                    return self.busWrite(.u8, offset, value);
                }
            }.f,
            .write16_fn = &struct {
                fn f(p: *Peripheral, offset: u32, value: u16) BusError!void {
                    const self: *T = @fieldParentPtr("peri", p);
                    return self.busWrite(.u16, offset, value);
                }
            }.f,
            .write32_fn = &struct {
                fn f(p: *Peripheral, offset: u32, value: u32) BusError!void {
                    const self: *T = @fieldParentPtr("peri", p);
                    return self.busWrite(.u32, offset, value);
                }
            }.f,
        };
    }
};

// ============================================================================
// MMIO Page Table
// ============================================================================

pub const MmioPageTable = struct {
    pub const page_size = 4096;

    pub const Entry = struct {
        peri: *Peripheral,
        base_page: u8,
    };

    pages: [256]?Entry = [_]?Entry{null} ** 256,

    pub fn map(self: *MmioPageTable, page: u8, peri: *Peripheral) void {
        self.pages[page] = .{ .peri = peri, .base_page = page };
    }

    pub fn mapRange(self: *MmioPageTable, start_page: u8, count: u8, peri: *Peripheral) void {
        for (0..count) |i| {
            self.pages[start_page + @as(u8, @intCast(i))] = .{ .peri = peri, .base_page = start_page };
        }
    }
};

// ============================================================================
// Peripheral Implementations
// ============================================================================

pub const DebugOutput = struct {
    peri: Peripheral,
    writer: *std.Io.Writer,

    const vtable = Peripheral.makeVTable(DebugOutput);

    pub fn init(writer: *std.Io.Writer) DebugOutput {
        return .{
            .peri = .{ .vtable = &vtable },
            .writer = writer,
        };
    }

    pub fn peripheral(self: *DebugOutput) *Peripheral {
        return &self.peri;
    }

    fn busRead(_: *DebugOutput, comptime size: MemAccessSize, _: u32) BusError!size.get_type() {
        return error.Unmapped;
    }

    fn busWrite(self: *DebugOutput, comptime size: MemAccessSize, offset: u32, value: size.get_type()) BusError!void {
        if (size != .u8) {
            if (offset == 0) return error.InvalidSize;
            return error.Unmapped;
        }
        if (offset != 0) return error.Unmapped;
        self.writer.writeByte(@truncate(value)) catch |err| {
            std.log.scoped(.rv32_emulator).err("failed to write debug output: {}", .{err});
        };
    }
};

pub const SystemInfo = struct {
    peri: Peripheral,
    ram_size: u32,

    const vtable = Peripheral.makeVTable(SystemInfo);

    pub fn init(ram_size: u32) SystemInfo {
        return .{
            .peri = .{ .vtable = &vtable },
            .ram_size = ram_size,
        };
    }

    pub fn peripheral(self: *SystemInfo) *Peripheral {
        return &self.peri;
    }

    fn busRead(self: *SystemInfo, comptime size: MemAccessSize, offset: u32) BusError!size.get_type() {
        if (offset != 0) return error.Unmapped;
        if (size != .u32) return error.InvalidSize;
        return self.ram_size;
    }

    fn busWrite(_: *SystemInfo, comptime _: MemAccessSize, _: u32, _: anytype) BusError!void {
        return error.WriteProtected;
    }
};

pub const Timer = struct {
    peri: Peripheral = .{ .vtable = &vtable },
    mtime_us: u64 = 0,
    rtc_s: u64 = 0,
    mtime_hi_latch: u32 = 0,
    rtc_hi_latch: u32 = 0,

    const vtable = Peripheral.makeVTable(Timer);

    pub fn peripheral(self: *Timer) *Peripheral {
        return &self.peri;
    }

    /// Called by the host to update the current time.
    pub fn setTime(self: *Timer, mtime_us: u64, rtc_s: u64) void {
        self.mtime_us = mtime_us;
        self.rtc_s = rtc_s;
    }

    fn busRead(self: *Timer, comptime size: MemAccessSize, offset: u32) BusError!size.get_type() {
        if (size != .u32) return error.InvalidSize;
        return switch (offset) {
            0x00 => blk: {
                self.mtime_hi_latch = @truncate(self.mtime_us >> 32);
                break :blk @truncate(self.mtime_us);
            },
            0x04 => self.mtime_hi_latch,
            0x10 => blk: {
                self.rtc_hi_latch = @truncate(self.rtc_s >> 32);
                break :blk @truncate(self.rtc_s);
            },
            0x14 => self.rtc_hi_latch,
            else => return error.Unmapped,
        };
    }

    fn busWrite(_: *Timer, comptime _: MemAccessSize, _: u32, _: anytype) BusError!void {
        return error.WriteProtected;
    }
};

pub const VideoControl = struct {
    peri: Peripheral = .{ .vtable = &vtable },
    flush_requested: bool = false,

    const vtable = Peripheral.makeVTable(VideoControl);

    pub fn peripheral(self: *VideoControl) *Peripheral {
        return &self.peri;
    }

    pub fn isFlushRequested(self: *const VideoControl) bool {
        return self.flush_requested;
    }

    pub fn ackFlush(self: *VideoControl) void {
        self.flush_requested = false;
    }

    fn busRead(_: *VideoControl, comptime size: MemAccessSize, _: u32) BusError!size.get_type() {
        return error.Unmapped;
    }

    fn busWrite(self: *VideoControl, comptime size: MemAccessSize, offset: u32, value: size.get_type()) BusError!void {
        if (offset != 0) return error.Unmapped;
        if (size != .u32) return error.InvalidSize;
        self.flush_requested = (value != 0);
    }
};

pub const Framebuffer = struct {
    pub const WIDTH = 640;
    pub const HEIGHT = 400;
    pub const BUFFER_SIZE = WIDTH * HEIGHT;
    pub const PAGE_COUNT = @divFloor((BUFFER_SIZE + MmioPageTable.page_size - 1), MmioPageTable.page_size);

    peri: Peripheral = .{ .vtable = &vtable },
    buffer: [BUFFER_SIZE]u8 = [_]u8{0} ** BUFFER_SIZE,

    const vtable = Peripheral.makeVTable(Framebuffer);

    pub fn peripheral(self: *Framebuffer) *Peripheral {
        return &self.peri;
    }

    pub fn pixels(self: *Framebuffer) *[BUFFER_SIZE]u8 {
        return &self.buffer;
    }

    pub fn pixelsConst(self: *const Framebuffer) *const [BUFFER_SIZE]u8 {
        return &self.buffer;
    }

    fn busRead(self: *Framebuffer, comptime size: MemAccessSize, offset: u32) BusError!size.get_type() {
        const bytes = comptime size.byte_count();
        if (offset + bytes > BUFFER_SIZE) return error.Unmapped;
        return std.mem.readInt(size.get_type(), self.buffer[offset..][0..bytes], .little);
    }

    fn busWrite(self: *Framebuffer, comptime size: MemAccessSize, offset: u32, value: size.get_type()) BusError!void {
        const bytes = comptime size.byte_count();
        if (offset + bytes > BUFFER_SIZE) return error.Unmapped;
        std.mem.writeInt(size.get_type(), self.buffer[offset..][0..bytes], value, .little);
    }
};

/// A generic fixed-size ring buffer for 32-bit events with deduplication.
/// Used by both the Keyboard and Mouse peripherals. Consecutive identical
/// events are coalesced to avoid flooding the FIFO.
pub fn EventFifo(comptime capacity: u16) type {
    return struct {
        const Self = @This();
        pub const FIFO_SIZE = capacity;

        fifo: [capacity]u32 = [_]u32{0} ** capacity,
        head: u16 = 0,
        tail: u16 = 0,
        count: u16 = 0,
        /// Last enqueued event for deduplication.
        last_event: ?u32 = null,

        /// Push an event. Returns false if FIFO is full.
        /// Deduplicates: if the event is identical to the last pushed event,
        /// it is silently accepted but not enqueued.
        pub fn push(self: *Self, entry: u32) bool {
            if (self.last_event == entry) return true;
            if (self.count >= capacity) return false;

            self.last_event = entry;
            self.fifo[self.tail] = entry;
            self.tail = @intCast((@as(u32, self.tail) + 1) % capacity);
            self.count += 1;
            return true;
        }

        /// Pop and return one entry. Returns 0 if empty.
        pub fn pop(self: *Self) u32 {
            if (self.count == 0) return 0;
            const entry = self.fifo[self.head];
            self.head = @intCast((@as(u32, self.head) + 1) % capacity);
            self.count -= 1;
            return entry;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.count == 0;
        }
    };
}

/// An Input Event Device provides a FIFO of 32-bit events to the emulated
/// system. Both the Keyboard and Mouse use this type with the same register
/// layout: STATUS at +0x00 and DATA at +0x04.
pub fn InputEventDevice(comptime fifo_capacity: u16) type {
    return struct {
        const Self = @This();

        peri: Peripheral = .{ .vtable = &vtable },
        fifo: EventFifo(fifo_capacity) = .{},

        const vtable = Peripheral.makeVTable(Self);

        pub fn peripheral(self: *Self) *Peripheral {
            return &self.peri;
        }

        fn busRead(self: *Self, comptime size: MemAccessSize, offset: u32) BusError!size.get_type() {
            if (size != .u32) return error.InvalidSize;
            return switch (offset) {
                0x00 => @as(u32, if (!self.fifo.isEmpty()) 1 else 0),
                0x04 => self.fifo.pop(),
                else => return error.Unmapped,
            };
        }

        fn busWrite(_: *Self, comptime _: MemAccessSize, _: u32, _: anytype) BusError!void {
            return error.WriteProtected;
        }
    };
}

pub const Keyboard = struct {
    pub const FIFO_SIZE = 16;
    pub const KeyState = enum(u1) { up = 0, down = 1 };

    device: InputEventDevice(FIFO_SIZE) = .{},

    pub fn peripheral(self: *Keyboard) *Peripheral {
        return self.device.peripheral();
    }

    /// Push a key event. Returns false if FIFO is full.
    pub fn pushKey(self: *Keyboard, usage: u16, state: KeyState) bool {
        const entry: u32 = (@as(u32, @intFromEnum(state)) << 31) | @as(u32, usage);
        return self.device.fifo.push(entry);
    }
};

pub const Mouse = struct {
    pub const FIFO_SIZE = 64;

    pub const EventType = enum(u2) {
        pointing = 0b00,
        button_down = 0b01,
        button_up = 0b10,
    };

    pub const Button = enum(u16) {
        left = 0,
        right = 1,
        middle = 2,
    };

    const PointingEntry = packed struct(u32) {
        y: u12,
        x: u12,
        padding: u6 = 0,
        type: EventType,
    };
    const ButtonEntry = packed struct(u32) {
        button: Button,
        padding: u14 = 0,
        type: EventType,
    };

    device: InputEventDevice(FIFO_SIZE) = .{},

    pub fn peripheral(self: *Mouse) *Peripheral {
        return self.device.peripheral();
    }

    /// Push a pointing event with absolute coordinates (clamped to u12).
    pub fn pushPointing(self: *Mouse, x: i32, y: i32) bool {
        const cx: u12 = @intCast(std.math.clamp(x, 0, 4095));
        const cy: u12 = @intCast(std.math.clamp(y, 0, 4095));

        const entry: PointingEntry = .{
            .x = cx,
            .y = cy,
            .type = .pointing,
        };
        return self.device.fifo.push(@bitCast(entry));
    }

    /// Push a button down event.
    pub fn pushButtonDown(self: *Mouse, button: Button) bool {
        const entry: ButtonEntry = .{
            .button = button,
            .type = .button_down,
        };
        return self.device.fifo.push(@bitCast(entry));
    }

    /// Push a button up event.
    pub fn pushButtonUp(self: *Mouse, button: Button) bool {
        const entry: ButtonEntry = .{
            .button = button,
            .type = .button_up,
        };
        return self.device.fifo.push(@bitCast(entry));
    }
};

pub const BlockDevice = struct {
    pub const BLOCK_SIZE = 512;
    pub const BUFFER_OFFSET = 0x100;

    pub const Command = enum(u32) {
        read = 1,
        write = 2,
        clear_error = 3,
        _,
    };

    pub const Request = struct {
        is_write: bool,
        lba: u32,
    };

    peri: Peripheral,
    present: bool,
    busy: bool,
    err_flag: bool,
    block_count: u32,
    lba: u32,
    buffer: [BLOCK_SIZE]u8,
    pending_request: ?Request,
    /// Whether getPendingRequest has already been called for the current request.
    request_consumed: bool,

    const vtable = Peripheral.makeVTable(BlockDevice);

    pub fn init(present: bool, block_count: u32) BlockDevice {
        return .{
            .peri = .{ .vtable = &vtable },
            .present = present,
            .busy = false,
            .err_flag = false,
            .block_count = if (present) block_count else 0,
            .lba = 0,
            .buffer = [_]u8{0} ** BLOCK_SIZE,
            .pending_request = null,
            .request_consumed = false,
        };
    }

    pub fn peripheral(self: *BlockDevice) *Peripheral {
        return &self.peri;
    }

    /// Check if there is a pending request. Returns it exactly once, then null.
    pub fn getPendingRequest(self: *BlockDevice) ?Request {
        if (self.request_consumed) return null;
        if (self.pending_request) |req| {
            self.request_consumed = true;
            return req;
        }
        return null;
    }

    pub fn transferBuffer(self: *BlockDevice) *[BLOCK_SIZE]u8 {
        return &self.buffer;
    }

    pub fn complete(self: *BlockDevice, success: bool) error{NoPendingRequest}!void {
        if (self.pending_request == null) return error.NoPendingRequest;
        self.busy = false;
        self.err_flag = !success;
        self.pending_request = null;
        self.request_consumed = false;
    }

    fn isBufferAccessible(self: *const BlockDevice) bool {
        return self.present and !self.busy and !self.err_flag;
    }

    fn busRead(self: *BlockDevice, comptime size: MemAccessSize, offset: u32) BusError!size.get_type() {
        // Buffer region
        if (offset >= BUFFER_OFFSET and offset < BUFFER_OFFSET + BLOCK_SIZE) {
            if (!self.isBufferAccessible()) return error.Unmapped;
            const buf_off = offset - BUFFER_OFFSET;
            const bytes = comptime size.byte_count();
            if (buf_off + bytes > BLOCK_SIZE) return error.Unmapped;
            return std.mem.readInt(size.get_type(), self.buffer[buf_off..][0..bytes], .little);
        }
        // Register region: u32 only
        if (size != .u32) return error.InvalidSize;
        return switch (offset) {
            0x00 => @as(u32, @intFromBool(self.present)) |
                (@as(u32, @intFromBool(self.busy)) << 1) |
                (@as(u32, @intFromBool(self.err_flag)) << 2),
            0x04 => self.block_count,
            0x08 => self.lba,
            else => return error.Unmapped,
        };
    }

    fn busWrite(self: *BlockDevice, comptime size: MemAccessSize, offset: u32, value: size.get_type()) BusError!void {
        // Buffer region
        if (offset >= BUFFER_OFFSET and offset < BUFFER_OFFSET + BLOCK_SIZE) {
            if (!self.isBufferAccessible()) return error.Unmapped;
            const buf_off = offset - BUFFER_OFFSET;
            const bytes = comptime size.byte_count();
            if (buf_off + bytes > BLOCK_SIZE) return error.Unmapped;
            std.mem.writeInt(size.get_type(), self.buffer[buf_off..][0..bytes], value, .little);
            return;
        }
        // Register region: u32 only
        if (size != .u32) return error.InvalidSize;
        switch (offset) {
            0x00, 0x04 => return error.WriteProtected,
            0x08 => {
                if (!self.present) return;
                self.lba = value;
            },
            0x0C => {
                if (!self.present or self.busy) return;
                const cmd: Command = @enumFromInt(value);
                switch (cmd) {
                    .read => {
                        self.busy = true;
                        self.err_flag = false;
                        self.pending_request = .{ .is_write = false, .lba = self.lba };
                        self.request_consumed = false;
                    },
                    .write => {
                        self.busy = true;
                        self.err_flag = false;
                        self.pending_request = .{ .is_write = true, .lba = self.lba };
                        self.request_consumed = false;
                    },
                    .clear_error => {
                        self.err_flag = false;
                    },
                    _ => {},
                }
            },
            else => return error.Unmapped,
        }
    }
};
