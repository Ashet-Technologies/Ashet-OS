const std = @import("std");
const builtin = @import("builtin");

const is_debug_mode = (builtin.mode == .Debug);
const is_safe_mode = switch (builtin) {
    .Debug, .ReleaseSafe => true,
    .ReleaseSmall, .ReleaseFast => false,
};

pub const Hardening = enum {
    /// No hardening is done
    none,

    /// A basic check is done if a node is contained in a list or not.
    ///
    /// If the lists can be pinned
    basic,

    /// A check is performed if the node is in the associated list.
    full,
};

pub const LinkedListOptions = struct {
    /// If this is set, the linked list is hardened against
    hardening: Hardening = switch (builtin.mode) {
        .Debug => .full,
        .ReleaseSafe => .basic,
        .ReleaseSmall, .ReleaseFast => .none,
    },

    /// If this is true, a linked list object must not be moved in memory
    /// and the implementation can assume the address of a linked list object
    /// won't change over its lifetime.
    address_pinning: bool = false,

    /// This type can be used to create additional variants of linked lists with
    /// the same value type.
    ///
    /// This is useful if those lists must not be confused at compile time.
    tag: type = void,
};

pub fn DoublyLinkedList(comptime T: type, comptime options: LinkedListOptions) type {
    return struct {
        const List = @This();

        const no_list_sentinel = switch (options.hardening) {
            .none => 0,
            .basic, .full => if (options.address_pinning)
                null
            else
                false,
        };

        /// Node inside the linked list wrapping the actual data.
        pub const Node = struct {
            comptime {
                // Make `Node` depend on options.tag so we're having a
                _ = options.tag;
            }

            data: T,

            prev: ?*Node = null,
            next: ?*Node = null,

            /// Hardening sentinel.
            /// Stores additional information if a node is currently in a list
            /// and depending on the mode, in which list.
            sentinel: switch (options.hardening) {
                // We use a u0 here as it takes up no memory, but contrary to void supports == operator
                .none => u0,
                .basic, .full => if (options.address_pinning)
                    ?*const List
                else
                    bool,
            } = no_list_sentinel,
        };

        first: ?*Node = null,
        last: ?*Node = null,
        len: usize = 0,

        /// Insert a new node after an existing one.
        ///
        /// Arguments:
        ///     node: Pointer to a node in the list.
        ///     new_node: Pointer to the new node to insert.
        pub fn insertAfter(list: *List, node: *Node, new_node: *Node) void {
            assert_consistency(list);
            defer assert_consistency(list);

            std.debug.assert(assert_node_unassigned(new_node));
            defer std.debug.assert(!assert_node_unassigned(new_node));

            std.debug.assert(hard_test_contains(list, node));
            defer std.debug.assert(hard_test_contains(list, node));

            std.debug.assert(!hard_test_contains(list, new_node));
            defer std.debug.assert(hard_test_contains(list, new_node));

            new_node.prev = node;
            new_node.next = node.next;
            new_node.sentinel = list.sentinel();

            if (node.next) |next_node| {
                // Intermediate node.
                std.debug.assert(node != list.last);
                next_node.prev = new_node;
            } else {
                // Last element of the list.
                std.debug.assert(node == list.last);
                list.last = new_node;
            }
            node.next = new_node;

            list.len += 1;
        }

        /// Insert a new node before an existing one.
        ///
        /// Arguments:
        ///     node: Pointer to a node in the list.
        ///     new_node: Pointer to the new node to insert.
        pub fn insertBefore(list: *List, node: *Node, new_node: *Node) void {
            assert_consistency(list);
            defer assert_consistency(list);

            std.debug.assert(assert_node_unassigned(new_node));
            defer std.debug.assert(!assert_node_unassigned(new_node));

            std.debug.assert(hard_test_contains(list, node));
            defer std.debug.assert(hard_test_contains(list, node));

            std.debug.assert(!hard_test_contains(list, new_node));
            defer std.debug.assert(hard_test_contains(list, new_node));

            new_node.next = node;
            new_node.sentinel = list.sentinel();
            if (node.prev) |prev_node| {
                // Intermediate node.
                new_node.prev = prev_node;
                prev_node.next = new_node;
            } else {
                // First element of the list.
                new_node.prev = null;
                list.first = new_node;
            }
            node.prev = new_node;

            list.len += 1;
        }

        /// Concatenate list2 onto the end of list1, removing all entries from the former.
        ///
        /// Arguments:
        ///     list1: the list to concatenate onto
        ///     list2: the list to be concatenated
        pub fn concatByMoving(list1: *List, list2: *List) void {
            const l1_len = list1.len;
            const l2_len = list2.len;

            defer std.debug.assert(list1.len == l1_len + l2_len);
            defer std.debug.assert(list2.len == 0);

            assert_consistency(list1);
            assert_consistency(list2);
            defer assert_consistency(list1);
            defer assert_consistency(list2);

            const l2_first = list2.first orelse return;
            if (list1.last) |l1_last| {
                l1_last.next = list2.first;
                l2_first.prev = list1.last;
                list1.len += list2.len;
            } else {
                // list1 was empty
                list1.first = list2.first;
                list1.len = list2.len;
            }
            list1.last = list2.last;
            list2.first = null;
            list2.last = null;
            list2.len = 0;

            if (options.hardening != .none) {
                // If we have hardening, we have to update the
                // sentinels of the lists:

                var iter: ?*Node = l2_first;
                while (iter) |node| : (iter = node.next) {
                    node.sentinel = list1.sentinel();
                }
            }
        }

        /// Insert a new node at the end of the list.
        ///
        /// Arguments:
        ///     new_node: Pointer to the new node to insert.
        pub fn append(list: *List, new_node: *Node) void {
            assert_consistency(list);
            defer assert_consistency(list);

            std.debug.assert(assert_node_unassigned(new_node));
            defer std.debug.assert(!assert_node_unassigned(new_node));

            std.debug.assert(!hard_test_contains(list, new_node));
            defer std.debug.assert(hard_test_contains(list, new_node));

            if (list.last) |last| {
                // Insert after last.
                list.insertAfter(last, new_node);
            } else {
                // Empty list.
                list.prepend(new_node);
            }
        }

        /// Insert a new node at the beginning of the list.
        ///
        /// Arguments:
        ///     new_node: Pointer to the new node to insert.
        pub fn prepend(list: *List, new_node: *Node) void {
            assert_consistency(list);
            defer assert_consistency(list);

            std.debug.assert(assert_node_unassigned(new_node));
            defer std.debug.assert(!assert_node_unassigned(new_node));

            std.debug.assert(!hard_test_contains(list, new_node));
            defer std.debug.assert(hard_test_contains(list, new_node));

            if (list.first) |first| {
                // Insert before first.
                list.insertBefore(first, new_node);
            } else {
                // Empty list.
                list.first = new_node;
                list.last = new_node;
                new_node.prev = null;
                new_node.next = null;

                list.len = 1;
            }
            new_node.sentinel = list.sentinel();
        }

        /// Remove a node from the list.
        ///
        /// Arguments:
        ///     node: Pointer to the node to be removed.
        pub fn remove(list: *List, node: *Node) void {
            assert_consistency(list);
            defer assert_consistency(list);

            std.debug.assert(!assert_node_unassigned(node));
            defer std.debug.assert(assert_node_unassigned(node));

            std.debug.assert(hard_test_contains(list, node));
            defer std.debug.assert(!hard_test_contains(list, node));

            if (node.prev) |prev_node| {
                // Intermediate node.
                prev_node.next = node.next;
            } else {
                // First element of the list.
                list.first = node.next;
            }

            if (node.next) |next_node| {
                // Intermediate node.
                next_node.prev = node.prev;
            } else {
                // Last element of the list.
                list.last = node.prev;
            }

            node.sentinel = no_list_sentinel;
            node.prev = null;
            node.next = null;

            list.len -= 1;
            std.debug.assert(list.len == 0 or (list.first != null and list.last != null));
        }

        /// Remove and return the last node in the list.
        ///
        /// Returns:
        ///     A pointer to the last node in the list.
        pub fn pop(list: *List) ?*Node {
            assert_consistency(list);
            defer assert_consistency(list);

            const last = list.last orelse return null;
            list.remove(last);
            return last;
        }

        /// Remove and return the first node in the list.
        ///
        /// Returns:
        ///     A pointer to the first node in the list.
        pub fn popFirst(list: *List) ?*Node {
            assert_consistency(list);
            defer assert_consistency(list);

            const first = list.first orelse return null;
            list.remove(first);
            return first;
        }

        /// Returns `true` if the `list` contains the given `node`.
        ///
        /// NOTE: This function performs a linear search.
        pub fn contains(list: *const List, needle: *const Node) bool {
            assert_consistency(list);

            var iter = list.first;
            while (iter) |haystack| : (iter = haystack.next) {
                if (haystack == needle)
                    return true;
            }
            return false;
        }

        fn assert_consistency(list: *const List) void {
            switch (options.hardening) {
                .none => {},

                .basic => {
                    // This only performs constant-time checks:
                    if (list.first) |first| {
                        std.debug.assert(first.prev == null);
                        std.debug.assert(list.len > 0);
                    }
                    if (list.last) |last| {
                        std.debug.assert(last.next == null);
                        std.debug.assert(list.len > 0);
                    }
                    switch (list.len) {
                        0 => {
                            std.debug.assert(list.first == null);
                            std.debug.assert(list.last == null);
                        },
                        1 => {
                            std.debug.assert(list.first != null);
                            std.debug.assert(list.last != null);
                            std.debug.assert(list.first == list.last);
                            std.debug.assert(list.first.?.next == null);
                            std.debug.assert(list.first.?.prev == null);
                        },
                        2 => {
                            std.debug.assert(list.first != null);
                            std.debug.assert(list.last != null);
                            std.debug.assert(list.first != list.last);
                            std.debug.assert(list.first.?.next == list.last);
                            std.debug.assert(list.first.?.prev == null);

                            std.debug.assert(list.last.?.next == null);
                            std.debug.assert(list.last.?.prev == list.first);
                        },
                        else => {
                            std.debug.assert(list.first != null);
                            std.debug.assert(list.last != null);
                            std.debug.assert(list.first != list.last);

                            std.debug.assert(list.first.?.next != list.last);
                            std.debug.assert(list.first.?.prev == null);

                            std.debug.assert(list.last.?.next == null);
                            std.debug.assert(list.last.?.prev != list.first);
                        },
                    }
                },

                .full => {

                    // Assert that the list is consistent over forward iteration:
                    {
                        var previous: ?*Node = null;
                        var iter = list.first;
                        var count: usize = 0;
                        while (iter) |node| : (iter = node.next) {
                            std.debug.assert(node.prev == previous);

                            // these checks are only performed once per node:
                            {
                                std.debug.assert(node.sentinel == list.sentinel());
                                std.debug.assert(node.prev != node);
                                std.debug.assert(node.next != node);
                                std.debug.assert((node.next == null and node.prev == null) or (node.next != node.prev));
                                if (node.next) |_next| {
                                    std.debug.assert(_next.prev == node);
                                }
                                if (node.prev) |_prev| {
                                    std.debug.assert(_prev.next == node);
                                }
                            }

                            previous = node;
                            count += 1;
                        }
                        std.debug.assert(previous == list.last);
                        std.debug.assert(count == list.len);
                    }

                    // Assert that the list is consistent over backward iteration:
                    {
                        var next: ?*Node = null;
                        var iter = list.last;
                        var count: usize = 0;
                        while (iter) |node| : (iter = node.prev) {
                            std.debug.assert(node.next == next);

                            next = node;
                            count += 1;
                        }
                        std.debug.assert(next == list.first);
                        std.debug.assert(count == list.len);
                    }
                },
            }
        }

        fn assert_node_unassigned(node: *const Node) bool {
            return switch (options.hardening) {
                .none => true,
                .basic, .full => {
                    const unassigned = (node.sentinel == no_list_sentinel);
                    if (unassigned) {
                        // Nodes must be reset if not assigned!
                        std.debug.assert(node.prev == null);
                        std.debug.assert(node.next == null);
                    }
                    return unassigned;
                },
            };
        }

        /// Asserts that `node` is contained in `list` depending on the hardening mode.
        fn hard_test_contains(list: *const List, node: *const Node) bool {
            switch (options.hardening) {
                .none => return true,

                .basic => return (node.sentinel == list.sentinel()),

                .full => {
                    const sentinel_ok = (node.sentinel == list.sentinel());
                    const search_ok = list.contains(node);

                    std.debug.assert(sentinel_ok == search_ok);

                    return sentinel_ok;
                },
            }
        }

        /// Returns the hardening sentinel for this list depending on the sentinel mode.
        inline fn sentinel(list: *const List) switch (options.hardening) {
            // We use a u0 here as it takes up no memory, but contrary to void supports == operator
            .none => u0,
            .basic, .full => if (options.address_pinning)
                ?*const List
            else
                bool,
        } {
            return switch (options.hardening) {
                .none => 0,
                .basic, .full => if (options.address_pinning)
                    list
                else
                    true,
            };
        }

        fn log_list_structure(list: *const List) void {
            std.log.err("List {}: first={}, last={}", .{ fmt_addr(list), fmt_addr(list.first), fmt_addr(list.last) });

            var iter = list.first;
            while (iter) |node| : (iter = node.next) {
                log_node_structure(node);
            }
        }

        fn log_node_structure(node: *const Node) void {
            std.log.err("Node {}: prev={}, next={}, sentinel={}", .{
                fmt_addr(node), fmt_addr(node.prev), fmt_addr(node.next), if (options.address_pinning)
                    fmt_addr(node.sentinel)
                else
                    node.sentinel,
            });
        }

        fn fmt_addr(ptr: ?*const anyopaque) Addr {
            return .{ .ptr = ptr };
        }

        const Addr = struct {
            ptr: ?*const anyopaque,

            pub fn format(addr: Addr, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
                _ = fmt;
                _ = opt;
                if (addr.ptr) |ptr| {
                    try writer.print("0x{X:0>8}", .{
                        @intFromPtr(ptr),
                    });
                } else {
                    try writer.writeAll("<null>");
                }
            }
        };
    };
}

