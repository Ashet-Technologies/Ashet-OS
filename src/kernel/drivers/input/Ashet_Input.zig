const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ashet_input);
const machine = ashet.machine.peripherals;

const Ashet_Input = @This();
const Driver = ashet.drivers.Driver;
const InputEventDevice = machine.InputEventDevice;

driver: Driver = .{
    .name = "Ashet Input",
    .class = .{
        .input = .{
            .pollFn = poll,
        },
    },
},

keyboard: *volatile InputEventDevice,
mouse: *volatile InputEventDevice,

pub fn init(
    keyboard: *volatile InputEventDevice,
    mouse: *volatile InputEventDevice,
) Ashet_Input {
    return .{
        .keyboard = keyboard,
        .mouse = mouse,
    };
}

fn poll(driver: *Driver) void {
    const device: *Ashet_Input = @fieldParentPtr("driver", driver);

    // Drain keyboard FIFO
    while (device.keyboard.status.ready) {
        const raw = device.keyboard.data;
        const event: InputEventDevice.KeyboardEvent = @bitCast(raw);

        ashet.input.push_raw_event(.{ .keyboard = .{
            .usage = @enumFromInt(event.usage_code),
            .down = event.key_down,
        } });
    }

    // Drain mouse FIFO
    while (device.mouse.status.ready) {
        const raw = device.mouse.data;
        const event: InputEventDevice.MouseEvent = @bitCast(raw);

        switch (event.event_type) {
            .pointing => {
                const pos = event.asPointing();
                ashet.input.push_raw_event(.{ .mouse_abs_motion = .{
                    .x = @intCast(pos.x),
                    .y = @intCast(pos.y),
                } });
            },
            .button_down => {
                const button = event.asButton();
                ashet.input.push_raw_event(.{ .mouse_button = .{
                    .button = switch (button) {
                        .left => ashet.abi.MouseButton.left,
                        .right => ashet.abi.MouseButton.right,
                        .middle => ashet.abi.MouseButton.middle,
                    },
                    .down = true,
                } });
            },
            .button_up => {
                const button = event.asButton();
                ashet.input.push_raw_event(.{ .mouse_button = .{
                    .button = switch (button) {
                        .left => ashet.abi.MouseButton.left,
                        .right => ashet.abi.MouseButton.right,
                        .middle => ashet.abi.MouseButton.middle,
                    },
                    .down = false,
                } });
            },
        }
    }
}
