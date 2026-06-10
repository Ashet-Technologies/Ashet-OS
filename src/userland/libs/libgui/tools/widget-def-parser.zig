const std = @import("std");
const model = @import("widget-model");

const Allocator = std.mem.Allocator;
const ParserError = error{ParseFailed} || Allocator.Error;

pub const Failure = struct {
    line: usize,
    message: []const u8,
};

const Entry = struct {
    line: usize,
    indent: usize,
    text: []const u8,
    continuations: std.ArrayListUnmanaged([]const u8) = .empty,
};

const DraftTypeDeclaration = struct {
    line: usize,
    data: model.TypeDeclaration,
};

const DraftMessage = struct {
    line: usize,
    data: model.Message,
};

const DraftPropertyOption = struct {
    line: usize,
    title: []const u8,
    value: model.Literal,
};

const DraftProperty = struct {
    line: usize,
    name: []const u8,
    title: []const u8,
    docs: model.DocLines,
    set_with: ?model.PropertyBinding,
    default_value: ?model.Literal,
    option_labels: []const DraftPropertyOption,
};

const DraftWidget = struct {
    line: usize,
    name: []const u8,
    uuid: []const u8,
    docs: model.DocLines,
    width_constraint: ?model.AxisConstraint,
    height_constraint: ?model.AxisConstraint,
    properties: []const DraftProperty,
    controls: []const DraftMessage,
    events: []const DraftMessage,
    types: []const DraftTypeDeclaration,
};

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();
    const args = try std.process.argsAlloc(allocator);

    var output_path: ?[]const u8 = null;
    var input_path: ?[]const u8 = null;

    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.startsWith(u8, arg, "--output=")) {
            output_path = arg[9..];
            continue;
        }
        if (std.mem.eql(u8, arg, "--output")) {
            index += 1;
            if (index >= args.len) return usage();
            output_path = args[index];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) return usage();
        if (input_path != null) return usage();
        input_path = arg;
    }

    const resolved_input = input_path orelse return usage();
    const resolved_output = output_path orelse return usage();

    const source = try std.fs.cwd().readFileAlloc(allocator, resolved_input, 1 * 1024 * 1024);

    var parser = try Parser.init(allocator, source);
    const document = parser.parseDocument() catch |err| switch (err) {
        error.ParseFailed => {
            std.debug.assert(parser.failures.items.len > 0);
            for (parser.failures.items) |failure| {
                if (failure.line == 0) {
                    std.log.err("{s}: {s}", .{ resolved_input, failure.message });
                } else {
                    std.log.err("{s}:{d}: {s}", .{ resolved_input, failure.line, failure.message });
                }
            }
            return 1;
        },
        else => return err,
    };

    var output_file = try std.fs.cwd().createFile(resolved_output, .{});
    defer output_file.close();

    var output_buffer: [4096]u8 = undefined;
    var output_writer = output_file.writer(&output_buffer);
    try model.to_json_str(document, &output_writer.interface);
    try output_writer.interface.writeByte('\n');
    try output_writer.interface.flush();
    return 0;
}

fn usage() u8 {
    std.log.err("usage: widget-def-parser --output=<path> <input>", .{});
    return 1;
}

