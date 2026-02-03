const std = @import("std");
const builtin = @import("builtin");
const machine_info = @import("machine-info");
const log = std.log.scoped(.main);

pub const abi = @import("ashet-abi");
pub const apps = @import("components/apps.zig");
pub const drivers = @import("drivers/drivers.zig");
pub const filesystem = @import("components/filesystem.zig");
pub const input = @import("components/input.zig");
pub const overlapped = @import("components/overlapped.zig");
pub const memory = @import("components/memory.zig");
pub const multi_tasking = @import("components/multi_tasking.zig");
pub const network = @import("components/network.zig");
pub const scheduler = @import("components/scheduler.zig");
pub const serial = @import("components/serial.zig");
pub const storage = @import("components/storage.zig");
pub const syscalls = @import("components/syscalls.zig");
pub const time = @import("components/time.zig");
pub const resources = @import("components/resources.zig");
pub const gui = @import("components/gui.zig");
pub const graphics = @import("components/graphics.zig");
pub const video = @import("components/video.zig");
pub const shared_memory = @import("components/shared_memory.zig");
pub const random = @import("components/random.zig");
pub const sync = @import("components/sync.zig");
pub const pipes = @import("components/pipes.zig");
pub const ipc = @import("components/ipc.zig");
pub const io = @import("components/io.zig");

pub const ports = @import("port/targets.zig");

pub const utils = @import("utils/utils.zig");

pub const platform_id: ports.Platform = machine_info.platform_id;
pub const machine_id: ports.Machine = machine_info.machine_id;

pub const platform = if (machine_id.is_hosted())
    @import("port/platform/hosted.zig")
else switch (platform_id) {
    .rv32 => @import("port/platform/rv32.zig"),
    .arm => @import("port/platform/arm.zig"),
    .x86 => @import("port/platform/x86.zig"),
};

pub const machine = switch (machine_id) {
    .@"x86-pc-generic" => @import("port/machine/x86/pc-generic/pc-generic.zig"),
    .@"rv32-qemu-virt" => @import("port/machine/rv32/qemu-virt/rv32-qemu-virt.zig"),
    .@"arm-ashet-hc" => @import("port/machine/arm/ashet-hc/ashet-hc.zig"),
    .@"arm-ashet-vhc" => @import("port/machine/arm/ashet-vhc/ashet-vhc.zig"),
    .@"arm-qemu-virt" => @import("port/machine/arm/qemu-virt/arm-qemu-virt.zig"),
    .@"x86-hosted-linux" => @import("port/machine/x86/hosted-linux/hosted-linux.zig"),
    .@"x86-hosted-windows" => @import("port/machine/x86/hosted-windows/hosted-windows.zig"),
};

pub const machine_config: ports.MachineConfig = machine.machine_config;

pub const LogLevel = std.log.Level;

