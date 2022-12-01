const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    // try udp_demo();
    try tcp_demo();
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

    const len = try socket.write("Hello, World!\n");

    try ashet.debug.writer().print("sent {} bytes", .{len});
}

fn udp_demo() !void {
    var socket = try ashet.net.Udp.open();
    defer socket.close();

    try socket.bind(ashet.net.EndPoint.new(
        ashet.net.IP.ipv4(.{ 0, 0, 0, 0 }),
        8000,
    ));

    _ = try socket.sendTo(
        ashet.net.EndPoint.new(
            ashet.net.IP.ipv4(.{ 10, 0, 2, 2 }),
            5555,
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
