const std = @import("std");

const ConfigFileIterator = @This();

iter: std.mem.TokenIterator(u8, .any),

line_iter: std.mem.TokenIterator(u8, .any) = undefined,

pub fn init(str: []const u8) ConfigFileIterator {
    return .{
        .iter = std.mem.tokenizeAny(u8, str, "\r\n"),
    };
}

pub fn next(self: *ConfigFileIterator) ?*std.mem.TokenIterator(u8, .any) {
    while (self.iter.next()) |raw_line| {
        const trimmed_line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (std.mem.startsWith(u8, trimmed_line, "#"))
            continue;
        self.line_iter = std.mem.tokenizeAny(u8, trimmed_line, " \t");
        return &self.line_iter;
    }
    return null;
}
