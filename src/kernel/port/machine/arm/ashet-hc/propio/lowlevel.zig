const std = @import("std");
const logger = std.log.scoped(.propio_lowlevel);
const microzig = @import("microzig");
const rp2350 = microzig.hal;

const SpScQueue = @import("../../../../../utils/spsc_queue.zig").SpScQueue;

const hw_alloc = @import("../hw_alloc.zig");

const pio = hw_alloc.pio.propio;

const rx_sm: rp2350.pio.StateMachine = .sm0;
const tx_sm: rp2350.pio.StateMachine = .sm1;

const rxd_pin = hw_alloc.pins.prop_rxd;
const rxf_pin = hw_alloc.pins.prop_rxf;

const txd_pin = hw_alloc.pins.prop_txd;
const txf_pin = hw_alloc.pins.prop_txf;

const rx_dma_chan = hw_alloc.dma.prop_rx;
const tx_dma_chan = hw_alloc.dma.prop_tx;

const pio_clkdiv = @divExact(hw_alloc.clock_config.get_frequency(.clk_sys).?, 3 * hw_alloc.cfg.propeller2_propio_baud);

const RawFrame = [hw_alloc.cfg.propio_buffer_size]u8;

var rxbuf_empty_queue: SpScQueue(*RawFrame, hw_alloc.cfg.propio_buffer_count) = .empty;
var rxbuf_received_queue: SpScQueue([]u8, hw_alloc.cfg.propio_buffer_count) = .empty;

var rxbuf_buffer: [hw_alloc.cfg.propio_buffer_count]RawFrame = undefined;

pub fn init() !void {
    rx_dma_chan.claim() catch @panic("dma channel conflict!");
    tx_dma_chan.claim() catch @panic("dma channel conflict!");

    rxd_pin.set_function(.pio0);
    rxf_pin.set_function(.pio0);

    txd_pin.set_function(.pio0);
    txf_pin.set_function(.pio0);

    // Shift the used pins by 16 (we use pins in the upper range)
    pio.get_regs().GPIOBASE.write(.{ .GPIOBASE = 1 });

    try pio.sm_load_and_start_program(tx_sm, propio_tx_program.get_program_by_name("propio_tx"), .{
        .clkdiv = .{ .int = pio_clkdiv, .frac = 0 }, // 1 MBaud
        .pin_mappings = .{
            .out = .single(txd_pin),
            .set = .single(txd_pin),
            .side_set = .single(txf_pin),
            .in_base = null,
        },
        .exec = .{
            // TODO: attach CTS here: .jmp_pin = @intFromEnum(fr_pin),
        },
        .shift = .{
            .autopull = true,
            .out_shiftdir = .right,

            .join_tx = true,

            .pull_threshold = 8,

            .in_count = 0, // TODO: attach CTS here!
        },
    });

    try pio.sm_load_and_start_program(rx_sm, propio_rx_program.get_program_by_name("propio_rx"), .{
        .clkdiv = .{ .int = pio_clkdiv, .frac = 0 }, // 1 MBaud
        .pin_mappings = .{
            .in_base = rxd_pin,
        },
        .exec = .{
            .jmp_pin = rxf_pin,
        },
        .shift = .{
            .autopush = true,
            .in_shiftdir = .right,

            .join_rx = true,

            .push_threshold = 8,

            .in_count = 1, // "PINS" only yields RX pin
        },
    });

    try pio.sm_set_pin(tx_sm, txf_pin, 1, 1);
    try pio.sm_set_pin(tx_sm, txd_pin, 1, 1);

    try pio.sm_set_pindir(tx_sm, txf_pin, 1, .out);
    try pio.sm_set_pindir(tx_sm, txd_pin, 1, .out);

    pio.get_regs().IRQ.write(.{ .IRQ = 0xFF });
    pio.get_irq_regs(.irq0).enable.write(.{
        .SM0_RXNEMPTY = 0,
        .SM1_RXNEMPTY = 0,
        .SM2_RXNEMPTY = 0,
        .SM3_RXNEMPTY = 0,
        .SM0_TXNFULL = 0,
        .SM1_TXNFULL = 0,
        .SM2_TXNFULL = 0,
        .SM3_TXNFULL = 0,
        .SM0 = 1,
        .SM1 = 0,
        .SM2 = 0,
        .SM3 = 0,
        .SM4 = 0,
        .SM5 = 0,
        .SM6 = 0,
        .SM7 = 0,
    });

    tx_dma_chan.set_irq0_enabled(true);

    // fill the receive buffer queue for the interrupt:
    for (&rxbuf_buffer) |*buffer| {
        _ = rxbuf_empty_queue.enqueue(buffer);
    }

    rx_dma_chan.setup_transfer_raw(
        0, // we'll set that later!
        @intFromPtr(get_sub_word(pio.sm_get_rx_fifo(rx_sm), 3)),
        hw_alloc.cfg.propio_buffer_size,
        .{
            .data_size = .size_8,
            .dreq = switch (rx_sm) {
                .sm0 => .pio0_rx0,
                .sm1 => .pio0_rx1,
                .sm2 => .pio0_rx2,
                .sm3 => .pio0_rx3,
            },
            .enable = true,
            .read_increment = false,
            .write_increment = true,
            .trigger = false,
        },
    );

    prime_next_dma_transfer();

    pio.sm_set_enabled(rx_sm, true);
    pio.sm_set_enabled(tx_sm, true);

    hw_alloc.irq.propio_dma.set_priority(.lowest);
    hw_alloc.irq.propio_pio.set_priority(.lowest);

    hw_alloc.irq.propio_dma.set_handler(dma_tx_frame_end);
    hw_alloc.irq.propio_pio.set_handler(pio_rx_frame_end);

    hw_alloc.irq.propio_pio.enable();
    hw_alloc.irq.propio_dma.enable();
}

