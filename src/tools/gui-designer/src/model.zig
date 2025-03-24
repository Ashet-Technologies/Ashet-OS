const std = @import("std");
const ashet = @import("ashet-abi");

pub const Rectangle = ashet.Rectangle;
pub const Size = ashet.Size;
pub const Point = ashet.Point;
pub const Color = ashet.Color;

pub const Window = struct {
    design_size: Size = .new(400, 300),

    min_size: Size = .new(0, 0),
    max_size: Size = .new(std.math.maxInt(u16), std.math.maxInt(u16)),

    widgets: std.ArrayListUnmanaged(Widget) = .empty,
};

pub const Widget = struct {
    bounds: ashet.Rectangle,
    anchor: Anchor = .top_left,
    visible: bool = true,
    class: *const Class,
};

pub const Class = struct {
    pub const generic: Class = .{
        .name = "generic",
    };

    name: [:0]const u8,

    min_size: Size = .new(0, 0),
    max_size: Size = .new(std.math.maxInt(u16), std.math.maxInt(u16)),

    default_size: Size = .new(50, 40),
};

/// The anchor defines which side of a widget should stick to the parent boundary.
pub const Anchor = struct {
    pub const all: Anchor = .{ .top = true, .bottom = true, .left = true, .right = true };
    pub const top_left: Anchor = .{ .top = true, .bottom = false, .left = true, .right = false };
    pub const top_right: Anchor = .{ .top = true, .bottom = false, .left = false, .right = true };
    pub const bottom_left: Anchor = .{ .top = false, .bottom = true, .left = true, .right = false };
    pub const bottom_right: Anchor = .{ .top = false, .bottom = true, .left = false, .right = true };
    pub const none: Anchor = .{ .top = false, .bottom = false, .left = false, .right = false };

    top: bool,
    bottom: bool,
    left: bool,
    right: bool,
};

pub const Metadata = struct {
    const ZStringContext = struct {
        pub fn hash(self: @This(), s: [:0]const u8) u32 {
            _ = self;
            return std.array_hash_map.hashString(s);
        }
        pub fn eql(self: @This(), a: [:0]const u8, b: [:0]const u8, b_index: usize) bool {
            _ = self;
            _ = b_index;
            return std.array_hash_map.eqlString(a, b);
        }
    };

    const ZStringArrayHashMapUnmanaged = std.array_hash_map.ArrayHashMapUnmanaged([:0]const u8, *Class, ZStringContext, true);

    arena: *std.heap.ArenaAllocator,

    classes: ZStringArrayHashMapUnmanaged = .empty,

    pub fn deinit(metadata: *const Metadata) void {
        const arena = metadata.arena;
        const allocator = arena.child_allocator;
        arena.deinit();
        allocator.destroy(arena);
    }

    pub fn class_by_name(mt: *const Metadata, name: []const u8) ?*const Class {
        return mt.classes.getAdapted(name, std.array_hash_map.StringContext{});
    }

    pub fn get_class_names(mt: *const Metadata) []const [:0]const u8 {
        return mt.classes.keys();
    }
};

pub fn load_metadata(allocator: std.mem.Allocator, json_str: []const u8) !*const Metadata {
    const parse_options: std.json.ParseOptions = .{
        .allocate = .alloc_always,
    };

    const JRoot = struct {
        classes: std.json.Value,
    };

    const JClass = struct {
        default_size: ?Size = null,
        min_size: ?Size = null,
        max_size: ?Size = null,
    };

    const arena: *std.heap.ArenaAllocator = blk: {
        const arena = try allocator.create(std.heap.ArenaAllocator);
        arena.* = .init(allocator);
        break :blk arena;
    };
    errdefer allocator.destroy(arena);
    errdefer arena.deinit();

    const result = try arena.allocator().create(Metadata);
    result.* = .{
        .arena = arena,
        .classes = .empty,
    };

    const parsed_root = try std.json.parseFromSliceLeaky(JRoot, arena.allocator(), json_str, parse_options);

    if (parsed_root.classes != .object)
        return error.TypeMismatch;

    const classes_src = &parsed_root.classes.object;
    for (classes_src.keys(), classes_src.values()) |key, jvalue| {
        if (jvalue != .object)
            return error.TypeMismatch;

        const zkey = try arena.allocator().dupeZ(u8, key);

        const jclass = try std.json.parseFromValueLeaky(JClass, arena.allocator(), jvalue, parse_options);

        const class = try arena.allocator().create(Class);
        class.* = .{
            .name = zkey,
            .default_size = jclass.default_size orelse .new(100, 50),
            .min_size = jclass.min_size orelse .new(0, 0),
            .max_size = jclass.max_size orelse .new(std.math.maxInt(u15), std.math.maxInt(u15)),
        };

        try result.classes.putNoClobber(arena.allocator(), zkey, class);
    }

    return result;
}
