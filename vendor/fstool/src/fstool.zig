const std = @import("std");
const args_parser = @import("args");

const CliOptions = struct {
    image: []const u8 = "",
    help: bool = false,

    pub const shorthands = .{
        .i = "image",
        .h = "help",
    };

    pub const meta = .{
        .usage_summary = "",
        .full_text =
        \\
        ,
        .option_docs = .{
            .image = "Which disk image to operate on?",
            .help = "Prints this help",
        },
    };
};

const CliVerb = union(enum) {
    tree: struct {
        //
    },

    put: struct {
        //
    },

    get: struct {
        output: []const u8 = "",

        pub const shorthands = .{
            .o = "output",
        };
    },

    mkdir: struct {
        parents: bool = false,

        pub const shorthands = .{
            .p = "parents",
        };
    },

    rm: struct {
        recursive: bool = false,
        force: bool = false,

        pub const shorthands = .{
            .r = "recursive",
            .f = "force",
        };
    },
};

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = args_parser.parseWithVerbForCurrentProcess(CliOptions, CliVerb, allocator, .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try usage(std.io.getStdOut());
        return 0;
    }

    if (cli.options.image.len == 0) {
        try usage(std.io.getStdOut());
        return 1;
    }

    return 0;
}

fn usage(file: std.fs.File) !void {
    const writer = file.writer();

    try args_parser.printHelp(CliOptions, "fs", writer);
}
