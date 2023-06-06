const std = @import("std");

const FatFS = @import("vendor/zfat/Sdk.zig");

const rootfs_dir = std.Build.InstallDir{ .custom = "rootfs" };

const AshetContext = struct {
    b: *std.build.Builder,
    bmpconv: BitmapConverter,
    target: std.zig.CrossTarget,
    hosted_build: bool,

    fn createAshetApp(ctx: AshetContext, name: []const u8, source: []const u8, maybe_icon: ?[]const u8, optimize: std.builtin.OptimizeMode, dependencies: []const std.Build.ModuleDependency) void {
        const exe = ctx.b.addExecutable(.{
            .name = ctx.b.fmt("{s}.app", .{name}),
            .root_source_file = if (ctx.hosted_build)
                .{ .path = "src/libuserland/main.zig" }
            else
                .{ .path = source },
            .optimize = optimize,
            .target = ctx.target,
        });

        exe.omit_frame_pointer = false; // this is useful for debugging

        if (ctx.hosted_build) {
            exe.addModule("ashet", ctx.b.modules.get("ashet").?);
            exe.addModule("ashet-std", ctx.b.modules.get("ashet-std").?);
            exe.addModule("ashet-abi", ctx.b.modules.get("ashet-abi").?);
            exe.addAnonymousModule("app", .{
                .source_file = .{ .path = source },
                .dependencies = std.mem.concat(ctx.b.allocator, std.Build.ModuleDependency, &.{
                    &.{
                        .{ .name = "ashet", .module = ctx.b.modules.get("ashet").? },
                        .{ .name = "ashet-gui", .module = ctx.b.modules.get("ashet-gui").? },
                    },
                    dependencies,
                }) catch @panic("oom"),
            });

            exe.linkSystemLibrary("sdl2");
            exe.linkLibC();
            ctx.b.installArtifact(exe);
        } else {
            exe.addModule("ashet", ctx.b.modules.get("ashet").?);
            exe.addModule("ashet-gui", ctx.b.modules.get("ashet-gui").?); // just add GUI to all apps by default *shrug*
            for (dependencies) |dep| {
                exe.addModule(dep.name, dep.module);
            }

            exe.single_threaded = true; // AshetOS doesn't support multithreading in a modern sense
            exe.pie = true; // AshetOS requires PIE executables
            exe.force_pic = true; // which need PIC code
            exe.linkage = .static; // but everything is statically linked, we don't support shared objects
            exe.strip = false;

            exe.setLinkerScriptPath(.{ .path = "src/libashet/application.ld" });

            const install_app_code_step = ctx.b.addInstallFile(exe.getOutputSource(), ctx.b.fmt("apps/{s}/code", .{name}));
            install_app_code_step.dir = rootfs_dir;
            ctx.b.getInstallStep().dependOn(&install_app_code_step.step);

            if (maybe_icon) |src_icon| {
                const icon_file = ctx.bmpconv.convert(
                    .{ .path = src_icon },
                    ctx.b.fmt("{s}.icon", .{name}),
                    .{
                        .geometry = .{ 32, 32 },
                        .palette = .{ .predefined = "src/kernel/data/palette.gpl" },
                        // .palette = .{ .sized = 15 },
                    },
                );

                const install_app_icon_step = ctx.b.addInstallFile(icon_file, ctx.b.fmt("apps/{s}/icon", .{name}));
                install_app_icon_step.dir = rootfs_dir;
                ctx.b.getInstallStep().dependOn(&install_app_icon_step.step);
            }
        }

        // return exe;
    }
};

const ziglibc_file = std.build.FileSource{ .path = "vendor/libc/ziglibc.txt" };

