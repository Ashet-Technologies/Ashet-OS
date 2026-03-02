const std = @import("std");
const emu = @import("emulator");

/// Standalone test runner for the RV32IMC emulator. Reads a raw machine code
/// binary and a JSON test description from the command line, boots the emulator,
/// runs until EBREAK, then compares final register state and debug output
/// against the expected values from the JSON file.
///
/// Exit code 0 means all checks passed; non-zero indicates a mismatch or error.
/// Designed to be invoked as a build-system run step so each assembly test gets
/// its own process and failure message.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 3) {
        std.debug.print("usage: test-runner <rom.bin> <test.json>\n", .{});
        std.process.exit(1);
    }

    const rom_path = args[1];
    const json_path = args[2];

    // -----------------------------------------------------------------------
    // Load ROM binary, pad to 4-byte alignment
    // -----------------------------------------------------------------------
    const rom_raw = try std.fs.cwd().readFileAlloc(allocator, rom_path, 1024 * 1024);
    defer allocator.free(rom_raw);

    const padded_len = (rom_raw.len + 3) & ~@as(usize, 3);
    const rom_buf = try allocator.alignedAlloc(u8, 4, padded_len);
    defer allocator.free(rom_buf);
    @memcpy(rom_buf[0..rom_raw.len], rom_raw);
    @memset(rom_buf[rom_raw.len..], 0);

    // -----------------------------------------------------------------------
    // Parse JSON test description using dynamic Value parsing, which handles
    // heterogeneous types (register maps as objects, debug as string or array)
    // without needing custom parse methods.
    // -----------------------------------------------------------------------
    const json_raw = try std.fs.cwd().readFileAlloc(allocator, json_path, 64 * 1024);
    defer allocator.free(json_raw);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_raw, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    const test_name = if (root.get("name")) |v| v.string else "unnamed";

    // -----------------------------------------------------------------------
    // Set up RAM
    // -----------------------------------------------------------------------
    const ram_size: usize = if (root.get("ram_size")) |v| switch (v) {
        .integer => |i| @intCast(@max(i, 4)),
        else => 4,
    } else 4;

    const ram_buf = try allocator.alignedAlloc(u8, 4, ram_size);
    defer allocator.free(ram_buf);
    @memset(ram_buf, 0);

    // -----------------------------------------------------------------------
    // Set up debug capture
    // -----------------------------------------------------------------------
    var debug_capture = DebugCapture.init(allocator);
    defer debug_capture.deinit();

    // -----------------------------------------------------------------------
    // Initialize system and apply initial register state
    // -----------------------------------------------------------------------
    var system = emu.System.init(rom_buf, ram_buf, debug_capture.writer());

    if (root.get("initial_regs")) |regs_val| {
        if (regs_val == .object) {
            var it = regs_val.object.iterator();
            while (it.next()) |entry| {
                const reg = parseRegName(entry.key_ptr.*) orelse {
                    std.debug.print("FAIL [{s}]: invalid register name in initial_regs: '{s}'\n", .{ test_name, entry.key_ptr.* });
                    std.process.exit(1);
                };
                const val = jsonToU32(entry.value_ptr.*) orelse {
                    std.debug.print("FAIL [{s}]: invalid value for {s} in initial_regs\n", .{ test_name, entry.key_ptr.* });
                    std.process.exit(1);
                };
                system.cpu.write_reg(reg, val);
            }
        }
    }

    // -----------------------------------------------------------------------
    // Run
    // -----------------------------------------------------------------------
    const result = system.step(100_000);
    if (result) |_| {
        std.debug.print("FAIL [{s}]: program did not terminate within 100000 instructions\n", .{test_name});
        std.process.exit(1);
    } else |err| switch (err) {
        error.Ebreak => {},
        else => {
            std.debug.print("FAIL [{s}]: unexpected CPU error: {s}\n", .{ test_name, @errorName(err) });
            std.process.exit(1);
        },
    }

    // -----------------------------------------------------------------------
    // Validate expected registers
    // -----------------------------------------------------------------------
    var failures: usize = 0;

    if (root.get("expected_regs")) |regs_val| {
        if (regs_val == .object) {
            var it = regs_val.object.iterator();
            while (it.next()) |entry| {
                const reg = parseRegName(entry.key_ptr.*) orelse {
                    std.debug.print("FAIL [{s}]: invalid register name in expected_regs: '{s}'\n", .{ test_name, entry.key_ptr.* });
                    failures += 1;
                    continue;
                };
                const expected = jsonToU32(entry.value_ptr.*) orelse {
                    std.debug.print("FAIL [{s}]: invalid value for {s} in expected_regs\n", .{ test_name, entry.key_ptr.* });
                    failures += 1;
                    continue;
                };
                const actual = system.cpu.read_reg(reg);
                if (actual != expected) {
                    std.debug.print("FAIL [{s}]: x{d} = 0x{X:0>8} (expected 0x{X:0>8})\n", .{ test_name, reg, actual, expected });
                    failures += 1;
                }
            }
        }
    }

    // -----------------------------------------------------------------------
    // Validate expected debug output
    // -----------------------------------------------------------------------
    if (root.get("expected_debug")) |debug_val| {
        const expected_debug = parseDebugExpectation(allocator, debug_val) catch |err| {
            std.debug.print("FAIL [{s}]: cannot parse expected_debug: {s}\n", .{ test_name, @errorName(err) });
            std.process.exit(1);
        };
        defer if (expected_debug) |d| allocator.free(d);

        const actual_debug = debug_capture.captured();
        const expected = expected_debug orelse &[_]u8{};

        if (!std.mem.eql(u8, actual_debug, expected)) {
            std.debug.print("FAIL [{s}]: debug output mismatch\n", .{test_name});
            std.debug.print("  expected ({d} bytes): ", .{expected.len});
            printBytes(expected);
            std.debug.print("  actual   ({d} bytes): ", .{actual_debug.len});
            printBytes(actual_debug);
            failures += 1;
        }
    }

    if (failures > 0) {
        std.debug.print("{d} check(s) failed for [{s}]\n", .{ failures, test_name });
        std.process.exit(1);
    }

    std.debug.print("PASS [{s}]\n", .{test_name});
}

