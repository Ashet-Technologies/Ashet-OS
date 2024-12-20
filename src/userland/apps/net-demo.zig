const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    try tcp_demo();
    try udp_demo();
}

fn tcp_demo() !void {
    var socket = try ashet.net.Tcp.open();
    defer socket.close();

    const actual = try socket.bind(ashet.net.EndPoint.new(
        ashet.net.IP.ipv4(.{ 0, 0, 0, 0 }),
        0,
    ));

    try ashet.debug.writer().print("bound socket to: {}\r\n", .{actual});

    try socket.connect(ashet.net.EndPoint.new(
        ashet.net.IP.ipv4(.{ 10, 0, 2, 2 }),
        4567,
    ));

    ashet.debug.write("Connected.\r\n");

    const writer = socket.writer();
    const reader = socket.reader();

    try writer.writeAll("Welcome to the Ashet Interactive Remote Shell (AIRS). Enter your request:\n");

    var buffered_reader = std.io.bufferedReader(reader);

    // try writer.writeAll(&lolwtfbiggy);

    while (true) {
        var line_buf: [512]u8 = undefined;

        const line = (try buffered_reader.reader().readUntilDelimiterOrEof(&line_buf, '\n')) orelse break;

        try writer.print("You said: {s}\n", .{line});

        ashet.process.yield();
    }

    ashet.debug.write("the server has closed the connection\n");
}

const lolwtfbiggy = [1]u8{'?'} ** 128_000;

fn udp_demo() !void {
    var socket = try ashet.net.Udp.open();
    defer socket.close();

    _ = try socket.bind(ashet.net.EndPoint.new(
        ashet.net.IP.ipv4(.{ 0, 0, 0, 0 }),
        8000,
    ));

    _ = try socket.sendTo(
        ashet.net.EndPoint.new(
            ashet.net.IP.ipv4(.{ 10, 0, 2, 2 }),
            4567,
        ),
        "Hello, World!\n",
    );

    while (true) {
        var buf: [256]u8 = undefined;
        var ep: ashet.net.EndPoint = undefined;
        const len = try socket.receiveFrom(&ep, &buf);
        if (len > 0) {
            std.log.info("received {s} from {}", .{ buf[0..len], ep });
        }
        ashet.process.yield();
    }
}
