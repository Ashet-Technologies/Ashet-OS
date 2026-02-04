const std = @import("std");
const logger = std.log.scoped(.p2boot);

const ChunkingWriter = @import("p2boot/ChunkingWriter.zig");

const ashet = @import("../../../../main.zig");
const microzig = @import("microzig");
const rp2350 = @import("rp2350-hal");

const hw_alloc = @import("hw_alloc.zig");

pub fn init() void {
    hw_alloc.pins.prop_txd.set_function(.uart);
    hw_alloc.pins.prop_rxd.set_function(.uart);

    hw_alloc.pins.prop_rst.set_function(.sio);
    hw_alloc.pins.prop_rst.set_direction(.out);

    hw_alloc.uart.propeller2.apply(.{
        .baud_rate = hw_alloc.cfg.propeller2_p2boot_baud,
        .clock_config = hw_alloc.clock_config,
    });
}

pub fn deinit() void {
    hw_alloc.pins.prop_txd.set_function(.disabled);
    hw_alloc.pins.prop_rxd.set_function(.disabled);

    hw_alloc.pins.prop_rst.set_function(.disabled);
}

pub fn reset() !void {
    var buffer: [256]u8 = undefined;

    hw_alloc.pins.prop_rst.put(0); // Put P2 into RESET
    rp2350.time.sleep_ms(50);
    hw_alloc.pins.prop_rst.put(1);
    rp2350.time.sleep_ms(100);

    // Flush buffers
    hw_alloc.uart.propeller2.clear_errors();
    hw_alloc.uart.propeller2.read_blocking(&buffer, .init_relative(rp2350.time.get_time_since_boot(), .from_ms(1))) catch {};

    const reader = hw_alloc.uart.propeller2.reader(.init_relative(rp2350.time.get_time_since_boot(), .from_ms(150)));

    try hw_alloc.uart.propeller2.write_blocking("> Prop_Chk 0 0 0 0\r", .no_deadline);

    // Skip over "\r\n" reply from P2
    try reader.skipUntilDelimiterOrEof('\n');

    var fbs = std.io.fixedBufferStream(&buffer);

    try reader.streamUntilDelimiter(fbs.writer(), '\n', null);

    logger.info("received \"{f}\" from P2", .{std.zig.fmtString(fbs.getWritten())});

    if (!std.mem.eql(u8, fbs.getWritten(), "Prop_Ver G\r")) {
        logger.err("no southbridge detected!", .{});
        return error.BadHandshake;
    }
}

const pll_setup: u32 = 0b0000000_1_000000_0000001110_1111_10_00; // enable crystal+PLL, stay in RCFAST mode
const pll_enable: u32 = 0b0000000_1_000000_0000001110_1111_10_11; // now switch to PLL running at 300.0 MHz

pub fn clock_init() !void {
    try hw_alloc.uart.propeller2.write_blocking(std.fmt.comptimePrint("> Prop_Clk 0 0 0 0 {X:0>8}\r", .{pll_setup}), null);
    rp2350.time.sleep_ms(10);
    try hw_alloc.uart.propeller2.write_blocking(std.fmt.comptimePrint("> Prop_Clk 0 0 0 0 {X:0>8}\r", .{pll_enable}), null);
}

pub fn launch(buffer: []const u8) !void {
    try hw_alloc.uart.propeller2.write_blocking("> Prop_Txt 0 0 0 0 ", .no_deadline);
    {
        var write_buffer: [ChunkingWriter.chunk_size]u8 = undefined;
        var chunk_writer: ChunkingWriter = .init(hw_alloc.uart.propeller2, &write_buffer);

        try std.base64.standard.Encoder.encodeWriter(
            &chunk_writer.writer,
            buffer,
        );

        try chunk_writer.writer.flush();
    }

    try hw_alloc.uart.propeller2.write_blocking(" ?\r", .no_deadline);

    logger.info("await response...", .{});
    const response = try read_word_timeout(hw_alloc.uart.propeller2, rp2350.time.deadline_in_ms(150));
    switch (response) {
        '.' => {},
        '!' => {
            logger.err("invalid checksum!", .{});
            return error.LoadFailed;
        },
        else => {
            logger.err("unexpected response from Prop_Txt: 0x{X:0>8}!", .{response});
            return error.LoadFailed;
        },
    }
}

fn read_word_timeout(uart: rp2350.uart.UART, timeout: microzig.drivers.time.Deadline) rp2350.uart.ReceiveError!u8 {
    while (true) {
        if (try uart.read_word()) |word|
            return word;
        try timeout.check(ashet.time.Instant.now());
    }
}
