const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.vga);
const vga_regs = @import("x86/vga-regs.zig");

const x86 = ashet.ports.platforms.x86;
const VGA = @This();
const Driver = ashet.drivers.Driver;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

const modes = @import("x86/vga-mode-presets.zig");

const width = 320;
const height = 200;

backbuffer: [width * height]Color align(ashet.memory.page_size) = undefined,

driver: Driver = .{
    .name = "VGA",
    .class = .{
        .video = .{
            .get_properties_fn = get_properties,
            .begin_write_pixels_fn = begin_write_pixels,
            .get_one_vblank_event_fn = get_one_vblank_event,
            .mapping_fns = .{
                .create_mapped_buffer_fn = ashet.video.VideoDevice.default_create_mapped_buffer_front,
                .get_mapped_buffer_fn = get_mapped_buffer,
                .destroy_mapped_buffer_fn = ashet.video.VideoDevice.destroy_mapped_buffer_noop,
            },
        },
    },
},

vblank_irq_support: VBlankIrqSupport,
next_expected_retrace: ashet.time.Instant,

const memory_ranges = [_]x86.vmm.Range{
    .{ .base = 0xA0000, .length = 0x20000 },
    // these are included in the range above:
    // .{.base = 0xA0000, .length = 0x10000 },
    // .{.base = 0xB0000, .length = 0x08000 },
    // .{.base = 0xB8000, .length = 0x08000 },
};

pub fn init(vga: *VGA) !void {
    for (memory_ranges) |range| {
        x86.vmm.update(range, .read_write);
    }

    writeVgaRegisters(g_320x200x256);

    loadFixedPalette();

    setupVBlankIrq();

    const vblank_irq_support = test_blank_irq();

    const vmem = @as([*]align(ashet.memory.page_size) Color, @ptrFromInt(0xA0000))[0 .. width * height];

    @memset(vmem, ashet.video.defaults.border_color);

    ashet.video.load_splash_screen(.{
        .base = vmem.ptr,
        .width = width,
        .height = height,
        .stride = width,
    });

    const next_expected_retrace: ashet.time.Instant = switch (vblank_irq_support) {
        .supported => undefined,
        .unsupported => ashet.time.Instant.now().add_ms(16),
    };

    vga.* = VGA{
        .vblank_irq_support = vblank_irq_support,
        .next_expected_retrace = next_expected_retrace,
    };
}

fn get_properties(driver: *Driver) ashet.video.DeviceProperties {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    _ = vd;
    return .{
        .resolution = .{
            .width = width,
            .height = height,
        },
        .buffer_support = .front_stable,
    };
}

fn get_one_vblank_event(driver: *Driver) bool {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));

    return switch (vd.vblank_irq_support) {
        .supported => readAndResetIrq(),

        .unsupported => blk: {
            var had_vblank_event = false;
            const now = ashet.time.Instant.now();
            while (vd.next_expected_retrace.less_or_equal(now)) {
                vd.next_expected_retrace = vd.next_expected_retrace.add_ms(16);
                had_vblank_event = true;
            }
            break :blk had_vblank_event;
        },
    };
}

fn get_mapped_buffer(driver: *Driver, buffer: ashet.video.BufferKind) ashet.video.VideoMemory {
    _ = driver;
    return switch (buffer) {
        .front_buffer => .{
            .base = @ptrFromInt(0xA0000),
            .stride = width,
        },
        .back_buffer => @panic("kernel bug: driver layer invoked get_mapped_buffer for unsupported buffer"),
    };
}

fn begin_write_pixels(
    driver: *Driver,
    call: *ashet.overlapped.AsyncCall,
    rectangle: ashet.abi.Rectangle,
    pixels: []const Color,
    stride: usize,
    mode: ashet.abi.video.PresentMode,
) void {
    const vd: *VGA = @alignCast(@fieldParentPtr("driver", driver));
    _ = vd;

    const target = @as([*]align(ashet.memory.page_size) Color, @ptrFromInt(0xA0000))[0 .. width * height];

    switch (mode) {
        .dont_care, .immediate => {},

        // TODO(gpu_support): This is blocking, which is really *not nice*, but it's a kind of viable
        //                    solution for a first draft.
        .vblank => wait_for_vsync(),
    }

    ashet.video.utils.copy_pixels(
        Color,
        .{
            .dst_buffer = .{
                .data = target,
                .width = width,
                .height = height,
                .stride = width,
            },
            .dst_pos = .{
                .x = @intCast(rectangle.x),
                .y = @intCast(rectangle.y),
            },
            .src_buffer = .{
                .data = pixels.ptr,
                .width = rectangle.width,
                .height = rectangle.height,
                .stride = stride,
            },
        },
        null,
    );

    return call.finalize(ashet.abi.video.WritePixels, .{});
}

const VBlankIrqSupport = enum { supported, unsupported };

