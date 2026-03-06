const std = @import("std");
const emu = @import("emulator");
const args_parser = @import("args");
const zgui = @import("zgui");
const glfw = @import("zglfw");
const zopengl = @import("zopengl");
const palette = @import("palette.zig");

const gl = zopengl.bindings;

const FB_WIDTH = emu.Framebuffer.WIDTH;
const FB_HEIGHT = emu.Framebuffer.HEIGHT;
const FB_PIXELS = FB_WIDTH * FB_HEIGHT;

const DEFAULT_RAM_SIZE = 8 * 1024 * 1024;
const INSTRUCTIONS_PER_FRAME = 10_000;

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const CliOptions = struct {
    @"ram-size": u32 = DEFAULT_RAM_SIZE,
    disk0: ?[]const u8 = null,
    disk1: ?[]const u8 = null,
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
    };

    pub const meta = .{
        .@"ram-size" = .{ .description = "RAM size in bytes (default 8MB)" },
        .disk0 = .{ .description = "Block device 0 image file" },
        .disk1 = .{ .description = "Block device 1 image file" },
    };
};

// ---------------------------------------------------------------------------
// Debug log ring buffer
// ---------------------------------------------------------------------------

const DebugLog = struct {
    const MAX_LINES = 1000;
    const LINE_LEN = 256;

    lines: [MAX_LINES][LINE_LEN]u8 = undefined,
    lengths: [MAX_LINES]u16 = .{0} ** MAX_LINES,
    write_pos: usize = 0,
    line_count: usize = 0,

    current_line: [LINE_LEN]u8 = undefined,
    current_len: usize = 0,

    fn pushByte(self: *DebugLog, byte: u8) void {
        if (byte == '\n') {
            self.flushLine();
            return;
        }
        if (self.current_len < LINE_LEN) {
            self.current_line[self.current_len] = byte;
            self.current_len += 1;
        }
    }

    fn flushLine(self: *DebugLog) void {
        const dst = self.write_pos % MAX_LINES;
        const len = self.current_len;
        @memcpy(self.lines[dst][0..len], self.current_line[0..len]);
        self.lengths[dst] = @intCast(len);
        self.write_pos += 1;
        if (self.line_count < MAX_LINES) self.line_count += 1;
        self.current_len = 0;
    }

    fn getLine(self: *const DebugLog, index: usize) []const u8 {
        const start = if (self.line_count < MAX_LINES) 0 else self.write_pos - MAX_LINES;
        const pos = (start + index) % MAX_LINES;
        return self.lines[pos][0..self.lengths[pos]];
    }
};

// ---------------------------------------------------------------------------
// Custom writer for DebugOutput: ring buffer + stdout mirror
// ---------------------------------------------------------------------------

const DebugWriter = struct {
    log: *DebugLog,
    stdout: ?*std.Io.Writer,
    interface: std.Io.Writer = undefined,

    const vtable: std.Io.Writer.VTable = .{
        .drain = drain,
        .flush = flush,
    };

    fn init(buf: []u8, log: *DebugLog, stdout: ?*std.Io.Writer) DebugWriter {
        return DebugWriter{
            .log = log,
            .stdout = stdout,
            .interface = .{
                .vtable = &vtable,
                .buffer = buf,
            },
        };
    }

    fn writeSlice(dw: *DebugWriter, data: []const u8) !void {
        for (data) |byte| {
            dw.log.pushByte(byte);
        }
        if (dw.stdout) |stdout| {
            try stdout.writeAll(data);
        }
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *DebugWriter = @fieldParentPtr("interface", w);

        // First consume whatever was in the buffer:
        try self.writeSlice(self.interface.buffer[0..self.interface.end]);
        self.interface.end = 0;

        var total: usize = 0;
        if (data.len > 0) {
            for (data[0 .. data.len - 1]) |bytes| {
                try self.writeSlice(bytes);
                total += bytes.len;
            }
            // Handle the last (possibly splatted) slice
            const last = data[data.len - 1];
            for (0..splat) |_| {
                try self.writeSlice(last);
                total += last.len;
            }
        }

        return total;
    }

    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *DebugWriter = @fieldParentPtr("interface", w);

        try std.Io.Writer.defaultFlush(w);

        if (self.stdout) |stdout| {
            try stdout.flush();
        }
    }
};

