const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.@"virtio-input");
const virtio = @import("virtio");

const Host_VNC_Input = @This();
const Driver = ashet.drivers.Driver;

const queue_size = 8;
const eventq = 0;
const statusq = 1;

driver: Driver = .{
    .name = "Host VNC Input",
    .class = .{
        .input = .{
            .pollFn = poll,
        },
    },
},

pub fn init() Host_VNC_Input {
    return .{};
}

fn poll(driver: *Driver) void {
    const device = @fieldParentPtr(Host_VNC_Input, "driver", driver);

    _ = device;
    // ashet.input.pushRawEvent(.{ .keyboard = .{
    //     .scancode = evt.code,
    //     .down = evt.value != 0,
    // } });

    // ashet.input.pushRawEvent(.{ .mouse_motion = .{
    //     .dx = 0,
    //     .dy = @as(i32, @bitCast(evt.value)),
    // } });
}
