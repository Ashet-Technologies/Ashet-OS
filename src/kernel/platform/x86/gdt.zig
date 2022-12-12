const std = @import("std");
const ashet = @import("../../main.zig");

const Granularity = enum(u1) {
    byte = 0,
    page = 1,
};

const SegmentSize = enum(u1) {
    bits16 = 0,
    bits32 = 1,
};

const DescriptorType = enum(u1) {
    system = 0,
    code_or_data = 1,
};

const GrowDirection = enum(u1) {
    up = 0,
    down = 1,
};

const Descriptor = packed struct(u64) {
    pub const Access = packed struct(u8) {
        accessed: bool = false,
        writeable: bool,
        direction: GrowDirection,
        executable: bool,
        type: DescriptorType,
        priviledge: u2,
        present: bool,

        pub fn readOnlySegment(priviledge: u2) Access {
            return Access{
                .writeable = false,
                .direction = .up,
                .executable = false,
                .type = .code_or_data,
                .priviledge = priviledge,
                .present = true,
            };
        }

        pub fn readWriteSegment(priviledge: u2) Access {
            return Access{
                .writeable = true,
                .direction = .up,
                .executable = false,
                .type = .code_or_data,
                .priviledge = priviledge,
                .present = true,
            };
        }

        pub fn codeSegment(priviledge: u2, readable: bool) Access {
            return Access{
                .writeable = readable,
                .direction = .up,
                .executable = true,
                .type = .code_or_data,
                .priviledge = priviledge,
                .present = true,
            };
        }
    };

    pub const Flags = packed struct(u4) {
        userbit: u1 = 0,
        longmode: bool,
        size: SegmentSize,
        granularity: Granularity,
    };

    limit0: u16, // 0 Limit 0-7
    // 1 Limit 8-15
    base0: u24, // 2 Base 0-7
    // 3 Base 8-15
    // 4 Base 16-23
    access: Access, // 5 Accessbyte 0-7 (vollständig)
    limit1: u4, // 6 Limit 16-19
    flags: Flags, // 6 Flags 0-3 (vollständig)
    base1: u8, // 7 Base 24-31

    pub fn init(base: u32, limit: u32, access: Access, flags: Flags) Descriptor {
        return Descriptor{
            .limit0 = @truncate(u16, limit & 0xFFFF),
            .limit1 = @truncate(u4, (limit >> 16) & 0xF),
            .base0 = @truncate(u24, base & 0xFFFFFF),
            .base1 = @truncate(u8, (base >> 24) & 0xFF),
            .access = access,
            .flags = flags,
        };
    }
};

var gdt: [4]Descriptor align(16) = [4]Descriptor{
    // 0, 0x00: null descriptor
    @bitCast(Descriptor, @as(u64, 0)),

    // 1, 0x08: Kernel Code Segment
    Descriptor.init(0, 0xfffff, Descriptor.Access.codeSegment(0, true), Descriptor.Flags{
        .granularity = .page,
        .size = .bits32,
        .longmode = false,
    }),

    // 2, 0x10: Kernel Data Segment
    Descriptor.init(0, 0xfffff, Descriptor.Access.readWriteSegment(0), Descriptor.Flags{
        .granularity = .page,
        .size = .bits32,
        .longmode = false,
    }),

    // 3, 0x18: Syscall Data Segment
    undefined,
};

const DescriptorTable = extern struct {
    limit: u16,
    table: [*]Descriptor align(2),
};

export const gdtp = DescriptorTable{
    .table = &gdt,
    .limit = @sizeOf(@TypeOf(gdt)) - 1,
};

pub fn init() void {
    gdt[3] = Descriptor.init(@ptrToInt(&ashet.syscalls.syscall_table), @sizeOf(ashet.abi.SysCallTable), Descriptor.Access.readOnlySegment(0), Descriptor.Flags{
        .granularity = .byte,
        .size = .bits32,
        .longmode = false,
    });
    asm volatile ("lgdt gdtp");
    asm volatile (
        \\ mov $0x10, %%ax
        \\ mov %%ax, %%ds
        \\ mov %%ax, %%es
        \\ mov %%ax, %%gs
        \\ mov %%ax, %%ss
        \\ mov $0x18, %%ax
        \\ mov %%ax, %%fs
        \\ ljmp $0x8, $.reload // change code segment by using far jumping
        \\ .reload:
    );
}