const Parser = struct {
    allocator: Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .empty,
    failures: std.ArrayListUnmanaged(Failure) = .empty,
    index: usize = 0,

    fn init(allocator: Allocator, source: []const u8) !Parser {
        var parser = Parser{ .allocator = allocator };
        try parser.tokenize(source);
        return parser;
    }

    fn parseDocument(parser: *Parser) ParserError!model.Document {
        var widgets: std.ArrayList(DraftWidget) = .empty;
        var top_level_types: std.ArrayList(DraftTypeDeclaration) = .empty;

        while (parser.peek()) |entry| {
            if (entry.indent != 0) {
                try parser.fail_report(entry.line, "top-level declarations must not be indented", .{});
                parser.skip_until_next_zero_indent();
                continue;
            }
            if (std.mem.startsWith(u8, entry.text, "widget ")) {
                const widget = parser.parseWidget() catch |err| switch (err) {
                    error.ParseFailed => {
                        parser.skip_until_next_zero_indent();
                        continue;
                    },
                    else => return err,
                };
                try widgets.append(parser.allocator, widget);
                continue;
            }
            if (std.mem.startsWith(u8, entry.text, "type ")) {
                const type_decl = parser.parseTypeDeclaration() catch |err| switch (err) {
                    error.ParseFailed => {
                        parser.skip_until_next_zero_indent();
                        continue;
                    },
                    else => return err,
                };
                try top_level_types.append(parser.allocator, type_decl);
                continue;
            }
            try parser.fail_report(entry.line, "unexpected top-level declaration '{s}'", .{entry.text});
            parser.skip_until_next_zero_indent();
        }

        try parser.validate(top_level_types.items, widgets.items);

        if (parser.failures.items.len != 0) {
            return parser.parse_failed();
        }

        return .{
            .types = try parser.materializeTypeDeclarations(top_level_types.items),
            .widgets = try parser.materializeWidgets(widgets.items),
        };
    }

    fn tokenize(parser: *Parser, source: []const u8) !void {
        var iter = std.mem.splitScalar(u8, source, '\n');
        var line_number: usize = 0;

        while (iter.next()) |line_with_cr| {
            line_number += 1;
            const line = std.mem.trimRight(u8, line_with_cr, "\r");
            const without_comment = stripComment(line);
            if (isBlank(without_comment)) continue;

            const indent = parser.readIndent(line_number, without_comment) catch |err| switch (err) {
                error.ParseFailed => continue,
                else => return err,
            };
            const first_non_space = firstNonSpace(without_comment).?;
            if (without_comment[first_non_space] == '|') {
                if (parser.entries.items.len == 0) {
                    try parser.fail_report(line_number, "continuation line does not have a preceding declaration", .{});
                    continue;
                }

                const continuation = std.mem.trimRight(u8, without_comment[first_non_space + 1 ..], " ");
                try parser.entries.items[parser.entries.items.len - 1].continuations.append(
                    parser.allocator,
                    try parser.allocator.dupe(u8, continuation),
                );
                continue;
            }

            const text = std.mem.trimRight(u8, without_comment[first_non_space..], " ");
            try parser.entries.append(parser.allocator, .{
                .line = line_number,
                .indent = indent,
                .text = try parser.allocator.dupe(u8, text),
            });
        }
    }

    fn readIndent(parser: *Parser, line: usize, text: []const u8) ParserError!usize {
        var indent: usize = 0;
        while (indent < text.len and text[indent] == ' ') : (indent += 1) {}
        if (indent < text.len and text[indent] == '\t') {
            return parser.fail_fatal(line, "tabs are not allowed for indentation", .{});
        }
        if (indent % 4 != 0) {
            return parser.fail_fatal(line, "indentation must use multiples of four spaces", .{});
        }
        return indent;
    }

    fn validate(
        parser: *Parser,
        top_level_types: []const DraftTypeDeclaration,
        widgets: []const DraftWidget,
    ) ParserError!void {
        const NamespaceEntry = struct {
            line: usize,
            kind: enum { widget, type },
        };

        var namespace = std.StringHashMap(NamespaceEntry).init(parser.allocator);
        var uuids = std.StringHashMap(usize).init(parser.allocator);

        for (top_level_types) |top_level_type| {
            const result = try namespace.getOrPut(top_level_type.data.name);
            if (result.found_existing) {
                try parser.fail_report(
                    top_level_type.line,
                    "top-level type '{s}' conflicts with an existing {s} declared at line {d}",
                    .{ top_level_type.data.name, @tagName(result.value_ptr.kind), result.value_ptr.line },
                );
                continue;
            }
            result.value_ptr.* = .{ .line = top_level_type.line, .kind = .type };
        }

        for (widgets) |widget| {
            const name_result = try namespace.getOrPut(widget.name);
            if (name_result.found_existing) {
                try parser.fail_report(
                    widget.line,
                    "widget '{s}' conflicts with an existing {s} declared at line {d}",
                    .{ widget.name, @tagName(name_result.value_ptr.kind), name_result.value_ptr.line },
                );
            } else {
                name_result.value_ptr.* = .{ .line = widget.line, .kind = .widget };
            }

            const uuid_result = try uuids.getOrPut(widget.uuid);
            if (uuid_result.found_existing) {
                try parser.fail_report(
                    widget.line,
                    "widget '{s}' reuses UUID '{s}' first declared at line {d}",
                    .{ widget.name, widget.uuid, uuid_result.value_ptr.* },
                );
            } else {
                uuid_result.value_ptr.* = widget.line;
            }

            try parser.validateWidget(widget);
        }
    }

    fn validateWidget(parser: *Parser, widget: DraftWidget) ParserError!void {
        var local_types = std.StringHashMap(usize).init(parser.allocator);
        var messages = std.StringHashMap(struct {
            line: usize,
            kind: []const u8,
        }).init(parser.allocator);
        var properties = std.StringHashMap(usize).init(parser.allocator);

        for (widget.types) |local_type| {
            if (std.mem.eql(u8, local_type.data.name, widget.name)) {
                try parser.fail_report(
                    local_type.line,
                    "widget-local type '{s}' conflicts with widget '{s}'",
                    .{ local_type.data.name, widget.name },
                );
                continue;
            }
            const result = try local_types.getOrPut(local_type.data.name);
            if (result.found_existing) {
                try parser.fail_report(
                    local_type.line,
                    "widget '{s}' contains duplicate type '{s}' first declared at line {d}",
                    .{ widget.name, local_type.data.name, result.value_ptr.* },
                );
                continue;
            }
            result.value_ptr.* = local_type.line;
        }

        for (widget.controls) |control| {
            const result = try messages.getOrPut(control.data.name);
            if (result.found_existing) {
                try parser.fail_report(
                    control.line,
                    "widget '{s}' contains duplicate message '{s}' already declared as {s} at line {d}",
                    .{ widget.name, control.data.name, result.value_ptr.kind, result.value_ptr.line },
                );
                continue;
            }
            result.value_ptr.* = .{ .line = control.line, .kind = "control" };
        }

        for (widget.events) |event| {
            const result = try messages.getOrPut(event.data.name);
            if (result.found_existing) {
                try parser.fail_report(
                    event.line,
                    "widget '{s}' contains duplicate message '{s}' already declared as {s} at line {d}",
                    .{ widget.name, event.data.name, result.value_ptr.kind, result.value_ptr.line },
                );
                continue;
            }
            result.value_ptr.* = .{ .line = event.line, .kind = "event" };
        }

        for (widget.properties) |property| {
            const result = try properties.getOrPut(property.name);
            if (result.found_existing) {
                try parser.fail_report(
                    property.line,
                    "widget '{s}' contains duplicate property '{s}' first declared at line {d}",
                    .{ widget.name, property.name, result.value_ptr.* },
                );
                continue;
            }
            result.value_ptr.* = property.line;

            if (property.set_with == null) {
                try parser.fail_report(
                    property.line,
                    "property '{s}' on widget '{s}' is missing a set-with binding",
                    .{ property.name, widget.name },
                );
                continue;
            }
            if (property.default_value == null) {
                try parser.fail_report(
                    property.line,
                    "property '{s}' on widget '{s}' is missing a default value",
                    .{ property.name, widget.name },
                );
                continue;
            }

            const binding = property.set_with.?;
            const property_type = findControlParameterType(widget.controls, binding) orelse {
                const control = findControl(widget.controls, binding.control_name) orelse {
                    try parser.fail_report(
                        property.line,
                        "property '{s}' on widget '{s}' references unknown control '{s}'",
                        .{ property.name, widget.name, binding.control_name },
                    );
                    continue;
                };

                try parser.fail_report(
                    property.line,
                    "property '{s}' on widget '{s}' references unknown parameter '{s}' on control '{s}' declared at line {d}",
                    .{ property.name, widget.name, binding.parameter_name, binding.control_name, control.line },
                );
                continue;
            };

            try parser.validateLiteralAgainstType(property.line, property.default_value.?, property_type, "default");

            for (property.option_labels, 0..) |option, option_index| {
                try parser.validateLiteralAgainstType(option.line, option.value, property_type, "option value");

                for (property.option_labels[0..option_index]) |previous| {
                    if (literalEql(previous.value, option.value)) {
                        try parser.fail_report(
                            option.line,
                            "property '{s}' on widget '{s}' redefines a property option value",
                            .{ property.name, widget.name },
                        );
                        break;
                    }
                }
            }
        }
    }

    fn validateLiteralAgainstType(
        parser: *Parser,
        line: usize,
        literal: model.Literal,
        type_ref: model.TypeRef,
        context: []const u8,
    ) ParserError!void {
        switch (type_ref.kind) {
            .builtin => switch (type_ref.builtin.?) {
                .bool => switch (literal) {
                    .boolean => {},
                    else => try parser.fail_report(
                        line,
                        "{s} literal for type '{s}' must be boolean, found {s}",
                        .{ context, type_ref.name, literalTagName(literal) },
                    ),
                },
                .i8 => try parser.validateIntegerLiteralAgainstType(line, literal, i8, context, type_ref.name),
                .i16 => try parser.validateIntegerLiteralAgainstType(line, literal, i16, context, type_ref.name),
                .i32 => try parser.validateIntegerLiteralAgainstType(line, literal, i32, context, type_ref.name),
                .u8 => try parser.validateIntegerLiteralAgainstType(line, literal, u8, context, type_ref.name),
                .u16 => try parser.validateIntegerLiteralAgainstType(line, literal, u16, context, type_ref.name),
                .u32 => try parser.validateIntegerLiteralAgainstType(line, literal, u32, context, type_ref.name),
                .isize => try parser.validateIntegerLiteralAgainstType(line, literal, isize, context, type_ref.name),
                .usize => try parser.validateIntegerLiteralAgainstType(line, literal, usize, context, type_ref.name),
                .str => switch (literal) {
                    .string => {},
                    else => try parser.fail_report(
                        line,
                        "{s} literal for type '{s}' must be string, found {s}",
                        .{ context, type_ref.name, literalTagName(literal) },
                    ),
                },
                .strbuf, .contextptr, .framebuf => {
                    try parser.fail_report(
                        line,
                        "{s} literals do not support widget property type '{s}' yet",
                        .{ context, type_ref.name },
                    );
                },
            },
            .named => switch (literal) {
                .identifier => {},
                else => try parser.fail_report(
                    line,
                    "{s} literal for named type '{s}' must be an identifier, found {s}",
                    .{ context, type_ref.name, literalTagName(literal) },
                ),
            },
        }
    }

    fn validateIntegerLiteralAgainstType(
        parser: *Parser,
        line: usize,
        literal: model.Literal,
        comptime Int: type,
        context: []const u8,
        type_name: []const u8,
    ) ParserError!void {
        const value = switch (literal) {
            .integer => |integer| integer,
            else => {
                try parser.fail_report(
                    line,
                    "{s} literal for type '{s}' must be integer, found {s}",
                    .{ context, type_name, literalTagName(literal) },
                );
                return;
            },
        };

        if (std.math.cast(Int, value) == null) {
            try parser.fail_report(
                line,
                "{s} literal {d} is out of range for type '{s}'",
                .{ context, value, type_name },
            );
        }
    }

    fn parseWidget(parser: *Parser) ParserError!DraftWidget {
        const entry = parser.advance().?;
        const header = try parseHeaderAssignment(parser, entry.line, entry.text, "widget ");

        var docs: model.DocLines = &.{};
        var width_constraint: ?model.AxisConstraint = null;
        var height_constraint: ?model.AxisConstraint = null;
        var properties: std.ArrayList(DraftProperty) = .empty;
        var controls: std.ArrayList(DraftMessage) = .empty;
        var events: std.ArrayList(DraftMessage) = .empty;
        var types: std.ArrayList(DraftTypeDeclaration) = .empty;
        var next_identifier: u32 = 1;
        var has_size_constraint = false;
        var has_width_constraint = false;
        var has_height_constraint = false;

        while (parser.peek()) |child| {
            if (child.indent <= entry.indent) break;
            if (child.indent != entry.indent + 4) {
                return parser.fail_fatal(child.line, "unexpected indentation inside widget '{s}'", .{header.name});
            }

            if (std.mem.startsWith(u8, child.text, "docs:")) {
                if (docs.len != 0) {
                    try parser.fail_report(child.line, "widget '{s}' has multiple docs blocks", .{header.name});
                    parser.skip_entry_and_nested(child.indent);
                    continue;
                }
                docs = try parser.parseDocLines(parser.advance().?);
                continue;
            }
            if (beginsDirective(child.text, "size")) {
                const size_entry = parser.advance().?;
                const value = try parseDirectiveAssignment(parser, size_entry.line, size_entry.text, "size");
                const parsed = try parseSizeConstraint(parser, size_entry.line, value);

                if (has_size_constraint or has_width_constraint or has_height_constraint) {
                    try parser.fail_report(
                        size_entry.line,
                        "widget '{s}' cannot mix 'size' with separate width or height constraints",
                        .{header.name},
                    );
                    continue;
                }

                width_constraint = parsed.width;
                height_constraint = parsed.height;
                has_size_constraint = true;
                continue;
            }
            if (beginsDirective(child.text, "width")) {
                const width_entry = parser.advance().?;
                const value = try parseDirectiveAssignment(parser, width_entry.line, width_entry.text, "width");

                if (has_size_constraint or has_width_constraint) {
                    try parser.fail_report(
                        width_entry.line,
                        "widget '{s}' declares width constraints more than once or conflicts with 'size'",
                        .{header.name},
                    );
                    continue;
                }

                width_constraint = try parseAxisConstraint(parser, width_entry.line, value);
                has_width_constraint = true;
                continue;
            }
            if (beginsDirective(child.text, "height")) {
                const height_entry = parser.advance().?;
                const value = try parseDirectiveAssignment(parser, height_entry.line, height_entry.text, "height");

                if (has_size_constraint or has_height_constraint) {
                    try parser.fail_report(
                        height_entry.line,
                        "widget '{s}' declares height constraints more than once or conflicts with 'size'",
                        .{header.name},
                    );
                    continue;
                }

                height_constraint = try parseAxisConstraint(parser, height_entry.line, value);
                has_height_constraint = true;
                continue;
            }
            if (std.mem.startsWith(u8, child.text, "property ")) {
                try properties.append(parser.allocator, try parser.parseProperty());
                continue;
            }
            if (std.mem.startsWith(u8, child.text, "control ")) {
                try controls.append(parser.allocator, try parser.parseMessage("control", next_identifier));
                next_identifier += 1;
                continue;
            }
            if (std.mem.startsWith(u8, child.text, "event ")) {
                try events.append(parser.allocator, try parser.parseMessage("event", next_identifier));
                next_identifier += 1;
                continue;
            }
            if (std.mem.startsWith(u8, child.text, "type ")) {
                try types.append(parser.allocator, try parser.parseTypeDeclaration());
                continue;
            }
            try parser.fail_report(child.line, "unexpected widget child '{s}'", .{child.text});
            parser.skip_entry_and_nested(child.indent);
        }

        return .{
            .line = entry.line,
            .name = header.name,
            .uuid = header.value,
            .docs = docs,
            .width_constraint = width_constraint,
            .height_constraint = height_constraint,
            .properties = try properties.toOwnedSlice(parser.allocator),
            .controls = try controls.toOwnedSlice(parser.allocator),
            .events = try events.toOwnedSlice(parser.allocator),
            .types = try types.toOwnedSlice(parser.allocator),
        };
    }

    fn parseProperty(parser: *Parser) ParserError!DraftProperty {
        const entry = parser.advance().?;
        const header = try parsePropertyHeader(parser, entry.line, entry.text);

        var docs: model.DocLines = &.{};
        var set_with: ?model.PropertyBinding = null;
        var default_value: ?model.Literal = null;
        var option_labels: std.ArrayList(DraftPropertyOption) = .empty;

        while (parser.peek()) |child| {
            if (child.indent <= entry.indent) break;
            if (child.indent != entry.indent + 4) {
                return parser.fail_fatal(child.line, "unexpected indentation inside property '{s}'", .{header.name});
            }

            if (std.mem.startsWith(u8, child.text, "docs:")) {
                if (docs.len != 0) {
                    try parser.fail_report(child.line, "property '{s}' has multiple docs blocks", .{header.name});
                    parser.skip_entry_and_nested(child.indent);
                    continue;
                }
                docs = try parser.parseDocLines(parser.advance().?);
                continue;
            }

            if (std.mem.startsWith(u8, child.text, "set-with:")) {
                const binding_entry = parser.advance().?;
                if (set_with != null) {
                    try parser.fail_report(binding_entry.line, "property '{s}' has multiple set-with bindings", .{header.name});
                    continue;
                }
                set_with = try parsePropertyBinding(parser, binding_entry.line, std.mem.trim(u8, binding_entry.text[9..], " "));
                continue;
            }

            if (std.mem.startsWith(u8, child.text, "default:")) {
                const default_entry = parser.advance().?;
                if (default_value != null) {
                    try parser.fail_report(default_entry.line, "property '{s}' has multiple default values", .{header.name});
                    continue;
                }
                default_value = try parseLiteral(parser, default_entry.line, std.mem.trim(u8, default_entry.text[8..], " "));
                continue;
            }

            if (std.mem.startsWith(u8, child.text, "option ")) {
                try option_labels.append(parser.allocator, try parser.parsePropertyOption());
                continue;
            }

            try parser.fail_report(child.line, "unexpected property child '{s}'", .{child.text});
            parser.skip_entry_and_nested(child.indent);
        }

        return .{
            .line = entry.line,
            .name = header.name,
            .title = header.title,
            .docs = docs,
            .set_with = set_with,
            .default_value = default_value,
            .option_labels = try option_labels.toOwnedSlice(parser.allocator),
        };
    }

    fn parsePropertyOption(parser: *Parser) ParserError!DraftPropertyOption {
        const entry = parser.advance().?;
        const tail = entry.text[7..];
        const eq_index = std.mem.indexOfScalar(u8, tail, '=') orelse
            return parser.fail_fatal(entry.line, "property option is missing '='", .{});

        const value = try parseLiteral(parser, entry.line, std.mem.trim(u8, tail[0..eq_index], " "));
        const title = try parseQuotedString(parser, entry.line, std.mem.trim(u8, tail[eq_index + 1 ..], " "), "property option title");

        return .{
            .line = entry.line,
            .title = title,
            .value = value,
        };
    }

    fn parseTypeDeclaration(parser: *Parser) ParserError!DraftTypeDeclaration {
        const entry = parser.advance().?;
        const parsed = try parseHeaderAssignment(parser, entry.line, entry.text, "type ");

        var parts: std.ArrayList([]const u8) = .empty;
        try parts.append(parser.allocator, parsed.value);
        for (entry.continuations.items) |continuation| {
            try parts.append(parser.allocator, continuation);
        }

        return .{
            .line = entry.line,
            .data = .{
                .name = parsed.name,
                .zig_type = try std.mem.join(parser.allocator, "\n", parts.items),
            },
        };
    }

    fn parseMessage(parser: *Parser, comptime kind: []const u8, identifier: u32) ParserError!DraftMessage {
        const entry = parser.advance().?;
        const tail = entry.text[kind.len + 1 ..];

        const open_paren = std.mem.indexOfScalar(u8, tail, '(') orelse
            return parser.fail_fatal(entry.line, "{s} is missing '('", .{kind});
        const close_paren = std.mem.lastIndexOfScalar(u8, tail, ')') orelse
            return parser.fail_fatal(entry.line, "{s} is missing ')'", .{kind});
        if (close_paren < open_paren) {
            return parser.fail_fatal(entry.line, "{s} has malformed parameter list", .{kind});
        }

        const name = std.mem.trim(u8, tail[0..open_paren], " ");
        try ensureIdentifier(parser, entry.line, name, kind);

        const parameters = try parser.parseParameters(entry.line, tail[open_paren + 1 .. close_paren]);
        const parameter_raw_slots = sumParameterSlots(parameters);
        if (parameter_raw_slots > 4) {
            try parser.fail_report(
                entry.line,
                "{s} '{s}' exceeds the 4-slot parameter limit with {d} raw slots",
                .{ kind, name, parameter_raw_slots },
            );
        }

        const return_suffix = std.mem.trim(u8, tail[close_paren + 1 ..], " ");
        const return_type: ?model.TypeRef = blk: {
            if (return_suffix.len == 0) break :blk null;
            if (std.mem.eql(u8, kind, "event")) {
                return parser.fail_fatal(entry.line, "event '{s}' must not declare a return type", .{name});
            }
            break :blk try parser.parseTypeRef(entry.line, return_suffix, false);
        };
        const return_raw_slots: u8 = if (return_type) |rt| rt.raw_slot_width else 0;

        var docs: model.DocLines = &.{};
        while (parser.peek()) |child| {
            if (child.indent <= entry.indent) break;
            if (child.indent != entry.indent + 4) {
                return parser.fail_fatal(child.line, "unexpected indentation inside {s} '{s}'", .{ kind, name });
            }
            if (!std.mem.startsWith(u8, child.text, "docs:")) {
                try parser.fail_report(child.line, "unexpected {s} child '{s}'", .{ kind, child.text });
                parser.skip_entry_and_nested(child.indent);
                continue;
            }
            if (docs.len != 0) {
                try parser.fail_report(child.line, "{s} '{s}' has multiple docs blocks", .{ kind, name });
                parser.skip_entry_and_nested(child.indent);
                continue;
            }
            docs = try parser.parseDocLines(parser.advance().?);
        }

        return .{
            .line = entry.line,
            .data = .{
                .identifier = identifier,
                .name = name,
                .docs = docs,
                .parameters = parameters,
                .parameter_raw_slots = parameter_raw_slots,
                .return_type = return_type,
                .return_raw_slots = return_raw_slots,
            },
        };
    }

    fn parseParameters(parser: *Parser, line: usize, text: []const u8) ParserError![]const model.Parameter {
        const trimmed = std.mem.trim(u8, text, " ");
        if (trimmed.len == 0) return &.{};

        var parameters: std.ArrayList(model.Parameter) = .empty;
        var iter = std.mem.splitScalar(u8, trimmed, ',');
        while (iter.next()) |item| {
            const parameter = std.mem.trim(u8, item, " ");
            const colon = std.mem.indexOfScalar(u8, parameter, ':') orelse
                return parser.fail_fatal(line, "parameters must use 'name: type' syntax", .{});

            const name = std.mem.trim(u8, parameter[0..colon], " ");
            const type_name = std.mem.trim(u8, parameter[colon + 1 ..], " ");
            try ensureIdentifier(parser, line, name, "parameter");
            try parameters.append(parser.allocator, .{
                .name = name,
                .type = try parser.parseTypeRef(line, type_name, true),
            });
        }

        return try parameters.toOwnedSlice(parser.allocator);
    }

    fn parseTypeRef(parser: *Parser, line: usize, text: []const u8, allow_two_slot: bool) ParserError!model.TypeRef {
        const name = std.mem.trim(u8, text, " ");
        if (name.len == 0) {
            return parser.fail_fatal(line, "type name must not be empty", .{});
        }

        if (std.meta.stringToEnum(model.BuiltinType, name)) |builtin| {
            const raw_slot_width = model.builtin_raw_slot_width(builtin);
            if (!allow_two_slot and raw_slot_width > 1) {
                return parser.fail_fatal(line, "type '{s}' is not allowed in this position", .{name});
            }
            return .{
                .name = name,
                .kind = .builtin,
                .builtin = builtin,
                .raw_slot_width = raw_slot_width,
            };
        }

        try ensureIdentifier(parser, line, name, "type");
        return .{
            .name = name,
            .kind = .named,
            .builtin = null,
            .raw_slot_width = 1,
        };
    }

    fn parseDocLines(parser: *Parser, entry: Entry) ParserError!model.DocLines {
        const base = normalizeDocLine(entry.text[5..]);
        var lines: std.ArrayList([]const u8) = .empty;
        try lines.append(parser.allocator, base);
        for (entry.continuations.items) |continuation| {
            try lines.append(parser.allocator, normalizeDocLine(continuation));
        }
        return try lines.toOwnedSlice(parser.allocator);
    }

    fn materializeTypeDeclarations(
        parser: *Parser,
        drafts: []const DraftTypeDeclaration,
    ) Allocator.Error![]const model.TypeDeclaration {
        const items = try parser.allocator.alloc(model.TypeDeclaration, drafts.len);
        for (drafts, 0..) |draft, item_index| {
            items[item_index] = draft.data;
        }
        return items;
    }

    fn materializeWidgets(parser: *Parser, drafts: []const DraftWidget) Allocator.Error![]const model.Widget {
        const widgets = try parser.allocator.alloc(model.Widget, drafts.len);
        for (drafts, 0..) |draft, item_index| {
            widgets[item_index] = .{
                .name = draft.name,
                .uuid = draft.uuid,
                .docs = draft.docs,
                .width_constraint = draft.width_constraint,
                .height_constraint = draft.height_constraint,
                .properties = try parser.materializeProperties(draft),
                .controls = try parser.materializeMessages(draft.controls),
                .events = try parser.materializeMessages(draft.events),
                .types = try parser.materializeTypeDeclarations(draft.types),
            };
        }
        return widgets;
    }

    fn materializeProperties(parser: *Parser, widget: DraftWidget) Allocator.Error![]const model.Property {
        const properties = try parser.allocator.alloc(model.Property, widget.properties.len);
        for (widget.properties, 0..) |draft, item_index| {
            const binding = draft.set_with.?;
            properties[item_index] = .{
                .name = draft.name,
                .title = draft.title,
                .docs = draft.docs,
                .set_with = binding,
                .default_value = draft.default_value.?,
                .option_labels = try parser.materializePropertyOptions(draft.option_labels),
                .type = findControlParameterType(widget.controls, binding).?,
            };
        }
        return properties;
    }

    fn materializePropertyOptions(parser: *Parser, drafts: []const DraftPropertyOption) Allocator.Error![]const model.PropertyOption {
        const options = try parser.allocator.alloc(model.PropertyOption, drafts.len);
        for (drafts, 0..) |draft, item_index| {
            options[item_index] = .{
                .title = draft.title,
                .value = draft.value,
            };
        }
        return options;
    }

    fn materializeMessages(parser: *Parser, drafts: []const DraftMessage) Allocator.Error![]const model.Message {
        const messages = try parser.allocator.alloc(model.Message, drafts.len);
        for (drafts, 0..) |draft, item_index| {
            messages[item_index] = draft.data;
        }
        return messages;
    }

    fn peek(parser: *Parser) ?Entry {
        if (parser.index >= parser.entries.items.len) return null;
        return parser.entries.items[parser.index];
    }

    fn advance(parser: *Parser) ?Entry {
        const entry = parser.peek() orelse return null;
        parser.index += 1;
        return entry;
    }

    fn skip_until_next_zero_indent(parser: *Parser) void {
        if (parser.peek() == null) return;

        _ = parser.advance();
        while (parser.peek()) |entry| {
            if (entry.indent == 0) break;
            _ = parser.advance();
        }
    }

    fn skip_entry_and_nested(parser: *Parser, indent: usize) void {
        if (parser.peek() == null) return;

        _ = parser.advance();
        while (parser.peek()) |entry| {
            if (entry.indent <= indent) break;
            _ = parser.advance();
        }
    }

    fn fail_report(parser: *Parser, line: usize, comptime fmt: []const u8, args: anytype) Allocator.Error!void {
        try parser.failures.append(parser.allocator, .{
            .line = line,
            .message = try std.fmt.allocPrint(parser.allocator, fmt, args),
        });
    }

    fn fail_fatal(parser: *Parser, line: usize, comptime fmt: []const u8, args: anytype) ParserError {
        try parser.fail_report(line, fmt, args);
        return parser.parse_failed();
    }

    fn parse_failed(parser: *Parser) error{ParseFailed} {
        std.debug.assert(parser.failures.items.len > 0);
        return error.ParseFailed;
    }
};

