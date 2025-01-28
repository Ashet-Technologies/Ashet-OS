const std = @import("std");

pub const EFLAGS = packed struct(u32) {
    carry: u1, //                       bit 0: CF - Carry Flag (S)
    _reserved0: u1, //                  bit 1:  *reserved*
    parity: u1, //                      bit 2:  PF - Parity Flag (S)
    _reserved1: u1, //                  bit 3:  *reserved*
    aux_carry: u1, //                   bit 4:  AF - Auxiliary Carry Flag (S)
    _reserved2: u1, //                  bit 5:  *reserved*
    zero: u1, //                        bit 6:  ZF - Zero Flag (S)
    sign: u1, //                        bit 7:  SF - Sign Flag (S)
    trap: u1, //                        bit 8:  TF - Trap Flag (X)
    interrupt_enable: bool, //          bit 9:  IF - Interrupt Enable Flag (X)
    direction: u1, //                   bit 10: DF - Direction Flag (C)
    overflow: u1, //                    bit 11: OF - Overflow Flag (S)
    io_priviledge_level: u2, //         bit 12: IOPL - I/O Privilege Level (X)
    nested_task: u1, //                 bit 14: NT - Nested Task Flag (X)
    _reserved3: u1, //                  bit 15: *reserved*
    resume_flag: u1, //                 bit 16: RF - Resume Flag (X)
    virtual_8086_mode: bool, //         bit 17: VM - Virtual 8086 Mode (X)
    virtual_interrupt_flag: bool, //    bit 19: VIF - Virtual Interrupt Flag (X)
    alignment_check: bool, //           bit 18: AC - Alignment Check (X)
    virtual_interrupt_pending: bool, // bit 20: VIP - Virtual Interrupt Pending (X)
    has_cpuid: bool, //                 bit 21: ID - ID Flag (X)
    _reserved4: u10, //                 bit 22: *reserved*
};

pub const CR0 = packed struct(u32) {
    protection_enabled: bool, // 0
    monitor_coprocessor_flag: enum(u1) { nothrow = 0, throw = 1 }, // 1
    fpu_emulation: bool, // 2
    task_switched: bool, // 3
    extension_type: u1, // 4
    numeric_error: bool, // 5
    _reserved0: u10, // 6..15
    kernel_write_protect: bool, // 16
    _reserved1: u1, // 17
    alignment_mask: bool, // 18
    _reserved2: u10, // 19...28
    force_write_through: bool, // 29
    cache_disable: bool, // 30
    paging: bool, // 31

    pub inline fn read() CR0 {
        return asm ("mov %%cr0, %[cr]"
            : [cr] "=r" (-> CR0),
        );
    }

    pub inline fn write(cr0: CR0) void {
        asm volatile ("mov %[cr], %%cr0"
            :
            : [cr] "r" (cr0),
        );
    }

    pub inline fn modify(items: anytype) void {
        var value = read();
        inline for (std.meta.fields(@TypeOf(items))) |fld| {
            @field(value, fld.name) = @field(items, fld.name);
        }
        write(value);
    }
};

pub const CR2 = packed struct(u32) {
    page_fault_address: u32,

    pub inline fn read() CR2 {
        return asm ("mov %%cr2, %[cr]"
            : [cr] "=r" (-> CR2),
        );
    }
};

pub const CR3 = packed struct(u32) {
    _reserved0: u3, // 0..2
    page_level_writes_transparent: bool, // 3
    page_level_cache_disable: bool, // 4
    _reserved1: u7, // 5..11
    page_directory_base: u20, // 12..31

    pub inline fn read() CR3 {
        return asm ("mov %%cr3, %[cr]"
            : [cr] "=r" (-> CR3),
        );
    }

    pub inline fn write(cr: CR3) void {
        asm volatile ("mov %[cr], %%cr3"
            :
            : [cr] "r" (cr),
        );
    }

    pub inline fn modify(items: anytype) void {
        var value = read();
        inline for (std.meta.fields(@TypeOf(items))) |fld| {
            @field(value, fld.name) = @field(items, fld.name);
        }
        write(value);
    }
};

pub const CR4 = packed struct(u32) {
    virtual_8086_enable: bool, // 0
    protected_mode_virtual_interrupt: bool, // 1
    time_stamp_disable: bool, // 2
    debugging_extension: bool, // 3
    page_size_extension: bool, // 4
    physical_address_extension: bool, // 5
    machine_check_enable: bool, // 6
    page_global_enable: bool, // 7
    performance_monitoring_counter_enable: bool, // 8
    osfxsr: bool, // 9
    unmasked_exception_support_flag: bool, // 10
    _reserved0: u22, // 11..31

    pub inline fn read() CR4 {
        return asm ("mov %%cr4, %[cr]"
            : [cr] "=r" (-> CR4),
        );
    }

    pub inline fn write(cr: CR4) void {
        asm volatile ("mov %[cr], %%cr4"
            :
            : [cr] "r" (cr),
        );
    }

    pub inline fn modify(items: anytype) void {
        var value = read();
        inline for (std.meta.fields(@TypeOf(items))) |fld| {
            @field(value, fld.name) = @field(items, fld.name);
        }
        write(value);
    }
};

pub const CR8 = packed struct(u32) {
    task_priority_level: u3,
    _reserved0: u28,

    pub inline fn read() CR8 {
        return asm ("mov %%cr8, %[cr]"
            : [cr] "=r" (-> CR3),
        );
    }

    pub inline fn write(cr: CR8) void {
        asm volatile ("mov %[cr], %%cr8"
            :
            : [cr] "r" (cr),
        );
    }

    pub inline fn modify(items: anytype) void {
        var value = read();
        inline for (std.meta.fields(@TypeOf(items))) |fld| {
            @field(value, fld.name) = @field(items, fld.name);
        }
        write(value);
    }
};
