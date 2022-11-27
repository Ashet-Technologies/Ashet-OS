const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

const ColorIndex = ashet.abi.ColorIndex;

pub fn main() void {
    if (!ashet.video.acquire()) {
        ashet.process.exit(1);
    }

    ashet.video.setResolution(400, 300);
    ashet.video.setBorder(ColorIndex.get(2));

    render();

    while (true) {
        if (ashet.input.getEvent()) |event| {
            switch (event) {
                .mouse => |data| std.log.info("mouse => {}", .{data}),
                .keyboard => |data| {
                    if (data.pressed and data.key == .escape)
                        return;
                    std.log.info("keyboard: pressed={}, alt={}, shift={}, ctrl={}, altgr={}, scancode={d: >3}, key={s: <10}, text='{?s}'", .{
                        @boolToInt(data.pressed),
                        @boolToInt(data.modifiers.alt),
                        @boolToInt(data.modifiers.shift),
                        @boolToInt(data.modifiers.ctrl),
                        @boolToInt(data.modifiers.alt_graph),
                        data.scancode,
                        @tagName(data.key),
                        data.text,
                    });
                },
            }
        }

        ashet.process.yield();
    }
}

var clonebuffer: [400 * 300]ColorIndex = undefined;

fn render() void {
    std.mem.set(ColorIndex, &clonebuffer, ColorIndex.get(0));
    //

    //
    std.mem.copy(ColorIndex, ashet.video.getVideoMemory()[0..clonebuffer.len], &clonebuffer);
}