pub const log_levels = struct {
    pub var default: LogLevel = .debug;
    pub var userland: LogLevel = .debug;
    pub var strace: LogLevel = .warn;

    // kernel components
    pub var ashex_loader: LogLevel = .info;
    pub var drivers: LogLevel = .info;
    pub var elf_loader: LogLevel = .info;
    pub var filesystem: LogLevel = .info;
    pub var gui: LogLevel = .debug;
    pub var io: LogLevel = .info;
    pub var main: LogLevel = .debug;
    pub var memory: LogLevel = .debug;
    pub var mprot: LogLevel = .info; // very noise modules!
    pub var multitasking: LogLevel = .debug;
    pub var network: LogLevel = .info;
    pub var overlapped: LogLevel = .info; // very noise modules!
    pub var page_allocator: LogLevel = .debug;
    pub var resources: LogLevel = .info;
    pub var scheduler: LogLevel = .info;
    pub var ui: LogLevel = .debug;
    pub var graphics: LogLevel = .info;
    pub var input: LogLevel = .info;
    pub var video: LogLevel = .debug;
    pub var storage: LogLevel = .warn; // very noise modules!
    pub var gpt_part: LogLevel = .warn; // very noise modules!
    pub var mbr_part: LogLevel = .warn; // very noise modules!
    pub var x86_vmm: LogLevel = .info; // very noise modules!
    pub var i2c: LogLevel = .info;
    pub var syscalls: LogLevel = .debug;

    pub var wayland_display: LogLevel = .info;

    // drivers:
    pub var @"virtio-net": LogLevel = .info;
    pub var @"virtio-gpu": LogLevel = .info;
    pub var @"virtio-input": LogLevel = .info;
    pub var @"virtio-blog": LogLevel = .debug;
    pub var kbc: LogLevel = .info;
    pub var enc28j60: LogLevel = .info;
    pub var hstx_dvi: LogLevel = .info;
    pub var nested_i2c_device: LogLevel = .debug;

    pub var generic_ps2: LogLevel = .info;

    pub var ds1306: LogLevel = .info;

    // home computer:
    pub var propio: LogLevel = .warn;
    pub var propio_lowlevel: LogLevel = .info;
    pub var propio_ps2: LogLevel = .warn;
    pub var p2boot: LogLevel = .warn;
    pub var ashet_hc: LogLevel = .info;
    pub var ashet_hc_psram: LogLevel = .info;

    // external modules:
    pub var fatfs: LogLevel = .info;
    pub var agp_sw_rast: LogLevel = .info;

    // platforms:
    pub var hosted: LogLevel = .debug;
    pub var host_vnc_server: LogLevel = .info;

    // platforms.x86:
    pub var idt: LogLevel = .debug;

    // machines:
    pub var bios_pc: LogLevel = .debug;
};

comptime {
    if (!builtin.is_test) {
        // force instantiation of the machine and platform elements
        _ = machine;
        _ = platform;
        _ = platform.start; // explicitly refer to the entry point implementation

        // Force-instantiate the VFAT driver to provide the FatFS implementation:
        _ = drivers.filesystem.VFAT;

        @export(&ashet_kernelMain, .{
            .name = "ashet_kernelMain",
        });
    }
}

comptime {
    // export the syscalls:
    _ = syscalls;
}

fn ashet_kernelMain() callconv(.c) noreturn {
    // trampoline into kernelMain() to have full stack tracing.
    kernelMain();
}

fn kernelMain() noreturn {
    // First thing to do: Set up the stack smashing guard to a hardcoded
    // value instead of initializing it with .data/.rodata initialization.
    //
    // this is necessary as the compiler will emit code that will load
    // this value in every preamble in debug builds.
    __stack_chk_guard = __stack_chk_guard_init;

    Debug.setTraceLoc(@src());
    memory.loadKernelMemory(machine_config.load_sections);

    if (machine_config.early_initialize) |early_initialize| {
        // If required, initialize the machine basics first,
        // set up linear memory or detect how much memory is available.

        Debug.setTraceLoc(@src());
        early_initialize();
    }

    // Populate RAM with the right sections, and compute how
    // much dynamic memory we have available:

    Debug.setTraceLoc(@src());
    log.info("initialize linear memory...", .{});
    memory.initializeLinearMemory();

    // Initialize scheduler before HAL as it doesn't require anything except memory pages for thread
    // storage, queues and stacks.

    Debug.setTraceLoc(@src());
    log.info("initialize scheduler...", .{});
    scheduler.initialize();

    full_panic = true;

    log.info("entering checked main()", .{});
    main() catch {
        if (@errorReturnTrace()) |error_trace| {
            Debug.write("error return trace:\r\n");
            Debug.printStackTrace("  ", error_trace, Debug.println);
        }

        @panic("system failure");
    };

    @panic("TODO: Poweroff");
}