fn parseHeaderAssignment(parser: *Parser, line: usize, text: []const u8, prefix: []const u8) ParserError!struct {
    name: []const u8,
    value: []const u8,
} {
    const tail = text[prefix.len..];
    const eq_index = std.mem.indexOfScalar(u8, tail, '=') orelse
        return parser.fail_fatal(line, "declaration '{s}' is missing '='", .{text});

    const name = std.mem.trim(u8, tail[0..eq_index], " ");
    const value = std.mem.trim(u8, tail[eq_index + 1 ..], " ");

    try ensureIdentifier(parser, line, name, prefix[0 .. prefix.len - 1]);

    if (std.mem.eql(u8, prefix, "widget ")) {
        if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
            return parser.fail_fatal(line, "widget '{s}' must assign a quoted UUID", .{name});
        }
        return .{ .name = name, .value = value[1 .. value.len - 1] };
    }

    if (value.len == 0) {
        return parser.fail_fatal(line, "type '{s}' must declare a Zig type body", .{name});
    }
    return .{ .name = name, .value = value };
}

fn parsePropertyHeader(parser: *Parser, line: usize, text: []const u8) ParserError!struct {
    name: []const u8,
    title: []const u8,
} {
    const tail = text[9..];
    const eq_index = std.mem.indexOfScalar(u8, tail, '=') orelse
        return parser.fail_fatal(line, "property declaration '{s}' is missing '='", .{text});

    const name = std.mem.trim(u8, tail[0..eq_index], " ");
    try ensurePropertyIdentifier(parser, line, name);

    const title = try parseQuotedString(parser, line, std.mem.trim(u8, tail[eq_index + 1 ..], " "), "property title");
    return .{ .name = name, .title = title };
}

