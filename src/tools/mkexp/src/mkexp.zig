const std = @import("std");
const args_parser = @import("args");
const expcard = @import("expcard");

const EEPROM_Size = enum(u32) {
    @"32k" = @divExact(32768, 8),
    @"64k" = @divExact(65536, 8),
    @"128k" = @divExact(131072, 8),
};

const CliOptions = struct {
    help: bool = false,

    size: EEPROM_Size = .@"32k",

    pub const shorthands = .{
        .h = "help",
        .s = "size",
    };
};

const CliVerb = union(enum) {
    encode: struct {
        firmware: ?[]const u8 = null,
        // icon16: ?[]const u8 = null,
        // icon24: ?[]const u8 = null,
        // icon32: ?[]const u8 = null,
        output: []const u8 = "-",

        pub const shorthands = .{
            .o = "output",
            .f = "firmware",
        };
    },
    decode: struct {
        json: bool = false,
        output: []const u8 = "-",

        pub const shorthands = .{
            .b = "json",
            .o = "output",
        };
    },
    @"render-md": struct {},
};

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cli = args_parser.parseWithVerbForCurrentProcess(CliOptions, CliVerb, allocator, .print) catch return 1;
    defer cli.deinit();

    const verb = cli.verb orelse {
        std.debug.print(
            \\{s} [--help] [--size=<size>] <verb>
            \\
            \\Options:
            \\  -h, --help              Prints this help
            \\  -s, --size=32k|64k|128k Selects the size of the EEPROM image used to encode.
            \\
            \\Verbs:
            \\  encode 
            \\      Encodes an EEPROM image from 
            \\
            \\      -f, --firmware <path>   If given, embeds the given firmware binary inside the eeprom.
            \\      -o, --output <path>     If given, renders the output file to <path> instead of stdout.
            \\
            \\  decode
            \\      Decodes an EEPROM image and prints its contents to stdout.
            \\      
            \\      -j, --json              If given, will print the information as a re-encodable JSON file.
            \\      -o, --output <path>     If given, renders the output file to <path> instead of stdout.
            \\
            \\  render-md
            \\      Renders the EEPROM image description as markdown.
            \\
            \\
        , .{
            cli.executable_name orelse "mkexp",
        });
        // TODO: Print usage
        return 1;
    };

    switch (verb) {
        .encode => |options| {
            if (cli.positionals.len != 1)
                return 1;

            const json_data = try std.fs.cwd().readFileAlloc(allocator, cli.positionals[0], 1 << 20);

            var image: expcard.EEPROM_Image = .{
                .metadata = try expcard.json.load_metadata(json_data),
                // .icon = .{},
                .firmware = .{ .data = @splat(0x00) },
            };

            if (options.firmware) |firmware_path| {
                var fd = try std.fs.cwd().openFile(firmware_path, .{});
                defer fd.close();
                const stat = try fd.stat();
                if (stat.size > image.firmware.data.len)
                    return error.FirmwareTooBig;

                try fd.reader().readNoEof(image.firmware.data[0..stat.size]);

                image.metadata.Properties.@"Has Firmware" = true;
            } else {
                image.metadata.Properties.@"Has Firmware" = false;
            }

            image.metadata.fix_checksum();

            var max_eeprom_image: [16384]u8 = @splat(0xFF);

            const raw_image: []u8 = max_eeprom_image[0..@intFromEnum(cli.options.size)];
            var fbs: std.io.FixedBufferStream([]u8) = .{ .buffer = raw_image, .pos = 0 };

            try fbs.writer().writeStructEndian(image, .little);
            std.debug.assert(fbs.pos == raw_image.len);

            if (std.mem.eql(u8, options.output, "-")) {
                try std.io.getStdOut().writeAll(raw_image);
            } else {
                try std.fs.cwd().writeFile(.{
                    .sub_path = options.output,
                    .data = raw_image,
                });
            }

            return 0;
        },

        .decode => @panic("not implemented yet!"),

        .@"render-md" => {
            expcard.dump_type(expcard.MetadataBlock);
            return 0;
        },
    }
}