// ===========================================================================
// Helpers
// ===========================================================================

/// Parse a register name like "x0" through "x31" into a u5 index.
fn parseRegName(name: []const u8) ?u5 {
    if (name.len < 2 or name.len > 3 or name[0] != 'x') return null;
    return std.fmt.parseInt(u5, name[1..], 10) catch null;
}

/// Convert a JSON value (integer) to u32. Handles both positive and negative
/// integers — negative values are stored as their two's complement u32
/// representation, matching how the emulator stores register contents.
fn jsonToU32(val: std.json.Value) ?u32 {
    return switch (val) {
        .integer => |i| @bitCast(@as(i32, @intCast(i))),
        else => null,
    };
}

/// Parse the "expected_debug" field. Accepts either:
///   - a JSON string: bytes are the UTF-8 content
///   - a JSON array of integers: each element is one byte
///   - an empty string: returns null (no output expected)
fn parseDebugExpectation(allocator: std.mem.Allocator, val: std.json.Value) !?[]u8 {
    switch (val) {
        .string => |s| {
            if (s.len == 0) return null;
            const buf = try allocator.alloc(u8, s.len);
            @memcpy(buf, s);
            return buf;
        },
        .array => |arr| {
            if (arr.items.len == 0) return null;
            const buf = try allocator.alloc(u8, arr.items.len);
            for (arr.items, 0..) |item, i| {
                buf[i] = switch (item) {
                    .integer => |n| @intCast(n),
                    else => return error.InvalidCharacter,
                };
            }
            return buf;
        },
        else => return error.InvalidCharacter,
    }
}

fn printBytes(bytes: []const u8) void {
    std.debug.print("[", .{});
    for (bytes, 0..) |b, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("0x{X:0>2}", .{b});
    }
    std.debug.print("]\n", .{});
}

// ===========================================================================
// Debug capture — collects bytes written to the debug output peripheral
// ===========================================================================

const DebugCapture = struct {
    data: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) DebugCapture {
        return .{ .data = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *DebugCapture) void {
        self.data.deinit();
    }

    fn writer(self: *DebugCapture) emu.System.DebugWriter {
        return .{
            .context = @ptrCast(self),
            .write_fn = &struct {
                fn f(ctx: *anyopaque, byte: u8) void {
                    const cap: *DebugCapture = @alignCast(@ptrCast(ctx));
                    cap.data.append(byte) catch {};
                }
            }.f,
        };
    }

    fn captured(self: *const DebugCapture) []const u8 {
        return self.data.items;
    }
};