fn parseDirectiveAssignment(parser: *Parser, line: usize, text: []const u8, directive: []const u8) ParserError![]const u8 {
    const tail = text[directive.len..];
    const eq_index = std.mem.indexOfScalar(u8, tail, '=') orelse
        return parser.fail_fatal(line, "directive '{s}' is missing '='", .{directive});

    if (std.mem.trim(u8, tail[0..eq_index], " ").len != 0) {
        return parser.fail_fatal(line, "directive '{s}' has unexpected tokens before '='", .{directive});
    }

    const value = std.mem.trim(u8, tail[eq_index + 1 ..], " ");
    if (value.len == 0) {
        return parser.fail_fatal(line, "directive '{s}' requires a value", .{directive});
    }
    return value;
}

fn parseQuotedString(parser: *Parser, line: usize, text: []const u8, context: []const u8) ParserError![]const u8 {
    if (text.len < 2 or text[0] != '"' or text[text.len - 1] != '"') {
        return parser.fail_fatal(line, "{s} must be a quoted string", .{context});
    }
    return text[1 .. text.len - 1];
}

fn ensureIdentifier(parser: *Parser, line: usize, text: []const u8, kind: []const u8) ParserError!void {
    if (!isIdentifier(text)) {
        return parser.fail_fatal(line, "invalid {s} identifier '{s}'", .{ kind, text });
    }
}

