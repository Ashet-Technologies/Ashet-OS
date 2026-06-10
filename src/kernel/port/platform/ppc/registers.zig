// pub const audio = @import("registers/audio.zig");
// pub const dsp = @import("registers/dsp.zig");
pub const memory = @import("registers/memory.zig");
pub const processor = @import("registers/processor.zig");
// pub const video = @import("registers/video.zig");
// pub const exi = @import("registers/exi.zig");
// pub const pe = @import("registers/pe.zig");
pub const cp = @import("registers/cp.zig");
pub const timebase = @import("registers/timebase.zig");

pub const HID0 = SpecialRegister(1008, packed struct(u32) {
    noopti: bool = false,
    reserved1: u1 = 0,
    bht: bool = false,
    abe: bool = false,
    reserved2: u1 = 0,
    btic: bool = false,
    dcfa: bool = false,
    sge: bool = false,
    ifem: bool = false,
    spd: bool = false,
    dcfi: bool = false,
    icfi: bool = false,
    dlock: bool = false,
    ilock: bool = false,
    dce: bool = false,
    ice: bool = false,
    nhr: bool = false,
    reserved3: u3 = 0,
    dpm: bool = false,
    sleep: bool = false,
    nap: bool = false,
    doze: bool = false,
    par: bool = false,
    eclk: bool = false,
    reserved4: u1 = 0,
    bclk: bool = false,
    ebd: bool = false,
    eba: bool = false,
    dbp: bool = false,
    emcp: bool = false,
});

pub const HID1 = SpecialRegister(1009, packed struct(u32) {
    reserved1: u28 = 0,
    pcr3: u1,
    pcr2: u1,
    pcr1: u1,
    pcr0: u1,
});

pub const HID2 = SpecialRegister(920, packed struct(u32) {
    reserved1: u16 = 0,
    dqoee: bool = false,
    dcmee: bool = false,
    dncee: bool = false,
    dchee: bool = false,
    dqoerr: bool = false,
    dcmerr: bool = false,
    dncerr: bool = false,
    dcherr: bool = false,
    dma_queue_len: u4 = 0, // TODO Double check
    locked_cache_enable: bool = false,
    paired_single_enable: bool = false,
    write_pipe_enable: bool = false,
    loadstore_quantize_enable: bool = false,
});

pub const WPAR = SpecialRegister(921, packed struct(u32) {
    bne: bool = false,
    reserved: u5 = 0,
    address: u26 = 0, // shift away the lowest 6 bits to get the cache line
});

pub const L2CR = SpecialRegister(1017, packed struct(u32) {
    l2ip: bool = false,
    reserved1: u17 = 0,
    l2ts: bool = false,
    l2wt: bool = false,
    reserved2: u1 = 0,
    l2i: bool = false,
    l2do: bool = false,
    reserved3: u7 = 0,
    l2ce: bool = false,
    l2e: bool = false,
});

const BATBlockLength = enum(u11) {
    @"128Kbytes" = 0b0,
    @"256Kbytes" = 0b1,
    @"512Kbytes" = 0b11,
    @"1Mbyte" = 0b111,
    @"2Mbyte" = 0b1111,
    @"4Mbyte" = 0b11111,
    @"8Mbyte" = 0b111111,
    @"16Mbyte" = 0b1111111,
    @"32Mbyte" = 0b11111111,
    @"64Mbyte" = 0b111111111,
    @"128Mbyte" = 0b1111111111,
    @"256Mbyte" = 0b11111111111,
};

pub const BATU = packed struct(u32) {
    /// Problem state valid bit
    vp: bool = false,
    /// Supervisor state valid bit
    vs: bool = false,
    /// Block-length Mask
    bl: BATBlockLength = .@"128Kbytes",
    reserved1: u4 = 0,
    /// Block Effective Page Index
    bepi: u15 = 0,
};

const WIMG = packed struct(u4) {
    guarded: bool = false,
    memory_coherence: bool = false,
    caching_inhibited: bool = false,
    write_through: bool = false,
};

const PP = enum(u2) {
    noaccess = 0,
    readonly = 1,
    readwrite = 2,
};

pub const BATL = packed struct(u32) {
    /// Protection bits
    pp: PP = .noaccess,
    reserved1: u1 = 0,
    /// Storage Access Controls
    wimg: WIMG = .{},
    reserved2: u10 = 0,
    /// Block Real Page Number
    brpn: u15 = 0,
};

pub const IBAT0U = SpecialRegister(528, BATU);
pub const IBAT0L = SpecialRegister(529, BATL);
pub const IBAT1U = SpecialRegister(530, BATU);
pub const IBAT1L = SpecialRegister(531, BATL);
pub const IBAT2U = SpecialRegister(532, BATU);
pub const IBAT2L = SpecialRegister(533, BATL);
pub const IBAT3U = SpecialRegister(534, BATU);
pub const IBAT3L = SpecialRegister(535, BATL);

