const std = @import("std");

// I/O Operation

pub fn Generic_ARC(comptime Type: type) type {
    return extern struct {
        const ARC = @This();

        type: Type,
        tag: usize, // user specified data

        pub fn cast(arc: *ARC, comptime T: type) *T {
            comptime std.debug.assert(is_arc(T));
            std.debug.assert(arc.type == T.arc_type);
            return @fieldParentPtr("arc", arc);
        }

        pub fn is_arc(comptime T: type) bool {
            if (!@hasField(T, "arc")) return false;
            if (std.meta.fieldInfo(T, .arc).type != ARC) return false;

            if (!@hasDecl(T, "Inputs")) return false;
            if (!@hasDecl(T, "Outputs")) return false;
            if (!@hasDecl(T, "Error")) return false;
            if (!@hasDecl(T, "arc_type")) return false;
            if (@TypeOf(T.arc_type) != Type) return false;

            return true;
        }
    };
}
