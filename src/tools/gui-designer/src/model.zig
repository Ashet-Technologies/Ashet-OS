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

    pub fn deinit(window: *Window, allocator: std.mem.Allocator) void {
        for (window.widgets.items) |*widget| {
            widget.deinit(allocator);
        }
        window.widgets.deinit(allocator);
        window.* = undefined;
    }

    pub fn widget_from_pos(window: *Window, pos: Point) ?WidgetRef {
        var i: usize = window.widgets.items.len;
        while (i > 0) {
            i -= 1;

            const widget = &window.widgets.items[i];
            if (widget.bounds.contains(pos))
                return .{ .index = i, .ptr = widget };
        }
        return null;
    }
};

pub const WidgetRef = struct {
    ptr: *Widget,
    index: usize,
};

pub const Widget = struct {
    bounds: ashet.Rectangle,
    anchor: Anchor = .top_left,
    visible: bool = true,
    class: *const Class,
    identifier: std.ArrayListUnmanaged(u8) = .empty,
    properties: ZStringArrayHashMapUnmanaged(Value) = .empty,

    pub fn init(class: *const Class, allocator: std.mem.Allocator, bounds: Rectangle) !Widget {
        var widget: Widget = .{
            .class = class,
            .bounds = .new(bounds.position(), .new(
                std.math.clamp(bounds.width, class.min_size.width, class.max_size.width),
                std.math.clamp(bounds.height, class.min_size.height, class.max_size.height),
            )),
        };

        for (class.properties.keys(), class.properties.values()) |name, decl| {
            try widget.properties.putNoClobber(
                allocator,
                name,
                decl.default_value,
            );
        }

        return widget;
    }

    pub fn deinit(widget: *Widget, allocator: std.mem.Allocator) void {
        widget.identifier.deinit(allocator);
        widget.properties.deinit(allocator);
        widget.* = undefined;
    }
};

pub const Class = struct {
    pub const generic: Class = .{
        .name = "generic",
    };

    name: [:0]const u8,

    min_size: Size = .new(0, 0),
    max_size: Size = .new(std.math.maxInt(u16), std.math.maxInt(u16)),

    default_size: Size = .new(50, 40),

    properties: ZStringArrayHashMapUnmanaged(*const PropertyDescriptor) = .empty,
};

pub const PropertyDescriptor = struct {
    name: [:0]const u8,
    default_value: Value,
};

pub const Type = enum {
    string,
    int,
    float,
    bool,
    color,
};

pub const Value = union(Type) {
    string: String,
    int: i32,
    float: f32,
    bool: bool,
    color: ashet.Color,

    pub const String = struct {
        pub const empty: String = .{ .data = @splat(0) };

        data: [1024:0]u8,

        pub fn from_slice(text: []const u8) error{OutOfMemory}!String {
            var string: String = .empty;
            if (text.len > string.data.len)
                return error.OutOfMemory;
            @memcpy(string.data[0..text.len], text);
            return string;
        }

        pub fn slice(string: *const String) [:0]const u8 {
            return std.mem.sliceTo(&string.data, 0);
        }
    };
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
    arena: *std.heap.ArenaAllocator,

    classes: ZStringArrayHashMapUnmanaged(*Class) = .empty,

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
        properties: std.json.Value = .null,
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

        switch (jclass.properties) {
            .null => {},

            .object => |jprops| {
                for (jprops.keys(), jprops.values()) |propkey, value| {
                    if (value != .string)
                        return error.TypeMismatch;

                    const proptype = std.meta.stringToEnum(Type, value.string) orelse return error.InvalidType;

                    const prop = try arena.allocator().create(PropertyDescriptor);
                    prop.* = .{
                        .name = try arena.allocator().dupeZ(u8, propkey),
                        .default_value = switch (proptype) {
                            .bool => .{ .bool = false },
                            .color => .{ .color = .white },
                            .int => .{ .int = 0 },
                            .float => .{ .float = 0 },
                            .string => .{ .string = .empty },
                        },
                    };

                    try class.properties.putNoClobber(arena.allocator(), prop.name, prop);
                }
            },

            else => return error.TypeMismatch,
        }

        inline for (.{ "width", "height" }) |prop| {
            if (@field(class.min_size, prop) > @field(class.max_size, prop)) {
                std.log.err("Class '{s}' min_size.{s} is bigger than max_size.{s}.", .{
                    class.name,
                    prop,
                    prop,
                });
                return error.InvalidData;
            }

            if (@field(class.default_size, prop) < @field(class.min_size, prop)) {
                std.log.warn("Class '{s}' default_size.{s} is less than min_size.{s}. Clamping!", .{
                    class.name,
                    prop,
                    prop,
                });
            }
            if (@field(class.default_size, prop) > @field(class.max_size, prop)) {
                std.log.warn("Class '{s}' default_size.{s} is more than max_size.{s}. Clamping!", .{
                    class.name,
                    prop,
                    prop,
                });
            }
            @field(class.default_size, prop) = @max(@field(class.min_size, prop), @min(@field(class.max_size, prop), @field(class.default_size, prop)));
        }

        try result.classes.putNoClobber(arena.allocator(), zkey, class);
    }

    return result;
}

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