fn ensurePropertyIdentifier(parser: *Parser, line: usize, text: []const u8) ParserError!void {
    if (!isPropertyIdentifier(text)) {
        return parser.fail_fatal(line, "invalid property identifier '{s}'", .{text});
    }
}

fn isIdentifier(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!std.ascii.isAlphabetic(text[0]) and text[0] != '_') return false;
    for (text[1..]) |char| {
        if (!std.ascii.isAlphanumeric(char) and char != '_') return false;
    }
    return true;
}

fn isPropertyIdentifier(text: []const u8) bool {
    var iter = std.mem.splitScalar(u8, text, '-');
    var saw_segment = false;
    while (iter.next()) |segment| {
        if (!isIdentifier(segment)) return false;
        saw_segment = true;
    }
    return saw_segment;
}

fn beginsDirective(text: []const u8, directive: []const u8) bool {
    if (!std.mem.startsWith(u8, text, directive)) return false;
    if (text.len == directive.len) return true;

    return switch (text[directive.len]) {
        ' ', '=' => true,
        else => false,
    };
}

fn findControl(controls: []const DraftMessage, control_name: []const u8) ?DraftMessage {
    for (controls) |control| {
        if (std.mem.eql(u8, control.data.name, control_name)) return control;
    }
    return null;
}