///
/// As QEMU does not actually implement the latching vertical blanking IRQ
/// we need for Ashet OS "await vblank" semantics, we need to emulate this.
///
/// On a real VGA card we can rely on the blanking interval though.
///
/// To detect if the IRQ is supported, we manually await a vertical blank
///
fn test_blank_irq() VBlankIrqSupport {
    logger.info("testing VGA IRQ support...", .{});
    wait_for_vsync();

    _ = readAndResetIrq(); // IRQ is now off

    // Wait for the next frame to happen
    wait_for_vsync();

    // If an IRQ has latched after a frame, we are now actually safe that we can rely on the vblank information:
    if (readAndResetIrq()) {
        return .supported;
    }

    return .unsupported;
}

pub fn setupVBlankIrq() void {
    const io_address_select = vga_regs.MiscellaneousOutputRegister.read().io_address_select;

    const crtc_index = io_address_select.crtcIndexPort();
    const crtc_data = io_address_select.crtcDataPort();

    // Preserve the currently selected CRTC register.
    const previous_index = crtc_index.read();
    defer crtc_index.write(previous_index);

    // Vertical Retrace End register.
    crtc_index.write(0x11);

    var value = crtc_data.read();

    // Bit 5 = 0: enable vertical-retrace interrupt generation.
    //
    // Bit 4 = 0: clear the pending vertical-retrace interrupt.
    value &= ~@as(u8, 0x30);
    crtc_data.write(value);

    // Bit 4 = 1: permit the next vertical-retrace interrupt to occur.
    value |= 0x10;
    crtc_data.write(value);
}

/// Reads the VGA vertical-retrace interrupt latch and, if set, clears and
/// rearms it for the next vertical retrace.
///
/// Returns whether a vertical-retrace interrupt was pending.
pub fn readAndResetIrq() bool {
    const pending = vga_regs.InputStatus0Register.read().crt_interrupt_pending;

    // Don't touch the latch when there is nothing to acknowledge. In
    // particular, this avoids clearing an interrupt that arrives immediately
    // after the status read.
    if (!pending)
        return false;

    const io_address_select = vga_regs.MiscellaneousOutputRegister.read().io_address_select;

    const crtc_index = io_address_select.crtcIndexPort();
    const crtc_data = io_address_select.crtcDataPort();

    // Preserve the currently selected CRTC register.
    const previous_index = crtc_index.read();
    defer crtc_index.write(previous_index);

    crtc_index.write(0x11);

    const value = crtc_data.read();

    // Bit 4 = 0 clears the interrupt latch.
    crtc_data.write(value & ~@as(u8, 0x10));

    // Bit 4 = 1 rearms it for the next vertical retrace.
    crtc_data.write(value | 0x10);

    return true;
}

fn writeVgaRegisters(config: VgaRegisterConfig) void {
    // Write MISCELLANEOUS register.
    config.miscellaneous_output.write();

    const io_address_select = config.miscellaneous_output.io_address_select;
    const crtc_index = io_address_select.crtcIndexPort();
    const crtc_data = io_address_select.crtcDataPort();

    // Write SEQUENCER registers.
    for (config.sequencer, 0..) |value, index| {
        vga_regs.VgaPort.sequencer_index.write(@intCast(index));
        vga_regs.VgaPort.sequencer_data.write(value);
    }

    // Unlock CRTC registers.
    crtc_index.write(0x03);
    crtc_data.write(crtc_data.read() | 0x80);

    crtc_index.write(0x11);
    crtc_data.write(crtc_data.read() & ~@as(u8, 0x80));

    // Write CRTC registers.
    for (config.crtc, 0..) |value, index| {
        crtc_index.write(@intCast(index));
        crtc_data.write(value);
    }

    // Write GRAPHICS CONTROLLER registers.
    for (config.graphics_controller, 0..) |value, index| {
        vga_regs.VgaPort.graphics_controller_index.write(@intCast(index));
        vga_regs.VgaPort.graphics_controller_data.write(value);
    }

    // Write ATTRIBUTE CONTROLLER registers.
    for (config.attribute_controller, 0..) |value, index| {
        // Reset Attribute Controller flip-flop to index state.
        _ = vga_regs.InputStatus1Register.read(io_address_select);

        vga_regs.VgaPort.attribute_index_data.write(@intCast(index));
        vga_regs.VgaPort.attribute_index_data.write(value);
    }

    // Lock 16-color palette and unblank display.
    _ = vga_regs.InputStatus1Register.read(io_address_select);
    vga_regs.VgaPort.attribute_index_data.write(0x20);
}

fn setPlane(plane: u2) void {
    const pmask: u8 = @as(u8, 1) << plane;

    // Set read plane.
    vga_regs.VgaPort.graphics_controller_index.write(4);
    vga_regs.VgaPort.graphics_controller_data.write(plane);

    // Set write plane.
    vga_regs.VgaPort.sequencer_index.write(2);
    vga_regs.VgaPort.sequencer_data.write(pmask);
}