/// Fetches a single frame if available from the receive queue.
/// Return value MUST be returned to `return_frame_raw` as soon as possible.
pub fn get_available_frame_raw() ?[]u8 {
    return rxbuf_received_queue.dequeue();
}

/// Returns a frame into the buffer queue.
pub fn return_frame_raw(frame: []u8) void {
    std.debug.assert(frame.len > 0 and frame.len <= hw_alloc.cfg.propio_buffer_size);

    // can't fail as the queues can't yield more than queue capacity buffers.
    std.debug.assert(rxbuf_empty_queue.enqueue(@ptrCast(frame.ptr)));
}

/// Writes a single frame blockingly into the device.
///
/// Must not have a DMA transfer active at the same time!
pub fn writev_frame_blocking(slices: []const []const u8) void {
    const Vec = microzig.utilities.SliceVector([]const u8);
    const vec = Vec.init(slices);
    const total_len = vec.size();

    pio.sm_blocking_write(tx_sm, total_len - 1);

    var iter = vec.iterator();
    while (iter.next_chunk(null)) |chunk| {
        for (chunk) |item| {
            pio.sm_blocking_write(tx_sm, item);
        }
    }
}

// /// Writes a single frame blockingly into the device.
// ///
// /// Must not have a DMA transfer active at the same time!
// pub fn writev_frame_blocking(slices: []const []const u8) void {
//     const Vec = microzig.utilities.Slice_Vector([]const u8);
//     const vec = Vec.init(slices);
//     const total_len = vec.size();

//     tx_dma_chan.wait_for_finish_blocking();

//     pio.sm_blocking_write(tx_sm, total_len - 1);

//     var iter = vec.iterator();
//     while (iter.next_chunk(null)) |chunk| {
//         tx_dma_chan.setup_transfer_raw(
//             @intFromPtr(get_sub_word(pio.sm_get_tx_fifo(tx_sm), 0)),
//             @intFromPtr(chunk.ptr),
//             chunk.len,
//             .{
//                 .data_size = .size_8,
//                 .dreq = .pio0_tx1,
//                 .enable = true,
//                 .read_increment = true,
//                 .write_increment = false,
//                 .trigger = true,
//             },
//         );
//         tx_dma_chan.wait_for_finish_blocking();
//     }
// }