fn findControlParameterType(controls: []const DraftMessage, binding: model.PropertyBinding) ?model.TypeRef {
    const control = findControl(controls, binding.control_name) orelse return null;
    for (control.data.parameters) |parameter| {
        if (std.mem.eql(u8, parameter.name, binding.parameter_name)) return parameter.type;
    }
    return null;
}

fn literalTagName(literal: model.Literal) []const u8 {
    return @tagName(std.meta.activeTag(literal));
}

fn literalEql(lhs: model.Literal, rhs: model.Literal) bool {
    return switch (lhs) {
        .boolean => |lhs_value| switch (rhs) {
            .boolean => |rhs_value| lhs_value == rhs_value,
            else => false,
        },
        .integer => |lhs_value| switch (rhs) {
            .integer => |rhs_value| lhs_value == rhs_value,
            else => false,
        },
        .string => |lhs_value| switch (rhs) {
            .string => |rhs_value| std.mem.eql(u8, lhs_value, rhs_value),
            else => false,
        },
        .identifier => |lhs_value| switch (rhs) {
            .identifier => |rhs_value| std.mem.eql(u8, lhs_value, rhs_value),
            else => false,
        },
    };
}

fn parseAxisConstraint(parser: *Parser, line: usize, text: []const u8) ParserError!model.AxisConstraint {
    const trimmed = std.mem.trim(u8, text, " ");
    if (std.mem.indexOf(u8, trimmed, "...")) |ellipsis_index| {
        const min_text = std.mem.trim(u8, trimmed[0..ellipsis_index], " ");
        const max_text = std.mem.trim(u8, trimmed[ellipsis_index + 3 ..], " ");

        if (min_text.len == 0 and max_text.len == 0) {
            return parser.fail_fatal(line, "axis constraint must set at least one bound", .{});
        }

        const min_value = if (min_text.len == 0) null else try parseConstraintNumber(parser, line, min_text);
        const max_value = if (max_text.len == 0) null else try parseConstraintNumber(parser, line, max_text);

        if (min_value != null and max_value != null and min_value.? > max_value.?) {
            return parser.fail_fatal(
                line,
                "axis constraint lower bound {d} exceeds upper bound {d}",
                .{ min_value.?, max_value.? },
            );
        }

        return .{ .min = min_value, .max = max_value };
    }

    const fixed = try parseConstraintNumber(parser, line, trimmed);
    return .{ .min = fixed, .max = fixed };
}

