const std = @import("std");
const logger = std.log.scoped(.ashet_hc);
const ashet = @import("../../../../main.zig");
const rp2350 = @import("rp2350");
const hal = @import("rp2350-hal");
const expcard = @import("expcard");
const rp2350_regs = rp2350.peripherals;

const psram = @import("psram.zig");

pub const hw_alloc = @import("hw_alloc.zig");

const Nested_I2C_Bus = @import("drivers/Nested_I2C_Bus.zig");

const HSTX_Driver = ashet.drivers.video.HSTX_DVI_2;

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
    .debug_write = debug_log.local_write,
    .get_linear_memory_region = get_linear_memory_region,
    .halt = machine_halt,
    .get_log_prefix = get_log_prefix,
    .uses_hardware_multithreading = true,
};

const hw = struct {
    //! list of fixed hardware components

    var rtc: ashet.drivers.rtc.Dummy_RTC = undefined;

    var uart0: ashet.drivers.serial.RP2xxx = undefined;
    var uart1: ashet.drivers.serial.RP2xxx = undefined;

    // var fb_video: ashet.drivers.video.Virtual_Video_Output = undefined;
    var hstx_video: HSTX_Driver = undefined;

    var xip_flash: ashet.drivers.block.Memory_Mapped_Flash = undefined;

    var nic: ashet.drivers.network.ENC28J60 = undefined;

    var system_i2c: Nested_I2C_Bus = undefined;
    var expansion_i2c: [7]Nested_I2C_Bus = undefined;
};

fn get_tick_count_ms() u64 {
    // var cs = ashet.CriticalSection.enter();
    // defer cs.leave();

    // return systick.total_count_ms;

    return @intFromEnum(hal.time.get_time_since_boot()) / 1000;
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

    hw_alloc.pins.i2c_sda.set_function(.i2c);
    hw_alloc.pins.i2c_scl.set_function(.i2c);

    debug_log.init() catch {
        // this is ... unfortunate and definitly a bug,
        // but we can't even print something yet, so we're
        // just going into a hang loop:
        while (true) {
            ashet.platform.profile.wfe();
        }
    };

    // Clear screen, start log:

    debug_log.write(0, ashet.utils.ansi.clear_screen);
    debug_log.write(1, ashet.utils.ansi.clear_screen);

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

    logger.info("initialize interrupt tables...", .{});
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

    // DMA read and write win over CPU:
    rp2350.peripherals.BUSCTRL.BUS_PRIORITY.write_default(.{
        .DMA_W = 1,
        .DMA_R = 1,
        .PROC0 = 0,
        .PROC1 = 0,
    });
    while (rp2350.peripherals.BUSCTRL.BUS_PRIORITY_ACK.read().BUS_PRIORITY_ACK == 0) {
        //
    }

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

    ashet.platform.profile.enable_interrupts();

    // Initialize devices and drivers:
    {
        hw.rtc = .init(1739025296 * std.time.ns_per_s);

        // hw.fb_video = ashet.drivers.video.Virtual_Video_Output.init();

        hw.hstx_video = try .init(clock_config);

        hw.xip_flash = .init(
            disk_image_start,
            disk_image_end - disk_image_start,
        );

        // TODO: Implement a driver for the ENC424J600
        // hw.nic = try .init(spi0, .init(.{ 0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF }), .{});

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

        {
            try propio.init_propeller2();

            try backplane.scan_modules();
        }

        // FIXME: The UARTs must be initialized *after* the Propeller 2 right now
        //        as we're using UART1 to bootstrap the Propeller.
        hw.uart0 = try .init(clock_config, hw_alloc.uart.com1, hw_alloc.cfg.default_baud);
        hw.uart1 = try .init(clock_config, hw_alloc.uart.com2, hw_alloc.cfg.default_baud);
    }

    ashet.drivers.install(&hw.rtc.driver);
    ashet.drivers.install(&hw.uart0.driver);
    ashet.drivers.install(&hw.uart1.driver);
    ashet.drivers.install(&hw.hstx_video.driver);
    ashet.drivers.install(&hw.xip_flash.driver);
    // ashet.drivers.install(&hw.nic.driver);
    ashet.drivers.install(&hw.system_i2c.driver);
    for (&hw.expansion_i2c) |*slot| {
        ashet.drivers.install(&slot.driver);
    }
}