pub fn ZStringArrayHashMapUnmanaged(comptime T: type) type {
    return std.array_hash_map.ArrayHashMapUnmanaged([:0]const u8, T, ZStringContext, true);
}

pub fn save_design(window: Window, unbuffered_stream: anytype) !void {
    var buffered_writer = std.io.bufferedWriter(unbuffered_stream);

    var json = std.json.writeStream(buffered_writer.writer(), .{
        .whitespace = .indent_2,
    });

    try json.beginObject();

    try json.objectField("design_size");
    try json.write(window.design_size);

    try json.objectField("min_size");
    try json.write(window.min_size);

    try json.objectField("max_size");
    try json.write(window.max_size);

    try json.objectField("widgets");
    try json.beginArray();

    for (window.widgets.items) |widget| {
        try json.beginObject();

        try json.objectField("identifier");
        try json.write(widget.identifier.items);

        try json.objectField("bounds");
        try json.write(widget.bounds);

        try json.objectField("anchor");
        try json.write(widget.anchor);

        try json.objectField("visible");
        try json.write(widget.visible);

        try json.objectField("class");
        try json.write(widget.class.name);

        try json.objectField("properties");
        try json.beginObject();
        for (widget.properties.keys(), widget.properties.values()) |key, value| {
            try json.objectField(key);
            switch (value) {
                inline .bool, .int, .float => |val| try json.write(val),

                .string => |val| try json.write(val.slice()),

                .color => |color| {
                    const rgb = color.to_rgb888();
                    var buf: [7]u8 = undefined;
                    const hex = std.fmt.bufPrint(&buf, "#{X:0>2}{X:0>2}{X:0>2}", .{ rgb.r, rgb.g, rgb.b }) catch unreachable;
                    try json.write(hex);
                },
            }
        }
        try json.endObject();

        try json.endObject();
    }

    try json.endArray();

    try json.endObject();

    try buffered_writer.flush();
}

pub fn load_design(stream: anytype, allocator: std.mem.Allocator, metadata: *const Metadata) !Window {
    var buffered_reader = std.io.bufferedReader(stream);
    const reader = buffered_reader.reader();

    const JWidget = struct {
        identifier: []const u8 = "",
        bounds: Rectangle,
        anchor: Anchor = .top_left,
        visible: bool = true,
        class: []const u8,
        properties: std.json.Value,
    };

    const JDesign = struct {
        design_size: Size,

        min_size: Size = .new(0, 0),
        max_size: Size = .new(std.math.maxInt(u16), std.math.maxInt(u16)),

        widgets: []const JWidget,
    };

    var jreader = std.json.reader(allocator, reader);
    defer jreader.deinit();

    const jdesign = try std.json.parseFromTokenSource(JDesign, allocator, &jreader, .{});
    defer jdesign.deinit();

    var window: Window = .{
        .design_size = jdesign.value.design_size,
        .min_size = jdesign.value.min_size,
        .max_size = jdesign.value.max_size,
    };
    errdefer window.deinit(allocator);

    for (jdesign.value.widgets) |jwidget| {
        const widget = try window.widgets.addOne(allocator);
        widget.* = .{
            .class = metadata.class_by_name(jwidget.class) orelse return error.BadClass,
            .anchor = jwidget.anchor,
            .bounds = jwidget.bounds,
            .identifier = .empty,
            .properties = .empty,
            .visible = jwidget.visible,
        };
        try widget.identifier.appendSlice(allocator, jwidget.identifier);

        switch (jwidget.properties) {
            .null => {},
            .object => |*jproperties| {
                for (jproperties.keys(), jproperties.values()) |name, jvalue| {
                    const prop = widget.class.properties.getEntryAdapted(name, std.array_hash_map.StringContext{}) orelse return error.BadProperty;

                    const value: Value = switch (prop.value_ptr.*.default_value) {
                        .string => .{
                            .string = try .from_slice(try jcast(jvalue, .string)),
                        },

                        .int => .{
                            .int = std.math.cast(i32, try jcast(jvalue, .integer)) orelse return error.Overflow,
                        },

                        .float => .{
                            .float = @floatCast(try jcast(jvalue, .float)),
                        },

                        .bool => .{
                            .bool = try jcast(jvalue, .bool),
                        },

                        .color => blk: {
                            const hexstr = try jcast(jvalue, .string);

                            if (hexstr.len != 7 or hexstr[0] != '#')
                                return error.BadColor;

                            const r = try std.fmt.parseInt(u8, hexstr[1..3], 16);
                            const g = try std.fmt.parseInt(u8, hexstr[3..5], 16);
                            const b = try std.fmt.parseInt(u8, hexstr[5..7], 16);
                            break :blk .{
                                .color = .from_rgb(r, g, b),
                            };
                        },
                    };

                    try widget.properties.put(
                        allocator,
                        prop.key_ptr.*,
                        value,
                    );
                }
            },
            else => return error.TypeMismatch,
        }
    }

    return window;
}

fn jcast(value: std.json.Value, comptime jtype: std.meta.Tag(std.json.Value)) !@FieldType(std.json.Value, @tagName(jtype)) {
    return switch (value) {
        jtype => |payload| payload,
        else => return error.TypeMismatch,
    };
}