fn parseSizeConstraint(parser: *Parser, line: usize, text: []const u8) ParserError!struct {
    width: model.AxisConstraint,
    height: model.AxisConstraint,
} {
    const trimmed = std.mem.trim(u8, text, " ");
    const x_index = std.mem.indexOfScalar(u8, trimmed, 'x') orelse
        return parser.fail_fatal(line, "size constraint must use '<width>x<height>' syntax", .{});

    const width = try parseConstraintNumber(parser, line, std.mem.trim(u8, trimmed[0..x_index], " "));
    const height = try parseConstraintNumber(parser, line, std.mem.trim(u8, trimmed[x_index + 1 ..], " "));

    return .{
        .width = .{ .min = width, .max = width },
        .height = .{ .min = height, .max = height },
    };
}

fn parseConstraintNumber(parser: *Parser, line: usize, text: []const u8) ParserError!u16 {
    return std.fmt.parseInt(u16, text, 10) catch |err| switch (err) {
        error.InvalidCharacter => return parser.fail_fatal(line, "constraint value '{s}' must be a decimal integer", .{text}),
        error.Overflow => return parser.fail_fatal(line, "constraint value '{s}' exceeds the supported u16 range", .{text}),
    };
}

fn parsePropertyBinding(parser: *Parser, line: usize, text: []const u8) ParserError!model.PropertyBinding {
    const dot_index = std.mem.indexOfScalar(u8, text, '.') orelse
        return parser.fail_fatal(line, "set-with bindings must use 'control.parameter' syntax", .{});
    const last_dot_index = std.mem.lastIndexOfScalar(u8, text, '.').?;
    if (last_dot_index != dot_index) {
        return parser.fail_fatal(line, "set-with bindings must contain exactly one '.'", .{});
    }

    const control_name = std.mem.trim(u8, text[0..dot_index], " ");
    const parameter_name = std.mem.trim(u8, text[dot_index + 1 ..], " ");
    try ensureIdentifier(parser, line, control_name, "control");
    try ensureIdentifier(parser, line, parameter_name, "parameter");

    return .{ .control_name = control_name, .parameter_name = parameter_name };
}

fn parseLiteral(parser: *Parser, line: usize, text: []const u8) ParserError!model.Literal {
    const trimmed = std.mem.trim(u8, text, " ");
    if (trimmed.len == 0) {
        return parser.fail_fatal(line, "literal value must not be empty", .{});
    }

    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return .{ .string = trimmed[1 .. trimmed.len - 1] };
    }
    if (std.mem.eql(u8, trimmed, "true")) return .{ .boolean = true };
    if (std.mem.eql(u8, trimmed, "false")) return .{ .boolean = false };

    const maybe_integer = std.fmt.parseInt(i64, trimmed, 10) catch |err| switch (err) {
        error.InvalidCharacter => null,
        error.Overflow => return parser.fail_fatal(line, "integer literal '{s}' exceeds the supported i64 range", .{trimmed}),
    };
    if (maybe_integer) |integer| {
        return .{ .integer = integer };
    }

    if (!isIdentifier(trimmed)) {
        return parser.fail_fatal(line, "literal '{s}' must be a quoted string, boolean, integer, or identifier", .{trimmed});
    }

    return .{ .identifier = trimmed };
}

fn sumParameterSlots(parameters: []const model.Parameter) u8 {
    var total: u8 = 0;
    for (parameters) |parameter| total += parameter.type.raw_slot_width;
    return total;
}

fn stripComment(text: []const u8) []const u8 {
    return text[0 .. std.mem.indexOfScalar(u8, text, '#') orelse text.len];
}

fn isBlank(text: []const u8) bool {
    return std.mem.trim(u8, text, " ").len == 0;
}

fn firstNonSpace(text: []const u8) ?usize {
    for (text, 0..) |char, item_index| {
        if (char != ' ') return item_index;
    }
    return null;
}

fn normalizeDocLine(text: []const u8) []const u8 {
    if (text.len != 0 and text[0] == ' ') return text[1..];
    return text;
}