fn main() !void {
    errdefer |err| log.err("main() failed with {}", .{err});

    // Initialize memory protection, which might need
    // dynamic page allocations to store certain data:
    log.info("initialize memory protection...", .{});
    try memory.protection.initialize();

    // now that we have memory protection enabled, we can
    // initialize multi-tasking. this should happen as early
    // as possible as it is necessary to have a "kernel process"
    // which can be used to schedule kernel i/o.
    log.info("initialize process handling...", .{});
    multi_tasking.initialize();

    // Initialize the entropy pool so it can begin gathering bits
    // for critical start-up applications. The pool needs at least
    // some amount of hardware entropy to be safe to use in later
    // start-ups. We will utilize the cycle-counter for this.
    log.info("initialize entropy pool...", .{});
    random.initialize();

    // Before we initialize the hardware, we already add hardware independent drivers
    // for stuff like file systems, virtual block devices and so on...
    log.info("install builtin drivers...", .{});
    drivers.installBuiltinDrivers();

    // Initialize the hardware into a well-defined state. After this, we can safely perform I/O ops.
    // This will install all relevant drivers, set up interrupts if necessary and so on.
    log.info("initialize machine...", .{});
    try machine_config.initialize();

    log.info("initialize video...", .{});
    try video.initialize();

    log.info("scan partition tables...", .{});
    storage.scan_partition_tables();

    log.info("initialize filesystem...", .{});
    filesystem.initialize();

    log.info("initialize overlapped workers...", .{});
    try overlapped.initialize();

    log.info("initialize input...", .{});
    input.initialize();

    log.info("spawn kernel main thread...", .{});
    {
        const thread = try scheduler.Thread.spawn(global_kernel_tick, null, .{
            .stack_size = 3 * 1024 * 1024,
        });
        try thread.setName("os.tick");
        try thread.start();
        thread.detach();
    }

    log.info("startup network...", .{});
    try network.start();

    {
        log.info("starting entry point thread...", .{});

        const thread = try scheduler.Thread.spawn(threaded_kernel_init_unchecked, null, .{
            .stack_size = 32 * 1024,
        });
        try thread.setName("os.entrypoint");
        try thread.start();
        thread.detach();
    }

    syscalls.strace_enabled.remove(.process_debug_write_log);
    syscalls.strace_enabled.remove(.overlapped_await_completion);
    syscalls.strace_enabled.remove(.overlapped_await_completion_of);
    syscalls.strace_enabled.remove(.overlapped_schedule);
    syscalls.strace_enabled.remove(.process_thread_yield);
    syscalls.strace_enabled.remove(.gui_get_window_max_size);
    syscalls.strace_enabled.remove(.gui_get_window_title);
    syscalls.strace_enabled.remove(.gui_get_desktop_data);
    syscalls.strace_enabled.remove(.datetime_now);
    syscalls.strace_enabled.remove(.clock_monotonic);

    log.info("entering scheduler...", .{});
    scheduler.start();

    // All tasks stopped, what should we do now?
    log.warn("All threads stopped. System is now halting.", .{});
}

fn threaded_kernel_init_unchecked(_: ?*anyopaque) callconv(.c) u32 {
    threaded_kernel_init() catch |err| {
        std.log.err("failed to initialize kernel: {s}", .{@errorName(err)});
        if (@errorReturnTrace()) |trace|
            Debug.printStackTrace("  ", trace, Debug.println);
        @panic("kernel initialization failed");
    };
    return 0;
}

/// This thread is just loading the startup application, and
/// is then quitting.
///
/// It's required to use a thread here to keep the IO subsystem
/// up and running. If we would try loading the application from
/// the `main()` function, we'd be blocking.
fn threaded_kernel_init() !void {
    log.info("initialize graphics subsystem...", .{});
    try graphics.initialize();

    log.info("loading entry point...", .{});

    try apps.startApp(.{ .name = "init" });

    log.info("start application successfully loaded!", .{});

    if (machine_id != .@"arm-ashet-hc") {
        // This is neat, but incredibly annoying over *true* serial:

        var deadline = time.Deadline.init_rel(10_000);
        while (true) {
            while (!deadline.is_reached()) {
                scheduler.yield();
            }
            deadline.move_forward(10_000);

            log.info("regular memory dump:", .{});
            memory.debug.dumpPageMap();
        }
    }
}

/// This function runs to keep certain kernel tasks alive and
/// working.
fn global_kernel_tick(_: ?*anyopaque) callconv(.c) u32 {
    while (true) {
        video.tick();
        input.tick();
        time.tick();
        io.i2c.tick();
        scheduler.yield();
    }
}

