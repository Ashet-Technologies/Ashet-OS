const std = @import("std");
const logger = std.log.scoped(.ashet_hc);
const ashet = @import("../../../../main.zig");
const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");
const rp2350_regs = rp2350.devices.RP2350.peripherals;

const psram = @import("psram.zig");

const disk_image_start = 0x10800000;
const disk_image_end = 0x11000000;

pub const clock_config = blk: {
    var cfg = hal.clocks.config.preset.default();
    cfg.hstx.?.integer_divisor = 1;
    break :blk cfg;
};

pub const debug_uart = hal.uart.instance.UART0;

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = null,
    .early_initialize = early_initialize,
    .get_tick_count_ms = get_tick_count_ms,
    .initialize = initialize,
    .debug_write = debug_write,
    .get_linear_memory_region = get_linear_memory_region,
};

const pinout = struct {
    const debug_tx = hal.gpio.num(0);
    const debug_rx = hal.gpio.num(1);
    const xip_cs1 = hal.gpio.num(8);

    // // bitbang interface:
    // const dbg_sel = hal.gpio.num(9);
    // const dbg_sck = hal.gpio.num(10);
    // const dbg_sda = hal.gpio.num(11);
};

const hw = struct {
    //! list of fixed hardware components

    var rtc: ashet.drivers.rtc.Dummy_RTC = undefined;

    var uart0: ashet.drivers.serial.RP2xxx = undefined;
    var uart1: ashet.drivers.serial.RP2xxx = undefined;

    // var fb_video: ashet.drivers.video.Virtual_Video_Output = undefined;
    var hstx_video: ashet.drivers.video.HSTX_DVI = undefined;

    var xip_flash: ashet.drivers.block.Memory_Mapped_Flash = undefined;
};

fn get_tick_count_ms() u64 {
    var cs = ashet.CriticalSection.enter();
    defer cs.leave();

    return systick.total_count_ms;
}

comptime {
    std.debug.assert(@sizeOf(rp2350.devices.RP2350.VectorTable) >= @sizeOf(ashet.platform.profile.start.InterruptTable));
}

var interrupt_table: rp2350.devices.RP2350.VectorTable align(128) = undefined;

fn early_initialize() void {
    // Disable watch dog, reset all peripherials, and set the clocks and PLLs:
    hal.init_sequence(clock_config);

    pinout.xip_cs1.set_function(.gpck_xip_cs_coresight_trace);
    pinout.debug_tx.set_function(.uart_first);
    pinout.debug_rx.set_function(.uart_first);
    // pinout.dbg_sel.set_function(.sio);
    // pinout.dbg_sck.set_function(.sio);
    // pinout.dbg_sda.set_function(.sio);

    // pinout.dbg_sel.set_direction(.out);
    // pinout.dbg_sck.set_direction(.out);
    // pinout.dbg_sda.set_direction(.out);
    // pinout.dbg_sel.put(0);
    // pinout.dbg_sck.put(0);
    // pinout.dbg_sda.put(0);

    debug_uart.apply(.{
        .baud_rate = 115_200,
        .clock_config = clock_config,
    });

    logger.info("Debug output ready.", .{});

    // bitbang_write("Debug ready.\r\n");

    psram.init() catch @panic("failed to initialize psram!");

    configure_interrupt_table();

    logger.info("Machine early initialize done.", .{});
    logger.info("sys_clk: {} Hz", .{comptime clock_config.sys.?.frequency()});
    logger.info("usb_clk: {} Hz", .{comptime clock_config.usb.?.frequency()});

    logger.info("starting core 1...", .{});

    hal.multicore.launch_core1_with_stack(core1_main, &core1_stack);

    while (ashet.utils.volatile_read(bool, &core1_ready) == false) {
        //
    }

    logger.info("core1 fully started", .{});
}

var core1_ready: bool = false;
var core1_stack: [128]u32 = undefined;

fn core1_main() linksection(".ramtext") void {
    logger.info("core1 launched.", .{});

    configure_interrupt_table();

    ashet.drivers.video.HSTX_DVI.start_backend(clock_config);

    ashet.utils.volatile_write(bool, &core1_ready, true);

    while (true) {
        ashet.platform.profile.wfe();
    }
}

