const std = @import("std");
const ashet = @import("ashet");

pub usingnamespace ashet.core;

pub fn main() !void {
    const prompt = "#> ";
    while (true) {
        ashet.console.write(prompt);

        var buffer: [128]u8 = undefined;
        const maybe_result = ashet.console.readLine(&buffer, 64 - prompt.len) catch |err| {
            ashet.console.print("\r\nerror: {s}\r\n", .{@errorName(err)});
            continue;
        };
        if (maybe_result) |result| {
            ashet.console.write("\r\n");
            if (result.len > 0) {
                execute(result) catch |err| {
                    ashet.console.print("error: {s}\r\n", .{@errorName(err)});
                };
            }
        } else {
            // cancelled
            ashet.console.write("\r");
        }
    }
}

fn execute(str: []const u8) !void {
    var args = std.mem.tokenize(u8, str, "\r\n\t ");

    const cmd = args.next() orelse return error.NoCommand;

    inline for (comptime std.meta.declarations(builtin_commands)) |decl| {
        if (std.mem.eql(u8, decl.name, cmd)) {
            const func = @field(builtin_commands, decl.name);
            const t: std.builtin.Type = @typeInfo(@TypeOf(func));
            if (t.Fn.args.len == 1) {
                return func(&args);
            } else {
                return func();
            }
        }
    }

    return error.CommandNotFound;
}

const builtin_commands = struct {
    pub fn quit() void {
        ashet.process.exit(0);
    }

    pub fn echo(args: *std.mem.TokenIterator(u8)) void {
        var first = true;
        while (args.next()) |arg| {
            if (!first) {
                ashet.console.write(" ");
            }
            ashet.console.write(arg);
            first = false;
        }
        ashet.console.write("\r\n");
    }

    pub fn cat(args: *std.mem.TokenIterator(u8)) !void {
        while (args.next()) |file_name| {
            var buffer: [ashet.abi.max_path]u8 = undefined;
            const path = try std.fmt.bufPrintZ(&buffer, "{s}", .{file_name});

            var file = ashet.syscalls().fs.openFile(path.ptr, path.len, .read_only, .open_existing);
            if (file != .invalid) {
                defer ashet.syscalls().fs.close(file);

                while (true) {
                    const len = ashet.syscalls().fs.read(file, &buffer, buffer.len);
                    if (len == 0)
                        break;
                    ashet.console.write(buffer[0..len]);
                }
            } else {
                ashet.console.print("could not open {s}\r\n", .{file_name});
            }
        }
    }

    pub fn font() void {
        ashet.console.write("  0 1 2 3 4 5 6 7 8 9 A B C D E F\r\n");

        var i: usize = 0;
        while (i < 256) : (i += 1) {
            if (i % 16 == 0) {
                ashet.console.print("{X}", .{i / 16});
            }
            var str = [2]u8{ ' ', @truncate(u8, i) };

            ashet.console.output(&str);

            if (i % 16 == 15) {
                ashet.console.write("\r\n");
            }
        }
    }
};
