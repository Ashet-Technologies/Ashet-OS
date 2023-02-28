const std = @import("std");

const ziglibc = @import("vendor/ziglibc/ziglibcbuild.zig");

const FatFS = @import("vendor/zfat/Sdk.zig");

const AshetContext = struct {
    b: *std.build.Builder,
    mkicon: *std.build.LibExeObjStep,
    target: std.zig.CrossTarget,

    fn createAshetApp(ctx: AshetContext, name: []const u8, source: []const u8, maybe_icon: ?[]const u8, optimize: std.builtin.OptimizeMode) *std.build.LibExeObjStep {
        const exe = ctx.b.addExecutable(.{
            .name = ctx.b.fmt("{s}.app", .{name}),
            .root_source_file = .{ .path = source },
            .optimize = optimize,
            .target = ctx.target,
        });

        exe.omit_frame_pointer = false; // this is useful for debugging
        exe.single_threaded = true; // AshetOS doesn't support multithreading in a modern sense
        exe.pie = true; // AshetOS requires PIE executables
        exe.force_pic = true; // which need PIC code
        exe.linkage = .static; // but everything is statically linked, we don't support shared objects
        exe.strip = false; // never strip debug info

        exe.setLinkerScriptPath(.{ .path = "src/libashet/application.ld" });
        exe.addModule("ashet", ctx.b.modules.get("ashet").?);
        exe.addModule("ashet-gui", ctx.b.modules.get("ashet-gui").?); // just add GUI to all apps by default *shrug*
        exe.install();

        const install_step = ctx.b.addInstallArtifact(exe);
        install_step.dest_dir = .{ .custom = "apps" };
        ctx.b.getInstallStep().dependOn(&install_step.step);

        if (maybe_icon) |src_icon| {
            const mkicon = ctx.mkicon.run();

            mkicon.addArg(src_icon);
            mkicon.addArg(ctx.b.fmt("zig-out/apps/{s}.icon", .{name}));
            mkicon.addArg("32x32");

            ctx.b.getInstallStep().dependOn(&mkicon.step);
        }

        return exe;
    }
};

const ziglibc_file = std.build.FileSource{ .path = "vendor/libc/ziglibc.txt" };

fn addBitmap(target: *std.build.LibExeObjStep, mkicon: *std.build.LibExeObjStep, src: []const u8, dst: []const u8, size: []const u8) void {
    const gen = mkicon.run();
    gen.addArg(src);
    gen.addArg(dst);
    gen.addArg(size);
    target.step.dependOn(&gen.step);
}

const machines = @import("src/kernel/machine/all.zig");
const platforms = @import("src/kernel/platform/all.zig");

const MachineID = std.meta.DeclEnum(machines.specs);
const MachineSpec = machines.MachineSpec;

fn resolveMachine(id: MachineID) MachineSpec {
    inline for (comptime std.meta.declarations(machines.specs)) |decl| {
        if (id == @field(MachineID, decl.name)) {
            return @field(machines.specs, decl.name);
        }
    }
    unreachable;
}

