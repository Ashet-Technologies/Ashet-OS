const std = @import("std");

/// A database that maps fully-qualified names (as dot-joined strings) to stable
/// u32 UIDs.  On first run the file is created; on subsequent runs it reads the
/// file and reuses existing IDs, allocating new ones for new FQNs.
pub const UidDatabase = struct {
    allocator: std.mem.Allocator,
    entries: std.StringArrayHashMap(u32),
    next_id: u32,

    /// JSON schema used for persistence.
    const FileFormat = struct {
        entries: []const Entry,

        const Entry = struct {
            fqn: []const u8,
            uid: u32,
        };
    };

    pub fn init(allocator: std.mem.Allocator) UidDatabase {
        return .{
            .allocator = allocator,
            .entries = .init(allocator),
            .next_id = 1,
        };
    }

    pub fn deinit(db: *UidDatabase) void {
        // Free owned key copies
        for (db.entries.keys()) |key| {
            db.allocator.free(key);
        }
        db.entries.deinit();
        db.* = undefined;
    }

    /// Look up `fqn`; if not present, assign the next available ID and persist
    /// that mapping.  Returns the (possibly newly-assigned) UID.
    pub fn get_or_assign(db: *UidDatabase, fqn: []const u8) !u32 {
        if (db.entries.get(fqn)) |uid| return uid;

        const key = try db.allocator.dupe(u8, fqn);
        const uid = db.next_id;
        db.next_id += 1;
        try db.entries.put(key, uid);
        return uid;
    }

    /// Load a database from `path`.  If the file does not exist an empty
    /// database is returned instead.
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !UidDatabase {
        var db = init(allocator);
        errdefer db.deinit();

        const content = std.fs.cwd().readFileAlloc(allocator, path, 1 << 20) catch |err| switch (err) {
            error.FileNotFound => return db,
            else => return err,
        };
        defer allocator.free(content);

        const parsed = try std.json.parseFromSlice(FileFormat, allocator, content, .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        for (parsed.value.entries) |entry| {
            const key = try allocator.dupe(u8, entry.fqn);
            try db.entries.put(key, entry.uid);
            if (entry.uid >= db.next_id) {
                db.next_id = entry.uid + 1;
            }
        }

        return db;
    }

    /// Save the database to `path` atomically.
    pub fn save(db: *const UidDatabase, path: []const u8) !void {
        const entries = try db.allocator.alloc(FileFormat.Entry, db.entries.count());
        defer db.allocator.free(entries);

        for (db.entries.keys(), db.entries.values(), 0..) |key, value, i| {
            entries[i] = .{ .fqn = key, .uid = value };
        }

        const format: FileFormat = .{ .entries = entries };

        var atomic_buffer: [4096]u8 = undefined;
        var atomic_file = try std.fs.cwd().atomicFile(path, .{ .write_buffer = &atomic_buffer });
        defer atomic_file.deinit();

        const writer = &atomic_file.file_writer.interface;
        const options: std.json.Stringify.Options = .{
            .whitespace = .indent_2,
        };
        try writer.print("{f}", .{std.json.fmt(format, options)});
        try writer.flush();

        try atomic_file.finish();
    }
};