pub const DBAT0U = SpecialRegister(536, BATU);
pub const DBAT0L = SpecialRegister(537, BATL);
pub const DBAT1U = SpecialRegister(538, BATU);
pub const DBAT1L = SpecialRegister(539, BATL);
pub const DBAT2U = SpecialRegister(540, BATU);
pub const DBAT2L = SpecialRegister(541, BATL);
pub const DBAT3U = SpecialRegister(542, BATU);
pub const DBAT3L = SpecialRegister(543, BATL);

const LDType = enum(u3) {
    noconversion = 0,
    unsigned8bit = 4,
    unsigned16bit = 5,
    signed8bit = 6,
    signed16bit = 7,
};

const GQR = packed struct(u32) {
    st_type: LDType = .noconversion,
    reserved1: u5 = 0,
    /// Twos complement scale from -32 to 31
    st_scale: u6 = 0,
    reserved2: u2 = 0,
    ld_type: LDType = .noconversion,
    reserved3: u5 = 0,
    /// Twos complement scale from -32 to 31
    ld_scale: u6 = 0,
    reserved4: u2 = 0,
};

pub const GQR0 = SpecialRegister(912, GQR);
pub const GQR1 = SpecialRegister(913, GQR);
pub const GQR2 = SpecialRegister(914, GQR);
pub const GQR3 = SpecialRegister(915, GQR);
pub const GQR4 = SpecialRegister(916, GQR);
pub const GQR5 = SpecialRegister(917, GQR);
pub const GQR6 = SpecialRegister(918, GQR);
pub const GQR7 = SpecialRegister(919, GQR);

const RTCSelect = enum(u2) {
    @"31" = 0,
    @"23" = 1,
    @"19" = 2,
    @"15" = 3,
};

const PMC1Events = enum(u7) {
    none = 0,
    processor_cycles = 1,
    instructions = 2,
    tbl_bittransitions = 3,
    instruction_dispatch = 4,
    eieio_instruction = 5,
    tablesearch_cycles = 6,
    l2cache_hit = 7,
    validea_instruction = 8, // TODO Better name
    breakpoint_hit = 9,
    l1cache_latency_miss = 10,
    branch_unresolved = 11,
    dispatcher_stall_cycles = 12,
};

const PMC2Events = enum(u6) {
    none = 0,
    processor_cycles = 1,
    instructions = 2,
    tbl_bittransitions = 3,
    instruction_dispatch = 4,
    l1cache_miss = 5,
    itbl_miss = 6,
    l2cache_i_miss = 7,
    branches_fallthrough = 8,
    reserved_loads = 10,
    loads_and_stores = 11,
    snoops = 12,
    l1cache_castouts = 13,
    systemunit_instructions = 14,
    first_speculative_branch_resolved_correctly = 15,
};

/// Monitor Mode Control 0
pub const MMCR0 = SpecialRegister(952, packed struct(u32) {
    pmc2select: PMC2Events = .none,
    pmc1select: PMC1Events = .none,
    pmctrigger: bool = false,
    pmcintcontrol: bool = false,
    pmc1intcontrol: bool = false,
    threshold: u6 = 0,
    intonbittrans: bool = false,
    rtcselect: RTCSelect = .@"31",
    discount: bool = false,
    enint: bool = false,
    dmr: bool = false,
    dms: bool = false,
    du: bool = false,
    dp: bool = false,
    dis: bool = false,
});

const PMC3Events = enum(u5) {
    none = 0,
    processor_cycles = 1,
    instructions = 2,
    tbl_bittransitions = 3,
    instruction_dispatch = 4,
    l1cache_miss = 5,
    dtbl_miss = 6,
    l2cache_d_miss = 7,
    branches_predicted = 8,
    conditional_store_instructions = 10,
    fpu_instructions = 11,
    l2cache_castout_snoops = 12,
    l2cache_hits = 13,
    l1cache_miss_cycles = 15,
    second_speculative_branch_resolved_correctly = 16,
    bpu_stalls = 17,
};

const PMC4Events = enum(u5) {
    none = 0,
    processor_cycles = 1,
    instructions = 2,
    tbl_bittransitions = 3,
    instruction_dispatch = 4,
    l2cache_castouts = 5,
    dtbl_cycles = 6,
    branches_mispredicted = 8,
    conditional_store_instuctions_with_reservation = 10,
    sync_instuction = 11,
    snoop_retries = 12,
    integer_operations = 13,
    bpu_unresolved_cycles = 14,
};

/// Monitor Mode Control 1
pub const MMCR1 = SpecialRegister(956, packed struct(u32) {
    reserved: u22 = 0,
    pmc4select: PMC4Events = .none,
    pmc3select: PMC3Events = .none,
});

