const std = @import("std");

pub fn reify_function(comptime func: anytype) @TypeOf(_reify_function(func).invoke) {
    return _reify_function(func).invoke;
}

fn _reify_function(comptime func: anytype) type {
    //
    const F = @TypeOf(func);
    const fnInfo = @typeInfo(F).@"fn";

    std.debug.assert(fnInfo.params.len == 1);

    const ArgTuple = fnInfo.params[0].type.?;
    const CC = fnInfo.calling_convention;

    const arg_info = @typeInfo(ArgTuple).@"struct";
    std.debug.assert(arg_info.is_tuple);

    var a_backing: [arg_info.fields.len]type = undefined;
    for (&a_backing, arg_info.fields) |*out, in| {
        out.* = in.type;
    }

    const A = a_backing;
    const R = fnInfo.return_type.?;

    return struct {
        pub const invoke = @field(@This(), std.fmt.comptimePrint("n{}", .{A.len}));

        fn n0() callconv(CC) R {
            return func(.{});
        }

        fn n1(a0: A[0]) callconv(CC) R {
            return func(.{a0});
        }

        fn n2(a0: A[0], a1: A[1]) callconv(CC) R {
            return func(.{ a0, a1 });
        }

        fn n3(a0: A[0], a1: A[1], a2: A[2]) callconv(CC) R {
            return func(.{ a0, a1, a2 });
        }

        fn n4(a0: A[0], a1: A[1], a2: A[2], a3: A[3]) callconv(CC) R {
            return func(.{ a0, a1, a2, a3 });
        }
    };
}