fn configure_interrupt_table() void {
    // Remap interrupt table:
    {
        // Create default variant:
        interrupt_table = .{
            .initial_stack_pointer = @intFromPtr(ashet.platform.profile.start.initial_vector_table.initial_stack_pointer),
            .Reset = ashet.platform.profile.start.initial_vector_table.reset,
        };

        // Copy the original interrupt table into this one:
        const alias: *ashet.platform.profile.start.InterruptTable = @ptrCast(&interrupt_table);

        alias.* = ashet.platform.profile.start.initial_vector_table.*;
    }

    ashet.platform.profile.registers.system_control_block.vtor.write(.{
        .table_offset = @truncate(@intFromPtr(&interrupt_table) >> 7),
    });
}

fn initialize() !void {
    logger.info("cpuid: {s}", .{
        ashet.platform.profile.registers.system_control_block.cpuid.read(),
    });

    logger.info("initialize SysTick...", .{});
    systick.init();

    // Initialize devices and drivers:
    {
        hw.rtc = ashet.drivers.rtc.Dummy_RTC.init(1739025296 * std.time.ns_per_s);

        hw.uart0 = try ashet.drivers.serial.RP2xxx.init(clock_config, hal.uart.instance.UART0);
        hw.uart1 = try ashet.drivers.serial.RP2xxx.init(clock_config, hal.uart.instance.UART1);

        // hw.fb_video = ashet.drivers.video.Virtual_Video_Output.init();

        hw.hstx_video = try ashet.drivers.video.HSTX_DVI.init(clock_config);

        hw.xip_flash = ashet.drivers.block.Memory_Mapped_Flash.init(
            disk_image_start,
            disk_image_end - disk_image_start,
        );
    }

    ashet.drivers.install(&hw.rtc.driver);
    ashet.drivers.install(&hw.uart0.driver);
    ashet.drivers.install(&hw.uart1.driver);
    ashet.drivers.install(&hw.hstx_video.driver);
    ashet.drivers.install(&hw.xip_flash.driver);

    rp2350_regs.UART0.UARTIMSC.modify(.{
        .RXIM = 1,
    });
    rp2350_regs.UART0.UARTIFLS.modify(.{
        .RXIFLSEL = 0b000,
    });

    IRQ.UART0_IRQ.set_handler(uart0_irq_handler);

    IRQ.UART0_IRQ.enable();

    ashet.platform.profile.enable_interrupts();
}

var mouse_buffer: [3]u8 = undefined;
var mouse_buffer_index: usize = 0;
var mouse_last_state: u8 = 0;

fn uart0_irq_handler() callconv(.C) void {
    while (debug_uart.is_readable()) {
        const byte = debug_uart.reader().readByte() catch unreachable;

        mouse_buffer[mouse_buffer_index] = byte;
        mouse_buffer_index += 1;

        if (mouse_buffer_index == 3) {
            const bmask: u8 = mouse_buffer[0] & 0b111;
            const dx: i8 = @bitCast(mouse_buffer[1]);
            const dy: i8 = @bitCast(mouse_buffer[2]);

            if (bmask != mouse_last_state) {
                const buttons = [3]struct { ashet.abi.MouseButton, u8 }{
                    .{ .left, 0x01 },
                    .{ .right, 0x02 },
                    .{ .middle, 0x04 },
                };
                for (buttons) |group| {
                    const button, const mask = group;

                    const old = (mouse_last_state & mask);
                    const now = (bmask & mask);

                    if (old != now) {
                        ashet.input.push_raw_event_from_irq(.{
                            .mouse_button = .{
                                .button = button,
                                .down = (now != 0),
                            },
                        });
                    }
                }

                mouse_last_state = bmask;
            }
            if (dx != 0 or dy != 0) {
                ashet.input.push_raw_event_from_irq(.{
                    .mouse_rel_motion = .{
                        .dx = dx,
                        .dy = -dy, // somehow inverted
                    },
                });
            }

            mouse_buffer_index = 0;
        }
    }
}