test "continuation lines fold into docs and type bodies" {
    const source =
        \\widget Demo = "123"
        \\    docs: First line.
        \\        | Second line.
        \\    type Payload = extern struct {
        \\    |    value: usize,
        \\    |}
        \\    control set_value(payload: Payload)
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    const document = try parser.parseDocument();

    try std.testing.expectEqual(@as(usize, 1), document.widgets.len);
    try std.testing.expectEqual(@as(u32, 1), document.widgets[0].controls[0].identifier);
    try std.testing.expectEqualStrings("First line.", document.widgets[0].docs[0]);
    try std.testing.expectEqualStrings("Second line.", document.widgets[0].docs[1]);
    try std.testing.expectEqualStrings("extern struct {\n    value: usize,\n}", document.widgets[0].types[0].zig_type);
}

test "indentation must be a multiple of four spaces" {
    const source =
        \\widget Demo = "123"
        \\  docs: bad
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    try std.testing.expectError(error.ParseFailed, parser.parseDocument());
    try std.testing.expectEqual(@as(usize, 1), parser.failures.items.len);
    try std.testing.expectEqual(@as(usize, 2), parser.failures.items[0].line);
}

test "duplicate widget UUIDs fail validation" {
    const source =
        \\widget One = "123"
        \\widget Two = "123"
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    try std.testing.expectError(error.ParseFailed, parser.parseDocument());
    try std.testing.expectEqual(@as(usize, 1), parser.failures.items.len);
    try std.testing.expect(std.mem.indexOf(u8, parser.failures.items[0].message, "reuses UUID") != null);
}

test "messages enforce four raw slots" {
    const source =
        \\widget Demo = "123"
        \\    control boom(a: str, b: str, c: str)
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    try std.testing.expectError(error.ParseFailed, parser.parseDocument());
    try std.testing.expectEqual(@as(usize, 1), parser.failures.items.len);
    try std.testing.expect(std.mem.indexOf(u8, parser.failures.items[0].message, "4-slot") != null);
}

test "parser smoke test round-trips to parsable json" {
    const source =
        \\type Shared = usize
        \\widget Demo = "12345678-1234-1234-1234-123456789abc"
        \\    docs: Demo widget.
        \\    control set_text(text: str)
        \\        docs: Sets text.
        \\    event changed(index: u32)
        \\        docs: Fired on change.
        \\    type Payload = extern struct {
        \\    |   value: usize,
        \\    |}
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    const document = try parser.parseDocument();

    try std.testing.expectEqual(@as(usize, 1), document.widgets.len);

    var json: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer json.deinit();

    try model.to_json_str(document, &json.writer);

    const reparsed = try model.from_json_str(arena.allocator(), json.written());
    try std.testing.expectEqual(@as(usize, 1), reparsed.value.widgets.len);
    try std.testing.expectEqual(@as(usize, 1), reparsed.value.types.len);
}

test "widget metadata parses size constraints and properties" {
    const source =
        \\widget Demo = "12345678-1234-1234-1234-123456789abc"
        \\    width = 3...
        \\    height = 15
        \\    control set_alignment(horizontal: Alignment, vertical: Alignment)
        \\    type Alignment = enum(u8) {
        \\    |   near = 0,
        \\    |   middle = 1,
        \\    |   far = 2,
        \\    |   _,
        \\    |}
        \\    property vertical-alignment = "Vertical Alignment"
        \\        docs: Defines how the text is anchored vertically.
        \\        set-with: set_alignment.vertical
        \\        default: middle
        \\        option near = "Top"
        \\        option middle = "Middle"
        \\        option far = "Bottom"
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    const document = try parser.parseDocument();

    try std.testing.expectEqual(@as(usize, 1), document.widgets.len);
    try std.testing.expectEqual(@as(?u16, 3), document.widgets[0].width_constraint.?.min);
    try std.testing.expectEqual(@as(?u16, null), document.widgets[0].width_constraint.?.max);
    try std.testing.expectEqual(@as(?u16, 15), document.widgets[0].height_constraint.?.min);
    try std.testing.expectEqual(@as(?u16, 15), document.widgets[0].height_constraint.?.max);
    try std.testing.expectEqual(@as(usize, 1), document.widgets[0].properties.len);
    try std.testing.expectEqualStrings("vertical-alignment", document.widgets[0].properties[0].name);
    try std.testing.expectEqualStrings("Vertical Alignment", document.widgets[0].properties[0].title);
    try std.testing.expectEqualStrings("set_alignment", document.widgets[0].properties[0].set_with.control_name);
    try std.testing.expectEqualStrings("vertical", document.widgets[0].properties[0].set_with.parameter_name);
    try std.testing.expectEqualStrings("Alignment", document.widgets[0].properties[0].type.name);
    try std.testing.expect(document.widgets[0].properties[0].default_value == .identifier);
    try std.testing.expectEqualStrings("middle", document.widgets[0].properties[0].default_value.identifier);
    try std.testing.expectEqual(@as(usize, 3), document.widgets[0].properties[0].option_labels.len);
}

test "size conflicts with width constraints" {
    const source =
        \\widget Demo = "12345678-1234-1234-1234-123456789abc"
        \\    size = 9x9
        \\    width = 3...
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    try std.testing.expectError(error.ParseFailed, parser.parseDocument());
    try std.testing.expect(parser.failures.items.len != 0);
    try std.testing.expect(hasFailureContaining(parser.failures.items, "size"));
}

test "properties validate set-with bindings" {
    const source =
        \\widget Demo = "12345678-1234-1234-1234-123456789abc"
        \\    control set_text(text: str)
        \\    property label = "Label"
        \\        set-with: set_text.value
        \\        default: "hello"
    ;

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = try Parser.init(arena.allocator(), source);
    try std.testing.expectError(error.ParseFailed, parser.parseDocument());
    try std.testing.expect(parser.failures.items.len != 0);
    try std.testing.expect(hasFailureContaining(parser.failures.items, "unknown parameter 'value'"));
}

fn hasFailureContaining(failures: []const Failure, needle: []const u8) bool {
    for (failures) |failure| {
        if (std.mem.indexOf(u8, failure.message, needle) != null) return true;
    }
    return false;
}
