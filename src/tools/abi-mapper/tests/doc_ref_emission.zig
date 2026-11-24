const std = @import("std");
const abi_parser = @import("abi-parser");
const model = abi_parser.model;

test "doc references survive JSON roundtrip emission" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var roundtrip = try analyze_and_roundtrip_json(std.testing.io, allocator, "tests/doc_ref_emission.abi");
    defer roundtrip.deinit();

    const bind = find_syscall_by_fqn(roundtrip.value.syscalls, "resources.bind") orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(has_ref_fqn(bind.docs, "resources.destroy"));

    const bind_operation = find_enum_by_fqn(roundtrip.value.enums, "resources.BindOperation") orelse
        return error.TestUnexpectedResult;
    const at_least_weak = find_enum_item_by_name(bind_operation.items, "at_least_weak") orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(has_ref_fqn(at_least_weak.docs, "resources.BindOperation.weak"));

    const router = find_struct_by_fqn(roundtrip.value.structs, "link.Router") orelse
        return error.TestUnexpectedResult;
    try std.testing.expect(has_ref_fqn(router.docs, "link.Route.prefix_len"));
    try std.testing.expect(has_code_value(router.docs, "::"));
}

test "stress fixture serializes to valid JSON" {
    if (true) return error.SkipZigTest;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var roundtrip = try analyze_and_roundtrip_json(std.testing.io, allocator, "tests/stress/ashet-1.0.abi");
    defer roundtrip.deinit();

    try std.testing.expect(roundtrip.value.root.len > 0);
}

fn analyze_and_roundtrip_json(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !std.json.Parsed(model.Document) {
    const analyzed_document = try analyze_file(io, allocator, path);

    var json: std.Io.Writer.Allocating = .init(allocator);
    defer json.deinit();
    try model.to_json_str(analyzed_document, &json.writer);

    return model.from_json_str(allocator, json.written());
}

fn analyze_file(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !model.Document {
    const abi_source = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 20));

    var tokenizer: abi_parser.syntax.Tokenizer = .init(abi_source, path);
    var parser: abi_parser.syntax.Parser = .{
        .allocator = allocator,
        .core = .init(&tokenizer),
    };
    const ast_document = try parser.accept_document();
    var errors: std.ArrayList(abi_parser.sema.AnalysisError) = .empty;
    defer errors.deinit(allocator);
    return abi_parser.sema.analyze(allocator, ast_document, null, &errors);
}

fn find_syscall_by_fqn(
    syscalls: []const model.GenericCall,
    expected: []const u8,
) ?model.GenericCall {
    for (syscalls) |syscall| {
        if (fqn_equals(syscall.full_qualified_name, expected)) {
            return syscall;
        }
    }
    return null;
}

fn find_struct_by_fqn(
    structs: []const model.Struct,
    expected: []const u8,
) ?model.Struct {
    for (structs) |item| {
        if (fqn_equals(item.full_qualified_name, expected)) {
            return item;
        }
    }
    return null;
}

fn find_enum_by_fqn(
    enums: []const model.Enumeration,
    expected: []const u8,
) ?model.Enumeration {
    for (enums) |item| {
        if (fqn_equals(item.full_qualified_name, expected)) {
            return item;
        }
    }
    return null;
}

fn find_enum_item_by_name(items: []const model.EnumItem, name: []const u8) ?model.EnumItem {
    for (items) |item| {
        if (std.mem.eql(u8, item.name, name)) {
            return item;
        }
    }
    return null;
}

fn fqn_equals(fqn: model.FQN, expected: []const u8) bool {
    var parts = std.mem.splitScalar(u8, expected, '.');
    var index: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0 or index >= fqn.len) {
            return false;
        }
        if (!std.mem.eql(u8, fqn[index], part)) {
            return false;
        }
        index += 1;
    }
    return index == fqn.len;
}

fn has_ref_fqn(docs: model.DocComment, expected: []const u8) bool {
    for (docs.sections) |section| {
        for (section.blocks) |block| {
            switch (block) {
                .paragraph => |paragraph| {
                    if (inlines_have_ref_fqn(paragraph.content, expected)) return true;
                },
                .unordered_list => |list| {
                    for (list.items) |item| {
                        if (inlines_have_ref_fqn(item, expected)) return true;
                    }
                },
                .ordered_list => |list| {
                    for (list.items) |item| {
                        if (inlines_have_ref_fqn(item, expected)) return true;
                    }
                },
                .code_block => {},
            }
        }
    }
    return false;
}

fn inlines_have_ref_fqn(inlines: []const model.DocComment.Inline, expected: []const u8) bool {
    for (inlines) |inl| {
        switch (inl) {
            .ref => |r| {
                if (std.mem.eql(u8, r.fqn, expected)) return true;
            },
            .emphasis => |e| {
                if (inlines_have_ref_fqn(e.content, expected)) return true;
            },
            .link => |l| {
                if (inlines_have_ref_fqn(l.content, expected)) return true;
            },
            .text, .code => {},
        }
    }
    return false;
}

fn has_code_value(docs: model.DocComment, expected: []const u8) bool {
    for (docs.sections) |section| {
        for (section.blocks) |block| {
            switch (block) {
                .paragraph => |paragraph| {
                    if (inlines_have_code_value(paragraph.content, expected)) return true;
                },
                .unordered_list => |list| {
                    for (list.items) |item| {
                        if (inlines_have_code_value(item, expected)) return true;
                    }
                },
                .ordered_list => |list| {
                    for (list.items) |item| {
                        if (inlines_have_code_value(item, expected)) return true;
                    }
                },
                .code_block => {},
            }
        }
    }
    return false;
}

fn inlines_have_code_value(inlines: []const model.DocComment.Inline, expected: []const u8) bool {
    for (inlines) |inl| {
        switch (inl) {
            .code => |code| {
                if (std.mem.eql(u8, code.value, expected)) return true;
            },
            .emphasis => |e| {
                if (inlines_have_code_value(e.content, expected)) return true;
            },
            .link => |l| {
                if (inlines_have_code_value(l.content, expected)) return true;
            },
            .text, .ref => {},
        }
    }
    return false;
}