const PMC = packed struct(u32) {
    counter: u31 = 0,
    overflow: bool = false,
};

/// Performance Monitor Counter 1
pub const PMC1 = SpecialRegister(953, PMC);
/// Performance Monitor Counter 2
pub const PMC2 = SpecialRegister(954, PMC);
/// Performance Monitor Counter 3
pub const PMC3 = SpecialRegister(957, PMC);
/// Performance Monitor Counter 4
pub const PMC4 = SpecialRegister(958, PMC);

/// User Performance Monitor Counter 1
pub const UPMC1 = SpecialRegister(937, PMC);
/// User Performance Monitor Counter 2
pub const UPMC2 = SpecialRegister(938, PMC);
/// User Performance Monitor Counter 3
pub const UPMC3 = SpecialRegister(941, PMC);
/// User Performance Monitor Counter 4
pub const UPMC4 = SpecialRegister(942, PMC);
/// Sampled Instruction Address
pub const SIA = SpecialRegister(955, u32);
/// User Sampled Instruction Address
pub const USIA = SpecialRegister(939, u32);

pub const IRQN = SpecialRegister(272, u32);
pub const IRQSP = SpecialRegister(273, u32);
pub const SPRG2 = SpecialRegister(274, u32);
pub const SPRG3 = SpecialRegister(275, u32);

pub const DSISR = SpecialRegister(18, u32);
pub const DAR = SpecialRegister(19, u32);

pub const MSR = packed struct(u32) {
    littleEndian: bool = false,
    resumeInterrupt: bool = false,
    reserved4: u2 = 0,
    dataAddressTranslation: bool = false,
    instructionAddressTranslation: bool = false,
    exceptionPrefix: bool = false,
    reserved3: u1 = 0,
    fpExceptionMode1: bool = false,
    branchTrace: bool = false,
    singlestepTrace: bool = false,
    fpExceptionMode0: bool = false,
    machineCheck: bool = false,
    floatingPoint: bool = false,
    privilegeLevel: bool = false,
    externalInterrupt: bool = false,
    exceptionLittleEndian: bool = false,
    reserved2: u1 = 0,
    powerManagement: bool = false,
    reserved1: u13 = 0,

    pub inline fn read() MSR {
        return asm volatile ("mfmsr %[r]"
            : [r] "=r" (-> MSR),
        );
    }

    pub inline fn write(msr: MSR) void {
        asm volatile ("mtmsr %[r]"
            :
            : [r] "r" (msr),
        );
    }

    pub inline fn modify(fields: anytype) void {
        var val = read();
        inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            @field(val, field.name) = @field(fields, field.name);
        }
        write(val);
    }
};

pub const SSR0 = struct {
    pub inline fn read() u32 {
        return asm volatile ("mfsrr0 %[r]"
            : [r] "=r" (-> u32),
        );
    }

    pub inline fn write(value: u32) void {
        asm volatile ("mtsrr0 %[r]"
            :
            : [r] "r" (value),
        );
    }

    pub inline fn modify(fields: anytype) void {
        var val = read();
        inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            @field(val, field.name) = @field(fields, field.name);
        }
        write(val);
    }
};

pub const SSR1 = struct {
    pub inline fn read() MSR {
        return asm volatile ("mfsrr1 %[r]"
            : [r] "=r" (-> MSR),
        );
    }

    pub inline fn write(msr: MSR) void {
        asm volatile ("mtsrr1 %[r]"
            :
            : [r] "r" (msr),
        );
    }

    pub inline fn modify(fields: anytype) void {
        var val = read();
        inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            @field(val, field.name) = @field(fields, field.name);
        }
        write(val);
    }
};

pub const LR = struct {
    pub inline fn read() u32 {
        return asm volatile ("mflr %[r]"
            : [r] "=r" (-> u32),
        );
    }
};

fn SpecialRegister(register: u10, backingType: type) type {
    return struct {
        // HACK: Force to u16 to avoid but with numbers turning negative in asm
        pub const registerId: u16 = register;
        pub const BackingType = backingType;
        pub const IntegerType = @typeInfo(backingType).@"struct".backing_integer.?;

        pub inline fn read() BackingType {
            return asm volatile ("mfspr %[r], %[reg]"
                : [r] "=r" (-> BackingType),
                : [reg] "i" (registerId),
            );
        }

        pub inline fn write(value: BackingType) void {
            asm volatile ("mtspr %[reg], %[value]"
                :
                : [reg] "i" (registerId),
                  [value] "r" (value),
            );
        }

        pub inline fn zero() void {
            asm volatile ("mtspr %[reg], %[value]"
                :
                : [reg] "i" (registerId),
                  [value] "r" (0),
            );
        }

        pub inline fn modify(fields: anytype) void {
            var val = read();
            inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                @field(val, field.name) = @field(fields, field.name);
            }
            write(val);
        }
    };
}
