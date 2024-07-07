const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const MI_SECURE = b.option(bool, "MI_SECURE", "Use full security mitigations (like guard pages, allocation randomization, double-free mitigation, and free-list corruption detection)") orelse false;
    const MI_DEBUG_FULL = b.option(bool, "MI_DEBUG_FULL", "Use full internal heap invariant checking in DEBUG mode (expensive)") orelse false;
    const MI_PADDING = b.option(bool, "MI_PADDING", "Enable padding to detect heap block overflow (always on in DEBUG or SECURE mode, or with Valgrind/ASAN)") orelse false;
    const MI_OVERRIDE = b.option(bool, "MI_OVERRIDE", "Override the standard malloc interface (e.g. define entry points for malloc() etc)") orelse true;
    const MI_XMALLOC = b.option(bool, "MI_XMALLOC", "Enable abort() call on memory allocation failure by default") orelse false;
    const MI_SHOW_ERRORS = b.option(bool, "MI_SHOW_ERRORS", "Show error and warning messages by default (only enabled by default in DEBUG mode)") orelse false;
    const MI_TRACK_VALGRIND = b.option(bool, "MI_TRACK_VALGRIND", "Compile with Valgrind support (adds a small overhead)") orelse false;
    const MI_TRACK_ASAN = b.option(bool, "MI_TRACK_ASAN", "Compile with address sanitizer support (adds a small overhead)") orelse false;
    const MI_TRACK_ETW = b.option(bool, "MI_TRACK_ETW", "Compile with Windows event tracing (ETW) support (adds a small overhead)") orelse false;
    // const MI_USE_CXX = b.option(bool, "MI_USE_CXX", "Use the C++ compiler to compile the library (instead of the C compiler)") orelse false;
    // const MI_SEE_ASM = b.option(bool, "MI_SEE_ASM", "Generate assembly files") orelse false;
    const MI_OSX_INTERPOSE = b.option(bool, "MI_OSX_INTERPOSE", "Use interpose to override standard malloc on macOS") orelse true;
    const MI_OSX_ZONE = b.option(bool, "MI_OSX_ZONE", "Use malloc zone to override standard malloc on macOS") orelse true;
    const MI_WIN_REDIRECT = b.option(bool, "MI_WIN_REDIRECT", "Use redirection module ('mimalloc-redirect') on Windows if compiling mimalloc as a DLL") orelse true;
    const MI_LOCAL_DYNAMIC_TLS = b.option(bool, "MI_LOCAL_DYNAMIC_TLS", "Use slightly slower, dlopen-compatible TLS mechanism (Unix)") orelse false;
    // const MI_LIBC_MUSL = b.option(bool, "MI_LIBC_MUSL", "Set this when linking with musl libc") orelse false;
    // const MI_BUILD_SHARED = b.option(bool, "MI_BUILD_SHARED", "Build shared library") orelse true;
    // const MI_BUILD_STATIC = b.option(bool, "MI_BUILD_STATIC", "Build static library") orelse true;
    // const MI_BUILD_OBJECT = b.option(bool, "MI_BUILD_OBJECT", "Build object library") orelse true;
    // const MI_BUILD_TESTS = b.option(bool, "MI_BUILD_TESTS", "Build test executables") orelse true;
    const MI_DEBUG_TSAN = b.option(bool, "MI_DEBUG_TSAN", "Build with thread sanitizer (needs clang)") orelse false;
    // const MI_DEBUG_UBSAN = b.option(bool, "MI_DEBUG_UBSAN", "Build with undefined-behavior sanitizer (needs clang++)") orelse false;
    const MI_SKIP_COLLECT_ON_EXIT = b.option(bool, "MI_SKIP_COLLECT_ON_EXIT", "Skip collecting memory on program exit") orelse false;
    const MI_NO_PADDING = b.option(bool, "MI_NO_PADDING", "Force no use of padding even in DEBUG mode etc.") orelse false;
    // const MI_INSTALL_TOPLEVEL = b.option(bool, "MI_INSTALL_TOPLEVEL", "Install directly into $CMAKE_INSTALL_PREFIX instead of PREFIX/lib/mimalloc-version") orelse false;
    const MI_NO_THP = b.option(bool, "MI_NO_THP", "Disable transparent huge pages support on Linux/Android for the mimalloc process only") orelse false;

    const lib = b.addStaticLibrary(.{
        .name = "mimalloc",
        .target = target,
        .optimize = optimize,
        .pic = true,
        .link_libc = true,
    });

    var flags = std.ArrayList([]const u8).init(b.allocator);
    defer flags.deinit();

    try flags.appendSlice(&.{
        "-std=c11",
        "-Wall",
        "-Wextra",
        "-Wpedantic",
    });

    var sources = try std.ArrayList([]const u8).initCapacity(b.allocator, mimalloc_sources.len);
    defer sources.deinit();

    sources.appendSlice(&mimalloc_sources) catch unreachable;

    if (MI_OVERRIDE) {
        if (target.result.isDarwin()) {
            if (MI_OSX_ZONE) {
                try sources.append("src/prim/osx/alloc-override-zone.c");
                lib.defineCMacro("MI_OSX_ZONE", null);
            }
            if (MI_OSX_INTERPOSE) {
                lib.defineCMacro("MI_OSX_INTERPOSE", null);
            }
        }
    }

    if (target.result.os.tag == .windows) {
        if (target.result.cpu.arch.isARM()) @panic("Cannot use redirection on Windows ARM");
        if (!MI_WIN_REDIRECT) {
            lib.defineCMacro("MI_WIN_NOREDIRECT", null);
        }
    }

    if (MI_SECURE) lib.defineCMacro("MI_SECURE", "4");
    if (MI_TRACK_VALGRIND) lib.defineCMacro("MI_TRACK_VALGRIND", null);

    if (MI_TRACK_ASAN) {
        if (target.result.isDarwin() and MI_OVERRIDE) @panic("Cannot enable address sanitizer support on macOS if MI_OVERRIDE is true");
        if (MI_TRACK_VALGRIND) @panic("Cannot enable address sanitizer support with also Valgrind support enabled");
        lib.defineCMacro("MI_TRACK_ASAN", null);
        try flags.append("-fsanitize=address");
    }

    if (MI_TRACK_ETW) {
        if (target.result.os.tag != .windows) @panic("Can only enable ETW support on Windows");
        if (MI_TRACK_VALGRIND or MI_TRACK_ASAN) @panic("Cannot enable ETW support with also Valgrind or ASAN support enabled");
        lib.defineCMacro("MI_TRACK_ETW", null);
    }

    if (MI_SKIP_COLLECT_ON_EXIT) lib.defineCMacro("MI_SKIP_COLLECT_ON_EXIT", null);
    if (MI_DEBUG_FULL) lib.defineCMacro("MI_DEBUG", "3");
    if (MI_NO_PADDING) {
        lib.defineCMacro("MI_PADDING", "0");
    } else if (MI_PADDING) {
        lib.defineCMacro("MI_PADDING", "1");
    }
    if (MI_XMALLOC) lib.defineCMacro("MI_XMALLOC", null);
    if (MI_SHOW_ERRORS) lib.defineCMacro("MI_SHOW_ERRORS", null);

    if (MI_DEBUG_TSAN) {
        lib.defineCMacro("MI_TSAN", null);
        try flags.appendSlice(&.{ "-fsanitize=thread", "-g", "-O1" });
    }

    if (target.result.isAndroid() or target.result.os.tag == .linux) {
        if (MI_NO_THP) lib.defineCMacro("MI_NO_THP", null);
    }

    if (target.result.isMusl()) lib.defineCMacro("MI_LIBC_MUSL", null);

    try flags.appendSlice(&.{
        "-Wno-unknown-pragmas",
        "-fvisibility=hidden",
        "-Wstrict-prototypes",
        "-Wno-static-in-inline",
    });

    if (target.result.os.tag != .haiku) {
        if (MI_LOCAL_DYNAMIC_TLS) {
            try flags.append("-ftls-model=local-dynamic");
        } else {
            if (target.result.isMusl()) {
                try flags.append("-ftls-model=local-dynamic");
            } else {
                try flags.append("-ftls-model=initial-exec");
            }
        }
        if (MI_OVERRIDE) try flags.append("-fno-builtin-malloc");
    }

    if (target.result.isMinGW()) {
        lib.defineCMacro("_WIN32_WINNT", "0x600");
    }

    if (target.result.os.tag == .windows) {
        lib.linkSystemLibrary("psapi");
        lib.linkSystemLibrary("shell32");
        lib.linkSystemLibrary("user32");
        lib.linkSystemLibrary("advapi32");
        lib.linkSystemLibrary("bcrypt");
    } else {
        // TODO: Find a way to link them conditionally if they exist
        // lib.linkSystemLibrary("pthread");
        // lib.linkSystemLibrary("rt");
        // lib.linkSystemLibrary("atomic");
    }

    const upstream = b.dependency("mimalloc", .{});
    lib.addCSourceFiles(.{
        .root = upstream.path("src"),
        .files = sources.items,
        .flags = flags.items,
    });
    lib.addIncludePath(upstream.path("include"));

    lib.installHeader(upstream.path("include/mimalloc.h"), "mimalloc.h");
    lib.installHeader(upstream.path("include/mimalloc-override.h"), "mimalloc-override.h");
    lib.installHeader(upstream.path("include/mimalloc-new-delete.h"), "mimalloc-new-delete.h");

    b.installArtifact(lib);
}

const mimalloc_sources = [_][]const u8{
    "alloc.c",
    "alloc-aligned.c",
    "alloc-posix.c",
    "arena.c",
    "bitmap.c",
    "heap.c",
    "init.c",
    "libc.c",
    "options.c",
    "os.c",
    "page.c",
    "random.c",
    "segment.c",
    "segment-map.c",
    "stats.c",
    "prim/prim.c",
};
