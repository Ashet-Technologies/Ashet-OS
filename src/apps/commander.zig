const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() void {
    ashet.video.setMode(.text);
    ashet.console.clear();

    const vmem = ashet.syscalls().video.getVideoMemory();
    for (fake_screenshot) |char, i| {
        const x = i % 64;
        const y = i / 64;

        const lh = x < 32;

        const attribs = if (y == 0)
            @as(u8, 0xF0) // menu bar
        else if (y == 31)
            @as(u8, 0xA0) // bottom bar
        else if (y == 1 and lh)
            @as(u8, 0xF2) // left address bar
        else if (y == 1 and !lh)
            @as(u8, 0xA3) // right address bar
        else if (x == 31 and y > 1 and y < 31)
            @as(u8, 0xFA) // left scroll bar
        else if (x == 63 and y > 1 and y < 31)
            @as(u8, 0xA3) // right scroll bar
        else if (y == 4 and lh)
            @as(u8, 0xF8) // selected item
        else if (!lh)
            @as(u8, 0x3F) // right side font
        else
            @as(u8, 0x0F); // left side font

        vmem[2 * i + 0] = char;
        vmem[2 * i + 1] = attribs;
    }

    while (true) {
        ashet.process.yield();
    }
}

const fake_screenshot = blk: {
    @setEvalBranchQuota(10_000);
    var buffer: [64 * 32]u8 = [1]u8{' '} ** (64 * 32);

    var line: usize = 0;
    var col: usize = 0;
    for (fake_screenshot_src) |char| {
        if (char == '\n') {
            col = 0;
            line += 1;
            continue;
        }
        std.debug.assert(col < 64);
        buffer[64 * line + col] = char;
        col += 1;
    }

    buffer[64 * 2 + 31] = '=';
    buffer[64 * 5 + 63] = '=';

    break :blk buffer;
};

const fake_screenshot_src =
    \\Commander
    \\CF0:/apps/                      USB1:/ashet/shell-utils/        
    \\./                        <DIR> ./                        <DIR>
    \\../                       <DIR> ../                       <DIR>
    \\browser/                  <DIR> code                       1129
    \\commander/                <DIR> 
    \\editor/                   <DIR> 
    \\music/                    <DIR> 
    \\shell/                    <DIR> 
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\
    \\F1 Info F2 Rename F3 Delete F4 Compress F5 Copy F6 Move TAB Swap
;