pub const global_hotkeys = struct {
    pub fn handle(event: abi.KeyboardEvent) bool {
        if (!event.pressed)
            return false;
        if (event.modifiers.alt) {
            switch (event.usage) {
                .f1 => @panic("F1 induced kernel panic"),
                .f9 => {
                    scheduler.use_stack_pattern_probing = !scheduler.use_stack_pattern_probing;
                    if (scheduler.use_stack_pattern_probing) {
                        std.log.warn("stack pattern probing enabled! expect slowdowns!", .{});
                    } else {
                        std.log.warn("stack pattern probing disabled!", .{});
                    }
                },
                .f10 => scheduler.dumpStats(),
                .f11 => network.dumpStats(),
                .f12 => {
                    const total_pages = memory.debug.getPageCount();
                    const free_pages = memory.debug.getFreePageCount();

                    log.info("current memory usage: {}/{} pages free, {Bi:.3}/{Bi:.3} used, {}% used", .{
                        free_pages,
                        total_pages,
                        memory.page_size * (total_pages - free_pages),
                        memory.page_size * total_pages,
                        100 - (100 * free_pages) / total_pages,
                    });
                    if (event.modifiers.shift) {
                        memory.debug.dumpPageMap();
                    }
                },

                else => {},
            }
        }
        return false;
    }
};

extern fn hang() callconv(.c) noreturn;

pub const Debug = struct {
    var trace_loc: std.builtin.SourceLocation = undefined;

    pub inline fn setTraceLoc(loc: std.builtin.SourceLocation) void {
        trace_loc = loc;
    }

    const Error = error{};
    fn writeWithErr(_: void, bytes: []const u8) Error!usize {
        machine_config.debug_write(bytes);
        return bytes.len;
    }
    const Writer = std.Io.GenericWriter(void, Error, writeWithErr);

    fn write_with_indent(indent: usize, bytes: []const u8) Error!usize {
        const indent_part: [8]u8 = .{' '} ** 8;

        var spliter = std.mem.splitScalar(u8, bytes, '\n');

        machine_config.debug_write(spliter.first());
        while (spliter.next()) |continuation| {
            machine_config.debug_write("\r\n");

            var i: usize = indent;
            while (i > 0) {
                const prefix = indent_part[0..@min(indent_part.len, i)];
                machine_config.debug_write(prefix);
                i -= prefix.len;
            }
            machine_config.debug_write(continuation);
        }

        return bytes.len;
    }
    const IndentWriter = std.Io.GenericWriter(usize, Error, write_with_indent);

    pub fn writer() Writer {
        return .{ .context = {} };
    }

    pub fn indent_writer(indent: u64) IndentWriter {
        return .{ .context = @truncate(indent) };
    }

    pub fn write(text: []const u8) void {
        machine_config.debug_write(text);
    }

    pub fn print(comptime fmt: []const u8, args: anytype) void {
        writer().print(fmt, args) catch {};
    }

    pub fn println(comptime fmt: []const u8, args: anytype) void {
        writer().print(fmt ++ "\r\n", args) catch {};
    }

    pub fn printStackTrace(prefix: []const u8, stack_trace: *std.builtin.StackTrace, comptime print_fn: fn (comptime []const u8, anytype) void) void {
        var frame_index: usize = 0;
        var frames_left: usize = @min(stack_trace.index, stack_trace.instruction_addresses.len);

        while (frames_left != 0) : ({
            frames_left -= 1;
            frame_index = (frame_index + 1) % stack_trace.instruction_addresses.len;
        }) {
            const return_address = stack_trace.instruction_addresses[frame_index];
            print_fn("{s}[{}] {f}", .{ prefix, frame_index, fmtCodeLocation(return_address) });
        }

        if (stack_trace.index > stack_trace.instruction_addresses.len) {
            const dropped_frames = stack_trace.index - stack_trace.instruction_addresses.len;
            print_fn("{s}({d} additional stack frames skipped...)", .{ prefix, dropped_frames });
        }
    }
};

extern var __kernel_stack_end: anyopaque;
extern var __kernel_stack_start: anyopaque;

pub fn stackCheck() void {
    const sp = platform.getStackPointer();

    var stack_end: usize = @intFromPtr(&__kernel_stack_end);
    var stack_start: usize = @intFromPtr(&__kernel_stack_start);

    if (scheduler.Thread.current()) |thread| {
        stack_start = @intFromPtr(thread.stack_memory.ptr);
        stack_end = stack_start + thread.stack_memory.len;

        _ = thread.check_canary();
    }

    if (sp > stack_end) {
        // stack underflow
        @breakpoint();
        @panic("STACK UNDERFLOW");
    } else if (sp <= stack_start) {
        // stack overflow
        @breakpoint();
        @panic("STACK OVERFLOW");
    } else {
        // stack nominal
    }
}