fn getFramebufferSegment() [*]volatile u8 {
    vga_regs.VgaPort.graphics_controller_index.write(6);

    const seg = (vga_regs.VgaPort.graphics_controller_data.read() >> 2) & 3;

    return @as([*]volatile u8, @ptrFromInt(switch (@as(u2, @truncate(seg))) {
        0, 1 => @as(u32, 0xA0000),
        2 => @as(u32, 0xB0000),
        3 => @as(u32, 0xB8000),
    }));
}

const RGB = packed struct {
    b: u8,
    g: u8,
    r: u8,
    x: u8,
};

// see: http://www.brackeen.com/vga/source/bc31/palette.c.html
fn loadPalette(vga: VGA, palette: [256]Color) void {
    _ = vga;

    // Tell the VGA that palette data is coming, starting at entry 0.
    vga_regs.VgaPort.palette_write_index.write(0);

    for (palette) |rgb| {
        // Enhance RGB565 to RGB666.
        vga_regs.VgaPort.palette_data.write(
            (@as(u6, rgb.r) << 1) | (rgb.r >> 4),
        );
        vga_regs.VgaPort.palette_data.write(
            @as(u6, rgb.g),
        );
        vga_regs.VgaPort.palette_data.write(
            (@as(u6, rgb.b) << 1) | (rgb.b >> 4),
        );
    }
}

fn loadFixedPalette() void {
    @setEvalBranchQuota(10_000);

    // Tell the VGA that palette data is coming, starting at entry 0.
    vga_regs.VgaPort.palette_write_index.write(0);

    inline for (0..256) |index| {
        const color: Color = comptime .from_u8(@intCast(index));
        const rgb = comptime color.to_rgb888();

        const r6 = comptime Color.compress_channel(rgb.r, u6);
        const g6 = comptime Color.compress_channel(rgb.g, u6);
        const b6 = comptime Color.compress_channel(rgb.b, u6);

        vga_regs.VgaPort.palette_data.write(r6);
        vga_regs.VgaPort.palette_data.write(g6);
        vga_regs.VgaPort.palette_data.write(b6);
    }
}

// pub fn setPaletteEntry(entry: u8, color: RGB) void {
//     vga_regs.VgaPort.palette_write_index.write(entry);
//     vga_regs.VgaPort.palette_data.write(color.r >> 2);
//     vga_regs.VgaPort.palette_data.write(color.g >> 2);
//     vga_regs.VgaPort.palette_data.write(color.b >> 2);
// }

fn wait_for_vsync() void {
    const io_address_select = vga_regs.MiscellaneousOutputRegister.read().io_address_select;

    // Wait until the current vertical retrace has ended.
    while (vga_regs.InputStatus1Register.read(io_address_select).vertical_retrace) {}

    // Wait until the next vertical retrace begins.
    while (!vga_regs.InputStatus1Register.read(io_address_select).vertical_retrace) {}
}

const VGA_NUM_REGS =
    1 +
    VGA_NUM_SEQ_REGS +
    VGA_NUM_CRTC_REGS +
    VGA_NUM_GC_REGS +
    VGA_NUM_AC_REGS;

const VGA_NUM_SEQ_REGS = 5;
const VGA_NUM_CRTC_REGS = 25;
const VGA_NUM_GC_REGS = 9;
const VGA_NUM_AC_REGS = 21;

pub const VgaRegisterConfig = struct {
    miscellaneous_output: vga_regs.MiscellaneousOutputRegister,

    sequencer: [VGA_NUM_SEQ_REGS]u8,
    crtc: [VGA_NUM_CRTC_REGS]u8,
    graphics_controller: [VGA_NUM_GC_REGS]u8,
    attribute_controller: [VGA_NUM_AC_REGS]u8,
};

pub const g_320x200x256: VgaRegisterConfig = .{
    .miscellaneous_output = @bitCast(@as(u8, 0x63)),

    .sequencer = .{
        0x03,
        0x01,
        0x0F,
        0x00,
        0x0E,
    },

    .crtc = .{
        0x5F,
        0x4F,
        0x50,
        0x82,
        0x54,
        0x80,
        0xBF,
        0x1F,
        0x00,
        0x41,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x9C,
        0x0E,
        0x8F,
        0x28,
        0x40,
        0x96,
        0xB9,
        0xA3,
        0xFF,
    },

    .graphics_controller = .{
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x40,
        0x05,
        0x0F,
        0xFF,
    },

    .attribute_controller = .{
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0x09,
        0x0A,
        0x0B,
        0x0C,
        0x0D,
        0x0E,
        0x0F,
        0x41,
        0x00,
        0x0F,
        0x00,
        0x00,
    },
};
