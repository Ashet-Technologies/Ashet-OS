const std = @import("std");

pub const Parity = enum(u3) {
    none = 0b000,
    odd = 0b001,
    even = 0b011,
    mark = 0b101,
    space = 0b111,
};

pub const DataBits = enum(u2) {
    five = 0b00,
    six = 0b01,
    seven = 0b10,
    eight = 0b11,
};

pub const StopBits = enum(u1) {
    one = 0,
    two = 1,
};

pub fn NS16C550(comptime IO: type) type {
    return struct {
        const Port = @This();

        io: IO,

        pub fn init(io: IO) Port {
            return .{
                .io = io,
            };
        }

        fn out(port: Port, reg: Register, value: u8) void {
            port.io.write(reg, value);
        }

        fn in(port: Port, reg: Register) u8 {
            return port.io.read(reg);
        }

        pub fn configure(port: Port, baud_rate: u32, data_bits: DataBits, parity: Parity, stop_bits: StopBits) void {
            const divisor: u16 = @intCast(115_200 / baud_rate);

            var divisor_bits: [2]u8 = undefined;
            std.mem.writeInt(u16, &divisor_bits, divisor, .Little);

            // disable interrupts
            port.out(.ier_divh, 0x00);

            // set DLAB, disable everything else
            port.out(.lcr, @bitCast(LCR{
                .data_bits = @enumFromInt(0),
                .stop_bits = @enumFromInt(0),
                .parity = @enumFromInt(0),
                .break_control = false,
                .divisor_latch_access = true,
            }));

            // Set divisor:
            port.out(.data_divl, divisor_bits[0]);
            port.out(.ier_divh, divisor_bits[1]);

            // Configure port
            port.out(.lcr, @bitCast(LCR{
                .parity = parity,
                .data_bits = data_bits,
                .stop_bits = stop_bits,
                .break_control = false,
                .divisor_latch_access = false,
            }));

            // Finalize initialization
            port.out(.iir_fcr, @bitCast(FCR{
                .fifo_enable = true,
                .rx_fifo = .clear,
                .tx_fifo = .clear,
                .dma = .disabled,
                .receiver_trigger = .fourteen,
            }));
            port.out(.mcr, @bitCast(MCR{
                .dtr = true,
                .rts = true,
                .out1 = false,
                .out2 = true,
                .loopback = false,
                .auto_flow_control = false,
            }));
        }

        fn get_lsr(port: Port) LSR {
            return @bitCast(port.in(.lsr));
        }

        pub fn can_write(port: Port) bool {
            return port.get_lsr().transmit_holding_register == .empty;
        }

        pub fn write_byte(port: Port, value: u8) void {
            while (!port.can_write()) {
                // TODO: Add timeout here
            }
            port.out(.data_divl, value);
        }

        pub fn can_read(port: Port) bool {
            return port.get_lsr().data_ready;
        }

        pub fn read_byte(port: Port) u8 {
            while (!port.can_read()) {
                // TODO: Add timeout here
            }
            return port.in(.data_divl);
        }
    };
}

const LCR = packed struct(u8) {
    data_bits: DataBits,
    stop_bits: StopBits,
    parity: Parity,
    break_control: bool,
    divisor_latch_access: bool,
};

const FCR = packed struct(u8) {
    fifo_enable: bool,
    rx_fifo: enum(u1) { keep = 0, clear = 1 },
    tx_fifo: enum(u1) { keep = 0, clear = 1 },
    dma: enum(u1) { disabled = 0, enabled = 1 },
    _reserved: u2 = 0,
    receiver_trigger: enum(u2) {
        one = 0b00,
        four = 0b01,
        eight = 0b10,
        fourteen = 0b11,
    },
};

const MCR = packed struct(u8) {
    dtr: bool,
    rts: bool,
    out1: bool,
    out2: bool,
    loopback: bool,
    auto_flow_control: bool,
    _reserved: u2 = 0,
};

const LSR = packed struct(u8) {
    data_ready: bool,
    overrun_error: bool,
    parity_error: bool,
    framing_error: bool,
    break_interrupt: bool,
    transmit_holding_register: enum(u1) { full = 0, empty = 1 },
    transmitter: enum(u1) { busy = 1, idle = 0 },
    rx_fifo_error: bool,
};

pub const Register = enum(u3) {
    data_divl = 0,
    ier_divh = 1,
    iir_fcr = 2,
    lcr = 3,
    mcr = 4,
    lsr = 5,
    msr = 6,
};