fn debug_write(msg: []const u8) void {
    debug_uart.write_blocking(msg, null) catch {};
}

extern const __machine_linmem_start: u8 align(4);
extern const __machine_linmem_end: u8 align(4);

fn get_linear_memory_region() ashet.memory.Range {
    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = @intFromPtr(&__machine_linmem_end);
    return .{ .base = linmem_start, .length = linmem_end - linmem_start };
}

const systick = struct {
    const regs = ashet.platform.profile.registers.sys_tick;

    var total_count_ms: u64 = 0;

    fn init() void {
        const calib = regs.calib.read();

        if (calib.ten_ms == 0) {
            @panic("Virtual SysTick requires known 10ms calibration, but none present!");
        }
        if (calib.skew != .exact) {
            logger.warn("SysTick has time skew!", .{});
        }

        regs.rvr.write(.{ .reload = @max(1, calib.ten_ms / 10) });

        interrupt_table.SysTick = increment_clock_irq;

        regs.csr.modify(.{
            .enabled = true,
            .interrupt = .enabled,
            .clock_source = .external_clock,
        });
    }

    fn increment_clock_irq() callconv(.C) void {
        total_count_ms +%= 1;
    }
};

export const image_def align(64) linksection(".text.image_def") = [_]u32{
    // For explanation, see RP2350 Datasheet, Chapter "5.9.5. Minimum Viable Image Metadata":
    PICOBIN_BLOCK_MARKER_START,
    0x10210142, // IMAGE_TYPE = EXE + Secure Arm + RP2350
    0x000001ff, // End Marker Item, Total Size 1
    0x00000000, // Pointer to the next block (self loop)
    PICOBIN_BLOCK_MARKER_END,
};

const PICOBIN_BLOCK_MARKER_START = 0xffffded3;
const PICOBIN_BLOCK_MARKER_END = 0xab123579;

// pub fn bitbang_write(data: []const u8) linksection(".ramcode") void {
//     @setRuntimeSafety(false);

//     const sck_mask = comptime pinout.dbg_sck.mask();
//     const sda_mask = comptime pinout.dbg_sda.mask();
//     const sel_mask = comptime pinout.dbg_sel.mask();

//     for (data) |byte| {
//         rp2350_regs.SIO.GPIO_OUT_SET.write_raw(sel_mask); // SEL=H
//         defer rp2350_regs.SIO.GPIO_OUT_CLR.write_raw(sel_mask); // SEL=L

//         var shift = byte;
//         for (0..8) |_| {
//             if ((shift & 0x80) != 0) {
//                 rp2350_regs.SIO.GPIO_OUT_SET.write_raw(sda_mask);
//             } else {
//                 rp2350_regs.SIO.GPIO_OUT_CLR.write_raw(sda_mask);
//             }

//             rp2350_regs.SIO.GPIO_OUT_SET.write_raw(sck_mask);

//             asm volatile ("nop");
//             asm volatile ("nop");
//             rp2350_regs.SIO.GPIO_OUT_CLR.write_raw(sck_mask);

//             shift <<= 1;
//         }
//     }
// }

