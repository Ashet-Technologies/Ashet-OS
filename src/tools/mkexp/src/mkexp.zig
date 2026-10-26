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

pub fn main(init: std.process.Init) !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var cli = args_parser.parseWithVerbForCurrentProcess(CliOptions, CliVerb, init, .print) catch return 1;
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

            const json_data = try std.Io.Dir.cwd().readFileAlloc(
                init.io,
                cli.positionals[0],
                allocator,
                .limited(1 << 20),
            );

            var image: expcard.EEPROM_Image = .{
                .metadata = try expcard.json.load_metadata(json_data),
                // .icon = .{},
                .firmware = .{ .data = @splat(0x00) },
            };

            if (options.firmware) |firmware_path| {
                var fd = try std.Io.Dir.cwd().openFile(init.io, firmware_path, .{});
                defer fd.close(init.io);
                const stat = try fd.stat(init.io);
                if (stat.size > image.firmware.data.len)
                    return error.FirmwareTooBig;

                var file_reader = fd.reader(init.io, &.{});
                try file_reader.interface.readSliceAll(image.firmware.data[0..stat.size]);

                image.metadata.Properties.@"Has Firmware" = true;
            } else {
                image.metadata.Properties.@"Has Firmware" = false;
            }

            image.metadata.fix_checksum();

            var max_eeprom_image: [16384]u8 = @splat(0xFF);

            const raw_image: []u8 = max_eeprom_image[0..@intFromEnum(cli.options.size)];
            var fbs: std.Io.Writer = .fixed(raw_image);

            try fbs.writeStruct(image, .little);
            std.debug.assert(fbs.end == raw_image.len);

            if (std.mem.eql(u8, options.output, "-")) {
                var stdout_writer = std.Io.File.stdout().writer(init.io, &.{});
                try stdout_writer.interface.writeAll(raw_image);
                try stdout_writer.flush();
            } else {
                try std.Io.Dir.cwd().writeFile(init.io, .{
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
