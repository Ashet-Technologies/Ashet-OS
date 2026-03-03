const std = @import("std");
const abi_parser = @import("abi-parser");
const model = abi_parser.model;

test "doc references resolve to contained syscall elements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const abi_source = try std.fs.cwd().readFileAlloc(
        allocator,
        "tests/doc_ref_resolution.abi",
        1 << 20,
    );

    var tokenizer: abi_parser.syntax.Tokenizer = .init(abi_source, "tests/doc_ref_resolution.abi");
    var parser: abi_parser.syntax.Parser = .{
        .allocator = allocator,
        .core = .init(&tokenizer),
    };
    const ast_document = try parser.accept_document();
    const analyzed_document = try abi_parser.sema.analyze(allocator, ast_document, null);

    const await_completion = find_syscall_by_fqn(
        analyzed_document.syscalls,
        "overlapped.await_completion",
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expect(has_ref_fqn(
        await_completion.docs,
        "overlapped.await_completion.completed",
    ));
    try std.testing.expect(has_ref_fqn(
        await_completion.docs,
        "overlapped.await_completion.completed_count",
    ));
    try std.testing.expect(has_ref_fqn(
        await_completion.docs,
        "overlapped.await_completion_of",
    ));
    try std.testing.expect(!has_ref_fqn(await_completion.docs, "completed"));

    const await_completion_of = find_syscall_by_fqn(
        analyzed_document.syscalls,
        "overlapped.await_completion_of",
    ) orelse return error.TestUnexpectedResult;

    try std.testing.expect(has_ref_fqn(
        await_completion_of.docs,
        "overlapped.await_completion",
    ));
    try std.testing.expect(has_ref_fqn(
        await_completion_of.docs,
        "overlapped.await_completion_of.events",
    ));
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
