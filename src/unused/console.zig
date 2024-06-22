const std = @import("std");
const ashet = @import("main.zig");
const TextEditor = @import("text-editor");

pub const Location = struct {
    x: u8,
    y: u8,
};

/// Width of the text console
pub const width = 64;

/// Height of the text console
pub const height = 32;

/// Current foreground color for newly characters
pub var fg: u4 = 0x00; // black

/// Current background color for newly characters
pub var bg: u4 = 0x0F; // white

pub var cursor: Location = .{ .x = 0, .y = 0 };

pub const attributes = ashet.abi.charAttributes;

fn memory() []align(4) u8 {
    return ashet.video.getVideoMemory()[0 .. width * height * 2];
}

/// Sets a single character on the screen.
pub fn set(x: u8, y: u8, char: u8, attrs: u8) void {
    memory()[charOffset(x, y)] = char;
    memory()[attrOffset(x, y)] = attrs;
}

pub fn clear() void {
    cursor = .{ .x = 0, .y = 0 };
    std.mem.set(
        u16,
        std.mem.bytesAsSlice(u16, memory()),
        ' ' | (@as(u16, attributes(fg, bg)) << 8),
    );
}

pub fn write(string: []const u8) void {
    for (string) |char| {
        put(char);
    }
}

pub fn put(char: u8) void {
    switch (char) {
        '\r' => cursor.x = 0,
        '\n' => newline(),
        else => putRaw(char),
    }
}

pub fn putRaw(char: u8) void {
    memory()[charOffset(cursor.x, cursor.y)] = char;
    memory()[attrOffset(cursor.x, cursor.y)] = attributes(fg, bg);

    cursor.x += 1;
    if (cursor.x >= width) {
        cursor.x = 0;
        newline();
    }
}

fn newline() void {
    cursor.y += 1;
    if (cursor.y >= height) {
        cursor.y -= 1;

        std.mem.copyForwards(
            u8,
            memory()[0..],
            memory()[charOffset(0, 1)..charOffset(0, height)],
        );
        for (std.mem.bytesAsSlice(u16, memory()[charOffset(0, height - 1)..charOffset(0, height)])) |*c| {
            c.* = ' ' | (@as(u16, attributes(fg, bg)) << 8);
        }
    }
}

fn charOffset(x: u8, y: u8) usize {
    return 2 * (@as(usize, y) * width + @as(usize, x));
}

fn attrOffset(x: u8, y: u8) usize {
    return charOffset(x, y) + 1;
}

fn writeForWriter(_: void, string: []const u8) WriteError!usize {
    write(string);
    return string.len;
}

const WriteError = error{};

pub const Writer = std.io.Writer(void, WriteError, writeForWriter);

pub fn writer() Writer {
    return Writer{ .context = {} };
}

pub fn output(string: []const u8) void {
    for (string) |c| {
        putRaw(c);
    }
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    writer().print(fmt, args) catch unreachable;
}

// pub fn readLine(buffer: []u8, width: u16) error{Failure}!?[]u8 {
//     var params = abi.ReadLineParams{
//         .buffer = buffer.ptr,
//         .buffer_len = buffer.len,
//         .width = width,
//     };

//     return switch (syscalls().console.readLine(&params)) {
//         .ok => buffer[0..params.buffer_len],
//         .cancelled => null,
//         .failed => error.Failure,
//     };
// }

fn fetchOrSpace(str: []const u8, index: usize) u8 {
    return if (index < str.len)
        str[index]
    else
        ' ';
}

pub fn readLine(buffer: []u8, limit: usize) error{ NoSpaceLeft, Cancelled, OutOfMemory, InvalidUtf8 }![]u8 {
    const max_len = @min(buffer.len, width - cursor.x);
    if (max_len < limit)
        return error.NoSpaceLeft;

    var fba = std.heap.FixedBufferAllocator.init(buffer);

    var editor = try TextEditor.init(fba.allocator(), "");
    defer editor.deinit();

    errdefer {
        const display_range = memory()[charOffset(cursor.x, cursor.y)..][0 .. 2 * limit];
        for (display_range, 0..) |*c, i| {
            c.* = if (i % 2 == 0)
                ' '
            else
                @as(u8, 0x0F);
        }
    }

    main_loop: while (true) {
        const display_range = memory()[charOffset(cursor.x, cursor.y)..][0 .. 2 * limit];
        for (display_range, 0..) |*c, i| {
            c.* = if (i % 2 == 0)
                fetchOrSpace(editor.getText(), i / 2)
            else if (i / 2 == editor.cursor)
                @as(u8, 0xF0)
            else
                @as(u8, 0xF2);
        }

        while (ashet.input.getKeyboardEvent()) |event| {
            if (!event.pressed)
                continue;
            switch (event.key) {
                // we can safely return the text pointer here as we
                // use a fixed buffer allocator to receive the contents
                .@"return" => break :main_loop,

                .escape => return error.Cancelled,

                .left => if (event.modifiers.ctrl)
                    editor.moveCursor(.left, .word)
                else
                    editor.moveCursor(.left, .letter),

                .right => if (event.modifiers.ctrl)
                    editor.moveCursor(.right, .word)
                else
                    editor.moveCursor(.right, .letter),

                .home => editor.moveCursor(.left, .line),
                .end => editor.moveCursor(.right, .line),

                .backspace => if (event.modifiers.ctrl)
                    editor.delete(.left, .word)
                else
                    editor.delete(.left, .letter),

                .delete => if (event.modifiers.ctrl)
                    editor.delete(.right, .word)
                else
                    editor.delete(.right, .letter),

                else => if (event.text) |text_ptr| {
                    const text = std.mem.sliceTo(text_ptr, 0);
                    try editor.insertText(text);
                },
            }
        }

        ashet.process.yield();
    }

    {
        const display_range = memory()[charOffset(cursor.x, cursor.y)..][0 .. 2 * limit];
        for (display_range, 0..) |*c, i| {
            c.* = if (i % 2 == 0)
                fetchOrSpace(editor.getText(), i / 2)
            else
                @as(u8, 0x0F);
        }
    }

    const res_buf = editor.bytes.toOwnedSlice();

    if (res_buf.len == 0) {
        return buffer[0..0];
    } else {

        // we want this to actually be true.
        // Let's just hope that the FixedBufferAllocator does it's job
        std.debug.assert(res_buf.ptr == buffer.ptr);

        return res_buf;
    }
}
