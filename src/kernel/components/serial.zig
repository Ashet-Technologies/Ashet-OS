const std = @import("std");
const hal = @import("hal");
const ashet = @import("../main.zig");

pub const SerialPort = struct {
    pub const DeviceError = error{InvalidBlock};
    pub const ReadError = DeviceError || error{};
    pub const WriteError = DeviceError || error{};

    name: []const u8,
    interface: *Interface,

    pub const Interface = struct {
        //
    };
};

pub fn enumerate() SerialPortEnumerator {
    return SerialPortEnumerator{};
}

pub const SerialPortEnumerator = struct {
    index: usize = 0,

    pub fn next(self: *SerialPortEnumerator) ?SerialPort {
        const list = hal.serial.devices;
        if (self.index >= list.len)
            return null;
        const item = list[self.index];
        self.index += 1;
        return item;
    }
};
