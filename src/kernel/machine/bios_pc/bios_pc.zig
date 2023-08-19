//! Generic PC (BIO)S platform
//!
//!

const std = @import("std");
const ashet = @import("root");
const x86 = ashet.platforms.all.x86;
const logger = std.log.scoped(.bios_pc);

const args = @import("args");

const VgaTerminal = @import("VgaTerminal.zig");

pub const machine_config = ashet.machines.MachineConfig{
    .load_sections = .{ .data = false, .bss = false },
};

const hw = struct {
    //! list of fixed hardware components

    var terminal = VgaTerminal{};

    var kbc: ashet.drivers.input.PC_KBC = undefined;

    var vbe: ashet.drivers.video.VESA_BIOS_Extension = undefined;
    var vga: ashet.drivers.video.VGA = undefined;

    var ata: [8]ashet.drivers.block.AT_Attachment = undefined;

    var rtc: ashet.drivers.rtc.CMOS = undefined;

    // TODO: Add a higher precision timer to the OS for better timeouts
    var pit: ashet.drivers.timer.Programmable_Interval_Timer = undefined;
};

var graphics_enabled: bool = false;

const DebugChannel = enum {
    none,
    parallel,
    serial,
};

const KernelOptions = struct {
    debug: DebugChannel = .serial,
};

var kernel_options: KernelOptions = .{};
var cli_ok: bool = true;

fn printCliError(err: args.Error) !void {
    logger.err("invalid cli argument: {}", .{err});
    cli_ok = false;
}

pub fn initialize() !void {
    // x86 requires GDT and IDT, as a lot of x86 devices are only well usable with
    // interrupts. We're also using the GDT for interrupts
    x86.gdt.init();
    x86.idt.init();

    const mbheader = x86.start.multiboot_info orelse @panic("Ashet OS must be bootet via a MultiBoot 1 compatible bootloader. Use syslinux or grub!");

    if (mbheader.flags.boot_loader_name) {
        logger.info("system bootloader: '{}'", .{
            std.zig.fmtEscapes(std.mem.sliceTo(mbheader.boot_loader_name, 0)),
        });
    }

    kernel_options = if (mbheader.flags.cmdline) blk: {
        const cli_string = std.mem.sliceTo(mbheader.cmdline, 0);
        logger.info("kernel commandline: '{}'", .{std.zig.fmtEscapes(cli_string)});

        var temp_buffer: [4096]u8 = undefined;

        var iter = std.mem.tokenize(u8, cli_string, "\t\r\n ");
        var fba = std.heap.FixedBufferAllocator.init(&temp_buffer);

        const opt = args.parse(KernelOptions, &iter, fba.allocator(), .{ .forward = printCliError }) catch |err| {
            logger.err("failed to parse kernel command line: {s}", .{@errorName(err)});
            break :blk KernelOptions{};
        };
        if (!cli_ok) {
            break :blk KernelOptions{};
        }
        break :blk opt.options;
    } else KernelOptions{};

    if (mbheader.flags.mods) {
        logger.info("found additional boot modules:", .{});

        const Module = extern struct {
            module_lo: u32,
            module_hi: u32,
            cmdline: [*:0]const u8,
            reserved: u32,
        };

        const modules = @as([*]const Module, @ptrFromInt(mbheader.mods.mods_addr))[0..mbheader.mods.mods_count];
        for (modules, 0..) |mod, index| {
            logger.info("  [{}] = {{ lo=0x{X:0>8}, hi=0x{X:0>8}, cmdline='{}' }}", .{
                index,
                mod.module_lo,
                mod.module_hi,
                std.zig.fmtEscapes(std.mem.sliceTo(mod.cmdline, 0)),
            });
        }
    }

    logger.info("multiboot info: {}", .{mbheader});

    if (ashet.drivers.video.VESA_BIOS_Extension.init(ashet.memory.allocator, mbheader)) |vbe| {
        hw.vbe = vbe;
        ashet.drivers.install(&hw.vbe.driver);
    } else |vbe_error| {
        std.log.warn("VBE not available ({s}), falling back to classic VGA", .{@errorName(vbe_error)});

        if (hw.vga.init()) |_| {
            ashet.drivers.install(&hw.vga.driver);
        } else |vga_error| {
            std.log.warn("VGA not available ({s}), panicking...", .{@errorName(vga_error)});
            @panic("Ashet OS does requires a video card!");
        }
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

    x86.enableInterrupts();

    if (ashet.drivers.input.PC_KBC.init()) |kbc| {
        hw.kbc = kbc;
        ashet.drivers.install(&hw.kbc.driver);
    } else |err| {
        logger.err("failed to initialize KBC with error {s}, no keyboard input available!", .{@errorName(err)});
    }
}

fn busyLoop(cnt: u32) void {
    var i: u32 = 0;
    while (i < cnt) : (i += 1) {
        asm volatile (""
            :
            : [x] "r" (i),
        );
    }
}

fn writeVirtualSPI(msg: []const u8) void {
    const Selector = packed struct(u8) {
        data: u1,
        clk: u1,
        cs: u1,
        padding: u5 = 0,

        fn map(sel: @This()) u8 {
            return @as(u8, @bitCast(sel));
        }
    };

    x86.out(u8, 0x378, Selector.map(.{ .data = 0, .clk = 0, .cs = 1 }));
    busyLoop(2);

    for (msg) |char| {
        var b: u8 = char;
        var m: u8 = 0x01;

        while (m != 0) {
            x86.out(u8, 0x378, Selector.map(.{ .data = @as(u1, @truncate((b & 0x80) >> 7)), .clk = 1, .cs = 1 }));
            busyLoop(1);

            x86.out(u8, 0x378, Selector.map(.{ .data = @as(u1, @truncate((b & 0x80) >> 7)), .clk = 0, .cs = 1 }));
            busyLoop(1);

            b <<= 1;
            m <<= 1;
        }
    }
    busyLoop(1);

    x86.out(u8, 0x378, Selector.map(.{ .data = 0, .clk = 0, .cs = 0 }));
    busyLoop(2);
}

pub fn debugWrite(msg: []const u8) void {
    switch (kernel_options.debug) {
        .none => {},
        .serial => {
            for (msg) |char| {
                x86.out(u8, 0x3F8, char);
            }
        },
        .parallel => {
            const DATA = 0x378;
            // const STATUS = 0x379;
            const CONTROL = 0x37A;

            const DATA_PIN: u8 = (1 << 1);

            for (msg) |char| {
                // while ((x86.in(u8, STATUS) & 0x80) == 0) {
                //     busyLoop(10);
                // }

                x86.out(u8, DATA, char);

                const status = x86.in(u8, CONTROL);
                x86.out(u8, CONTROL, status | DATA_PIN);
                busyLoop(150);
                x86.out(u8, CONTROL, status & ~DATA_PIN);
                busyLoop(15_000);
            }
        },
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
    .depth = 32,
});
