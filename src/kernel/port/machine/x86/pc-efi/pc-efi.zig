//! Generic PC (BIO)S platform
//!
//!

const std = @import("std");
const ashet = @import("kernel");
const x86 = ashet.platforms.all.x86;

const VgaTerminal = @import("VgaTerminal.zig");

pub const machine_config = ashet.machines.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
};

const hw = struct {
    //! list of fixed hardware components

    var terminal = VgaTerminal{};

    var kbc: ashet.drivers.input.PC_KBC = undefined;

    var vbe: ashet.drivers.video.VESA_BIOS_Extension = undefined;
    var vga: ashet.drivers.video.VGA = undefined;

    var ata: [8]ashet.drivers.block.AT_Attachment = undefined;

    var rtc: ashet.drivers.rtc.CMOS = undefined;
};

var graphics_enabled: bool = false;

pub fn initialize() !void {
    // x86 requires GDT and IDT, as a lot of x86 devices are only well usable with
    // interrupts. We're also using the GDT for interrupts
    x86.gdt.init();
    x86.idt.init();

    const mbheader = x86.start.multiboot_info orelse @panic("Ashet OS must be bootet via a MultiBoot 1 compatible bootloader. Use syslinux or grub!");

    if (mbheader.flags.vbe) {
        hw.vbe = ashet.drivers.video.VESA_BIOS_Extension.init(ashet.memory.allocator, mbheader) catch {
            @panic("Ashet OS does not support computers without VBE 2.0. Please use a graphics card that supports VBE.");
        };
        ashet.drivers.install(&hw.vbe.driver);
    } else {
        try hw.vga.init();
        ashet.drivers.install(&hw.vga.driver);
    }
    graphics_enabled = true;

    // RTC must be instantiated already as the ATA driver needs a system clock
    // for timeout measurement!

    hw.rtc = ashet.drivers.rtc.CMOS.init();
    ashet.drivers.install(&hw.rtc.driver);

    for (&hw.ata, 0..) |*ata, index| {
        // requires rtc to be initialized!
        ata.* = ashet.drivers.block.AT_Attachment.init(@as(u3, @truncate(index))) catch {
            continue;
        };
        ashet.drivers.install(&ata.driver);
    }

    hw.kbc = try ashet.drivers.input.PC_KBC.init();
    ashet.drivers.install(&hw.kbc.driver);

    x86.enableInterrupts();
}

pub fn debugWrite(msg: []const u8) void {
    for (msg) |char| {
        x86.out(u8, 0x3F8, char);
    }

    // if (!graphics_enabled) {
    //     hw.terminal.write(msg);
    // }
}

// pub const flash = ashet.memory.Section{ .offset = 0x2000_000, .length = 0x200_0000 };

extern const __machine_linmem_start: u8 align(4);
extern const __machine_linmem_end: u8 align(4);

pub fn getLinearMemoryRegion() ashet.memory.Section {
    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = @intFromPtr(&__machine_linmem_end);
    return ashet.memory.Section{ .offset = linmem_start, .length = linmem_end - linmem_start };
}

export const multiboot_header linksection(".multiboot") = x86.multiboot.Header.withChecksum(.{
    .flags = .{
        .req_modules_align_4k = false,
        .req_mem_info = true,
        .req_video_mode = false, // TODO: Set to true for better video
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
    .depth = 32,
});
