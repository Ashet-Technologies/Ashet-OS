const std = @import("std");

const UNKNOWN = false;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const queue_buffer_size = b.option(u32, "queue-size", "Set the XCB buffer queue size (default is 16384)") orelse 16384;

    const os_tag = target.result.os.tag;

    const is_posix = os_tag.isBSD() or (os_tag == .linux) or os_tag.isDarwin();
    const is_windows = (os_tag == .windows);

    const python_dep = b.dependency("cpython", .{
        .target = @as([]const u8, "x86_64-linux-musl"),
    });

    const python3 = python_dep.artifact("cpython");

    const xcb_proto = b.dependency("xcb_proto", .{});
    const libxcb = b.dependency("libxcb", .{});

    const c_client_py = libxcb.path("src/c_client.py");

    const PACKAGE_STRING = "libxcb 1.17.0";

    const config_h = b.addConfigHeader(.{
        .style = .{ .autoconf = b.path("config.h.in") },
        .include_path = "config.h",
    }, .{
        // from ./configure:
        .PACKAGE = "libxcb",
        .VERSION = "1.17.0",

        .PACKAGE_BUGREPORT = "https://gitlab.freedesktop.org/xorg/lib/libxcb/-/issues",
        .PACKAGE_NAME = "libxcb",
        .PACKAGE_STRING = PACKAGE_STRING,
        .PACKAGE_TARNAME = "libxcb",
        .PACKAGE_URL = "",
        .PACKAGE_VERSION = "1.17.0",
        .PACKAGE_VERSION_MAJOR = 1,
        .PACKAGE_VERSION_MINOR = 17,
        .PACKAGE_VERSION_PATCHLEVEL = 0,

        // Defined if GCC supports the visibility feature
        .GCC_HAS_VISIBILITY = true,

        // Has Wraphelp.c needed for XDM AUTH protocols
        .HASXDMAUTH = UNKNOWN,

        // Define if your platform supports abstract sockets
        .HAVE_ABSTRACT_SOCKETS = UNKNOWN,

        // Define to 1 if you have the <dlfcn.h> header file.
        .HAVE_DLFCN_H = is_posix,

        // getaddrinfo() function is available
        .HAVE_GETADDRINFO = is_posix,

        // Define to 1 if you have the <inttypes.h> header file.
        .HAVE_INTTYPES_H = true,

        // Define to 1 if you have the `is_system_labeled' function.
        .HAVE_IS_SYSTEM_LABELED = UNKNOWN,

        // Define to 1 if you have the `ws2_32' library (-lws2_32).
        .HAVE_LIBWS2_32 = is_windows,

        // Define to 1 if you have the <minix/config.h> header file.
        .HAVE_MINIX_CONFIG_H = (os_tag == .minix),

        // Define if your platform supports sendmsg
        .HAVE_SENDMSG = is_posix,

        // Have the sockaddr_un.sun_len member.
        .HAVE_SOCKADDR_SUN_LEN = is_posix,

        .HAVE_STDINT_H = true,
        .HAVE_STDIO_H = true,
        .HAVE_STDLIB_H = true,
        .HAVE_STRINGS_H = is_posix,
        .HAVE_STRING_H = true,
        .HAVE_SYS_STAT_H = is_posix,
        .HAVE_SYS_TYPES_H = is_posix,

        // Define to 1 if you have the <tsol/label.h> header file.
        .HAVE_TSOL_LABEL_H = UNKNOWN,

        // Define to 1 if you have the <unistd.h> header file.
        .HAVE_UNISTD_H = is_posix,

        // Define to 1 if you have the <wchar.h> header file.
        .HAVE_WCHAR_H = true,

        // Define if not provided by <limits.h>
        .IOV_MAX = 16,

        // Define to the sub-directory where libtool stores uninstalled libraries.
        .LT_OBJDIR = "",

        // Define to 1 if all of the C90 standard headers exist (not just the ones
        // required in a freestanding environment). This macro is provided for
        // backward compatibility; new code need not use it.
        .STDC_HEADERS = false,

        // poll() function is available
        .USE_POLL = UNKNOWN,

        ._ALL_SOURCE = (os_tag == .aix),
        ._DARWIN_C_SOURCE = os_tag.isDarwin(),
        .__EXTENSIONS__ = os_tag.isSolarish(),
        ._GNU_SOURCE = (os_tag == .linux),

        // Enable X/Open compliant socket functions that do not require linking
        // with -lxnet on HP-UX 11.11.
        ._HPUX_ALT_XOPEN_SOCKET_API = false,

        ._MINIX = (os_tag == .minix),
        ._NETBSD_SOURCE = (os_tag == .netbsd),
        ._OPENBSD_SOURCE = (os_tag == .openbsd),

        // Define to 1 if needed for POSIX-compatible behavior.
        ._POSIX_SOURCE = false,
        // Define to 2 if needed for POSIX-compatible behavior.
        ._POSIX_1_SOURCE = false,

        // Enable POSIX-compatible threading on Solaris.
        ._POSIX_PTHREAD_SEMANTICS = os_tag.isSolarish(),

        .__STDC_WANT_IEC_60559_ATTRIBS_EXT__ = false,
        .__STDC_WANT_IEC_60559_BFP_EXT__ = false,
        .__STDC_WANT_IEC_60559_DFP_EXT__ = false,
        .__STDC_WANT_IEC_60559_FUNCS_EXT__ = false,
        .__STDC_WANT_IEC_60559_TYPES_EXT__ = false,
        .__STDC_WANT_LIB_EXT2__ = false,
        .__STDC_WANT_MATH_SPEC_FUNCS__ = false,
        ._TANDEM_SOURCE = false,

        // XCB buffer queue size
        .XCB_QUEUE_BUFFER_SIZE = queue_buffer_size,

        // Number of bits in a file offset, on hosts where this is settable.
        ._FILE_OFFSET_BITS = 64,

        // Define for large files, on AIX-style hosts.
        ._LARGE_FILES = (os_tag == .aix),

        // Defined if needed to expose struct msghdr.msg_control
        ._XOPEN_SOURCE = {},
    });

    const xcb = b.addStaticLibrary(.{
        .name = "xcb",
        .target = target,
        .optimize = optimize,
        .version = std.SemanticVersion{ .major = 1, .minor = 17, .patch = 0 },
    });
    xcb.addConfigHeader(config_h);
    xcb.linkLibC();
    xcb.addIncludePath(libxcb.path("src"));
    xcb.installHeader(libxcb.path("src/xcb.h"), "xcb/xcb.h");

    for (c_sources) |rel_path| {
        xcb.addCSourceFile(.{
            .file = libxcb.path(rel_path),
            .flags = &c_flags,
        });
    }

    for (generated_sources) |gen_source_name| {
        // const c_file_name = b.fmt("{s}.c", .{gen_source_name});
        const xml_path = b.fmt("src/{s}.xml", .{gen_source_name});

        const xproto_xml = xcb_proto.path(xml_path);

        const convert_step = b.addRunArtifact(python3);
        convert_step.setEnvironmentVariable("PYTHONPATH", python_dep.path("Lib").getPath(b));
        convert_step.addFileArg(c_client_py);
        // convert_step.addArg("-c");
        // convert_step.addArg(PACKAGE_STRING);
        // convert_step.addArg("-l");
        // convert_step.addArg("XORG_MAN_PAGE");
        // convert_step.addArg("-s");
        // convert_step.addArg("LIB_MAN_SUFFIX");
        convert_step.addArg("-p"); // adds to python path
        convert_step.addDirectoryArg(xcb_proto.path("."));
        convert_step.addFileArg(xproto_xml);

        xcb.step.dependOn(&convert_step.step);
    }

    b.installArtifact(xcb);
}

const c_flags = [_][]const u8{
    //
};

const c_sources = [_][]const u8{
    "src/xcb_conn.c",
    "src/xcb_xid.c",
    "src/xcb_in.c",
    "src/xcb_auth.c",
    "src/xcb_out.c",
    "src/xcb_util.c",
    "src/xcb_list.c",
    "src/xcb_ext.c",
    // "src/config.h.in",
    // "src/xcbint.h",
    // "src/xcb.h",
    // "src/xcb_windefs.h",
    // "src/xcbext.h",
    // "src/c_client.py",
};

const generated_sources = [_][]const u8{
    "composite",
    "damage",
    "dbe",
    "dpms",
    "dri2",
    "dri3",
    "present",
    "glx",
    "randr",
    "record",
    "render",
    "res",
    "screensaver",
    "shape",
    "shm",
    "sync",
    "xevie",
    "xf86dri",
    "xfixes",
    "xinerama",
    "xinput",
    "xkb",
    "xprint",
    "xselinux",
    "xtest",
    "xv",
    "xvmc",
    "ge",
};