pub const IRQ = enum(u6) {
    TIMER0_IRQ_0 = 0,
    TIMER0_IRQ_1 = 1,
    TIMER0_IRQ_2 = 2,
    TIMER0_IRQ_3 = 3,
    TIMER1_IRQ_0 = 4,
    TIMER1_IRQ_1 = 5,
    TIMER1_IRQ_2 = 6,
    TIMER1_IRQ_3 = 7,
    PWM_IRQ_WRAP_0 = 8,
    PWM_IRQ_WRAP_1 = 9,
    DMA_IRQ_0 = 10,
    DMA_IRQ_1 = 11,
    DMA_IRQ_2 = 12,
    DMA_IRQ_3 = 13,
    USBCTRL_IRQ = 14,
    PIO0_IRQ_0 = 15,
    PIO0_IRQ_1 = 16,
    PIO1_IRQ_0 = 17,
    PIO1_IRQ_1 = 18,
    PIO2_IRQ_0 = 19,
    PIO2_IRQ_1 = 20,
    IO_IRQ_BANK0 = 21,
    IO_IRQ_BANK0_NS = 22,
    IO_IRQ_QSPI = 23,
    IO_IRQ_QSPI_NS = 24,
    SIO_IRQ_FIFO = 25,
    SIO_IRQ_BELL = 26,
    SIO_IRQ_FIFO_NS = 27,
    SIO_IRQ_BELL_NS = 28,
    SIO_IRQ_MTIMECMP = 29,
    CLOCKS_IRQ = 30,
    SPI0_IRQ = 31,
    SPI1_IRQ = 32,
    UART0_IRQ = 33,
    UART1_IRQ = 34,
    ADC_IRQ_FIFO = 35,
    I2C0_IRQ = 36,
    I2C1_IRQ = 37,
    OTP_IRQ = 38,
    TRNG_IRQ = 39,
    PROC0_IRQ_CTI = 40,
    PROC1_IRQ_CTI = 41,
    PLL_SYS_IRQ = 42,
    PLL_USB_IRQ = 43,
    POWMAN_IRQ_POW = 44,
    POWMAN_IRQ_TIMER = 45,
    SPAREIRQ_IRQ_0 = 46,
    SPAREIRQ_IRQ_1 = 47,
    SPAREIRQ_IRQ_2 = 48,
    SPAREIRQ_IRQ_3 = 49,
    SPAREIRQ_IRQ_4 = 50,
    SPAREIRQ_IRQ_5 = 51,

    pub fn set_handler(comptime irq: IRQ, handler: ashet.platform.profile.FunctionPointer) void {
        @field(interrupt_table, @tagName(irq)) = handler;
    }

    fn get_nvic_params(irq: IRQ) struct { usize, u32 } {
        const index = @intFromEnum(irq);
        const group = index / 32;
        const bitnum: u5 = @truncate(index % 32);
        const mask = @as(u32, 1) << bitnum;
        return .{ group, mask };
    }

    pub fn is_enabled(irq: IRQ) bool {
        const group, const mask = irq.get_nvic_params();
        return (ashet.platform.profile.registers.nvic.iser[group] & mask) != 0;
    }

    pub fn enable(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.registers.nvic.iser[group] = mask;
    }

    pub fn disable(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.registers.nvic.icer[group] = mask;
    }

    pub fn is_pending(irq: IRQ) bool {
        const group, const mask = irq.get_nvic_params();
        return (ashet.platform.profile.registers.nvic.ispr[group] & mask) != 0;
    }

    pub fn set_pending(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.registers.nvic.ispr[group] = mask;
    }

    pub fn clear_pending(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.registers.nvic.icpr[group] = mask;
    }

    pub fn is_active(irq: IRQ) bool {
        const group, const mask = irq.get_nvic_params();
        return (ashet.platform.profile.registers.nvic.iabr[group] & mask) != 0;
    }

    pub fn trigger(irq: IRQ) void {
        ashet.platform.profile.registers.nvic.stir.write_default(.{
            .interrupt_id = @intFromEnum(irq),
        });
    }

    pub fn get_priority(irq: IRQ) u8 {
        comptime std.debug.assert(@import("builtin").cpu.arch.endian() == .little);

        const index = @intFromEnum(irq);
        const group = index / 4;
        const offset = index % 4;

        const values: [4]u8 = @bitCast(ashet.platform.profile.registers.nvic.ipr[group]);
        return values[offset];
    }

    pub fn set_priority(irq: IRQ, prio: u8) void {
        comptime std.debug.assert(@import("builtin").cpu.arch.endian() == .little);

        const index = @intFromEnum(irq);
        const group = index / 4;
        const offset = index % 4;

        var values: [4]u8 = @bitCast(ashet.platform.profile.registers.nvic.ipr[group]);
        values[offset] = prio;
        ashet.platform.profile.registers.nvic.ipr[group] = @bitCast(values);
    }
};