pub fn build(b: *std.build.Builder) !void {
    const fatfs_config = FatFS.Config{
        .volumes = .{
            // .named = &.{"CF0"},
            .count = 8,
        },
        .rtc = .{
            .static = .{ .year = 2022, .month = .jul, .day = 10 },
        },
        .mkfs = true,
    };

    b.addModule(.{
        .name = "ashet-std",
        .source_file = .{ .path = "src/std/std.zig" },
    });

    b.addModule(.{
        .name = "virtio",
        .source_file = .{ .path = "vendor/libvirtio/src/virtio.zig" },
    });

    b.addModule(.{
        .name = "ashet-abi",
        .source_file = .{ .path = "src/abi/abi.zig" },
    });

    const zigimg = b.dependency("zigimg", .{}).module("zigimg");

    const text_editor_module = b.dependency("text-editor", .{}).module("text-editor");

    b.addModule(.{
        .name = "ashet",
        .source_file = .{ .path = "src/libashet/main.zig" },
        .dependencies = &.{
            .{ .name = "ashet-abi", .module = b.modules.get("ashet-abi").? },
            .{ .name = "ashet-std", .module = b.modules.get("ashet-std").? },
            .{ .name = "text-editor", .module = text_editor_module },
        },
    });

    b.addModule(.{
        .name = "ashet-gui",
        .source_file = .{ .path = "src/libgui/gui.zig" },
        .dependencies = &.{
            .{ .name = "ashet", .module = b.modules.get("ashet").? },
            .{ .name = "ashet-std", .module = b.modules.get("ashet-std").? },
            .{ .name = "text-editor", .module = text_editor_module },
        },
    });

    const tools_step = b.step("tools", "Builds the build and debug tools");

    const optimize = b.standardOptimizeOption(.{});

    const machine_id = b.option(MachineID, "machine", "Defines the machine Ashet OS should be built for.") orelse {
        var stderr = std.io.getStdErr();

        var writer = stderr.writer();
        try writer.writeAll("No machine selected. Use one of the following options:\n");

        inline for (comptime std.meta.declarations(machines.all)) |decl| {
            try writer.print("- {s}\n", .{decl.name});
        }

        std.os.exit(1);
    };

    const machine_spec = resolveMachine(machine_id);

    const tool_mkicon = b.addExecutable(.{ .name = "tool_mkicon", .root_source_file = .{ .path = "tools/mkicon.zig" } });
    tool_mkicon.addModule("zigimg", zigimg);
    tool_mkicon.addModule("ashet-abi", b.modules.get("ashet-abi").?);
    tool_mkicon.install();

    const machine_pkg = b.addWriteFile("machine.zig", blk: {
        var stream = std.ArrayList(u8).init(b.allocator);
        defer stream.deinit();

        var writer = stream.writer();

        try writer.writeAll("//! This is a machine-generated description of the Ashet OS target machine.\n\n");

        try writer.print("pub const machine = @import(\"root\").machines.all.{};\n", .{
            std.zig.fmtId(machine_spec.machine_id),
        });
        try writer.print("pub const platform = @import(\"root\").platforms.all.{};\n", .{
            std.zig.fmtId(machine_spec.platform.platform_id),
        });

        try writer.print("pub const machine_name = \"{}\";\n", .{
            std.zig.fmtEscapes(machine_spec.name),
        });
        try writer.print("pub const platform_name = \"{}\";\n", .{
            std.zig.fmtEscapes(machine_spec.platform.name),
        });

        break :blk try stream.toOwnedSlice();
    });

    const fatfs_module = FatFS.createModule(b, fatfs_config);

    const kernel_exe = b.addExecutable(.{
        .name = "ashet-os",
        .root_source_file = .{ .path = "src/kernel/main.zig" },
        .target = machine_spec.platform.target,
        .optimize = optimize,
    });

    {
        kernel_exe.single_threaded = true;
        kernel_exe.omit_frame_pointer = false;
        kernel_exe.strip = false; // never strip debug info
        if (optimize == .Debug) {
            // we always want frame pointers in debug build!
            kernel_exe.omit_frame_pointer = false;
        }
        kernel_exe.addModule("ashet-abi", b.modules.get("ashet-abi").?);
        kernel_exe.addModule("ashet-std", b.modules.get("ashet-std").?);
        kernel_exe.addModule("ashet", b.modules.get("ashet").?);
        kernel_exe.addModule("ashet-gui", b.modules.get("ashet-gui").?);
        kernel_exe.addModule("virtio", b.modules.get("virtio").?);
        kernel_exe.addAnonymousModule("machine", .{
            .source_file = machine_pkg.getFileSource("machine.zig").?,
        });
        kernel_exe.addModule("fatfs", fatfs_module);
        kernel_exe.setLinkerScriptPath(.{ .path = machine_spec.linker_script });
        kernel_exe.install();

        kernel_exe.addSystemIncludePath("vendor/ziglibc/inc/libc");

        FatFS.link(kernel_exe, fatfs_config);

        const kernel_libc = ziglibc.addLibc(b, .{
            .variant = .freestanding,
            .link = .static,
            .start = .ziglibc,
            .trace = false,
            .target = kernel_exe.target,
            .optimize = .ReleaseSafe,
        });
        kernel_libc.install();

        kernel_exe.linkLibrary(kernel_libc);

        {
            const lwip = create_lwIP(b, kernel_exe.target, .ReleaseSafe);
            lwip.is_linking_libc = false;
            lwip.strip = false;
            lwip.addSystemIncludePath("vendor/ziglibc/inc/libc");
            kernel_exe.linkLibrary(lwip);
            setup_lwIP(kernel_exe);
        }

        {
            const convert_wallpaper = tool_mkicon.run();
            convert_wallpaper.addArg("artwork/os/wallpaper-chances.png");
            convert_wallpaper.addArg("src/kernel/data/ui/wallpaper.abm");
            convert_wallpaper.addArg("400x300");
            kernel_exe.step.dependOn(&convert_wallpaper.step);
        }
        {
            const generate_stub_icon = tool_mkicon.run();
            generate_stub_icon.addArg("artwork/os/default-app-icon.png");
            generate_stub_icon.addArg("src/kernel/data/generic-app-icon.abm");
            generate_stub_icon.addArg("32x32");
            kernel_exe.step.dependOn(&generate_stub_icon.step);
        }

        {
            const kernel_step = b.step("kernel", "Only builds the OS kernel");
            kernel_step.dependOn(&kernel_exe.step);
        }
    }

    const raw_step = kernel_exe.installRaw("ashet-os.bin", .{
        .format = .bin,
        // .pad_to_size = 0x200_0000,
    });

    b.getInstallStep().dependOn(&raw_step.step);

    // Makes sure zig-out/disk.img exists, but doesn't touch the data at all
    const setup_disk_cmd = b.addSystemCommand(&.{
        "fallocate",
        "-l",
        "32M",
        "zig-out/disk.img",
    });

    const run_cmd = b.addSystemCommand(&.{"qemu-system-riscv32"});
    run_cmd.addArgs(&.{
        "-M", "virt",
        "-m",      "32M", // we have *some* overhead on the virt platform
        "-device", "virtio-gpu-device,xres=400,yres=300",
        "-device", "virtio-keyboard-device",
        "-device", "virtio-mouse-device",
        "-d",      "guest_errors",
        "-bios",   "none",
        "-drive",  "if=pflash,index=0,file=zig-out/bin/ashet-os.bin,format=raw",
        "-drive",  "if=pflash,index=1,file=zig-out/disk.img,format=raw",
    });
    run_cmd.step.dependOn(&setup_disk_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    var ctx = AshetContext{
        .b = b,
        .mkicon = tool_mkicon,
        .target = machine_spec.platform.target,
    };

    {
        _ = ctx.createAshetApp("shell", "src/apps/dummy.zig", "artwork/apps/shell.png", optimize);
        _ = ctx.createAshetApp("commander", "src/apps/dummy.zig", "artwork/apps/commander.png", optimize);
        _ = ctx.createAshetApp("editor", "src/apps/dummy.zig", "artwork/apps/text-editor.png", optimize);
        _ = ctx.createAshetApp("browser", "src/apps/dummy.zig", "artwork/apps/browser.png", optimize);
        _ = ctx.createAshetApp("music", "src/apps/dummy.zig", "artwork/apps/music.png", optimize);
        _ = ctx.createAshetApp("clock", "src/apps/clock.zig", "artwork/apps/clock.png", optimize);
        _ = ctx.createAshetApp("paint", "src/apps/paint.zig", "artwork/apps/paint.png", optimize);
        _ = ctx.createAshetApp("gui-demo", "src/apps/gui-demo.zig", null, optimize);
        _ = ctx.createAshetApp("net-demo", "src/apps/net-demo.zig", null, optimize);

        {
            const dungeon = ctx.createAshetApp("dungeon", "src/apps/dungeon/dungeon.zig", "artwork/apps/dungeon.png", optimize);
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/floor.png", "src/apps/dungeon/data/floor.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/wall-plain.png", "src/apps/dungeon/data/wall-plain.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/wall-cobweb.png", "src/apps/dungeon/data/wall-cobweb.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/wall-paper.png", "src/apps/dungeon/data/wall-paper.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/wall-vines.png", "src/apps/dungeon/data/wall-vines.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/wall-door.png", "src/apps/dungeon/data/wall-door.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/wall-post-l.png", "src/apps/dungeon/data/wall-post-l.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/wall-post-r.png", "src/apps/dungeon/data/wall-post-r.abm", "32x32");
            addBitmap(dungeon, tool_mkicon, "artwork/dungeon/enforcer.png", "src/apps/dungeon/data/enforcer.abm", "32x60");
        }
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const std_tests = b.addTest(.{ .root_source_file = .{ .path = "src/std/std.zig" }, .target = .{}, .optimize = optimize });

    const gui_tests = b.addTest(.{ .root_source_file = .{ .path = "src/libgui/gui.zig" }, .target = .{}, .optimize = optimize });
    {
        var iter = b.modules.get("ashet-gui").?.dependencies.iterator();
        while (iter.next()) |kv| {
            gui_tests.addModule(kv.key_ptr.*, kv.value_ptr.*);
        }
    }

    const test_step = b.step("test", "Run unit tests on the standard library");
    test_step.dependOn(&std_tests.step);
    test_step.dependOn(&gui_tests.step);
    {
        const debug_filter = b.addExecutable(.{
            .name = "debug-filter",
            .root_source_file = .{ .path = "tools/debug-filter.zig" },
        });
        debug_filter.linkLibC();
        debug_filter.install();

        tools_step.dependOn(&debug_filter.install_step.?.step);
    }

    {
        const init_disk = b.addExecutable(.{
            .name = "init-disk",
            .root_source_file = .{ .path = "tools/init-disk.zig" },
        });
        init_disk.linkLibC();
        init_disk.addModule("fatfs", fatfs_module);
        init_disk.install();
        FatFS.link(init_disk, fatfs_config);

        tools_step.dependOn(&init_disk.install_step.?.step);
    }
}

fn create_lwIP(b: *std.build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) *std.build.LibExeObjStep {
    const lib = b.addStaticLibrary(.{
        .name = "lwip",
        .target = target,
        .optimize = optimize,
    });

    const flags = [_][]const u8{ "-std=c99", "-fno-sanitize=undefined" };
    const files = [_][]const u8{
        // Core files
        "vendor/lwip/src/core/init.c",
        "vendor/lwip/src/core/udp.c",
        "vendor/lwip/src/core/inet_chksum.c",
        "vendor/lwip/src/core/altcp_alloc.c",
        "vendor/lwip/src/core/stats.c",
        "vendor/lwip/src/core/altcp.c",
        "vendor/lwip/src/core/mem.c",
        "vendor/lwip/src/core/ip.c",
        "vendor/lwip/src/core/pbuf.c",
        "vendor/lwip/src/core/netif.c",
        "vendor/lwip/src/core/tcp_out.c",
        "vendor/lwip/src/core/dns.c",
        "vendor/lwip/src/core/tcp_in.c",
        "vendor/lwip/src/core/memp.c",
        "vendor/lwip/src/core/tcp.c",
        "vendor/lwip/src/core/sys.c",
        "vendor/lwip/src/core/def.c",
        "vendor/lwip/src/core/timeouts.c",
        "vendor/lwip/src/core/raw.c",
        "vendor/lwip/src/core/altcp_tcp.c",

        // IPv4 implementation:
        "vendor/lwip/src/core/ipv4/dhcp.c",
        "vendor/lwip/src/core/ipv4/autoip.c",
        "vendor/lwip/src/core/ipv4/ip4_frag.c",
        "vendor/lwip/src/core/ipv4/etharp.c",
        "vendor/lwip/src/core/ipv4/ip4.c",
        "vendor/lwip/src/core/ipv4/ip4_addr.c",
        "vendor/lwip/src/core/ipv4/igmp.c",
        "vendor/lwip/src/core/ipv4/icmp.c",

        // IPv6 implementation:
        "vendor/lwip/src/core/ipv6/icmp6.c",
        "vendor/lwip/src/core/ipv6/ip6_addr.c",
        "vendor/lwip/src/core/ipv6/ip6.c",
        "vendor/lwip/src/core/ipv6/ip6_frag.c",
        "vendor/lwip/src/core/ipv6/mld6.c",
        "vendor/lwip/src/core/ipv6/dhcp6.c",
        "vendor/lwip/src/core/ipv6/inet6.c",
        "vendor/lwip/src/core/ipv6/ethip6.c",
        "vendor/lwip/src/core/ipv6/nd6.c",

        // Interfaces:
        "vendor/lwip/src/netif/bridgeif.c",
        "vendor/lwip/src/netif/ethernet.c",
        "vendor/lwip/src/netif/slipif.c",
        "vendor/lwip/src/netif/bridgeif_fdb.c",

        // sequential APIs
        // "vendor/lwip/src/api/err.c",
        // "vendor/lwip/src/api/api_msg.c",
        // "vendor/lwip/src/api/netifapi.c",
        // "vendor/lwip/src/api/sockets.c",
        // "vendor/lwip/src/api/netbuf.c",
        // "vendor/lwip/src/api/api_lib.c",
        // "vendor/lwip/src/api/tcpip.c",
        // "vendor/lwip/src/api/netdb.c",
        // "vendor/lwip/src/api/if_api.c",

        // 6LoWPAN
        "vendor/lwip/src/netif/lowpan6.c",
        "vendor/lwip/src/netif/lowpan6_ble.c",
        "vendor/lwip/src/netif/lowpan6_common.c",
        "vendor/lwip/src/netif/zepif.c",

        // PPP
        // "vendor/lwip/src/netif/ppp/polarssl/arc4.c",
        // "vendor/lwip/src/netif/ppp/polarssl/des.c",
        // "vendor/lwip/src/netif/ppp/polarssl/md4.c",
        // "vendor/lwip/src/netif/ppp/polarssl/sha1.c",
        // "vendor/lwip/src/netif/ppp/polarssl/md5.c",
        // "vendor/lwip/src/netif/ppp/ipcp.c",
        // "vendor/lwip/src/netif/ppp/magic.c",
        // "vendor/lwip/src/netif/ppp/pppoe.c",
        // "vendor/lwip/src/netif/ppp/mppe.c",
        // "vendor/lwip/src/netif/ppp/multilink.c",
        // "vendor/lwip/src/netif/ppp/chap-new.c",
        // "vendor/lwip/src/netif/ppp/auth.c",
        // "vendor/lwip/src/netif/ppp/chap_ms.c",
        // "vendor/lwip/src/netif/ppp/ipv6cp.c",
        // "vendor/lwip/src/netif/ppp/chap-md5.c",
        // "vendor/lwip/src/netif/ppp/upap.c",
        // "vendor/lwip/src/netif/ppp/pppapi.c",
        // "vendor/lwip/src/netif/ppp/pppos.c",
        // "vendor/lwip/src/netif/ppp/eap.c",
        // "vendor/lwip/src/netif/ppp/pppol2tp.c",
        // "vendor/lwip/src/netif/ppp/demand.c",
        // "vendor/lwip/src/netif/ppp/fsm.c",
        // "vendor/lwip/src/netif/ppp/eui64.c",
        // "vendor/lwip/src/netif/ppp/ccp.c",
        // "vendor/lwip/src/netif/ppp/pppcrypt.c",
        // "vendor/lwip/src/netif/ppp/utils.c",
        // "vendor/lwip/src/netif/ppp/vj.c",
        // "vendor/lwip/src/netif/ppp/lcp.c",
        // "vendor/lwip/src/netif/ppp/ppp.c",
        // "vendor/lwip/src/netif/ppp/ecp.c",
    };

    lib.addCSourceFiles(&files, &flags);

    setup_lwIP(lib);

    return lib;
}

fn setup_lwIP(dst: *std.build.LibExeObjStep) void {
    dst.addIncludePath("vendor/lwip/src/include");
    dst.addIncludePath("src/kernel/components/network/include");
}
