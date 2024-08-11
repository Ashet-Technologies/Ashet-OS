const std = @import("std");

// I/O Operation

pub fn Generic_ARC(comptime Type: type) type {
    return extern struct {
        const ARC = @This();

        type: Type,
        next: ?*ARC,
        tag: usize, // user specified data

        kernel_data: [7]usize = undefined, // internal data used by the kernel to store

        pub fn cast(comptime T: type, arc: *ARC) *T {
            std.debug.assert(arc.type == T.arc_type);
            return @fieldParentPtr("arc", arc);
        }

        fn undefined_default(comptime T: type) ?*const anyopaque {
            comptime {
                const value: T = undefined;
                return @ptrCast(&value);
            }
        }

        pub fn is_arc(comptime T: type) bool {
            // hit me with your best shot:
            return @hasField(T, "arc");
        }
    };
}
