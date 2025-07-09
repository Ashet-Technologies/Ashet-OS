const std = @import("std");

pub const Patch = struct {
    target_fqn: []const []const u8,

    patch_code: []const u8,
};

pub const PatchSet = struct {
    arena: std.heap.ArenaAllocator,
    patches: std.StringArrayHashMapUnmanaged(Patch) = .empty,

    pub fn get(set: PatchSet, fqn: []const []const u8) ?Patch {
        var lut_name_buf: [1024]u8 = undefined;

        var fba: std.heap.FixedBufferAllocator = .init(&lut_name_buf);

        const lut_name = std.mem.join(fba.allocator(), ".", fqn) catch @panic("buffer too short!");

        return set.patches.get(lut_name);
    }

    pub fn deinit(set: *PatchSet) void {
        set.arena.deinit();
        set.* = undefined;
    }
};

pub fn parse(allocator: std.mem.Allocator, patch_code: []const u8) !PatchSet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    errdefer arena.deinit();

    var patches: std.StringArrayHashMapUnmanaged(Patch) = .empty;
    errdefer patches.deinit(arena.allocator());

    var current_target: ?[]const u8 = null;
    var current_patch: std.ArrayList(u8) = .init(arena.allocator());
    defer current_patch.deinit();

    var lines = std.mem.splitScalar(u8, patch_code, '\n');

    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, " \r\t");

        if (std.mem.eql(u8, line, "</patch>")) {
            if (current_target == null) {
                return error.PatchNotOpened;
            }

            try patches.putNoClobber(arena.allocator(), current_target.?, .{
                .target_fqn = &.{}, // TODO!
                .patch_code = try current_patch.toOwnedSlice(),
            });

            current_target = null;
        } else if (std.mem.startsWith(u8, line, "<patch ") and std.mem.endsWith(u8, line, ">")) {
            if (current_target != null) {
                return error.PatchNotClosed;
            }

            current_target = std.mem.trim(u8, line[7 .. line.len - 1], " ");

            if (patches.get(current_target.?) != null) {
                return error.DuplicatePatch;
            }
        } else if (current_target != null) {
            try current_patch.appendSlice(line);
            try current_patch.append('\n');
        } else if (line.len > 0) {
            return error.CodeOutsidePatch;
        }
    }

    if (current_target != null) {
        return error.UnclosedPatch;
    }

    return .{
        .arena = arena,
        .patches = patches,
    };
}
