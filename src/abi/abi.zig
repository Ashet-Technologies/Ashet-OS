const std = @import("std");

/// The offset in memory where an application will be loaded to.
/// The entry point of an application is also at this address,
/// but `libashet` a tiny load stub that jumps to `_start`.
pub const application_load_address = 0x80800000;

/// A structure containing all system calls Ashet OS provides.
///
/// As Ashet OS is single-threaded by design and supports no thread local
/// structures, we use the `tp` register to store a fast-path to the syscall
/// interface.
/// This allows several benefits:
/// - Ashet OS can freely place this structure in RAM or ROM.
/// - A syscall is just an indirect call with the minimum number of only two instructions
pub const SysCallInterface = extern struct {
    pub inline fn get() *align(16) const SysCallInterface {
        return asm (""
            : [ptr] "={tp}" (-> *align(16) SysCallInterface),
        );
    }

    magic: u32 = 0x9a9d5a1b, // chosen by a fair dice roll

    console: Console,

    pub const Console = extern struct {
        print: fn ([*]const u8, usize) callconv(.C) void,
    };
};

pub const ExitCode = struct {
    pub const success = @as(u32, 0);
    pub const failure = @as(u32, 1);

    pub const killed = ~@as(u32, 0);
};

pub const ThreadFunction = fn (?*anyopaque) callconv(.C) u32;
