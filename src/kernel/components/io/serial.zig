const std = @import("std");
const ashet = @import("../../main.zig");

const SerialPortID = ashet.abi.io.serial.SerialPortID;

pub const SerialPort = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), _internal_destroy);

    system_resource: ashet.resources.SystemResource = .{ .type = .io_serial_serial_port },

    pub const destroy = Destructor.destroy;

    pub fn open(id: SerialPortID) error{}!*SerialPort {
        _ = id;
        @panic("TODO: SerialPort.open");
    }

    fn _internal_destroy(port: *SerialPort) void {
        // TODO: Fix serial port destruction
        ashet.memory.type_pool(SerialPort).free(port);
    }
};

pub fn query_metadata(id: SerialPortID) !void {
    _ = id;
    @panic("TODO: query_metadata");
}