var double_panic = false;
var full_panic = false;

pub const std_options = std.Options{
    .log_level = if (@import("builtin").mode == .Debug) .debug else .info,
    .logFn = kernel_log_fn,
};

fn kernel_log_once(comptime scope: @Type(.enum_literal)) void {
    const T = struct {
        var triggered: bool = false;

        fn print() void {
            if (triggered)
                return;
            triggered = true; // must be set before the log to prevent recursion
            std.log.warn("log scope .{f} has no explicit filter in root.log_levels", .{
                std.zig.fmtId(@tagName(scope)),
            });
        }
    };
    T.print();
}

var log_exclusive_lock: utils.SpinLock = .init;

fn kernel_log_fn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const ansi = true;

    const scope_name = @tagName(scope);

    if (@hasDecl(log_levels, scope_name)) {
        if (@intFromEnum(message_level) > @intFromEnum(@field(log_levels, scope_name)))
            return;
    } else {
        kernel_log_once(scope);
    }

    const color_code = comptime if (ansi)
        switch (message_level) {
            .err => utils.ansi.sgi(.fg_bright_red),
            .warn => utils.ansi.sgi(.fg_bright_yellow),
            .info => utils.ansi.sgi(.fg_bright_white),
            .debug => utils.ansi.sgi(.fg_white),
        }
    else
        "";
    const postfix = comptime if (ansi) utils.ansi.sgi(.reset) else ""; // reset terminal properties

    const level_txt = comptime switch (message_level) {
        .err => "E",
        .warn => "W",
        .info => "I",
        .debug => "D",
    };
    const scope_tag = comptime if (scope != .default)
        @tagName(scope)
    else
        "unscoped";

    const is_in_isr = platform.isInInterruptContext();

    const needs_lock = machine_config.uses_hardware_multithreading;

    {
        if (needs_lock and !is_in_isr) log_exclusive_lock.lock();
        defer if (needs_lock and !is_in_isr) log_exclusive_lock.unlock();

        const isr_prefix, const isr_suffix = if (is_in_isr)
            .{ "<<", ">>" }
        else
            .{ "", "" };

        const now = time.Instant.now();

        const machine_prefix = if (machine_config.get_log_prefix) |get_log_prefix|
            get_log_prefix()
        else
            "";

        Debug.writer().writeAll(color_code) catch return;

        const now_ms: u64 = @intFromEnum(now);
        Debug.writer().print("{s}{d: >6}.{d:0>3}{s}{s} [{s}] {s}: ", .{
            isr_prefix,
            now_ms / 1000,
            now_ms % 1000,
            if (machine_prefix.len > 0) " " else "",
            machine_prefix,
            level_txt,
            scope_tag,
        }) catch return;
        var count: std.Io.Writer.Discarding = .init(&.{});
        count.writer.print("{s}{d: >6}.{d:0>3}{s}{s} [{s}] {s}: ", .{
            isr_prefix,
            now_ms / 1000,
            now_ms % 1000,
            if (machine_prefix.len > 0) " " else "",
            machine_prefix,
            level_txt,
            scope_tag,
        }) catch unreachable;

        Debug.indent_writer(count.fullCount()).print(format, args) catch return;
        Debug.writer().print(postfix ++ "{s}\r\n", .{isr_suffix}) catch return;
    }
}

pub const CodeLocation = struct {
    pointer: usize,

    pub fn format(codeloc: CodeLocation, writer: *std.Io.Writer) !void {
        var iter = multi_tasking.processIterator();
        while (iter.next()) |proc| {
            const process_memory = proc.executable_memory orelse continue;

            const base = @intFromPtr(process_memory.ptr);
            const top = base +| process_memory.len;
            if (codeloc.pointer >= base and codeloc.pointer < top) {
                try writer.print("{s}:0x{X:0>8}", .{ proc.name, codeloc.pointer - base });
                return;
            }
        }

        try writer.print("kernel:0x{X:0>8}", .{codeloc.pointer});
    }
};

