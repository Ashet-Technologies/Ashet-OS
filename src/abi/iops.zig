const std = @import("std");
const error_set = @import("error_set.zig");

// I/O Operation

pub fn Generic_IOP(comptime Type: type) type {
    return extern struct {
        const IOP = @This();

        type: Type,
        next: ?*IOP,
        tag: usize, // user specified data

        kernel_data: [7]usize = undefined, // internal data used by the kernel to store

        pub const Definition = struct {
            type: Type,
            @"error": type,
            outputs: type = struct {},
            inputs: type = struct {},
        };

        /// Defines a new IO operation type.
        pub fn define(comptime def: Definition) type {
            if (!error_set.isErrorSet(def.@"error")) {
                @compileError("IOP.define expects .error to be a type created by ErrorSet()!");
            }

            const inputs = @typeInfo(def.inputs).Struct.fields;
            const outputs = @typeInfo(def.outputs).Struct.fields;

            const inputs_augmented = @Type(.{
                .Struct = .{
                    .layout = .Extern,
                    .fields = inputs,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });

            var output_fields = outputs[0..outputs.len].*;

            for (&output_fields) |*fld| {
                if (fld.default_value != null) {
                    @compileError(std.fmt.comptimePrint("IOP outputs are not allowed to have default values. {s}/{s} has one.", .{
                        @tagName(def.type),
                        fld.name,
                    }));
                }
                fld.default_value = undefinedDefaultFor(fld.type);
            }

            const outputs_augmented = @Type(.{
                .Struct = .{
                    .layout = .Extern,
                    .fields = &output_fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });

            return extern struct {
                const Self = @This();

                /// Marker used to recognize types as I/O ops.
                /// This marker cannot be accessed outside this file, so *all* IOPs must be
                /// defined in this file.
                /// This allows a certain safety against programming mistakes, as a foreign type cannot be accidently marked as an IOP.
                const iop_marker = IOP_Tag;

                pub const iop_type = def.type;

                pub const Inputs = inputs_augmented;
                pub const Outputs = outputs_augmented;
                pub const ErrorSet = def.@"error";
                pub const Error = Self.ErrorSet.Error;

                iop: IOP = .{
                    .type = def.type,
                    .next = null,
                    .tag = 0,
                    .kernel_data = undefined,
                },
                @"error": Self.ErrorSet.Enum = undefined,
                inputs: Inputs,
                outputs: Outputs = undefined,

                pub fn new(inputs_: Inputs) Self {
                    return Self{ .inputs = inputs_ };
                }

                pub fn chain(self: *Self, next: anytype) void {
                    const Next = @TypeOf(next.*);
                    if (comptime !isIOP(Next))
                        @compileError("next must be a pointer to IOP!");
                    const next_ptr: *Next = next;
                    const next_iop: *IOP = &next_ptr.iop;

                    var it: ?*IOP = &self.iop;
                    while (it) |p| : (it = p.next) {
                        if (p == &next_iop) // already in the chain
                            return;

                        if (p.next == null) {
                            p.next = &next_iop;
                            return;
                        }
                    }

                    unreachable;
                }

                pub fn check(val: Self) Error!void {
                    return Self.ErrorSet.throw(val.@"error");
                }

                pub fn setOk(val: *Self) void {
                    val.@"error" = .ok;
                }

                pub fn setError(val: *Self, err: Error) void {
                    val.@"error" = Self.ErrorSet.map(err);
                }
            };
        }

        const IOP_Tag = opaque {};
        pub fn isIOP(comptime T: type) bool {
            return @hasDecl(T, "iop_marker") and (T.iop_marker == IOP_Tag);
        }

        pub fn cast(comptime T: type, iop: *IOP) *T {
            if (comptime !isIOP(T)) @compileError("Only a type created by IOP.define can be passed to cast!");
            std.debug.assert(iop.type == T.iop_type);
            return @fieldParentPtr("iop", iop);
        }

        fn undefinedDefaultFor(comptime T: type) *T {
            comptime var value: T = undefined;
            return &value;
        }
    };
}