test "basic DoublyLinkedList test" {
    const L = DoublyLinkedList(u32, .{
        .address_pinning = true,
        .hardening = .full,
    });
    var list = L{};

    var one = L.Node{ .data = 1 };
    var two = L.Node{ .data = 2 };
    var three = L.Node{ .data = 3 };
    var four = L.Node{ .data = 4 };
    var five = L.Node{ .data = 5 };

    list.append(&two); // {2}
    list.append(&five); // {2, 5}
    list.prepend(&one); // {1, 2, 5}
    list.insertBefore(&five, &four); // {1, 2, 4, 5}
    list.insertAfter(&two, &three); // {1, 2, 3, 4, 5}

    // Traverse forwards.
    {
        var it = list.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try std.testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try std.testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    _ = list.popFirst(); // {2, 3, 4, 5}
    _ = list.pop(); // {2, 3, 4}
    list.remove(&three); // {2, 4}

    try std.testing.expect(list.first.?.data == 2);
    try std.testing.expect(list.last.?.data == 4);
    try std.testing.expect(list.len == 2);
}

test "DoublyLinkedList concatenation" {
    const L = DoublyLinkedList(u32, .{
        .address_pinning = true,
        .hardening = .full,
    });
    var list1 = L{};
    var list2 = L{};

    var one = L.Node{ .data = 1 };
    var two = L.Node{ .data = 2 };
    var three = L.Node{ .data = 3 };
    var four = L.Node{ .data = 4 };
    var five = L.Node{ .data = 5 };

    list1.append(&one);
    list1.append(&two);
    list2.append(&three);
    list2.append(&four);
    list2.append(&five);

    list1.concatByMoving(&list2);

    try std.testing.expect(list1.last == &five);
    try std.testing.expect(list1.len == 5);
    try std.testing.expect(list2.first == null);
    try std.testing.expect(list2.last == null);
    try std.testing.expect(list2.len == 0);

    // Traverse forwards.
    {
        var it = list1.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try std.testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list1.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try std.testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    // Swap them back, this verifies that concatenating to an empty list works.
    list2.concatByMoving(&list1);

    // Traverse forwards.
    {
        var it = list2.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try std.testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list2.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try std.testing.expect(node.data == (6 - index));
            index += 1;
        }
    }
}
