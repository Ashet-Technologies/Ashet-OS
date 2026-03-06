const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ashet_input);
const machine = ashet.machine.peripherals;

const Ashet_Input = @This();
const Driver = ashet.drivers.Driver;

const queue_size = 8;
const eventq = 0;
const statusq = 1;

driver: Driver = .{
    .name = "Ashet Input",
    .class = .{
        .input = .{
            .pollFn = poll,
        },
    },
},

mouse: *volatile machine.Mouse,
keyboard: *volatile machine.Keyboard,

last_mouse: machine.Mouse = .{
    .x = 0,
    .y = 0,
    .buttons = .{ .left = false, .middle = false, .right = false },
},

pub fn init(
    mouse: *volatile machine.Mouse,
    keyboard: *volatile machine.Keyboard,
) Ashet_Input {
    return .{
        .mouse = mouse,
        .keyboard = keyboard,
    };
}

fn poll(driver: *Driver) void {
    const device: *Ashet_Input = @fieldParentPtr("driver", driver);

    while (device.keyboard.status.ready) {
        const event = device.keyboard.data;

        ashet.input.push_raw_event(.{ .keyboard = .{
            .usage = @enumFromInt(event.usage_code),
            .down = event.key_down,
        } });
    }

    {
        const last = device.last_mouse;
        const current = device.mouse.*;

        if (current.x != last.x or current.y != last.y) {
            ashet.input.push_raw_event(.{ .mouse_abs_motion = .{
                .x = @intCast(@min(current.x, std.math.maxInt(i16))),
                .y = @intCast(@min(current.y, std.math.maxInt(i16))),
            } });
        }

        inline for (.{ "left", "right", "middle" }) |button_name| {
            if (@field(current.buttons, button_name) != @field(last.buttons, button_name)) {
                ashet.input.push_raw_event(.{ .mouse_button = .{
                    .button = @field(ashet.abi.MouseButton, button_name),
                    .down = @field(current.buttons, button_name),
                } });
            }
        }
    }
}
