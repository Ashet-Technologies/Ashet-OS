const std = @import("std");
const zpm = @import("zpm.zig");

const ziglibc = @import("vendor/ziglibc/ziglibcbuild.zig");

const FatFS = @import("vendor/zfat/Sdk.zig");

const pkgs = struct {
    pub usingnamespace zpm.pkgs;

    pub const libashet = std.build.Pkg{
        .name = "ashet",
        .source = .{ .path = "src/libashet/main.zig" },
        .dependencies = &.{ abi, ashet_std, pkgs.@"text-editor" },
    };

    pub const libgui = std.build.Pkg{
        .name = "ashet-gui",
        .source = .{ .path = "src/libgui/gui.zig" },
        .dependencies = &.{ libashet, ashet_std, pkgs.@"text-editor" },
    };

    pub const ashet_std = std.build.Pkg{
        .name = "ashet-std",
        .source = .{ .path = "src/std/std.zig" },
    };

    pub const virtio = std.build.Pkg{
        .name = "virtio",
        .source = .{ .path = "vendor/libvirtio/src/virtio.zig" },
    };

    pub const abi = std.build.Pkg{
        .name = "ashet-abi",
        .source = .{ .path = "src/abi/abi.zig" },
    };

    pub const hal_virt_riscv32 = std.build.Pkg{
        .name = "hal",
        .source = .{ .path = "src/kernel/hal/virt-riscv32/hal.zig" },
        .dependencies = &.{virtio},
    };

    pub const hal_virt_arm = std.build.Pkg{
        .name = "hal",
        .source = .{ .path = "src/kernel/hal/virt-arm/hal.zig" },
        .dependencies = &.{virtio},
    };

    pub const hal_ashet = std.build.Pkg{
        .name = "hal",
        .source = .{ .path = "src/kernel/hal/ashet/hal.zig" },
    };

    pub const hal_microvm = std.build.Pkg{
        .name = "hal",
        .source = .{ .path = "src/kernel/hal/microvm/hal.zig" },
        .dependencies = &.{virtio},
    };

    pub const zigimg = std.build.Pkg{
        .name = "zigimg",
        .source = .{ .path = "vendor/zigimg/zigimg.zig" },
    };
};

const PlatformConfig = struct {
    target: std.zig.CrossTarget,
    hal: std.build.Pkg,
    linkerscript: std.build.FileSource,
};

pub const Target = union(enum) {
    riscv32: RiscvPlatform,
    arm: ArmPlatform,
    x86: X86Platform,

    pub fn resolve(target: Target) PlatformConfig {
        switch (target) {
            .riscv32 => |platform| {
                const cpu = std.zig.CrossTarget{
                    .cpu_arch = .riscv32,
                    .os_tag = .freestanding,
                    .abi = .eabi,
                    .cpu_model = .{ .explicit = &std.Target.riscv.cpu.generic_rv32 },
                    .cpu_features_add = std.Target.riscv.featureSet(&[_]std.Target.riscv.Feature{
                        .c,
                        .m,
                        .reserve_x4, // Don't allow LLVM to use the "tp" register. We want that for our own purposes
                    }),
                };
                return switch (platform) {
                    .virt => PlatformConfig{
                        .target = cpu,
                        .hal = pkgs.hal_virt_riscv32,
                        .linkerscript = .{ .path = "src/kernel/hal/virt-riscv32/linker.ld" },
                    },
                    .ashet => PlatformConfig{
                        .target = cpu,
                        .hal = pkgs.hal_ashet,
                        .linkerscript = .{ .path = "" },
                    },
                };
            },
            .arm => |platform| {
                const cpu = std.zig.CrossTarget{
                    .cpu_arch = .arm,
                    .os_tag = .freestanding,
                    .abi = .eabi,
                    .cpu_model = .{ .explicit = &std.Target.arm.cpu.generic },
                };
                return switch (platform) {
                    .virt => PlatformConfig{
                        .target = cpu,
                        .hal = pkgs.hal_virt_arm,
                        .linkerscript = .{ .path = "" },
                    },
                };
            },
            .x86 => |platform| {
                const cpu = std.zig.CrossTarget{
                    .cpu_arch = .x86,
                    .os_tag = .freestanding,
                    .abi = .eabi,
                    .cpu_model = .{ .explicit = &std.Target.x86.cpu.i686 },
                };
                return switch (platform) {
                    .microvm => PlatformConfig{
                        .target = cpu,
                        .hal = pkgs.hal_microvm,
                        .linkerscript = .{ .path = "src/kernel/hal/microvm/linker.ld" },
                    },
                };
            },
        }
    }
};

