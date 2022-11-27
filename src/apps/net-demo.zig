const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
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