var current_dma_buffer: *RawFrame = undefined;

fn prime_next_dma_transfer() void {
    comptime std.debug.assert(hw_alloc.dma.prop_rx == rp2350.dma.channel(2));

    const next_buffer = rxbuf_empty_queue.dequeue() orelse @panic("propio buffer queue underrun.");
    std.debug.assert(next_buffer.len == hw_alloc.cfg.propio_buffer_size);
    current_dma_buffer = next_buffer;
    microzig.chip.peripherals.DMA.CH2_AL2_WRITE_ADDR_TRIG.raw = @intFromPtr(current_dma_buffer);
}

fn pio_rx_frame_end() callconv(.c) void {
    comptime std.debug.assert(hw_alloc.dma.prop_rx == rp2350.dma.channel(2));

    const count = current_dma_buffer.len - microzig.chip.peripherals.DMA.CH2_TRANS_COUNT.read().COUNT;

    logger.debug("end of frame after {} transfers: \"{X}\"", .{
        count,
        current_dma_buffer[0..count],
    });

    if (count > 0) {
        if (!rxbuf_received_queue.enqueue(current_dma_buffer[0..count]))
            @panic("propio buffer queue overrun");
    }

    microzig.chip.peripherals.DMA.CHAN_ABORT.write(.{ .CHAN_ABORT = (1 << @intFromEnum(rx_dma_chan)) });
    while (microzig.chip.peripherals.DMA.CHAN_ABORT.read().CHAN_ABORT != 0) {
        asm volatile ("" ::: .{ .memory = true });
    }

    pio.get_regs().IRQ.raw = 0x01; // acknowledge

    prime_next_dma_transfer();
}

fn dma_tx_frame_end() callconv(.c) void {
    tx_dma_chan.acknowledge_irq0();
    logger.debug("DMA done.", .{});
}

const propio_rx_program = blk: {
    @setEvalBranchQuota(20_000);
    break :blk rp2350.pio.assemble(
        \\
        \\.program propio_rx
        \\
        \\wait_for_frame:
        \\  wait 0 jmppin 0
        \\  irq set 1
        \\
        \\.wrap_target
        \\  set  x, 7               ; setup loop counter
        \\  wait 0 pin 0            ; wait for start bit
        \\  nop               [2]   ; delay 3 clocks to get into the center of the first bit
        \\rcv_bit:
        \\  in   pins, 1
        \\  jmp  x-- rcv_bit [1]     ; delay 2 clocks to keep in sync with the baud rate
        \\  jmp pin end_of_frame
        \\.wrap
        \\
        \\end_of_frame:
        \\  irq set 0
        \\  jmp wait_for_frame
        \\
    , .{});
};

const propio_tx_program = blk: {
    @setEvalBranchQuota(20_000);
    break :blk rp2350.pio.assemble(
        \\.program propio_tx
        \\.side_set 1
        \\
        \\.wrap_target
        \\wait_for_data:
        \\  set pins, 1         side 1
        \\  out y,   32         side 1      ; fetch length counter
        \\  nop                 side 0 [10] ; delay before sending off the first byte to let the receiver settle
        \\
        \\send_loop:
        \\  pull block          side 0      ;   wait until we have data in the OSR
        \\  set pins, 0         side 0      ; 0 send start bit
        \\  set x, 7            side 0 [1]  ; 2
        \\bitloop:
        \\  out pins, 1         side 0      ; send data bits
        \\  jmp x-- bitloop     side 0 [1]  ; 
        \\  set pins, 1         side 0 [1]  ; send stop bits
        \\  
        \\  jmp y-- send_loop   side 0      ; check if we have still bytes to send
        \\  nop                 side 0 [10] ; at the end, also keep the frame active a bit for the receiver
        \\.wrap
        \\
    , .{});
};

fn get_sub_word(ptr: *volatile u32, comptime i: u2) *volatile u8 {
    const grp: [*]volatile u8 = @ptrCast(ptr);
    return &grp[i];
}
