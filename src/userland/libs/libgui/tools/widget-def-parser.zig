const std = @import("std");
const model = @import("widget-def-model.zig");

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

const DraftWidget = struct {
    line: usize,
    name: []const u8,
    uuid: []const u8,
    docs: model.DocLines,
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
    }

    fn parseWidget(parser: *Parser) ParserError!DraftWidget {
        const entry = parser.advance().?;
        const header = try parseHeaderAssignment(parser, entry.line, entry.text, "widget ");

        var docs: model.DocLines = &.{};
        var controls: std.ArrayList(DraftMessage) = .empty;
        var events: std.ArrayList(DraftMessage) = .empty;
        var types: std.ArrayList(DraftTypeDeclaration) = .empty;
        var next_identifier: u32 = 1;

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
            .controls = try controls.toOwnedSlice(parser.allocator),
            .events = try events.toOwnedSlice(parser.allocator),
            .types = try types.toOwnedSlice(parser.allocator),
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
                .controls = try parser.materializeMessages(draft.controls),
                .events = try parser.materializeMessages(draft.events),
                .types = try parser.materializeTypeDeclarations(draft.types),
            };
        }
        return widgets;
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

fn ensureIdentifier(parser: *Parser, line: usize, text: []const u8, kind: []const u8) ParserError!void {
    if (!isIdentifier(text)) {
        return parser.fail_fatal(line, "invalid {s} identifier '{s}'", .{ kind, text });
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