fn addBitmap(target: *std.build.LibExeObjStep, bmpconv: BitmapConverter, src: []const u8, dst: []const u8, size: [2]u32) void {
    const file = bmpconv.convert(.{ .path = src }, std.fs.path.basename(dst), .{ .geometry = size });

    file.addStepDependencies(&target.step);
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

const UiGenerator = struct {
    builder: *std.Build,
    lua: *std.Build.CompileStep,
    mod_ashet_gui: *std.Build.Module,
    mod_ashet: *std.Build.Module,
    mod_system_assets: *std.Build.Module,

    pub fn render(gen: @This(), input: std.Build.FileSource) *std.Build.Module {
        const runner = gen.builder.addRunArtifact(gen.lua);
        runner.cwd = gen.builder.pathFromRoot(".");
        runner.addFileSourceArg(.{ .path = gen.builder.pathFromRoot("tools/ui-layouter.lua") });
        runner.addFileSourceArg(input);
        const out_file = runner.addOutputFileArg("ui-layout.zig");

        return gen.builder.createModule(.{
            .source_file = out_file,
            .dependencies = &.{
                .{ .name = "ashet", .module = gen.mod_ashet },
                .{ .name = "ashet-gui", .module = gen.mod_ashet_gui },
                .{ .name = "system-assets", .module = gen.mod_system_assets },
            },
        });
    }
};

const fatfs_config = FatFS.Config{
    .max_long_name_len = 121,
    .code_page = .us,
    .volumes = .{
        .count = 8,
    },
    .rtc = .{
        .static = .{ .year = 2022, .month = .jul, .day = 10 },
    },
    .mkfs = true,
};

pub fn build(b: *std.Build) !void {
    const hosted_build = b.option(bool, "hosted", "Builds the applications hosted for the current system") orelse false;

    const lua_dep = b.dependency("lua", .{
        .interpreter = true,
        .compiler = false,
        .@"shared-lib" = false,
        .@"static-lib" = false,
        .headers = false,
    });

    const lua_exe = lua_dep.artifact("lua");

    const turtlefont_dep = b.dependency("turtlefont", .{});

    const text_editor_module = b.dependency("text-editor", .{}).module("text-editor");
    const mod_hyperdoc = b.dependency("hyperdoc", .{}).module("hyperdoc");

    const mod_args = b.dependency("args", .{}).module("args");
    const mod_zigimg = b.dependency("zigimg", .{}).module("zigimg");

    const mod_ashet_std = b.addModule("ashet-std", .{
        .source_file = .{ .path = "src/std/std.zig" },
    });

    const mod_virtio = b.addModule("virtio", .{
        .source_file = .{ .path = "vendor/libvirtio/src/virtio.zig" },
    });

    const mod_ashet_abi = b.addModule("ashet-abi", .{
        .source_file = .{ .path = "src/abi/abi.zig" },
    });

    const mod_libashet = b.addModule("ashet", .{
        .source_file = .{ .path = "src/libashet/main.zig" },
        .dependencies = &.{
            .{ .name = "ashet-abi", .module = mod_ashet_abi },
            .{ .name = "ashet-std", .module = mod_ashet_std },
            // .{ .name = "text-editor", .module = text_editor_module },
        },
    });

    const mod_ashet_gui = b.addModule("ashet-gui", .{
        .source_file = .{ .path = "src/libgui/gui.zig" },
        .dependencies = &.{
            .{ .name = "ashet", .module = mod_libashet },
            .{ .name = "ashet-std", .module = mod_ashet_std },
            .{ .name = "text-editor", .module = text_editor_module },
            .{ .name = "turtlefont", .module = turtlefont_dep.module("turtlefont") },
        },
    });

    const mod_libhypertext = b.addModule("hypertext", .{
        .source_file = .{ .path = "src/libhypertext/hypertext.zig" },
        .dependencies = &.{
            .{ .name = "ashet", .module = mod_libashet },
            .{ .name = "ashet-gui", .module = mod_ashet_gui },
            .{ .name = "hyperdoc", .module = mod_hyperdoc },
        },
    });

    const mod_libashetfs = b.addModule("ashet-fs", .{
        .source_file = .{ .path = "src/libafs/afs.zig" },
        .dependencies = &.{},
    });

    const afs_tool = b.addExecutable(.{
        .name = "afs-tool",
        .root_source_file = .{ .path = "src/libafs/afs-tool.zig" },
    });
    afs_tool.addModule("args", mod_args);
    b.installArtifact(afs_tool);

    const tools_step = b.step("tools", "Builds the build and debug tools");

    const optimize = b.standardOptimizeOption(.{});

    const fatfs_module = FatFS.createModule(b, fatfs_config);

    const bmpconv = BitmapConverter.init(b);
    b.installArtifact(bmpconv.converter);
    {
        const tool_extract_icon = b.addExecutable(.{ .name = "tool_extract_icon", .root_source_file = .{ .path = "tools/extract-icon.zig" } });
        tool_extract_icon.addModule("zigimg", mod_zigimg);
        tool_extract_icon.addModule("ashet-abi", mod_ashet_abi);
        tool_extract_icon.addModule("args", mod_args);
        b.installArtifact(tool_extract_icon);
    }

    const system_icons = AssetBundleStep.create(b);
    {
        const desktop_icon_conv_options: BitmapConverter.Options = .{
            .geometry = .{ 32, 32 },
            .palette = .{
                .predefined = "src/kernel/data/palette.gpl",
            },
        };

        const tool_icon_conv_options: BitmapConverter.Options = .{
            .geometry = .{ 16, 16 },
            .palette = .{
                .predefined = "src/kernel/data/palette.gpl",
            },
        };
        system_icons.add("system/icons/back.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Go back.png" }, "back.abm", tool_icon_conv_options));
        system_icons.add("system/icons/forward.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Go forward.png" }, "forward.abm", tool_icon_conv_options));
        system_icons.add("system/icons/reload.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Refresh.png" }, "reload.abm", tool_icon_conv_options));
        system_icons.add("system/icons/home.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Home.png" }, "home.abm", tool_icon_conv_options));
        system_icons.add("system/icons/go.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Go.png" }, "go.abm", tool_icon_conv_options));
        system_icons.add("system/icons/stop.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Stop sign.png" }, "stop.abm", tool_icon_conv_options));
        system_icons.add("system/icons/menu.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Tune.png" }, "menu.abm", tool_icon_conv_options));
        system_icons.add("system/icons/plus.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-toolbar-icons/13.png" }, "plus.abm", tool_icon_conv_options));
        system_icons.add("system/icons/delete.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Delete.png" }, "delete.abm", tool_icon_conv_options));
        system_icons.add("system/icons/copy.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Copy.png" }, "copy.abm", tool_icon_conv_options));
        system_icons.add("system/icons/cut.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Cut.png" }, "cut.abm", tool_icon_conv_options));
        system_icons.add("system/icons/paste.abm", bmpconv.convert(.{ .path = "artwork/icons/small-icons/16x16-free-application-icons/16x16/Paste.png" }, "paste.abm", tool_icon_conv_options));

        system_icons.add("system/icons/default-app-icon.abm", bmpconv.convert(.{ .path = "artwork/os/default-app-icon.png" }, "menu.abm", desktop_icon_conv_options));
    }

    b.installDirectory(.{
        .source_dir = "rootfs",
        .install_dir = rootfs_dir,
        .install_subdir = ".",
    });

    var ui_gen = UiGenerator{
        .builder = b,
        .lua = lua_exe,
        .mod_ashet = mod_libashet,
        .mod_ashet_gui = mod_ashet_gui,
        .mod_system_assets = b.createModule(.{
            .source_file = system_icons.getOutput(),
            .dependencies = &.{},
        }),
    };

    const target = if (hosted_build)
        b.standardTargetOptions(.{})
    else machine_target: {
        const machine_id = b.option(MachineID, "machine", "Defines the machine Ashet OS should be built for.") orelse blk: {
            var stderr = std.io.getStdErr();

            var writer = stderr.writer();
            try writer.writeAll("No machine selected. Use one of the following options:\n");

            inline for (comptime std.meta.declarations(machines.all)) |decl| {
                try writer.print("- {s}\n", .{decl.name});
            }

            try writer.writeAll("Falling back to rv32_virt\n");

            break :blk .rv32_virt;
        };

        const machine_spec = resolveMachine(machine_id);

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

        const cguana_dep = b.anonymousDependency("vendor/ziglibc", @import("vendor/ziglibc/build.zig"), .{
            .target = machine_spec.platform.target,
            .link = .static,
            .start = .none,
            .trace = false,
            .optimize = .ReleaseSafe,
            .variant = .only_std,
        });

        const ashet_libc = cguana_dep.artifact("cguana");

        // const ashet_libc = cguana_dep.ziglibc.addLibc(b, .{
        //     .variant = .freestanding,
        //     .link = .static,
        //     .start = .ziglibc,
        //     .trace = false,
        //     .target = machine_spec.platform.target,
        //     .optimize = .ReleaseSafe,
        // });

        const kernel_exe = b.addExecutable(.{
            .name = "ashet-os",
            .root_source_file = .{ .path = "src/kernel/main.zig" },
            .target = machine_spec.platform.target,
            .optimize = optimize,
        });

        {
            kernel_exe.bundle_compiler_rt = true;
            kernel_exe.rdynamic = true; // Prevent the compiler from garbage collecting exported symbols
            kernel_exe.single_threaded = true;
            kernel_exe.omit_frame_pointer = false;
            kernel_exe.strip = false; // never strip debug info
            if (optimize == .Debug) {
                // we always want frame pointers in debug build!
                kernel_exe.omit_frame_pointer = false;
            }

            kernel_exe.addModule("system-assets", ui_gen.mod_system_assets);
            kernel_exe.addModule("ashet-abi", mod_ashet_abi);
            kernel_exe.addModule("ashet-std", mod_ashet_std);
            kernel_exe.addModule("ashet", mod_libashet);
            kernel_exe.addModule("ashet-gui", mod_ashet_gui);
            kernel_exe.addModule("virtio", mod_virtio);
            kernel_exe.addModule("ashet-fs", mod_libashetfs);
            kernel_exe.addModule("args", mod_args);
            kernel_exe.addAnonymousModule("machine", .{
                .source_file = machine_pkg.files.items[0].getFileSource(),
            });
            kernel_exe.addModule("fatfs", fatfs_module);
            kernel_exe.setLinkerScriptPath(.{ .path = machine_spec.linker_script });
            b.installArtifact(kernel_exe);

            kernel_exe.addSystemIncludePath("vendor/ziglibc/inc/libc");

            FatFS.link(kernel_exe, fatfs_config);

            kernel_exe.linkLibrary(ashet_libc);

            {
                const lwip = create_lwIP(b, kernel_exe.target, .ReleaseSafe);
                lwip.is_linking_libc = false;
                lwip.strip = false;
                lwip.addSystemIncludePath("vendor/ziglibc/inc/libc");
                kernel_exe.linkLibrary(lwip);
                setup_lwIP(kernel_exe);
            }

            {
                const kernel_step = b.step("kernel", "Only builds the OS kernel");
                kernel_step.dependOn(&kernel_exe.step);
            }
        }

        if (kernel_exe.target.getCpuArch() == .x86 or kernel_exe.target.getCpuArch() == .x86_64) {
            // prepare PXE environment:

            const install_pxe_kernel = b.addInstallArtifact(kernel_exe);
            install_pxe_kernel.dest_dir = .{ .custom = "pxe" };

            const install_pxe_root = b.addInstallDirectory(.{
                .source_dir = "rootfs-pxe",
                .install_dir = .{ .custom = "pxe" },
                .install_subdir = ".",
            });

            b.getInstallStep().dependOn(&install_pxe_root.step);
            b.getInstallStep().dependOn(&install_pxe_kernel.step);
        }

        const raw_step = b.addObjCopy(kernel_exe.getOutputSource(), .{
            .basename = "ashet-os.bin",
            .format = .bin,
            // .only_section
            // . pad_to = 0x200_0000,
        });

        const install_raw_step = b.addInstallFile(raw_step.getOutputSource(), "rom/ashet-os.bin");

        b.getInstallStep().dependOn(&install_raw_step.step);

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

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        break :machine_target machine_spec.platform.target;
    };

    var ctx = AshetContext{
        .b = b,
        .bmpconv = bmpconv,
        .target = target,
        .hosted_build = hosted_build,
    };

    {
        {
            const browser_assets = AssetBundleStep.create(b);

            ctx.createAshetApp("browser", "src/apps/browser/browser.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Search online.png", optimize, &.{
                .{
                    .name = "assets",
                    .module = b.createModule(.{
                        .source_file = browser_assets.getOutput(),
                        .dependencies = &.{},
                    }),
                },
                .{ .name = "hypertext", .module = mod_libhypertext },
                .{ .name = "main_window_layout", .module = ui_gen.render(.{ .path = b.pathFromRoot("src/apps/browser/main_window.lua") }) },
            });
        }

        ctx.createAshetApp("clock", "src/apps/clock/clock.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Time.png", optimize, &.{});
        ctx.createAshetApp("commander", "src/apps/commander/commander.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Folder.png", optimize, &.{});
        ctx.createAshetApp("editor", "src/apps/editor/editor.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Edit page.png", optimize, &.{});
        ctx.createAshetApp("music", "src/apps/music/music.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Play.png", optimize, &.{});
        ctx.createAshetApp("paint", "src/apps/paint/paint.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Painter.png", optimize, &.{});
        ctx.createAshetApp("terminal", "src/apps/terminal/terminal.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Tools.png", optimize, &.{
            .{ .name = "system-assets", .module = ui_gen.mod_system_assets },
        });
        ctx.createAshetApp("gui-demo", "src/apps/gui-demo.zig", null, optimize, &.{});
        ctx.createAshetApp("font-demo", "src/apps/font-demo.zig", null, optimize, &.{});
        ctx.createAshetApp("net-demo", "src/apps/net-demo.zig", null, optimize, &.{});

        {
            ctx.createAshetApp("wiki", "src/apps/wiki/wiki.zig", "artwork/icons/small-icons/32x32-free-design-icons/32x32/Help book.png", optimize, &.{
                .{ .name = "hypertext", .module = mod_libhypertext },
                .{ .name = "hyperdoc", .module = mod_hyperdoc },
                .{ .name = "ui-layout", .module = ui_gen.render(.{ .path = b.pathFromRoot("src/apps/wiki/ui.lua") }) },
            });
        }

        {
            ctx.createAshetApp("dungeon", "src/apps/dungeon/dungeon.zig", "artwork/apps/dungeon/dungeon.png", optimize, &.{});
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/floor.png", "src/apps/dungeon/data/floor.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-plain.png", "src/apps/dungeon/data/wall-plain.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-cobweb.png", "src/apps/dungeon/data/wall-cobweb.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-paper.png", "src/apps/dungeon/data/wall-paper.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-vines.png", "src/apps/dungeon/data/wall-vines.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-door.png", "src/apps/dungeon/data/wall-door.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-post-l.png", "src/apps/dungeon/data/wall-post-l.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/wall-post-r.png", "src/apps/dungeon/data/wall-post-r.abm", .{ 32, 32 });
            // addBitmap(dungeon, bmpconv, "artwork/dungeon/enforcer.png", "src/apps/dungeon/data/enforcer.abm", .{ 32, 60 });
        }
    }

    {
        const wikitool = b.addExecutable(.{
            .name = "wikitool",
            .root_source_file = .{ .path = "tools/wikitool.zig" },
        });

        wikitool.addModule("hypertext", mod_libhypertext);
        wikitool.addModule("hyperdoc", mod_hyperdoc);
        wikitool.addModule("args", mod_args);
        wikitool.addModule("zigimg", mod_zigimg);
        wikitool.addModule("ashet", mod_libashet);
        wikitool.addModule("ashet-gui", mod_ashet_gui);

        b.installArtifact(wikitool);
    }

    if (b.option([]const u8, "test-ui", "If set to a file, will compile the ui-layout-tester tool based on the file passed")) |file_name| {
        const ui_tester = b.addExecutable(.{
            .name = "ui-layout-tester",
            .root_source_file = .{ .path = "tools/ui-layout-tester.zig" },
        });

        ui_tester.addModule("ashet", mod_libashet);
        ui_tester.addModule("ashet-gui", mod_ashet_gui);
        ui_tester.addModule("ui-layout", ui_gen.render(.{ .path = b.pathFromRoot(file_name) }));

        ui_tester.linkSystemLibrary("sdl2");
        b.installArtifact(ui_tester);
        ui_tester.linkLibC();
    }

    const std_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/std/std.zig" },
        .target = .{},
        .optimize = optimize,
    });

    const fs_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/libafs/testsuite.zig" },
        .target = .{},
        .optimize = optimize,
    });

    const gui_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/libgui/gui.zig" },
        .target = .{},
        .optimize = optimize,
    });
    {
        var iter = b.modules.get("ashet-gui").?.dependencies.iterator();
        while (iter.next()) |kv| {
            gui_tests.addModule(kv.key_ptr.*, kv.value_ptr.*);
        }
    }

    const test_step = b.step("test", "Run unit tests on the standard library");
    test_step.dependOn(&b.addRunArtifact(std_tests).step);
    test_step.dependOn(&b.addRunArtifact(gui_tests).step);
    test_step.dependOn(&b.addRunArtifact(fs_tests).step);
    {
        const debug_filter = b.addExecutable(.{
            .name = "debug-filter",
            .root_source_file = .{ .path = "tools/debug-filter.zig" },
        });
        debug_filter.linkLibC();
        const install_step = b.addInstallArtifact(debug_filter);

        b.getInstallStep().dependOn(&install_step.step);

        tools_step.dependOn(&install_step.step);
    }

    {
        const init_disk = b.addExecutable(.{
            .name = "init-disk",
            .root_source_file = .{ .path = "tools/init-disk.zig" },
        });
        init_disk.linkLibC();
        init_disk.addModule("fatfs", fatfs_module);
        init_disk.addModule("args", mod_args);
        const install_step = b.addInstallArtifact(init_disk);
        FatFS.link(init_disk, fatfs_config);

        tools_step.dependOn(&install_step.step);
        b.getInstallStep().dependOn(&install_step.step);
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

const BitmapConverter = struct {
    builder: *std.Build,
    converter: *std.Build.CompileStep,

    pub fn init(builder: *std.Build) BitmapConverter {
        const zig_args_module = builder.dependency("args", .{}).module("args");
        const zigimg = builder.dependency("zigimg", .{}).module("zigimg");

        const tool_mkicon = builder.addExecutable(.{ .name = "tool_mkicon", .root_source_file = .{ .path = "tools/mkicon.zig" } });
        tool_mkicon.addModule("zigimg", zigimg);
        tool_mkicon.addModule("ashet-abi", builder.modules.get("ashet-abi").?);
        tool_mkicon.addModule("args", zig_args_module);

        return BitmapConverter{
            .builder = builder,
            .converter = tool_mkicon,
        };
    }

    pub const Options = struct {
        palette: Palette = .{ .sized = 15 },
        geometry: ?[2]u32 = null,

        const Palette = union(enum) {
            predefined: []const u8,
            sized: u8,
        };
    };

    pub fn convert(conv: BitmapConverter, source: std.Build.FileSource, basename: []const u8, options: Options) std.Build.FileSource {
        const mkicon = conv.builder.addRunArtifact(conv.converter);

        mkicon.addFileSourceArg(source);

        switch (options.palette) {
            .predefined => |palette| {
                mkicon.addArg("--palette");
                mkicon.addFileSourceArg(.{ .path = palette });
            },
            .sized => |size| {
                mkicon.addArg("--color-count");
                mkicon.addArg(conv.builder.fmt("{d}", .{size}));
            },
        }
        if (options.geometry) |geometry| {
            mkicon.addArg("--geometry");
            mkicon.addArg(conv.builder.fmt("{}x{}", .{ geometry[0], geometry[1] }));
        }

        mkicon.addArg("-o");
        const result = mkicon.addOutputFileArg(basename);

        return result;
    }
};

const AssetBundleStep = struct {
    step: std.Build.Step,
    builder: *std.build.Builder,
    files: std.StringHashMap(std.Build.FileSource),
    output_file: std.Build.GeneratedFile,

    pub fn create(builder: *std.Build) *AssetBundleStep {
        const bundle = builder.allocator.create(AssetBundleStep) catch @panic("oom");
        errdefer builder.allocator.destroy(bundle);

        bundle.* = AssetBundleStep{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "bundle assets",
                .owner = builder,
                .makeFn = make,
                .first_ret_addr = null,
                .max_rss = 0,
            }),
            .builder = builder,
            .files = std.StringHashMap(std.Build.FileSource).init(builder.allocator),
            .output_file = .{ .step = &bundle.step },
        };

        return bundle;
    }

    pub fn add(bundle: *AssetBundleStep, path: []const u8, item: std.Build.FileSource) void {
        bundle.files.putNoClobber(
            bundle.builder.dupe(path),
            item,
        ) catch @panic("oom");
        item.addStepDependencies(&bundle.step);

        const install_step = bundle.builder.addInstallFile(item, path);
        install_step.dir = rootfs_dir;
        bundle.builder.getInstallStep().dependOn(&install_step.step);
    }

    pub fn getOutput(bundle: *AssetBundleStep) std.Build.FileSource {
        return std.Build.FileSource{
            .generated = &bundle.output_file,
        };
    }

    fn make(step: *std.build.Step, node: *std.Progress.Node) !void {
        const bundle = @fieldParentPtr(AssetBundleStep, "step", step);

        var write_step = std.Build.WriteFileStep.create(bundle.builder);

        var embed_file = std.ArrayList(u8).init(bundle.builder.allocator);
        defer embed_file.deinit();

        const writer = embed_file.writer();

        try writer.writeAll(
            \\//! AUTOGENERATED CODE
            \\
        );

        {
            var it = bundle.files.iterator();
            while (it.next()) |kv| {
                _ = write_step.addCopyFile(
                    kv.value_ptr.*,
                    bundle.builder.fmt("blobs/{s}", .{kv.key_ptr.*}),
                );
                try writer.print("pub const {} = @embedFile(\"blobs/{}\");\n", .{
                    std.zig.fmtId(kv.key_ptr.*),
                    std.zig.fmtEscapes(kv.key_ptr.*),
                });
            }
        }

        const bundle_file_source = write_step.add("bundle.zig", try embed_file.toOwnedSlice());

        try write_step.step.makeFn(&write_step.step, node);

        bundle.output_file.path = bundle_file_source.getPath(bundle.builder);
    }
};