pub fn fmtCodeLocation(addr: usize) CodeLocation {
    return .{ .pointer = addr };
}

pub fn halt() noreturn {
    if (machine_config.halt) |machine_halt| {
        std.log.err("triggering machine halt...", .{});
        machine_halt();
    }

    if (builtin.mode == .Debug) {
        if (!double_panic) {
            @breakpoint();
        }
    }
    hang();
}

pub fn panic(message: []const u8, maybe_error_trace: ?*std.builtin.StackTrace, maybe_return_address: ?usize) noreturn {
    @branchHint(.cold);

    if (!full_panic) {
        machine_config.debug_write("PANIC: ");
        machine_config.debug_write(message);
        machine_config.debug_write("\r\n");
        Debug.print("last trace: {s}:{}:{} ({s})\r\n", .{
            Debug.trace_loc.file,
            Debug.trace_loc.line,
            Debug.trace_loc.column,
            Debug.trace_loc.fn_name,
        });
        machine_config.debug_write("\r\n");
        halt();
    }
    const sp = platform.getStackPointer();

    if (double_panic) {
        Debug.write("\r\nDOUBLE PANIC: ");
        Debug.write(message);
        Debug.write("\r\n");
        halt();
    }
    double_panic = true;

    Debug.write("\r\n");
    Debug.write("=========================================================================\r\n");
    Debug.write("Kernel Panic: ");
    Debug.write(message);
    Debug.write("\r\n");
    Debug.write("=========================================================================\r\n");
    Debug.write("\r\n");

    const current_thread = scheduler.Thread.current();

    if (maybe_return_address) |return_address| {
        Debug.print("    panic return address: {f}\r\n\r\n", .{fmtCodeLocation(return_address)});
    }
    Debug.print(" function return address: {f}\r\n\r\n", .{fmtCodeLocation(@returnAddress())});

    if (maybe_error_trace) |error_trace| {
        Debug.write("error return trace:\r\n");
        Debug.printStackTrace("  ", error_trace, Debug.println);
    }

    {
        var stack_end: usize = @intFromPtr(&__kernel_stack_end);
        var stack_start: usize = @intFromPtr(&__kernel_stack_start);

        if (current_thread) |thread| {
            stack_start = @intFromPtr(thread.stack_memory.ptr);
            stack_end = stack_start + thread.stack_memory.len;
        }

        std.debug.assert(stack_end > stack_start);

        const stack_size: usize = stack_end - stack_start;

        Debug.print("stack usage:\r\n", .{});

        Debug.print("  low:     0x{X:0>8}\r\n", .{stack_start});
        Debug.print("  pointer: 0x{X:0>8}\r\n", .{sp});
        Debug.print("  high:    0x{X:0>8}\r\n", .{stack_end});
        // Debug.print("  size:    {d:.3}\r\n", .{std.fmt.fmtIntSizeBin(stack_size)});
        Debug.print("  size:    {d}\r\n", .{stack_size});

        if (sp > stack_end) {
            // stack underflow
            Debug.print("  usage:   UNDERFLOW by {} bytes!\r\n", .{
                sp - stack_end,
            });
        } else if (sp <= stack_start) {
            // stack overflow
            Debug.print("  usage:   OVERFLOW by {} bytes!\r\n", .{
                stack_start - sp,
            });
        } else {
            // stack nominal
            Debug.print("  usage:   {d}%\r\n", .{
                100 - (100 * (sp - stack_start)) / stack_size,
            });
        }
        Debug.write("\r\n");
    }

    if (@import("builtin").mode == .Debug) {
        if (scheduler.Thread.current()) |thread| {
            Debug.print("current thread:\r\n", .{});
            Debug.print("  [!] {f}\r\n\r\n", .{thread});
        }

        Debug.write("waiting threads:\r\n");
        var index: usize = 0;
        var queue = scheduler.ThreadIterator.init();
        while (queue.next()) |thread| : (index += 1) {
            Debug.print("  [{d}] {f}\r\n", .{ index, thread });
        }
        Debug.write("\r\n");
    }

    {
        Debug.write("stack trace:\r\n");
        var index: usize = 0;
        var it = std.debug.StackIterator.init(@returnAddress(), null);
        while (it.next()) |addr| : (index += 1) {
            Debug.print("{d: >4}: {f}\r\n", .{ index, fmtCodeLocation(addr) });

            // if (current_thread) |thread| {
            //     if (thread.process) |proc| {
            //         const base = @intFromPtr(proc.process_memory.ptr);
            //         const top = base +| proc.process_memory.len;

            //         if (addr >= base and addr < top) {
            //             Debug.print("{d: >4}: {s}:0x{X:0>8}\r\n", .{ index, proc.file_name, addr - base });
            //             // Debug.print("0x{X:0>8}\r\n", .{addr - base});
            //             continue;
            //         }
            //     }
            // }

            // Debug.print("{d: >4}: kernel:0x{X:0>8}\r\n", .{ index, addr });
            // // Debug.print("0x{X:0>8}\r\n", .{addr});
        }
    }

    Debug.write("\r\n");

    Debug.write("Memory map:\r\n");
    memory.debug.dumpPageMap();

    // print the kernel message again so we have a wraparound
    Debug.write("\r\n");
    Debug.write("=========================================================================\r\n");
    Debug.write("Kernel Panic: ");
    Debug.write(message);
    Debug.write("\r\n");
    Debug.write("=========================================================================\r\n");
    Debug.write("\r\n");

    halt();
}