var core1_ready: bool = false;
var core1_stack: [1024]u32 align(16) = undefined;

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

    HSTX_Driver.init_backend(clock_config);

    // Enable MPU protection so Core 1 can't access XIP 0 and XIP 1 memories.
    // These memories have too much latency to allow real-time operation.
    {
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

    ashet.utils.volatile_write(bool, &core1_ready, true);

    HSTX_Driver.start_backend();

    while (true) {
        ashet.platform.profile.wfi();
    }
}

inline fn configure_interrupt_table(core_local_table: *align(256) rp2350.VectorTable) void {
    // Remap interrupt table:
    {
        // Create default variant:
        core_local_table.* = .{
            .initial_stack_pointer = ashet.platform.profile.start.initial_vector_table.initial_stack_pointer,
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

    debug_log.local_write("\r\nCORE HALT\r\n");

    // TODO: Implement proper "machine halt" by stopping everything.

    ashet.platform.profile.bkpt(0);

    while (true) {
        ashet.platform.profile.wfe();
    }
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

const propio = struct {
    const p2boot = @import("p2boot.zig");
    const protocol = @import("propio/protocol.zig");

    const backplane_bootrom_checksum: []const u8 = blk: {
        const raw_bootrom = @embedFile("propeller2.bin");
        if (raw_bootrom.len % 4 != 0) @compileError("propeller2.bin must have a length divisible by 4!");
        var checksummed_bootrom: [raw_bootrom.len + 4]u8 = undefined;

        @memcpy(checksummed_bootrom[0..raw_bootrom.len], raw_bootrom);
        var cs: u32 = 0x706F7250; // "Prop"
        for (std.mem.bytesAsSlice(u32, raw_bootrom)) |item| {
            const word = std.mem.littleToNative(u32, item);
            cs -%= word;
        }
        std.mem.writeInt(u32, checksummed_bootrom[raw_bootrom.len..][0..4], cs, .little);

        const immutable = checksummed_bootrom;
        break :blk &immutable;
    };

    fn init_propeller2() !void {
        logger.info("initialize Propeller 2 boot interface...", .{});

        p2boot.init();

        logger.info("reset Propeller 2 and catch bootloader...", .{});
        for (0..6) |retry| {
            if (p2boot.reset()) |_|
                break
            else |err| {
                logger.warn("failed to reset propeller 2 {} times: {s}", .{ retry, @errorName(err) });
                continue;
            }
        } else return error.P2ResetFailed;

        logger.info("detected P2, loading {} bytes of bootrom...", .{
            backplane_bootrom_checksum.len - 4,
        });

        try p2boot.launch(backplane_bootrom_checksum);

        logger.info("Propeller 2 launched.", .{});
        p2boot.deinit();

        logger.info("Initializing PropIO interface....", .{});
        try protocol.init();

        logger.info("code fully loaded, waiting for backplane ready.", .{});

        {
            var frame_buffer: [5]u8 = @splat(0);
            const len = try protocol.receive_one_blocking(&frame_buffer);
            logger.info("received handshake frame: {}", .{std.fmt.fmtSliceHexLower(frame_buffer[0..len])});
            if (len != 1 or frame_buffer[0] != 0xFF)
                return error.InvalidHandshake;
        }

        logger.info("Propeller 2 Backplane I/O ready.", .{});
    }
};

const backplane = struct {
    const Module = struct {
        id: propio.protocol.ModuleID,
        metadata: expcard.MetadataBlock,
        firmware: ?expcard.FirmwareBlock,
        driver: ?*ashet.drivers.propio.Device,
        propio_module: ashet.drivers.propio.Module = .{
            .send_fn = send_fifo_data,
        },
    };

    var modules: [7]?*Module = @splat(null);
    var worker_thread: *ashet.scheduler.Thread = undefined;

    pub fn scan_modules() !void {

        // TODO: Use DETECT pins of expansion slots to find out where cards are plugged in.

        // Scan the I²C subnets to find potential expansion cards:
        for (&modules, 0..7) |*mod, slot_index| {
            mod.* = initialize_module(@intCast(slot_index)) catch |err| {
                logger.err("failed to initialize expansion slot {}: {s}", .{ slot_index, @errorName(err) });
                continue;
            };
        }

        // TODO: Find drivers and start modules here!

        for (modules) |maybe_mod| {
            const mod: *Module = maybe_mod orelse continue;

            if (mod.metadata.@"Vendor ID" != 13) {
                logger.warn("Unknown vendor {} for module {}", .{ mod.metadata.@"Vendor ID", mod.id });
                continue;
            }

            if (mod.firmware == null) {
                // TODO: Just search for drivers that can handle this module and load it.
                logger.err("TODO: Implement driver search. No firmware for Module {}, VID {}, PID {}", .{
                    mod.id,
                    mod.metadata.@"Vendor ID",
                    mod.metadata.@"Product ID",
                });
                continue;
            }

            const propio_mod: propio.protocol.Module = switch (mod.metadata.@"Product ID") {
                1 => .{ // Quad PS/2 Module
                    .code = &mod.firmware.?.data,
                    .config = .{
                        .tx_fifo0 = .{
                            .base = 0,
                            .limit = 8,
                        },
                        .rx_fifo0 = .{
                            .base = 32,
                            .limit = 8,
                        },
                    },
                },

                else => {
                    logger.warn("Unknown product {} for module {}", .{ mod.metadata.@"Vendor ID", mod.id });
                    continue;
                },
            };

            // TODO: Implement the rest like firmware detection, driver loading, ...
            logger.info("expansion slot {} has firmware, uploading to Propeller 2 @ 0x{X:0>6}...", .{ mod.id, mod.id.get_code_address() });

            try propio.protocol.launch_module(mod.id, propio_mod);

            // TODO: Implement proper driver selection here!
            const driver = try ashet.drivers.input.PropIO_PS2_Device.init(&mod.propio_module);
            mod.driver = &driver.device;
            ashet.drivers.install(&driver.generic.driver);
        }

        const thread = try ashet.scheduler.Thread.spawn(process_propio_data, null, .{});
        defer thread.detach();

        thread.setName("PropIO") catch {};

        thread.start() catch unreachable; // Won't ever be non-started here

        worker_thread = thread;

        logger.info("PropIO startup completed.", .{});
    }

    fn process_propio_data(_: ?*anyopaque) callconv(.c) noreturn {
        var rx_frame_buf: [hw_alloc.cfg.propio_buffer_size]u8 = undefined;

        logger.info("PropIO worker ready.", .{});
        while (true) {

            // Consume all available propio packets one by one and dispatch them to the correct driver.
            // Afterwards, yield the thread and wait for more packets.
            while (true) {
                const maybe_len = propio.protocol.try_receive_one(&rx_frame_buf) catch |err| switch (err) {
                    error.Overflow => unreachable, // rx_frame is guaranteed to be big enough
                };

                const len = maybe_len orelse break;
                std.debug.assert(len > 0);

                const rx_frame = rx_frame_buf[0..len];

                handle_propio_frame(rx_frame) catch |err| {
                    logger.warn("error {s} when processing propio frame '{}'", .{
                        @errorName(err),
                        std.fmt.fmtSliceHexLower(rx_frame),
                    });
                };
            }

            // TODO: This thread could be suspended and be woken up by the propio module.
            //       This requires careful synchronization though, as the receiving part runs on the other core.
            ashet.scheduler.yield();
        }
    }

    fn handle_propio_frame(rx_frame: []const u8) !void {
        const frame_type = std.meta.intToEnum(propio.protocol.types.FrameType, rx_frame[0]) catch {
            logger.warn("received unknown frame from propio: '{}'", .{
                std.fmt.fmtSliceHexLower(rx_frame),
            });
            return;
        };

        switch (frame_type) {
            .write_fifo => {
                if (rx_frame.len < 2)
                    return error.InsufficientSize;

                const Pack = packed struct(u8) {
                    fifo: u3,
                    _reserved0: u1,
                    module: u3,
                    _reserved1: u1,
                };
                const pack: Pack = @bitCast(rx_frame[1]);
                const data = rx_frame[2..];

                const module = modules[pack.module] orelse {
                    // This should not happen as this means the backplane firmware
                    // would've passed data in a non-initialized module.
                    //
                    // In any case, this would be a bug.

                    logger.err("received FIFO data for uninitialized module {}, fifo {}: '{}'", .{
                        pack.module,
                        pack.fifo,
                        std.fmt.fmtSliceHexLower(data),
                    });
                    return;
                };

                const driver = module.driver orelse {
                    // This should not happen as this means the backplane firmware
                    // somehow sent data to the FIFO even though the module has no driver
                    // assigned and thus should not have started the module in the first place.

                    logger.err("received FIFO data for driverless module {}, fifo {}: '{}'", .{
                        pack.module,
                        pack.fifo,
                        std.fmt.fmtSliceHexLower(data),
                    });
                    return;
                };

                const fifo: ashet.drivers.propio.RxFifo = switch (pack.fifo) {
                    0...3 => {
                        logger.err("received FIFO data for TX FIFO in module {}, fifo {}: '{}'", .{
                            pack.module,
                            pack.fifo,
                            std.fmt.fmtSliceHexLower(data),
                        });
                        return;
                    },

                    4...7 => @enumFromInt(@as(u2, @intCast(pack.fifo - 4))),
                };

                // logger.info("received FIFO data for module {}, fifo {}: '{}'", .{
                //     pack.module,
                //     pack.fifo,
                //     std.fmt.fmtSliceHexLower(data),
                // });
                driver.notify_fifo_data(fifo, data);
            },

            .write_ram => {
                if (rx_frame.len < 4)
                    return error.InsufficientSize;

                const addr = std.mem.readInt(u24, rx_frame[1..4], .little);

                // TODO: Handle memory reads?
                logger.warn("received unsupported memory read response at address 0x{X:0>6}: '{}'", .{
                    addr,
                    std.fmt.fmtSliceHexLower(rx_frame[4..]),
                });
            },

            .nop,
            .start_module,
            .stop_module,
            => {
                logger.warn("received unsupported frame from propio: '{}'", .{
                    std.fmt.fmtSliceHexLower(rx_frame),
                });
            },
        }
    }

    fn initialize_module(slot_index: u3) !?*Module {
        const slot_mask: u8 = @as(u8, 1) << slot_index;

        // select the proper subnet:
        try hw_alloc.i2c.system_bus.write_blocking(hw_alloc.i2c_addresses.i2c_main_mux, std.mem.asBytes(&slot_mask), null);

        // try poking the eeprom with the read address:
        const read_addr: u16 = std.mem.nativeTo(u16, 0, .big);
        hw_alloc.i2c.system_bus.write_blocking(hw_alloc.i2c_addresses.expansion_eeprom, std.mem.asBytes(&read_addr), null) catch |err| switch (err) {
            error.DeviceNotPresent => {
                logger.warn("expansion slot {} has no EEPROM available", .{slot_index});
                return null;
            },

            error.Timeout,
            error.NoAcknowledge,
            error.TargetAddressReserved,
            error.NoData,
            error.TxFifoFlushed,
            error.UnknownAbort,
            => |e| return e,
        };

        const metadata_block: expcard.MetadataBlock = blk: {
            var header_block_data: [@sizeOf(expcard.MetadataBlock)]u8 = @splat(0);
            try hw_alloc.i2c.system_bus.read_blocking(hw_alloc.i2c_addresses.expansion_eeprom, &header_block_data, null);
            var fbs = std.io.fixedBufferStream(&header_block_data);

            const block = try fbs.reader().readStructEndian(expcard.MetadataBlock, .little);

            std.debug.assert(fbs.pos == header_block_data.len);

            break :blk block;
        };

        if (!metadata_block.is_checksum_ok()) {
            logger.warn("expansion slot {} available, but has invalid checksum. stored checksum: 0x{X:0>8}, actual checksum: expected checksum: 0x{X:0>8}", .{
                slot_index,
                metadata_block.@"CRC32 Checksum",
                metadata_block.compute_checksum(),
            });
            return null;
        }

        logger.info("expansion slot {} has valid card:", .{slot_index});

        logger.info("  Version:          {}", .{metadata_block.Version});
        logger.info("  Vendor:           {} (\"{}\")", .{ metadata_block.@"Vendor ID", std.zig.fmtEscapes(metadata_block.@"Vendor Name".slice()) });
        logger.info("  Product:          {} (\"{}\")", .{ metadata_block.@"Product ID", std.zig.fmtEscapes(metadata_block.@"Product Name".slice()) });
        logger.info("  Serial Number:    \"{}\"", .{std.zig.fmtEscapes(metadata_block.@"Serial Number".slice())});
        logger.info("  Properties:", .{});
        logger.info("    Requires Audio: {}", .{metadata_block.Properties.@"Requires Audio"});
        logger.info("    Requires Video: {}", .{metadata_block.Properties.@"Requires Video"});
        logger.info("    Requires USB:   {}", .{metadata_block.Properties.@"Requires USB"});
        logger.info("    Has Firmware:   {}", .{metadata_block.Properties.@"Has Firmware"});
        logger.info("    Has Icons:      {}", .{metadata_block.Properties.@"Has Icons"});
        logger.info("  Driver Interface: {}", .{metadata_block.@"Driver Interface"});

        if (metadata_block.Version != 1) {
            logger.warn("expansion slot {} available, but has unsupported version.", .{
                slot_index,
            });
            return null;
        }

        const module = try ashet.memory.type_pool(Module).alloc();
        errdefer ashet.memory.type_pool(Module).free(module);

        module.* = .{
            .id = @enumFromInt(slot_index + 1),
            .metadata = metadata_block,
            .firmware = null,
            .driver = null,
        };

        if (module.metadata.Properties.@"Has Firmware") {
            logger.info("expansion slot {} has firmware, loading from EEPROM...", .{slot_index});

            module.firmware = .{};
            errdefer module.firmware = null;

            const firmware_addr: u16 = std.mem.nativeTo(u16, @offsetOf(expcard.EEPROM_Image, "firmware"), .big);

            try hw_alloc.i2c.system_bus.write_blocking(hw_alloc.i2c_addresses.expansion_eeprom, std.mem.asBytes(&firmware_addr), null);
            try hw_alloc.i2c.system_bus.read_blocking(hw_alloc.i2c_addresses.expansion_eeprom, &module.firmware.?.data, null);
        }

        return module;
    }

    fn send_fifo_data(mod: *ashet.drivers.propio.Module, fifo: ashet.drivers.propio.TxFifo, data: []const u8) void {
        const module: *Module = @alignCast(@fieldParentPtr("propio_module", mod));

        propio.protocol.write_fifo(
            module.id,
            @enumFromInt(@intFromEnum(fifo)),
            data,
        );
    }
};

pub const perfctr = struct {
    const busctrl = rp2350.peripherals.BUSCTRL;

    const Counter = @TypeOf(busctrl.PERFSEL0.direct_access.PERFSEL0);

    pub fn setup(p0: Counter, p1: Counter, p2: Counter, p3: Counter) void {
        stop();

        @setRuntimeSafety(false);
        busctrl.PERFSEL0.write(.{ .PERFSEL0 = @enumFromInt(@intFromEnum(p0)) });
        busctrl.PERFSEL1.write(.{ .PERFSEL1 = @enumFromInt(@intFromEnum(p1)) });
        busctrl.PERFSEL2.write(.{ .PERFSEL2 = @enumFromInt(@intFromEnum(p2)) });
        busctrl.PERFSEL3.write(.{ .PERFSEL3 = @enumFromInt(@intFromEnum(p3)) });

        reset();
    }

    pub fn reset() void {
        stop();
        busctrl.PERFCTR0.write(.{ .PERFCTR0 = 0 });
        busctrl.PERFCTR1.write(.{ .PERFCTR1 = 0 });
        busctrl.PERFCTR2.write(.{ .PERFCTR2 = 0 });
        busctrl.PERFCTR3.write(.{ .PERFCTR3 = 0 });
        ashet.platform.profile.dwt_unit.reset();
    }

    pub inline fn start() void {
        std.debug.assert(busctrl.PERFCTR_EN.read().PERFCTR_EN == 0);
        ashet.platform.profile.dwt_unit.start();
        busctrl.PERFCTR_EN.write(.{ .PERFCTR_EN = 1 });
    }

    pub inline fn stop() void {
        busctrl.PERFCTR_EN.write(.{ .PERFCTR_EN = 0 });
        ashet.platform.profile.dwt_unit.stop();
    }

    pub fn dump() void {
        const ctr = ashet.platform.profile.dwt_unit.read();
        logger.info("Cycles     = {}", .{ctr});
        logger.info("PERF0[{s}] = {}", .{ @tagName(busctrl.PERFSEL0.read().PERFSEL0), busctrl.PERFCTR0.read().PERFCTR0 });
        logger.info("PERF1[{s}] = {}", .{ @tagName(busctrl.PERFSEL1.read().PERFSEL1), busctrl.PERFCTR1.read().PERFCTR1 });
        logger.info("PERF2[{s}] = {}", .{ @tagName(busctrl.PERFSEL2.read().PERFSEL2), busctrl.PERFCTR2.read().PERFCTR2 });
        logger.info("PERF3[{s}] = {}", .{ @tagName(busctrl.PERFSEL3.read().PERFSEL3), busctrl.PERFCTR3.read().PERFCTR3 });
    }
};

const debug_log = struct {
    const debug_tx_code = blk: {
        @setEvalBranchQuota(20_000);
        break :blk hal.pio.assemble(
            \\.program debug_tx
            \\
            \\.wrap_target
            \\  pull                            ; fetch data. blocks.
            \\  set pins, 0                     ; send start bit
            \\  set x, 7                        ; set bit counter
            \\bitloop:
            \\  out pins, 1                     ; send data bits
            \\  jmp x-- bitloop                 ; loop until all 8 data bits are sent
            \\  set pins, 1                     ; set line to idle, also send stop bit
            \\.wrap
            \\
        , .{});
    };

    const pio = hw_alloc.pio.debuglog;
    const debug_tx_pgm = debug_tx_code.get_program_by_name("debug_tx");

    fn init() !void {
        comptime std.debug.assert(pio == .pio1);
        hw_alloc.pins.debug_core0_tx.set_function(.pio1);
        hw_alloc.pins.debug_core1_tx.set_function(.pio1);

        // we first must set up the GPIOBASE, otherwise the pins are fucked up:
        pio.get_regs().GPIOBASE.write_raw(16);

        try pio.sm_load_and_start_program(.sm0, debug_tx_pgm, .{
            .clkdiv = .{ .int = 25, .frac = 0 }, // 1 MBaud
            .pin_mappings = .{
                .out = .single(hw_alloc.pins.debug_core0_tx),
                .set = .single(hw_alloc.pins.debug_core0_tx),
                .in_base = null,
            },
            .exec = .{},
            .shift = .{
                .autopull = false,
                .out_shiftdir = .right,

                .join_tx = true,

                .pull_threshold = 8,
            },
        });

        try pio.sm_load_and_start_program(.sm1, debug_tx_pgm, .{
            .clkdiv = .{ .int = 25, .frac = 0 }, // 1 MBaud
            .pin_mappings = .{
                .out = .single(hw_alloc.pins.debug_core1_tx),
                .set = .single(hw_alloc.pins.debug_core1_tx),
                .in_base = null,
            },
            .exec = .{},
            .shift = .{
                .autopull = false,
                .out_shiftdir = .right,

                .join_tx = true,

                .pull_threshold = 8,
            },
        });

        try pio.sm_set_pin(.sm0, hw_alloc.pins.debug_core0_tx, 1, 1);
        try pio.sm_set_pin(.sm1, hw_alloc.pins.debug_core1_tx, 1, 1);

        try pio.sm_set_pindir(.sm0, hw_alloc.pins.debug_core0_tx, 1, .out);
        try pio.sm_set_pindir(.sm1, hw_alloc.pins.debug_core1_tx, 1, .out);

        pio.sm_set_enabled(.sm0, true);
        pio.sm_set_enabled(.sm1, true);
    }

    fn write(port: u1, data: []const u8) void {
        const sm: hal.pio.StateMachine = switch (port) {
            0 => .sm0,
            1 => .sm1,
        };
        for (data) |byte| {
            pio.sm_blocking_write(sm, byte);
        }
    }

    /// Writes to the debug port for Core 0 or Core 1, depending on which core is executing.
    fn local_write(msg: []const u8) void {
        write(@truncate(rp2350.peripherals.SIO.CPUID.read().CPUID), msg);
    }
};
