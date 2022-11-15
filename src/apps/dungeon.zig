const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() void {
    ashet.video.setResolution(400, 300);
    ashet.video.setMode(.graphics);
    ashet.video.setBorder(2);

    render();

    while (true) {
        if (ashet.input.getEvent()) |event| {
            switch (event) {
                .mouse => |data| std.log.info("mouse => {}", .{data}),
                .keyboard => |data| std.log.info("keyboard: pressed={}, alt={}, shift={}, ctrl={}, altgr={}, scancode={d: >3}, key={s: <10}, text='{?s}'", .{
                    @boolToInt(data.pressed),
                    @boolToInt(data.modifiers.alt),
                    @boolToInt(data.modifiers.shift),
                    @boolToInt(data.modifiers.ctrl),
                    @boolToInt(data.modifiers.alt_graph),
                    data.scancode,
                    @tagName(data.key),
                    data.text,
                }),
            }
        }

        ashet.process.yield();
    }
}

var clonebuffer: [400 * 300]u8 = undefined;

fn render() void {
    std.mem.set(u8, &clonebuffer, 0);
    //

    //
    std.mem.copy(u8, ashet.video.getVideoMemory()[0..clonebuffer.len], &clonebuffer);
}
