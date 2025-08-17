const std = @import("std");
const logger = std.log.scoped(.ashet_hc);
const ashet = @import("../../../../main.zig");
const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");
const rp2350_regs = rp2350.peripherals;

const psram = @import("psram.zig");

pub const hw_alloc = @import("hw_alloc.zig");

const Nested_I2C_Bus = @import("drivers/Nested_I2C_Bus.zig");

const disk_image_start = 0x10800000;
const disk_image_end = 0x11000000;

pub const clock_config = blk: {
    var cfg = hal.clocks.config.preset.default();
    cfg.hstx.?.integer_divisor = 1;
    break :blk cfg;
};

pub const machine_config = ashet.ports.MachineConfig{
    .load_sections = .{ .data = true, .bss = true },
    .memory_protection = null,
    .early_initialize = early_initialize,
    .get_tick_count_ms = get_tick_count_ms,
    .initialize = initialize,
    .debug_write = debug_write,
    .get_linear_memory_region = get_linear_memory_region,
    .halt = machine_halt,
    .get_log_prefix = get_log_prefix,
};

const hw = struct {
    //! list of fixed hardware components

    var rtc: ashet.drivers.rtc.Dummy_RTC = undefined;

    var uart0: ashet.drivers.serial.RP2xxx = undefined;
    var uart1: ashet.drivers.serial.RP2xxx = undefined;

    // var fb_video: ashet.drivers.video.Virtual_Video_Output = undefined;
    var hstx_video: ashet.drivers.video.HSTX_DVI = undefined;

    var xip_flash: ashet.drivers.block.Memory_Mapped_Flash = undefined;

    var nic: ashet.drivers.network.ENC28J60 = undefined;

    var system_i2c: Nested_I2C_Bus = undefined;
    var expansion_i2c: [7]Nested_I2C_Bus = undefined;
};

fn get_tick_count_ms() u64 {
    var cs = ashet.CriticalSection.enter();
    defer cs.leave();

    return systick.total_count_ms;
}

comptime {
    std.debug.assert(@sizeOf(rp2350.VectorTable) >= @sizeOf(ashet.platform.profile.start.InterruptTable));
}

var interrupt_table_core0: rp2350.VectorTable align(256) = undefined;
var interrupt_table_core1: rp2350.VectorTable align(256) = undefined;