export fn ashet_lockInterrupts(enable_on_leave: *bool) void {
    const cs: CriticalSection = .enter();

    enable_on_leave.* = switch (cs) {
        .unchanged_on_leave => false,
        .enable_on_leave => true,
    };
}

export fn ashet_unlockInterrupts(enable_on_leave: bool) void {
    const cs: CriticalSection = switch (enable_on_leave) {
        false => .unchanged_on_leave,
        true => .enable_on_leave,
    };
    cs.leave();
}

export fn ashet_rand() u32 {
    // TODO: Improve this
    return 4; // chose by a fair dice roll
}

/// A critical section is a tiny helper that allows
/// a code section to be protected against interruption.
pub const CriticalSection = enum(u1) {
    unchanged_on_leave = 0,
    enable_on_leave = 1,

    pub fn enter() CriticalSection {
        const were_enabled = platform.areInterruptsEnabled();
        if (were_enabled) {
            platform.disableInterrupts();
        }
        return if (were_enabled) .enable_on_leave else .unchanged_on_leave;
    }

    pub fn leave(cs: CriticalSection) void {
        switch (cs) {
            .unchanged_on_leave => {},
            .enable_on_leave => platform.enableInterrupts(),
        }
    }
};

// TODO: move to foundation-libc
export fn memchr(buf: ?[*]const c_char, ch: c_int, len: usize) ?[*]c_char {
    const s = buf orelse return null;

    const searched: c_char = @bitCast(@as(u8, @truncate(@as(c_uint, @bitCast(ch)))));

    return if (std.mem.indexOf(c_char, s[0..len], &.{searched})) |index|
        @constCast(s + index)
    else
        null;
}

test {
    _ = resources;
}

export fn __ashet_os_panic(msg: [*]const u8, len: usize, ra: usize) noreturn {
    panic(msg[0..len], null, ra);
}

// The following code is necessary to manage the compiler_rt stack checking.
// In debug builds, Zig inserts a stack smashing guard which protects us against
// evil. The problem is:
// We "smash" the stack in "loadKernelMemory" by initializing the "__stack_chk_guard" variable
// from compiler_rt and thus the function will always fail as it has a false-positive detection
// triggered.
//
// Luckily, the variable is exported as weak in compiler_rt, and we can overwrite it with our own,
// which we initialize manually with an immediate value before calling any other function.

const __stack_chk_guard_init: usize = @truncate(0x125710640cadd0ac);

var __stack_chk_guard: usize = __stack_chk_guard_init;

comptime {
    if (builtin.os.tag == .freestanding) {
        @export(&__stack_chk_guard, .{
            .name = "__stack_chk_guard",
            .linkage = .strong,
            .visibility = .default,
        });
    }
}
