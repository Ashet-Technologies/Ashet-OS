const std = @import("std");
const agp = @import("agp");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var rand_engine = std.rand.DefaultPrng.init(0x1337);
    const rng = rand_engine.random();

    const rand_buffer = try arena.allocator().alloc(u8, 8192);
    rng.bytes(rand_buffer);

    const input_cmd_stream = try arena.allocator().alloc(agp.Command, 1024);
    for (input_cmd_stream) |*item| {
        item.* = rand_cmd(rng, rand_buffer);
    }

    const encoded_cmd_stream = blk: {
        var stream = std.ArrayList(u8).init(arena.allocator());
        defer stream.deinit();

        var encoder = agp.encoder(stream.writer());

        for (input_cmd_stream) |cmd| {
            try encoder.encode(cmd);
        }

        break :blk try stream.toOwnedSlice();
    };

    std.debug.print("encoded {} commands into {} bytes of data\n", .{
        input_cmd_stream.len,
        encoded_cmd_stream.len,
    });

    const output_cmd_stream = try arena.allocator().alloc(agp.Command, input_cmd_stream.len);

    {
        var fbs = std.io.fixedBufferStream(encoded_cmd_stream);
        var decoder = agp.decoder(fbs.reader());
        for (output_cmd_stream) |*cmd| {
            cmd.* = if (try decoder.next()) |in|
                in
            else
                @panic("decoder yielded none for expected cmd!");
        }
        std.debug.assert(fbs.pos == encoded_cmd_stream.len);
        std.debug.assert(try decoder.next() == null);
    }

    for (input_cmd_stream, output_cmd_stream) |expected, actual| {
        try std.testing.expectEqual(expected, actual);
    }
}

fn rand_cmd(rng: std.rand.Random, buffer_range: []const u8) agp.Command {
    const cmd_id = rng.enumValue(agp.CommandByte);
    switch (cmd_id) {
        inline else => |tag| {
            const Cmd = agp.Command.type_map.get(tag);

            var cmd: Cmd = undefined;

            inline for (std.meta.fields(Cmd)) |fld| {
                @field(cmd, fld.name) = switch (fld.type) {
                    []const u8 => blk: {
                        const start = rng.intRangeLessThan(usize, 0, buffer_range.len);
                        const end = rng.intRangeLessThan(usize, start, buffer_range.len);
                        break :blk buffer_range[start..end];
                    },

                    agp.ColorIndex => @enumFromInt(rng.int(u8)),
                    agp.Font => @ptrFromInt(rng.int(usize)),
                    agp.Framebuffer => @ptrFromInt(rng.int(usize)),
                    agp.Bitmap => @ptrFromInt(rng.int(usize)),

                    else => rng.int(fld.type),
                };
            }

            return @unionInit(agp.Command, @tagName(tag), cmd);
        },
    }
}