fn early_initialize() void {
    // Disable watch dog, reset all peripherials, and set the clocks and PLLs:
    hal.init_sequence(clock_config);

    hw_alloc.pins.xip_cs1.set_function(.gpck);
    hw_alloc.pins.debug_tx.set_function(.uart);
    hw_alloc.pins.debug_rx.set_function(.uart);

    hw_alloc.pins.i2c_sda.set_function(.i2c);
    // hw_alloc.pins.i2c_sda.set_pull(.up);
    hw_alloc.pins.i2c_scl.set_function(.i2c);
    // hw_alloc.pins.i2c_scl.set_pull(.up);

    // pinout.dbg_sel.set_function(.sio);
    // pinout.dbg_sck.set_function(.sio);
    // pinout.dbg_sda.set_function(.sio);

    // pinout.dbg_sel.set_direction(.out);
    // pinout.dbg_sck.set_direction(.out);
    // pinout.dbg_sda.set_direction(.out);
    // pinout.dbg_sel.put(0);
    // pinout.dbg_sck.put(0);
    // pinout.dbg_sda.put(0);

    hw_alloc.uart.debug.apply(.{
        .baud_rate = hw_alloc.uart.debug_baud,
        .clock_config = clock_config,
    });

    // Clear screen, start log:
    hw_alloc.uart.debug.write_blocking(ashet.utils.ansi.clear_screen, .no_deadline) catch {};

    logger.info("Debug output ready.", .{});

    logger.info("initialize video memory...", .{});
    videomem.init();

    logger.info("initialize PSRAM...", .{});
    psram.init() catch @panic("failed to initialize psram!");
    {
        const psram_base: [*]align(4096) u8 = @ptrCast(@alignCast(&__machine_linmem_start));
        const psram_len = @intFromPtr(&__machine_linmem_end) - @intFromPtr(&__machine_linmem_start);
        @memset(psram_base[0..psram_len], 0);
    }

    configure_interrupt_table(&interrupt_table_core0);
    logger.info("initialize ethernet spi...", .{});
    {
        hw_alloc.spi.ethernet.apply(.{
            .baud_rate = 1_000_000,
            .clock_config = clock_config,
        }) catch @panic("failed to initialize SPI");

        hw_alloc.pins.eth_mosi_pin.set_function(.spi);
        hw_alloc.pins.eth_miso_pin.set_function(.spi);
        hw_alloc.pins.eth_sck_pin.set_function(.spi);
        hw_alloc.pins.eth_cs_pin.set_function(.sio);
        hw_alloc.pins.eth_irq_pin.set_function(.sio);

        hw_alloc.pins.eth_irq_pin.set_direction(.in);

        hw_alloc.pins.eth_cs_pin.put(1);
        hw_alloc.pins.eth_cs_pin.set_direction(.out);
    }

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

fn initialize() !void {
    logger.info("cpuid: {s}", .{
        ashet.platform.profile.peripherals.system_control_block.cpuid.read(),
    });

    logger.info("initialize SysTick...", .{});
    systick.init();

    // Initialize devices and drivers:
    {
        hw.rtc = .init(1739025296 * std.time.ns_per_s);

        hw.uart0 = try .init(clock_config, hw_alloc.uart.debug, hw_alloc.uart.debug_baud);
        // hw.uart1 = try ashet.drivers.serial.RP2xxx.init(clock_config, hal.uart.instance.UART1, 115_200);

        // hw.fb_video = ashet.drivers.video.Virtual_Video_Output.init();

        hw.hstx_video = try .init(clock_config);

        hw.xip_flash = .init(
            disk_image_start,
            disk_image_end - disk_image_start,
        );

        hw.nic = try .init(spi0, .init(.{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }), .{});

        hw.system_i2c = try .init(.{
            .clock_config = clock_config,
            .i2c = hw_alloc.i2c.system_bus,
            .mux = hw_alloc.i2c_addresses.i2c_main_mux,
            .mask = 0x80,
            .name = "System Bus",
        });

        inline for (&hw.expansion_i2c, 0..) |*slot, slot_id| {
            const mask = (@as(u8, 1) << @as(u3, @intCast(slot_id)));
            slot.* = try .init(.{
                .clock_config = clock_config,
                .i2c = hw_alloc.i2c.system_bus,
                .mux = hw_alloc.i2c_addresses.i2c_main_mux,
                .mask = mask,
                .name = std.fmt.comptimePrint("Expansion Slot {}", .{slot_id}),
            });
        }
    }

    ashet.drivers.install(&hw.rtc.driver);
    ashet.drivers.install(&hw.uart0.driver);
    // ashet.drivers.install(&hw.uart1.driver);
    ashet.drivers.install(&hw.hstx_video.driver);
    ashet.drivers.install(&hw.xip_flash.driver);
    ashet.drivers.install(&hw.nic.driver);
    ashet.drivers.install(&hw.system_i2c.driver);
    for (&hw.expansion_i2c) |*slot| {
        ashet.drivers.install(&slot.driver);
    }

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

var core1_ready: bool = false;
var core1_stack: [1024]u32 = undefined;

fn configure_mpu_region(region: u3, rbar: ashet.platform.profile.peripherals.mpu.RBAR.Reg, rlar: ashet.platform.profile.peripherals.mpu.RLAR.Reg) void {
    ashet.platform.profile.peripherals.mpu.rnr.write(.{
        .region = region,
    });

    ashet.platform.profile.peripherals.mpu.rbar.write(rbar);
    ashet.platform.profile.peripherals.mpu.rlar.write(rlar);
}

fn core1_main() linksection(".sram.bank0") void {
    logger.info("core1 launched.", .{});

    configure_interrupt_table(&interrupt_table_core1);

    // DMA read and write win over CPU:
    rp2350.peripherals.BUSCTRL.BUS_PRIORITY.write_default(.{
        .DMA_W = 1,
        .DMA_R = 1,
        .PROC0 = 0,
        .PROC1 = 0,
    });

    ashet.drivers.video.HSTX_DVI.init_backend(clock_config);

    // TODO: Enable MPU protection so Core 1 can't access XIP 0 and XIP 1 memories.
    //       These memories have too much latency to allow real-time operation.
    if (false) {
        configure_mpu_region(0, .{
            .allow_execute = .no_execute,
            .permissions = .read_write_sec,
            .sharing = .non_shareable,
            .base = .from_int(0x1000_0000),
        }, .{
            .enable = true,
            .attribute_index = 0,
            .limit = .from_int(0x11FF_FFFF),
        });
        configure_mpu_region(1, .{
            .allow_execute = .when_accessible,
            .permissions = .read_write_sec,
            .sharing = .non_shareable,
            .base = .from_int(0x2000_0000),
        }, .{
            .enable = true,
            .attribute_index = 0,
            .limit = .from_int(0x200F_FFFF),
        });
        configure_mpu_region(2, .{
            .allow_execute = .no_execute,
            .permissions = .read_write_sec,
            .sharing = .non_shareable,
            .base = .from_int(0x4000_0000),
        }, .{
            .enable = true,
            .attribute_index = 1,
            .limit = .from_int(0xFFFF_FFFF),
        });

        ashet.platform.profile.peripherals.mpu.mair[0].write(.{
            .outer = .normal_non_cacheable,
            .inner = .{ .memory = .non_cacheable },
        });
        ashet.platform.profile.peripherals.mpu.mair[1].write(.{
            .outer = .device,
            .inner = .{ .device = .ng_nr_ne },
        });

        ashet.platform.profile.peripherals.mpu.ctrl.write(.{
            .enabled = true,
            .fault_handler_protection = .disabled, // allow hardfault/memfault to access everything
            .priviledged_access = .mpu_protected,
        });
    }

    ashet.drivers.video.HSTX_DVI.start_backend();

    ashet.utils.volatile_write(bool, &core1_ready, true);

    const busctrl = rp2350.peripherals.BUSCTRL;
    busctrl.PERFCTR0.write(.{ .PERFCTR0 = 0 });
    busctrl.PERFCTR1.write(.{ .PERFCTR1 = 0 });
    busctrl.PERFSEL0.write(.{ .PERFSEL0 = .xip_main0_access_contested });
    busctrl.PERFSEL1.write(.{ .PERFSEL1 = .xip_main1_access_contested });
    busctrl.PERFCTR_EN.write(.{ .PERFCTR_EN = 1 });

    while (true) {
        ashet.platform.profile.wfi();
    }
}

inline fn configure_interrupt_table(core_local_table: *align(256) rp2350.VectorTable) void {
    // Remap interrupt table:
    {
        // Create default variant:
        core_local_table.* = .{
            .initial_stack_pointer = @intFromPtr(ashet.platform.profile.start.initial_vector_table.initial_stack_pointer),
            .Reset = ashet.platform.profile.start.initial_vector_table.reset,
        };

        // Copy the original interrupt table into this one:
        const alias: *ashet.platform.profile.start.InterruptTable = @ptrCast(core_local_table);

        alias.* = ashet.platform.profile.start.initial_vector_table.*;
    }

    ashet.platform.profile.peripherals.system_control_block.vtor.write_raw(@intFromPtr(core_local_table));

    ashet.platform.profile.enable_fault_irq();
    ashet.platform.profile.enable_interrupts();
}

var mouse_buffer: [3]u8 = undefined;
var mouse_buffer_index: usize = 0;
var mouse_last_state: u8 = 0;

fn uart0_irq_handler() callconv(.C) void {
    const debug_uart = hw_alloc.uart.debug;
    const reader = debug_uart.reader(.no_deadline);

    while (debug_uart.is_readable()) {
        const byte = reader.readByte() catch unreachable;

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
    const debug_uart = hw_alloc.uart.debug;
    debug_uart.write_blocking(msg, .no_deadline) catch {};
}

extern var __machine_linmem_start: anyopaque align(4096);
extern var __machine_linmem_end: anyopaque align(4096);

fn get_linear_memory_region() ashet.memory.Range {
    const linmem_start = @intFromPtr(&__machine_linmem_start);
    const linmem_end = @intFromPtr(&__machine_linmem_end);
    return .{ .base = linmem_start, .length = linmem_end - linmem_start };
}

const systick = struct {
    const regs = ashet.platform.profile.peripherals.sys_tick;

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

        interrupt_table_core0.SysTick = increment_clock_irq;

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

fn get_log_prefix() []const u8 {
    return switch (rp2350.peripherals.SIO.CPUID.read().CPUID & 1) {
        0 => "core 0",
        1 => "core 1",
        else => unreachable,
    };
}

fn get_interrupt_table() *rp2350.VectorTable {
    return switch (rp2350.peripherals.SIO.CPUID.read().CPUID & 1) {
        0 => &interrupt_table_core0,
        1 => &interrupt_table_core1,
        else => unreachable,
    };
}

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
        @field(get_interrupt_table(), @tagName(irq)) = handler;
        ashet.platform.profile.isb();
        ashet.platform.profile.dsb();
    }

    pub fn get_handler(comptime irq: IRQ) ?ashet.platform.profile.FunctionPointer {
        return @field(get_interrupt_table(), @tagName(irq));
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
        return (ashet.platform.profile.peripherals.nvic.iser[group] & mask) != 0;
    }

    pub fn enable(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.peripherals.nvic.iser[group] = mask;
    }

    pub fn disable(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.peripherals.nvic.icer[group] = mask;
    }

    pub fn is_pending(irq: IRQ) bool {
        const group, const mask = irq.get_nvic_params();
        return (ashet.platform.profile.peripherals.nvic.ispr[group] & mask) != 0;
    }

    pub fn set_pending(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.peripherals.nvic.ispr[group] = mask;
    }

    pub fn clear_pending(irq: IRQ) void {
        const group, const mask = irq.get_nvic_params();
        ashet.platform.profile.peripherals.nvic.icpr[group] = mask;
    }

    pub fn is_active(irq: IRQ) bool {
        const group, const mask = irq.get_nvic_params();
        return (ashet.platform.profile.peripherals.nvic.iabr[group] & mask) != 0;
    }

    pub fn trigger(irq: IRQ) void {
        ashet.platform.profile.peripherals.nvic.stir.write_default(.{
            .interrupt_id = @intFromEnum(irq),
        });
    }

    pub fn get_priority(irq: IRQ) u8 {
        comptime std.debug.assert(@import("builtin").cpu.arch.endian() == .little);

        const index = @intFromEnum(irq);
        const group = index / 4;
        const offset = index % 4;

        const values: [4]u8 = @bitCast(ashet.platform.profile.peripherals.nvic.ipr[group]);
        return values[offset];
    }

    pub const Priority = enum(u8) {
        highest = 0,
        normal = 128,
        lowest = 255,
        _,
    };

    pub fn set_priority(irq: IRQ, prio: Priority) void {
        comptime std.debug.assert(@import("builtin").cpu.arch.endian() == .little);

        const index = @intFromEnum(irq);
        const group = index / 4;
        const offset = index % 4;

        var values: [4]u8 = @bitCast(ashet.platform.profile.peripherals.nvic.ipr[group]);
        values[offset] = @intFromEnum(prio);
        ashet.platform.profile.peripherals.nvic.ipr[group] = @bitCast(values);
    }
};

fn machine_halt() noreturn {
    ashet.platform.profile.disable_interrupts();

    debug_write("\r\nMACHINE HALT [");

    switch (rp2350.peripherals.SIO.CPUID.read().CPUID) {
        0 => debug_write("Core 0"),
        1 => debug_write("Core 1"),
        else => debug_write("WTf"),
    }
    debug_write("]\r\n");

    ashet.platform.profile.bkpt(0);

    while (true) {
        ashet.platform.profile.wfe();
    }
}

const spi0: ashet.drivers.network.ENC28J60.HardwareInterface = .{
    .param = undefined,
    .vtable = &.{
        .set_chipselect = spi0_set_chipselect,
        .write = spi0_write,
        .read = spi0_read,
    },
};

fn spi0_set_chipselect(dri: *anyopaque, asserted: bool) void {
    _ = dri;

    // hal.time.sleep_us(1);
    hw_alloc.pins.eth_cs_pin.put(if (asserted) 0 else 1);
    // hal.time.sleep_us(1);
}

fn spi0_write(dri: *anyopaque, output: []const u8) void {
    _ = dri;
    hw_alloc.spi.ethernet.write_blocking(u8, output);
}

fn spi0_read(dri: *anyopaque, tx_byte: u8, input: []u8) void {
    _ = dri;
    hw_alloc.spi.ethernet.read_blocking(u8, tx_byte, input);
}

const videomem = struct {
    extern var __rp2350_sram_bank1_start: anyopaque align(4);
    extern var __rp2350_sram_bank1_end: anyopaque align(4);
    extern const __rp2350_sram_bank1_load: anyopaque align(4);

    extern var __rp2350_sram_bank2_start: anyopaque align(4);
    extern var __rp2350_sram_bank2_end: anyopaque align(4);
    extern const __rp2350_sram_bank2_load: anyopaque align(4);

    extern var __rp2350_sram_bank3_start: anyopaque align(4);
    extern var __rp2350_sram_bank3_end: anyopaque align(4);
    extern const __rp2350_sram_bank3_load: anyopaque align(4);

    fn init_bank(
        start: *align(4) anyopaque,
        end: *align(4) anyopaque,
        load: *align(4) const anyopaque,
    ) void {
        const len_bytes = @intFromPtr(end) - @intFromPtr(start);
        const len_words = @divExact(len_bytes, @sizeOf(u32));

        const src = @as([*]const u32, @ptrCast(load));
        const dst = @as([*]u32, @ptrCast(start));

        @memcpy(dst[0..len_words], src[0..len_words]);
    }

    fn init() void {
        init_bank(
            &__rp2350_sram_bank1_start,
            &__rp2350_sram_bank1_end,
            &__rp2350_sram_bank1_load,
        );
        init_bank(
            &__rp2350_sram_bank2_start,
            &__rp2350_sram_bank2_end,
            &__rp2350_sram_bank2_load,
        );
        init_bank(
            &__rp2350_sram_bank3_start,
            &__rp2350_sram_bank3_end,
            &__rp2350_sram_bank3_load,
        );
    }
};
