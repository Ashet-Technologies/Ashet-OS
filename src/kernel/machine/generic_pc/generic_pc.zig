//! Generic PC (BIO)S platform
//!
//!

const std = @import("std");
const ashet = @import("root");
const x86 = ashet.platforms.all.x86;

pub const machine_config = ashet.machines.MachineConfig{
    .uninitialized_memory = false, // we assume the bootloader has already done a good job
};

const hw = struct {
    //! list of fixed hardware components
    // var rtc: ashet.drivers.rtc.Goldfish = undefined;
    // var cfi: ashet.drivers.block.CFI_NOR_Flash = undefined;

    var vbe: ashet.drivers.video.VESA_BIOS_Extension = undefined;
    var dummy_rtc: ashet.drivers.rtc.Dummy = undefined;
};

pub fn initialize() !void {
    const mbheader = x86.start.multiboot_info orelse @panic("Ashet OS must be bootet via a MultiBoot 1 compatible bootloader. Use syslinux or grub!");

    hw.vbe = ashet.drivers.video.VESA_BIOS_Extension.init(ashet.memory.allocator, mbheader) catch {
        @panic("Ashet OS does not support computers without VBE 2.0. Please use a graphics card that supports VBE.");
    };
    ashet.drivers.install(&hw.vbe.driver);

    hw.dummy_rtc = ashet.drivers.rtc.Dummy.init(1670610407 * std.time.ns_per_s);
    ashet.drivers.install(&hw.dummy_rtc.driver);
}

pub fn debugWrite(msg: []const u8) void {
    for (msg) |char| {
        x86.out(u8, 0x3F8, char);
    }
}

// pub const flash = ashet.memory.Section{ .offset = 0x2000_000, .length = 0x200_0000 };

extern const __machine_linmem_start: anyopaque align(4);
extern const __machine_linmem_end: anyopaque align(4);

pub fn getLinearMemoryRegion() ashet.memory.Section {
    const linmem_start = @ptrToInt(&__machine_linmem_start);
    const linmem_end = @ptrToInt(&__machine_linmem_end);
    return ashet.memory.Section{ .offset = linmem_start, .length = linmem_end - linmem_start };
}

export const multiboot_header linksection(".multiboot") = x86.multiboot.Header.withChecksum(.{
    .flags = .{
        .req_modules_align_4k = false,
        .req_mem_info = true,
        .req_video_mode = true,
        .hint_use_embedded_offsets = false,
    },

    .header_addr = undefined,
    .load_addr = undefined,
    .load_end_addr = undefined,
    .bss_end_addr = undefined,
    .entry_addr = undefined,

    .mode_type = .linear_fb,
    .width = 800,
    .height = 600,
    .depth = 8,
});