// ---------------------------------------------------------------------------
// Emulator application state
// ---------------------------------------------------------------------------

const EmulatorApp = struct {
    // Memory
    allocator: std.mem.Allocator,
    rom: []align(4) const u8,
    ram: []align(4) u8,

    // Emulator
    system: emu.System,

    // Peripherals
    framebuffer: emu.Framebuffer,
    video_control: emu.VideoControl,
    debug_output: emu.DebugOutput,
    keyboard: emu.Keyboard,
    mouse: emu.Mouse,
    timer: emu.Timer,
    system_info: emu.SystemInfo,
    block_devices: [2]emu.BlockDevice,

    // Debug log
    stdout_write_buffer: [4096]u8 = undefined,
    stdout_writer: std.fs.File.Writer,
    debug_log: DebugLog,

    debug_writer_buf: [256]u8 = undefined,
    debug_writer: DebugWriter,

    // OpenGL framebuffer texture
    fb_texture: gl.Uint = 0,
    rgba_buffer: [FB_PIXELS * 4]u8 = .{0} ** (FB_PIXELS * 4),

    // Execution state
    running: bool = true,
    speed_multiplier: f32 = 1.0,
    start_time: std.time.Instant,
    last_error: ?emu.CpuError = null,
    prev_instructions: u64 = 0,
    prev_time: std.time.Instant,
    ips: f64 = 0,
    ips_update_timer: f64 = 0,

    // GUI state
    dock_layout_done: bool = false,
    screen_origin: [2]f32 = .{ 0, 0 },
    screen_scale: f32 = 1.0,

    // Options
    live_video_update: bool = false,

    // Block device files
    block_files: [2]?std.fs.File = .{ null, null },

    // Memory view state
    mem_view_addr: u32 = 0,
    mem_view_addr_buf: [9:0]u8 = .{'0'} ** 9,

    fn create(allocator: std.mem.Allocator, rom: []align(4) const u8, ram_size: u32, disk_paths: [2]?[]const u8) !*EmulatorApp {
        const ram = try allocator.alignedAlloc(u8, .@"4", ram_size);
        @memset(ram, 0);

        const app = try allocator.create(EmulatorApp);
        app.* = .{
            .allocator = allocator,

            .start_time = std.time.Instant.now() catch @panic("no monotonic clock"),
            .prev_time = std.time.Instant.now() catch @panic("no monotonic clock"),

            .debug_log = .{},

            .stdout_write_buffer = undefined,
            .stdout_writer = std.fs.File.stdout().writer(&app.stdout_write_buffer),

            .debug_writer_buf = undefined,
            .debug_writer = .init(
                &app.debug_writer_buf,
                &app.debug_log,
                &app.stdout_writer.interface,
            ),

            .rom = rom,
            .ram = ram,
            .system = emu.System.init(rom, ram),
            .framebuffer = .{},
            .video_control = .{},
            .debug_output = emu.DebugOutput.init(&app.debug_writer.interface),
            .keyboard = .{},
            .mouse = .{},
            .timer = .{},
            .system_info = emu.SystemInfo.init(ram_size),
            .block_devices = .{
                emu.BlockDevice.init(disk_paths[0] != null, 0),
                emu.BlockDevice.init(disk_paths[1] != null, 0),
            },
        };

        // Open block device files and set block counts
        for (disk_paths, 0..) |maybe_path, i| {
            if (maybe_path) |path| {
                const file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| {
                    std.log.err("failed to open disk{d} '{s}': {}", .{ i, path, err });
                    app.block_devices[i] = emu.BlockDevice.init(false, 0);
                    continue;
                };
                const size = file.getEndPos() catch 0;
                const block_count: u32 = @intCast(size / emu.BlockDevice.BLOCK_SIZE);
                app.block_devices[i] = emu.BlockDevice.init(true, block_count);
                app.block_files[i] = file;
            }
        }

        // Wire MMIO page table
        app.system.mmio.mapRange(0x00, emu.Framebuffer.PAGE_COUNT, app.framebuffer.peripheral());
        app.system.mmio.map(0x40, app.video_control.peripheral());
        app.system.mmio.map(0x41, app.debug_output.peripheral());
        app.system.mmio.map(0x42, app.keyboard.peripheral());
        app.system.mmio.map(0x43, app.mouse.peripheral());
        app.system.mmio.map(0x44, app.timer.peripheral());
        app.system.mmio.map(0x45, app.system_info.peripheral());
        app.system.mmio.map(0x46, app.block_devices[0].peripheral());
        app.system.mmio.map(0x47, app.block_devices[1].peripheral());

        // Fill framebuffer with static noise so the screen pipeline is visible
        const pixels = app.framebuffer.pixels();

        var rng = std.Random.DefaultPrng.init(@truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
        for (pixels) |*p| {
            p.* = rng.random().int(u8);
        }

        return app;
    }

    fn destroy(app: *EmulatorApp) void {
        for (&app.block_files) |*mf| {
            if (mf.*) |f| f.close();
            mf.* = null;
        }
        app.allocator.free(app.ram);
        app.allocator.destroy(app);
    }

    // -----------------------------------------------------------------------
    // Per-frame logic
    // -----------------------------------------------------------------------

    fn updateTimer(app: *EmulatorApp) void {
        const now = std.time.Instant.now() catch return;
        const elapsed_ns = now.since(app.start_time);
        const mtime_us: u64 = elapsed_ns / 1000;
        const rtc_s: u64 = @intCast(@max(0, std.time.timestamp()));
        app.timer.setTime(mtime_us, rtc_s);
    }

    fn stepEmulator(app: *EmulatorApp) void {
        if (!app.running) return;

        const batch: usize = @intFromFloat(@max(1.0, @as(f32, INSTRUCTIONS_PER_FRAME) * app.speed_multiplier));

        const result_or_err = app.system.step(batch);

        app.debug_writer.interface.flush() catch @panic("flush error"); // flush the emulator-writen data to the ring buffer + stdout writer

        if (result_or_err) |_| {
            // ok
        } else |err| {
            app.running = false;
            app.last_error = err;

            std.debug.print("\r\n<<cpu halt: {t} @ 0x{X:0>8}>>\r\n", .{
                err,
                app.system.cpu.pc,
            });

            if (app.system.last_memory_error) |mem_err| {
                std.debug.print("\r\n<<memory error: {t} @ 0x{X:0>8}/{t} => {t}>>\r\n", .{
                    mem_err.op,
                    mem_err.address,
                    mem_err.size,
                    mem_err.err,
                });
            }
        }
    }

    fn updateFramebufferTexture(app: *EmulatorApp) void {
        if (app.live_video_update) {
            app.forceTextureUpload();
            return;
        }
        if (!app.video_control.isFlushRequested()) return;
        app.forceTextureUpload();
        app.video_control.ackFlush();
    }

    fn forceTextureUpload(app: *EmulatorApp) void {
        const pixels = app.framebuffer.pixelsConst();
        for (0..FB_PIXELS) |i| {
            const rgba = palette.table[pixels[i]];
            app.rgba_buffer[i * 4 + 0] = rgba[0];
            app.rgba_buffer[i * 4 + 1] = rgba[1];
            app.rgba_buffer[i * 4 + 2] = rgba[2];
            app.rgba_buffer[i * 4 + 3] = rgba[3];
        }

        gl.bindTexture(gl.TEXTURE_2D, app.fb_texture);
        gl.texSubImage2D(
            gl.TEXTURE_2D,
            0,
            0,
            0,
            FB_WIDTH,
            FB_HEIGHT,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            @ptrCast(&app.rgba_buffer),
        );
    }

    fn pollBlockDevices(app: *EmulatorApp) void {
        for (&app.block_devices, &app.block_files) |*bd, *maybe_file| {
            if (bd.getPendingRequest()) |req| {
                const file = maybe_file.* orelse {
                    bd.complete(false) catch {};
                    continue;
                };
                const offset = @as(u64, req.lba) * emu.BlockDevice.BLOCK_SIZE;
                if (req.is_write) {
                    file.seekTo(offset) catch {
                        bd.complete(false) catch {};
                        continue;
                    };
                    file.writeAll(bd.transferBuffer()) catch {
                        bd.complete(false) catch {};
                        continue;
                    };
                } else {
                    file.seekTo(offset) catch {
                        bd.complete(false) catch {};
                        continue;
                    };
                    const buf = bd.transferBuffer();
                    const n = file.readAll(buf) catch {
                        bd.complete(false) catch {};
                        continue;
                    };
                    if (n < emu.BlockDevice.BLOCK_SIZE) @memset(buf[n..], 0);
                }
                bd.complete(true) catch {};
            }
        }
    }

    // -----------------------------------------------------------------------
    // GUI rendering
    // -----------------------------------------------------------------------

    fn renderGui(app: *EmulatorApp) void {
        app.updateIps();
        app.setupDockspace();
        app.renderMenuBar();
        app.renderScreenPane();
        app.renderDebugTerminal();
        app.renderControlPanel();
        app.renderOptionsPanel();
        app.renderMemoryView();
    }

    fn updateIps(app: *EmulatorApp) void {
        const now = std.time.Instant.now() catch return;
        const elapsed_ns = now.since(app.prev_time);
        const elapsed_s: f64 = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        app.ips_update_timer += elapsed_s;
        if (app.ips_update_timer >= 0.5) {
            const current = app.system.cpu.total_instructions;
            const delta = current - app.prev_instructions;
            app.ips = @as(f64, @floatFromInt(delta)) / app.ips_update_timer;
            app.prev_instructions = current;
            app.ips_update_timer = 0;
        }
        app.prev_time = now;
    }

    fn setupDockspace(app: *EmulatorApp) void {
        const dockspace_id = zgui.dockSpaceOverViewport(0, zgui.getMainViewport(), .{ .auto_hide_tab_bar = true });

        if (app.dock_layout_done) return;
        app.dock_layout_done = true;

        var center_id = dockspace_id;
        const left_id = zgui.dockBuilderSplitNode(dockspace_id, .left, 0.15, null, &center_id);
        const right_id = zgui.dockBuilderSplitNode(center_id, .right, 0.30, null, &center_id);

        var screen_id = center_id;
        const bottom_id = zgui.dockBuilderSplitNode(center_id, .down, 0.25, null, &screen_id);

        var control_id = left_id;
        const options_id = zgui.dockBuilderSplitNode(left_id, .down, 0.3, null, &control_id);

        zgui.dockBuilderDockWindow("Control Panel", control_id);
        zgui.dockBuilderDockWindow("Options", options_id);
        zgui.dockBuilderDockWindow("Emulator Screen", screen_id);
        zgui.dockBuilderDockWindow("Debug Terminal", bottom_id);
        zgui.dockBuilderDockWindow("Memory View", right_id);
        zgui.dockBuilderFinish(dockspace_id);
    }

    fn renderMenuBar(app: *EmulatorApp) void {
        if (!zgui.beginMainMenuBar()) return;
        defer zgui.endMainMenuBar();

        if (zgui.beginMenu("Emulator", true)) {
            defer zgui.endMenu();

            if (zgui.menuItem(if (app.running) "Pause" else "Run", .{ .shortcut = "F5" })) {
                app.running = !app.running;
                if (app.running) app.last_error = null;
            }
            if (zgui.menuItem("Step", .{ .shortcut = "F10" })) {
                app.running = false;
                _ = app.system.step(1) catch |err| {
                    app.last_error = err;
                };
            }
            if (zgui.menuItem("Reset", .{ .shortcut = "Ctrl+R" })) {
                app.system.cpu = .{};
                app.running = false;
                app.last_error = null;
                app.prev_instructions = 0;
                app.ips = 0;
                app.start_time = std.time.Instant.now() catch app.start_time;
                app.prev_time = std.time.Instant.now() catch app.prev_time;
            }

            zgui.separator();
            if (zgui.menuItem("Quit", .{ .shortcut = "Ctrl+Q" })) {
                std.process.exit(0);
            }
        }

        if (zgui.beginMenu("View", true)) {
            defer zgui.endMenu();
            _ = zgui.menuItem("Control Panel", .{});
            _ = zgui.menuItem("Debug Terminal", .{});
            _ = zgui.menuItem("Memory View", .{});
            _ = zgui.menuItem("Options", .{});
        }
    }

    fn renderScreenPane(app: *EmulatorApp) void {
        defer zgui.end();
        if (!zgui.begin("Emulator Screen", .{})) return;

        const avail = zgui.getContentRegionAvail();
        if (avail[0] <= 0 or avail[1] <= 0) return;

        const scale = @min(avail[0] / @as(f32, FB_WIDTH), avail[1] / @as(f32, FB_HEIGHT));
        const w = @as(f32, FB_WIDTH) * scale;
        const h = @as(f32, FB_HEIGHT) * scale;

        // Center horizontally
        const pad_x = (avail[0] - w) / 2.0;
        if (pad_x > 0) {
            const cur = zgui.getCursorPos();
            zgui.setCursorPos(.{ cur[0] + pad_x, cur[1] });
        }

        app.screen_origin = zgui.getCursorScreenPos();
        app.screen_scale = scale;

        const tex_ref: zgui.TextureRef = .{
            .tex_data = null,
            .tex_id = @enumFromInt(app.fb_texture),
        };
        zgui.image(tex_ref, .{ .w = w, .h = h });
    }

    fn renderDebugTerminal(app: *EmulatorApp) void {
        defer zgui.end();
        if (!zgui.begin("Debug Terminal", .{})) return;

        for (0..app.debug_log.line_count) |i| {
            const line = app.debug_log.getLine(i);
            if (line.len > 0) {
                zgui.textUnformatted(line);
            } else {
                zgui.textUnformatted(" ");
            }
        }

        // Auto-scroll to bottom
        if (zgui.getScrollY() >= zgui.getScrollMaxY() - 1) {
            zgui.setScrollHereY(.{ .center_y_ratio = 1.0 });
        }
    }

    fn renderControlPanel(app: *EmulatorApp) void {
        defer zgui.end();
        if (!zgui.begin("Control Panel", .{})) return;

        // Run/Pause/Step/Reset buttons
        if (zgui.button(if (app.running) "Pause" else "Run", .{})) {
            app.running = !app.running;
            if (app.running) app.last_error = null;
        }
        zgui.sameLine(.{});
        if (zgui.button("Step", .{})) {
            app.running = false;
            _ = app.system.step(1) catch |err| {
                app.last_error = err;
            };
        }
        zgui.sameLine(.{});
        if (zgui.button("Reset", .{})) {
            app.system.cpu = .{};
            app.running = false;
            app.last_error = null;
            app.prev_instructions = 0;
            app.ips = 0;
            app.start_time = std.time.Instant.now() catch app.start_time;
            app.prev_time = std.time.Instant.now() catch app.prev_time;
        }

        // Speed control
        zgui.separator();
        _ = zgui.sliderFloat("Speed", .{ .v = &app.speed_multiplier, .min = 0.1, .max = 10.0 });

        // Error display
        if (app.last_error) |err| {
            zgui.separator();
            zgui.textUnformattedColored(.{ 1.0, 0.3, 0.3, 1.0 }, @errorName(err));
        }

        // Stats
        zgui.separator();
        var stats_buf: [60]u8 = undefined;
        const stats_str = std.fmt.bufPrint(&stats_buf, "Instructions: {d}", .{app.system.cpu.total_instructions}) catch "??";
        zgui.textUnformatted(stats_str);

        var ips_buf: [40]u8 = undefined;
        const ips_str = if (app.ips >= 1_000_000)
            std.fmt.bufPrint(&ips_buf, "IPS: {d:.2} M", .{app.ips / 1_000_000.0}) catch "??"
        else if (app.ips >= 1_000)
            std.fmt.bufPrint(&ips_buf, "IPS: {d:.2} K", .{app.ips / 1_000.0}) catch "??"
        else
            std.fmt.bufPrint(&ips_buf, "IPS: {d:.0}", .{app.ips}) catch "??";
        zgui.textUnformatted(ips_str);

        // Registers
        zgui.separator();
        zgui.textUnformatted("Registers");
        zgui.separator();

        if (zgui.beginTable("regs", .{ .column = 2, .flags = .{ .borders = .{ .inner_v = true } } })) {
            defer zgui.endTable();

            zgui.tableSetupColumn("Reg", .{ .flags = .{ .width_fixed = true }, .init_width_or_height = 30 });
            zgui.tableSetupColumn("Value", .{ .flags = .{ .width_stretch = true } });

            // PC
            zgui.tableNextRow(.{});
            _ = zgui.tableNextColumn();
            zgui.textUnformatted("PC");
            _ = zgui.tableNextColumn();
            var pc_buf: [11:0]u8 = undefined;
            _ = std.fmt.bufPrint(&pc_buf, "0x{X:0>8}", .{app.system.cpu.pc}) catch {};
            pc_buf[10] = 0;
            zgui.setNextItemWidth(-1);
            _ = zgui.inputText("##pc", .{ .buf = &pc_buf, .flags = .{ .read_only = true } });

            // x0-x31
            for (0..32) |reg| {
                const val = app.system.cpu.read_reg(@intCast(reg));
                zgui.pushIntId(@intCast(reg));
                defer zgui.popId();
                zgui.tableNextRow(.{});
                _ = zgui.tableNextColumn();
                var label_buf: [4]u8 = undefined;
                const label = std.fmt.bufPrint(&label_buf, "x{d}", .{reg}) catch "??";
                zgui.textUnformatted(label);
                _ = zgui.tableNextColumn();
                var val_buf: [11:0]u8 = undefined;
                _ = std.fmt.bufPrint(&val_buf, "0x{X:0>8}", .{val}) catch {};
                val_buf[10] = 0;
                zgui.setNextItemWidth(-1);
                _ = zgui.inputText("##reg", .{ .buf = &val_buf, .flags = .{ .read_only = true } });
            }
        }
    }

    fn renderOptionsPanel(app: *EmulatorApp) void {
        defer zgui.end();
        if (!zgui.begin("Options", .{})) return;

        _ = zgui.checkbox("Live video update", .{ .v = &app.live_video_update });
        if (zgui.isItemHovered(.{})) {
            if (zgui.beginTooltip()) {
                defer zgui.endTooltip();
                zgui.textUnformatted("Update display every frame, ignoring the flush flag");
            }
        }
    }

    fn renderMemoryView(app: *EmulatorApp) void {
        defer zgui.end();
        if (!zgui.begin("Memory View", .{})) return;

        // Address input
        if (zgui.inputText("Address", .{ .buf = &app.mem_view_addr_buf })) {
            // Parse hex address from the buffer
            const slice = std.mem.sliceTo(&app.mem_view_addr_buf, 0);
            app.mem_view_addr = std.fmt.parseInt(u32, slice, 16) catch app.mem_view_addr;
        }

        zgui.separator();

        // Hex dump: 16 rows of 16 bytes
        const base = app.mem_view_addr & 0xFFFFFFF0; // align to 16
        for (0..16) |row| {
            const row_addr = base +% @as(u32, @intCast(row * 16));
            var line_buf: [80]u8 = undefined;
            var pos: usize = 0;

            // Address
            const addr_str = std.fmt.bufPrint(line_buf[pos..], "{X:0>8}  ", .{row_addr}) catch break;
            pos += addr_str.len;

            // Hex bytes
            var ascii_buf: [16]u8 = undefined;
            for (0..16) |col| {
                const addr = row_addr +% @as(u32, @intCast(col));
                const byte = app.system.bus_read(addr, .u8) catch null;
                if (byte) |b| {
                    const hex = std.fmt.bufPrint(line_buf[pos..], "{X:0>2} ", .{b}) catch break;
                    pos += hex.len;
                    ascii_buf[col] = if (b >= 0x20 and b < 0x7F) b else '.';
                } else {
                    const hex = std.fmt.bufPrint(line_buf[pos..], "?? ", .{}) catch break;
                    pos += hex.len;
                    ascii_buf[col] = '.';
                }
            }

            // ASCII
            const sep = std.fmt.bufPrint(line_buf[pos..], " ", .{}) catch break;
            pos += sep.len;
            if (pos + 16 <= line_buf.len) {
                @memcpy(line_buf[pos..][0..16], &ascii_buf);
                pos += 16;
            }

            zgui.textUnformatted(line_buf[0..pos]);
        }
    }

    // -----------------------------------------------------------------------
    // Input handling
    // -----------------------------------------------------------------------

    fn processMouseInput(app: *EmulatorApp, window: *glfw.Window) void {
        const cursor = window.getCursorPos();
        const mx = @as(f32, @floatCast(cursor[0]));
        const my = @as(f32, @floatCast(cursor[1]));

        // Transform window coords to framebuffer coords
        const fb_x = (mx - app.screen_origin[0]) / app.screen_scale;
        const fb_y = (my - app.screen_origin[1]) / app.screen_scale;

        var buttons: u32 = 0;
        if (window.getMouseButton(.left) == .press) buttons |= 1;
        if (window.getMouseButton(.right) == .press) buttons |= 2;
        if (window.getMouseButton(.middle) == .press) buttons |= 4;

        app.mouse.setState(@intFromFloat(fb_x), @intFromFloat(fb_y), buttons);
    }

    // -----------------------------------------------------------------------
    // OpenGL texture setup
    // -----------------------------------------------------------------------

    fn createFramebufferTexture(app: *EmulatorApp) void {
        gl.genTextures(1, @ptrCast(&app.fb_texture));
        gl.bindTexture(gl.TEXTURE_2D, app.fb_texture);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texImage2D(
            gl.TEXTURE_2D,
            0,
            gl.RGBA,
            FB_WIDTH,
            FB_HEIGHT,
            0,
            gl.RGBA,
            gl.UNSIGNED_BYTE,
            @ptrCast(&app.rgba_buffer),
        );
    }
};

// ---------------------------------------------------------------------------
// GLFW key callback
// ---------------------------------------------------------------------------

fn keyCallback(window: *glfw.Window, key: glfw.Key, _: c_int, action: glfw.Action, _: glfw.Mods) callconv(.c) void {
    // Don't forward to emulator if ImGui wants keyboard input
    if (zgui.io.getWantCaptureKeyboard()) return;

    const app: *EmulatorApp = window.getUserPointer(EmulatorApp) orelse return;

    if (action == .repeat) return;
    const state: emu.Keyboard.KeyState = if (action == .press) .down else .up;

    if (glfwKeyToHid(key)) |hid| {
        _ = app.keyboard.pushKey(hid, state);
    }
}

fn glfwKeyToHid(key: glfw.Key) ?u16 {
    return switch (key) {
        // Letters: A-Z -> HID 0x04-0x1D
        .a => 0x04,
        .b => 0x05,
        .c => 0x06,
        .d => 0x07,
        .e => 0x08,
        .f => 0x09,
        .g => 0x0A,
        .h => 0x0B,
        .i => 0x0C,
        .j => 0x0D,
        .k => 0x0E,
        .l => 0x0F,
        .m => 0x10,
        .n => 0x11,
        .o => 0x12,
        .p => 0x13,
        .q => 0x14,
        .r => 0x15,
        .s => 0x16,
        .t => 0x17,
        .u => 0x18,
        .v => 0x19,
        .w => 0x1A,
        .x => 0x1B,
        .y => 0x1C,
        .z => 0x1D,
        // Digits: 1-0 -> HID 0x1E-0x27
        .one => 0x1E,
        .two => 0x1F,
        .three => 0x20,
        .four => 0x21,
        .five => 0x22,
        .six => 0x23,
        .seven => 0x24,
        .eight => 0x25,
        .nine => 0x26,
        .zero => 0x27,
        // Control keys
        .enter => 0x28,
        .escape => 0x29,
        .backspace => 0x2A,
        .tab => 0x2B,
        .space => 0x2C,
        .minus => 0x2D,
        .equal => 0x2E,
        .left_bracket => 0x2F,
        .right_bracket => 0x30,
        .backslash => 0x31,
        .semicolon => 0x33,
        .apostrophe => 0x34,
        .grave_accent => 0x35,
        .comma => 0x36,
        .period => 0x37,
        .slash => 0x38,
        .caps_lock => 0x39,
        // F keys
        .F1 => 0x3A,
        .F2 => 0x3B,
        .F3 => 0x3C,
        .F4 => 0x3D,
        .F5 => 0x3E,
        .F6 => 0x3F,
        .F7 => 0x40,
        .F8 => 0x41,
        .F9 => 0x42,
        .F10 => 0x43,
        .F11 => 0x44,
        .F12 => 0x45,
        // Navigation
        .print_screen => 0x46,
        .scroll_lock => 0x47,
        .pause => 0x48,
        .insert => 0x49,
        .home => 0x4A,
        .page_up => 0x4B,
        .delete => 0x4C,
        .end => 0x4D,
        .page_down => 0x4E,
        .right => 0x4F,
        .left => 0x50,
        .down => 0x51,
        .up => 0x52,
        .num_lock => 0x53,
        // Keypad
        .kp_divide => 0x54,
        .kp_multiply => 0x55,
        .kp_subtract => 0x56,
        .kp_add => 0x57,
        .kp_enter => 0x58,
        .kp_1 => 0x59,
        .kp_2 => 0x5A,
        .kp_3 => 0x5B,
        .kp_4 => 0x5C,
        .kp_5 => 0x5D,
        .kp_6 => 0x5E,
        .kp_7 => 0x5F,
        .kp_8 => 0x60,
        .kp_9 => 0x61,
        .kp_0 => 0x62,
        .kp_decimal => 0x63,
        // Modifiers
        .left_control => 0xE0,
        .left_shift => 0xE1,
        .left_alt => 0xE2,
        .left_super => 0xE3,
        .right_control => 0xE4,
        .right_shift => 0xE5,
        .right_alt => 0xE6,
        .right_super => 0xE7,
        .menu => 0x65,
        else => null,
    };
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

pub fn main() !u8 {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = args_parser.parseForCurrentProcess(CliOptions, allocator, .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        var stderr_buf: [1024]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
        args_parser.printHelp(CliOptions, "emulator", &stderr_writer.interface) catch {};
        stderr_writer.interface.flush() catch {};
        return 0;
    }

    // Load ROM
    const rom_path: []const u8 = if (cli.positionals.len > 0) cli.positionals[0] else {
        std.log.err("usage: emulator <rom.bin> [options]", .{});
        return 1;
    };

    const rom_file = std.fs.cwd().openFile(rom_path, .{}) catch |err| {
        std.log.err("cannot open ROM '{s}': {}", .{ rom_path, err });
        return 1;
    };
    defer rom_file.close();

    const rom_stat = try rom_file.stat();
    const rom_size = rom_stat.size;
    const rom = try allocator.alignedAlloc(u8, .@"4", rom_size);
    defer allocator.free(rom);

    var read_buf: [4096]u8 = undefined;
    var reader = rom_file.reader(&read_buf);
    reader.interface.readSliceAll(rom) catch {
        std.log.err("short read on ROM file", .{});
        return 1;
    };

    // Create emulator
    const app = try EmulatorApp.create(
        allocator,
        @alignCast(rom),
        cli.options.@"ram-size",
        .{ cli.options.disk0, cli.options.disk1 },
    );
    defer app.destroy();

    // Init GLFW + OpenGL
    try glfw.init();
    defer glfw.terminate();

    const gl_major = 4;
    const gl_minor = 0;
    glfw.windowHint(.context_version_major, gl_major);
    glfw.windowHint(.context_version_minor, gl_minor);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);
    glfw.windowHint(.opengl_forward_compat, true);
    glfw.windowHint(.client_api, .opengl_api);
    glfw.windowHint(.doublebuffer, true);

    const glfw_window = try glfw.Window.create(1280, 800, "Ashet OS Emulator", null);
    defer glfw_window.destroy();

    glfw_window.setSizeLimits(640, 400, -1, -1);
    glfw.makeContextCurrent(glfw_window);
    glfw.swapInterval(1);

    try zopengl.loadCoreProfile(glfw.getProcAddress, gl_major, gl_minor);

    // Set up input callbacks
    glfw_window.setUserPointer(@ptrCast(app));
    _ = glfw_window.setKeyCallback(keyCallback);

    // Init zgui
    zgui.init(allocator);
    defer zgui.deinit();

    zgui.io.setIniFilename(null);

    zgui.backend.init(glfw_window);
    defer zgui.backend.deinit();

    zgui.io.setConfigFlags(.{
        .dock_enable = true,
    });

    // Create framebuffer texture
    app.createFramebufferTexture();
    app.forceTextureUpload();

    // Main loop
    while (!glfw_window.shouldClose()) {
        glfw.pollEvents();

        app.updateTimer();
        app.processMouseInput(glfw_window);
        app.stepEmulator();
        app.pollBlockDevices();
        app.updateFramebufferTexture();

        const fb_size = glfw_window.getFramebufferSize();
        gl.viewport(0, 0, @intCast(fb_size[0]), @intCast(fb_size[1]));
        gl.clearBufferfv(gl.COLOR, 0, &[_]f32{ 0.1, 0.1, 0.1, 1.0 });

        zgui.backend.newFrame(@intCast(fb_size[0]), @intCast(fb_size[1]));
        app.renderGui();
        zgui.backend.draw();

        glfw_window.swapBuffers();
    }

    return 0;
}