pub const TargetId = std.meta.Tag(Target);

pub const RiscvPlatform = enum {
    virt,
    ashet,
};

pub const ArmPlatform = enum {
    virt,
};

pub const X86Platform = enum {
    microvm,
};

const AshetContext = struct {
    b: *std.build.Builder,
    mkicon: *std.build.LibExeObjStep,
    target: std.zig.CrossTarget,

    fn createAshetApp(ctx: AshetContext, name: []const u8, source: []const u8, maybe_icon: ?[]const u8, mode: std.builtin.Mode) *std.build.LibExeObjStep {
        const exe = ctx.b.addExecutable(ctx.b.fmt("{s}.app", .{name}), source);

        exe.omit_frame_pointer = false; // this is useful for debugging
        exe.single_threaded = true; // AshetOS doesn't support multithreading in a modern sense
        exe.pie = true; // AshetOS requires PIE executables
        exe.force_pic = true; // which need PIC code
        exe.linkage = .static; // but everything is statically linked, we don't support shared objects
        exe.strip = false; // never strip debug info

        exe.setLinkerScriptPath(.{ .path = "src/libashet/application.ld" });
        exe.setTarget(ctx.target);
        exe.setBuildMode(mode);
        exe.addPackage(pkgs.libashet);
        exe.addPackage(pkgs.libgui); // just add GUI to all apps by default *shrug*
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

pub fn build(b: *std.build.Builder) void {
    const fatfs_config = FatFS.Config{
        .volumes = .{
            // .named = &.{"CF0"},
            .count = 8,
        },
        .rtc = .{
            .static = .{ .year = 2022, .month = .jul, .day = 10 },
        },
    };

    const mode = b.standardReleaseOptions();

    const target_id = b.option(TargetId, "cpu", "The target cpu architecture") orelse .riscv32;
    const system_target: Target = switch (target_id) {
        .riscv32 => Target{
            .riscv32 = b.option(RiscvPlatform, "platform", "The target machine for the os") orelse .virt,
        },
        .arm => Target{
            .arm = b.option(ArmPlatform, "platform", "The target machine for the os") orelse .virt,
        },
        .x86 => Target{
            .x86 = b.option(X86Platform, "platform", "The target machine for the os") orelse .microvm,
        },
    };
    const system_platform = system_target.resolve();

    const tool_mkicon = b.addExecutable("tool_mkicon", "tools/mkicon.zig");
    tool_mkicon.addPackage(pkgs.zigimg);
    tool_mkicon.addPackage(pkgs.abi);
    tool_mkicon.install();

    const experiment = b.addExecutable("experiment", "tools/fs-experiments.zig");
    experiment.addPackage(FatFS.getPackage(b, "fatfs", fatfs_config));
    FatFS.link(experiment, fatfs_config);
    experiment.linkLibC();
    experiment.install();

    const kernel_exe = b.addExecutable("ashet-os", "src/kernel/main.zig");
    {
        kernel_exe.single_threaded = true;
        kernel_exe.omit_frame_pointer = false;
        kernel_exe.strip = false; // never strip debug info
        if (mode == .Debug) {
            // we always want frame pointers in debug build!
            kernel_exe.omit_frame_pointer = false;
        }
        kernel_exe.setTarget(system_platform.target);
        kernel_exe.setBuildMode(mode);
        kernel_exe.addPackage(system_platform.hal);
        kernel_exe.addPackage(pkgs.abi);
        kernel_exe.addPackage(pkgs.ashet_std);
        kernel_exe.addPackage(pkgs.libashet);
        kernel_exe.addPackage(FatFS.getPackage(b, "fatfs", fatfs_config));
        kernel_exe.setLinkerScriptPath(system_platform.linkerscript);
        kernel_exe.install();

        kernel_exe.addSystemIncludePath("vendor/ziglibc/inc/libc");

        FatFS.link(kernel_exe, fatfs_config);

        const kernel_libc = ziglibc.addLibc(b, .{
            .variant = .only_std,
            .link = .static,
            .start = .ziglibc,
            .trace = false,
            .target = kernel_exe.target,
        });
        kernel_libc.install();

        kernel_exe.linkLibrary(kernel_libc);

        {
            const lwip = create_lwIP(b, kernel_exe.target, .ReleaseSafe);
            lwip.is_linking_libc = false;
            lwip.addSystemIncludePath("vendor/ziglibc/inc/libc");
            kernel_exe.linkLibrary(lwip);
            setup_lwIP(kernel_exe);
        }

        {
            const convert_wallpaper = tool_mkicon.run();
            convert_wallpaper.addArg("artwork/os/wallpaper-chances.png");
            convert_wallpaper.addArg("src/kernel/data/ui/wallpaper.img");
            convert_wallpaper.addArg("400x300");
            kernel_exe.step.dependOn(&convert_wallpaper.step);
        }
        {
            const generate_stub_icon = tool_mkicon.run();
            generate_stub_icon.addArg("artwork/os/default-app-icon.png");
            generate_stub_icon.addArg("src/kernel/data/generic-app.icon");
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
        .pad_to_size = 0x200_0000,
    });

    b.getInstallStep().dependOn(&raw_step.step);

    // dd if=/dev/zero of=zig-out/disk.img bs=512 count=65536
    // mkfs.vfat -n ASHET -S 512 zig-out/disk.img
    // mformat -i zig-out/disk.img -v ASHET
    // ls -hal zig-out/disk.img
    // file zig-out/disk.img

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
        .target = system_platform.target,
    };

    {
        _ = ctx.createAshetApp("shell", "src/apps/dummy.zig", "artwork/apps/shell.png", mode);
        _ = ctx.createAshetApp("commander", "src/apps/dummy.zig", "artwork/apps/commander.png", mode);
        _ = ctx.createAshetApp("editor", "src/apps/dummy.zig", "artwork/apps/text-editor.png", mode);
        _ = ctx.createAshetApp("browser", "src/apps/dummy.zig", "artwork/apps/browser.png", mode);
        _ = ctx.createAshetApp("music", "src/apps/dummy.zig", "artwork/apps/music.png", mode);
        _ = ctx.createAshetApp("dungeon", "src/apps/dungeon.zig", "artwork/apps/dungeon.png", mode);
        _ = ctx.createAshetApp("clock", "src/apps/clock.zig", "artwork/apps/clock.png", mode);
        _ = ctx.createAshetApp("paint", "src/apps/paint.zig", "artwork/apps/paint.png", mode);
        _ = ctx.createAshetApp("gui-demo", "src/apps/gui-demo.zig", null, mode);
        _ = ctx.createAshetApp("net-demo", "src/apps/net-demo.zig", null, mode);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const std_tests = b.addTest("src/std/std.zig");
    std_tests.setTarget(.{});
    std_tests.setBuildMode(mode);

    const gui_tests = b.addTest("src/libgui/gui.zig");
    gui_tests.setTarget(.{});
    gui_tests.setBuildMode(mode);
    for (pkgs.libgui.dependencies.?) |dep| {
        gui_tests.addPackage(dep);
    }

    const test_step = b.step("test", "Run unit tests on the standard library");
    test_step.dependOn(&std_tests.step);
    test_step.dependOn(&gui_tests.step);

    // const simu_step = b.step("sim", "Runs the PC simulator");

    // const sdl_sdk = zpm.sdks.sdl.init(b);

    // const sim = b.addExecutable("ashet-os-sim", "src/simulator/sim.zig");
    // sim.setBuildMode(mode);
    // sim.setTarget(.{});
    // sim.addPackage(sdl_sdk.getNativePackage("sdl2"));
    // sim.addPackage(pkgs.abi);
    // sim.addPackage(std.build.Pkg{
    //     .name = "ashet",
    //     .source = .{ .path = "src/kernel/sim_pkg.zig" },
    //     .dependencies = &.{ pkgs.abi, std.build.Pkg{
    //         .name = "hal",
    //         .source = .{ .path = "src/simulator/loopback.zig" },
    //     } },
    // });
    // sim.install();

    // sdl_sdk.link(sim, .dynamic);

    // const run_sim = sim.run();

    // simu_step.dependOn(&run_sim.step);

    {
        const debug_filter = b.addExecutable("debug-filter", "tools/debug-filter.zig");
        debug_filter.linkLibC();
        debug_filter.install();
    }
}

fn create_lwIP(b: *std.build.Builder, target: std.zig.CrossTarget, mode: std.builtin.Mode) *std.build.LibExeObjStep {
    const lib = b.addStaticLibrary("lwip", null);
    lib.setTarget(target);
    lib.setBuildMode(mode);

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
