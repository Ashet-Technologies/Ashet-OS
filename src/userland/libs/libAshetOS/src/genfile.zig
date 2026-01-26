const std = @import("std");

pub fn main() !u8 {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    std.debug.assert(argv.len >= 1);

    var stdout = std.io.getStdOut().writer();

    for (argv[1..]) |data| {
        try stdout.print("{s}\n", .{data});
    }

    return 0;
}

// # The directory that contains `stdlib.h`.
// # On POSIX-like systems, include directories be found with: `cc -E -Wp,-v -xc /dev/null`
// include_dir=/usr/include

// # The system-specific include directory. May be the same as `include_dir`.
// # On Windows it's the directory that includes `vcruntime.h`.
// # On POSIX it's the directory that includes `sys/errno.h`.
// sys_include_dir=/usr/include

// # The directory that contains `crt1.o` or `crt2.o`.
// # On POSIX, can be found with `cc -print-file-name=crt1.o`.
// # Not needed when targeting MacOS.
// crt_dir=/usr/lib/gcc/x86_64-pc-linux-gnu/15.2.1/../../../../lib

// # The directory that contains `vcruntime.lib`.
// # Only needed when targeting MSVC on Windows.
// msvc_lib_dir=

// # The directory that contains `kernel32.lib`.
// # Only needed when targeting MSVC on Windows.
// kernel32_lib_dir=

// # The directory that contains `crtbeginS.o` and `crtendS.o`
// # Only needed when targeting Haiku.
// gcc_dir=
