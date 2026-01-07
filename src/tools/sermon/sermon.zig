const std = @import("std");
const builtin = @import("builtin");
const arg_parser = @import("args");
const serial = @import("serial");

const CliArguments = struct {
    help: bool = false,

    baud: u32 = 115200,
    parity: serial.Parity = .none,
    @"stop-bits": serial.StopBits = .one,
    @"word-size": serial.WordSize = .eight,
    handshake: serial.Handshake = .none,

    pub const shorthands = .{
        .h = "help",
        .b = "baud",
        .p = "parity",
        .s = "stop-bits",
        .d = "word-size",
        .f = "handshake",
    };

    pub const meta = .{};
};

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const cli = arg_parser.parseForCurrentProcess(CliArguments, allocator, .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try print_help(cli.executable_name, std.io.getStdOut());
        return 0;
    }

    const port_path = switch (cli.positionals.len) {
        0 => {
            try print_help(cli.executable_name, std.io.getStdErr());
            return 1;
        },

        1 => cli.positionals[0],

        else => {
            return usage_error("expects only a single positional argument", .{});
        },
    };

    const output = std.io.getStdOut();
    const stderr = std.io.getStdErr();

    const output_cfg = try IoOptions.configureOutputUncooked(output);
    defer output_cfg.restore(output) catch |err| std.log.err("failed to restore terminal settings for stdout: {s}. Try resetting/restarting your terminal!", .{@errorName(err)});

    // TODO: Add signal handler to allow graceful shutdown here.

    var any_run_ok = false;
    var reconnect_msg_printed = false;
    var any_run_executed = false;

    var spinner: Spinner = .ascii;

    while (true) {
        const stream_result = stream_port(output, any_run_executed, port_path, .{
            .baud_rate = cli.options.baud,
            .parity = cli.options.parity,
            .stop_bits = cli.options.@"stop-bits",
            .word_size = cli.options.@"word-size",
            .handshake = cli.options.handshake,
        });

        // Unconditionally reset any modifications done to graphics of the terminal:
        try output.writeAll("\x1B[0m");

        any_run_executed = true;
        if (stream_result) |_| {
            // ok
            any_run_ok = true;
            reconnect_msg_printed = false;
            try stderr.writeAll("<<disconnected>>\r\n");
        } else |err| {
            switch (err) {
                error.FileNotFound => {
                    if (!any_run_ok and !reconnect_msg_printed) {
                        try std.io.getStdErr().writer().print("waiting for {s}...\r\n", .{
                            port_path,
                        });
                        reconnect_msg_printed = true;
                    }
                    try output.writer().print("\r{s}\r", .{
                        spinner.next(),
                    });
                },

                else => |e| {
                    try output.writeAll("\n");
                    try std.io.getStdErr().writer().print("failed to stream data from {s}: {s}\r\n", .{
                        port_path,
                        @errorName(e),
                    });
                    return 1;
                },
            }
        }

        std.time.sleep(100 * std.time.ns_per_ms);
    }

    comptime unreachable;
}

const Spinner = struct {
    pub const ascii: Spinner = .{
        .animation = &.{
            "|",
            "/",
            "-",
            "\\",
        },
    };

    pos: usize = 0,
    animation: []const []const u8,

    pub fn next(spinner: *Spinner) []const u8 {
        const out = spinner.animation[spinner.pos];
        spinner.pos = @mod(spinner.pos + 1, spinner.animation.len);
        return out;
    }
};

fn stream_port(output: std.fs.File, print_connect_msg: bool, port_path: []const u8, config: serial.SerialConfig) !void {
    const port = try std.fs.cwd().openFile(port_path, .{ .mode = .read_only });
    defer port.close();

    try serial.flushSerialPort(port, .both);

    try serial.configureSerialPort(port, config);

    if (print_connect_msg) {
        try output.writeAll("\r<<connected>>\r\n");
    }

    var last_was_lf = true; // the last line was properly terminated by our application
    while (true) {
        var buffer: [1024]u8 = undefined;

        const count = try port.read(&buffer);
        if (count == 0) {
            // end of file
            break;
        }

        const chunk = buffer[0..count];

        try output.writeAll(chunk);

        last_was_lf = std.mem.endsWith(u8, chunk, "\n");
    }

    if (!last_was_lf) {
        try output.writeAll("\r\n");
    }
}

fn usage_error(comptime fmt: []const u8, args: anytype) u8 {
    std.io.getStdErr().writer().print("usage error: " ++ fmt ++ "\n", args) catch {};
    return 1;
}

fn print_help(exe_name: ?[]const u8, stream: std.fs.File) !void {
    try arg_parser.printHelp(CliArguments, exe_name orelse "sermon", stream.writer());
}

const IoOptions = switch (builtin.os.tag) {
    .windows => struct {
        // https://learn.microsoft.com/en-us/windows/console/getconsolemode

        const DWORD = std.os.windows.DWORD;
        const kernel32 = std.os.windows.kernel32;

        const ENABLE_PROCESSED_OUTPUT = 0x0001;
        const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

        restore_mode: ?DWORD,

        fn configureOutputUncooked(file: std.fs.File) !IoOptions {
            var mode: DWORD = 0;
            if (kernel32.GetConsoleMode(file.handle, &mode) != 0) {
                const new_mode = mode | ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING;

                if (kernel32.SetConsoleMode(file.handle, new_mode) == 0)
                    return error.ConsoleConfigFailed;

                return .{ .restore_mode = mode };
            } else {
                return .{ .restore_mode = null };
            }
        }

        fn restore(options: IoOptions, file: std.fs.File) !void {
            if (options.restore_mode) |old_mode| {
                if (kernel32.SetConsoleMode(file.handle, old_mode) == 0)
                    return error.ConsoleConfigFailed;
            }
        }
    },

    // assume unix
    else => struct {
        const VTIME = 5;
        const VMIN = 6;

        termios: ?std.posix.termios,

        fn configureOutputUncooked(file: std.fs.File) !IoOptions {
            const original = std.posix.tcgetattr(file.handle) catch |err| switch (err) {
                error.NotATerminal => return .{ .termios = null },
                else => |e| return e,
            };

            var settings = original;

            settings.oflag.OPOST = false;
            settings.oflag.ONLCR = false;
            settings.oflag.OCRNL = false;

            settings.lflag.ECHO = false;
            settings.lflag.ECHOE = false;
            settings.lflag.ECHOK = false;
            settings.lflag.ECHONL = false;
            settings.lflag.ECHOCTL = false;
            settings.lflag.ECHOKE = false;

            std.posix.tcsetattr(file.handle, .NOW, settings) catch |err| switch (err) {
                error.NotATerminal => return .{ .termios = original },
                else => |e| return e,
            };

            return IoOptions{
                .termios = original,
            };
        }

        fn restore(options: IoOptions, file: std.fs.File) !void {
            if (options.termios) |termios| {
                try std.posix.tcsetattr(file.handle, .NOW, termios);
            }
        }
    },
};
