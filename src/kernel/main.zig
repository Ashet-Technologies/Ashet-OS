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

pub const ports = @import("port/targets.zig");

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
    .@"pc-bios" => @import("port/machine/bios_pc/bios_pc.zig"),
    .@"qemu-virt-rv32" => @import("port/machine/rv32_virt/rv32_virt.zig"),
    .@"qemu-virt-arm" => @import("port/machine/arm_virt/arm_virt.zig"),
    .@"hosted-x86-linux" => @import("port/machine/linux_pc/linux_pc.zig"),
};

pub const machine_config: ports.MachineConfig = machine.machine_config;

pub const LogLevel = std.log.Level;

pub const log_levels = struct {
    pub var default: LogLevel = .debug;
    pub var userland: LogLevel = .debug;
    pub var strace: LogLevel = .debug;

    // kernel components
    pub var main: LogLevel = .debug;
    pub var scheduler: LogLevel = .debug;
    pub var io: LogLevel = .info;
    pub var ui: LogLevel = .debug;
    pub var network: LogLevel = .info;
    pub var filesystem: LogLevel = .debug;
    pub var resources: LogLevel = .info;
    pub var memory: LogLevel = .info;
    pub var drivers: LogLevel = .info;
    pub var page_allocator: LogLevel = .debug;
    pub var mprot: LogLevel = .info; // very noise modules!
    pub var x86_vmm: LogLevel = .info; // very noise modules!
    pub var overlapped: LogLevel = .info; // very noise modules!
    pub var elf_loader: LogLevel = .info;
    pub var video: LogLevel = .debug;
    pub var multitasking: LogLevel = .info;
    pub var gui: LogLevel = .debug;

    // drivers:
    pub var @"virtio-net": LogLevel = .info;
    pub var @"virtio-gpu": LogLevel = .info;
    pub var @"virtio-input": LogLevel = .info;
    pub var kbc: LogLevel = .info;

    // external modules:
    pub var fatfs: LogLevel = .info;

    // platforms:

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

        @export(ashet_kernelMain, .{
            .name = "ashet_kernelMain",
        });
    }
}

comptime {
    // export the syscalls:
    _ = syscalls;
}

fn ashet_kernelMain() callconv(.C) noreturn {
    // trampoline into kernelMain() to have full stack tracing.
    kernelMain();
}

fn kernelMain() noreturn {
    Debug.setTraceLoc(@src());
    memory.loadKernelMemory(machine_config.load_sections);

    if (@hasDecl(machine, "earlyInitialize")) {
        // If required, initialize the machine basics first,
        // set up linear memory or detect how much memory is available.

        Debug.setTraceLoc(@src());
        machine.earlyInitialize();
    }

    // Populate RAM with the right sections, and compute how
    // much dynamic memory we have available:

    Debug.setTraceLoc(@src());
    memory.initializeLinearMemory();

    // Initialize scheduler before HAL as it doesn't require anything except memory pages for thread
    // storage, queues and stacks.

    Debug.setTraceLoc(@src());
    scheduler.initialize();

    full_panic = true;

    log.info("entering checked main()", .{});
    main() catch {
        if (@errorReturnTrace()) |error_trace| {
            if (builtin.os.tag != .freestanding) {
                // hosted environment:
                std.debug.dumpStackTrace(error_trace.*);
            }
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
    try machine.initialize();

    log.info("initialize video...", .{});
    try video.initialize();

    log.info("initialize filesystem...", .{});
    filesystem.initialize();

    log.info("initialize overlapped workers...", .{});
    try overlapped.initialize();

    log.info("initialize input...", .{});
    input.initialize();

    log.info("initialize graphics subsystem...", .{});
    try graphics.initialize();

    log.info("spawn kernel main thread...", .{});
    {
        const thread = try scheduler.Thread.spawn(global_kernel_tick, null, .{
            .stack_size = 32 * 1024,
        });
        try thread.setName("os.tick");
        try thread.start();
        thread.detach();
    }

    log.info("startup network...", .{});
    try network.start();

    // try ui.start();

    {
        log.info("starting entry point thread...", .{});

        const thread = try scheduler.Thread.spawn(load_entry_point, null, .{
            .stack_size = 32 * 1024,
        });
        try thread.setName("os.entrypoint");
        try thread.start();
        thread.detach();
    }

    syscalls.strace_enabled.remove(.process_debug_write_log);
    syscalls.strace_enabled.remove(.overlapped_await_completion);
    syscalls.strace_enabled.remove(.overlapped_schedule);
    syscalls.strace_enabled.remove(.process_thread_yield);

    log.info("entering scheduler...", .{});
    scheduler.start();

    // All tasks stopped, what should we do now?
    log.warn("All threads stopped. System is now halting.", .{});
}

/// This thread is just loading the startup application, and
/// is then quitting.
///
/// It's required to use a thread here to keep the IO subsystem
/// up and running. If we would try loading the application from
/// the `main()` function, we'd be blocking.
fn load_entry_point(_: ?*anyopaque) callconv(.C) u32 {
    log.info("loading entry point...", .{});

    apps.startApp(.{
        .name = "init",
    }) catch |err| {
        log.err("failed to start up the init process: {s}", .{@errorName(err)});
        if (@errorReturnTrace()) |trace|
            Debug.printStackTrace("  ", trace, Debug.println);
        @panic("failed to start up the system");
    };

    log.info("start application successfully loaded!", .{});

    var deadline = time.Deadline.init_rel(10_000);
    while (true) {
        while (!deadline.is_reached()) {
            scheduler.yield();
        }
        deadline.move_forward(10_000);

        log.info("regular memory dump:", .{});
        memory.debug.dumpPageMap();
    }

    return 0;
}

/// This function runs to keep certain kernel tasks alive and
/// working.
fn global_kernel_tick(_: ?*anyopaque) callconv(.C) u32 {
    while (true) {
        video.tick();
        input.tick();
        time.tick();
        scheduler.yield();
    }
}

pub const global_hotkeys = struct {
    pub fn handle(event: abi.KeyboardEvent) bool {
        if (!event.pressed)
            return false;
        if (event.modifiers.alt) {
            switch (event.key) {
                .f1 => @panic("F1 induced kernel panic"),
                .f10 => scheduler.dumpStats(),
                .f11 => network.dumpStats(),
                .f12 => {
                    const total_pages = memory.debug.getPageCount();
                    const free_pages = memory.debug.getFreePageCount();

                    log.info("current memory usage: {}/{} pages free, {:.3}/{:.3} used, {}% used", .{
                        free_pages,
                        total_pages,
                        std.fmt.fmtIntSizeBin(memory.page_size * (total_pages - free_pages)),
                        std.fmt.fmtIntSizeBin(memory.page_size * total_pages),
                        100 - (100 * free_pages) / total_pages,
                    });
                },

                else => {},
            }
        }
        return false;
    }
};

extern fn hang() callconv(.C) noreturn;

pub const Debug = struct {
    var trace_loc: std.builtin.SourceLocation = undefined;

    pub inline fn setTraceLoc(loc: std.builtin.SourceLocation) void {
        trace_loc = loc;
    }

    const Error = error{};
    fn writeWithErr(_: void, bytes: []const u8) Error!usize {
        machine.debugWrite(bytes);
        return bytes.len;
    }
    const Writer = std.io.Writer(void, Error, writeWithErr);

    fn write_with_indent(indent: usize, bytes: []const u8) Error!usize {
        const indent_part: [8]u8 = .{' '} ** 8;

        var spliter = std.mem.splitScalar(u8, bytes, '\n');

        machine.debugWrite(spliter.first());
        while (spliter.next()) |continuation| {
            machine.debugWrite("\r\n");

            var i: usize = indent;
            while (i > 0) {
                const prefix = indent_part[0..@min(indent_part.len, i)];
                machine.debugWrite(prefix);
                i -= prefix.len;
            }
            machine.debugWrite(continuation);
        }

        return bytes.len;
    }
    const IndentWriter = std.io.Writer(usize, Error, write_with_indent);

    pub fn writer() Writer {
        return .{ .context = {} };
    }

    pub fn indent_writer(indent: u64) IndentWriter {
        return .{ .context = @truncate(indent) };
    }

    pub fn write(text: []const u8) void {
        machine.debugWrite(text);
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
            print_fn("{s}[{}] {}", .{ prefix, frame_index, fmtCodeLocation(return_address) });
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
        stack_end = @intFromPtr(thread.getBasePointer());
        stack_start = stack_end - thread.stack_size;
    }

    if (sp > stack_end) {
        // stack underflow
        @panic("STACK UNDERFLOW");
    } else if (sp <= stack_start) {
        // stack overflow
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

fn kernel_log_once(comptime scope: @Type(.EnumLiteral)) void {
    const T = struct {
        var triggered: bool = false;

        fn print() void {
            if (triggered)
                return;
            triggered = true; // must be set before the log to prevent recursion
            std.log.warn("log scope .{} has no explicit filter in root.log_levels", .{
                std.zig.fmtId(@tagName(scope)),
            });
        }
    };
    T.print();
}

fn kernel_log_fn(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
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

    const color_code = if (ansi)
        switch (message_level) {
            .err => "\x1B[91m", // red
            .warn => "\x1B[93m", // yellow
            .info => "\x1B[97m", // white
            .debug => "\x1B[90m", // gray
        }
    else
        "";
    const postfix = if (ansi) "\x1B[0m" else ""; // reset terminal properties

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

    {
        var cs = CriticalSection.enter();
        defer cs.leave();

        const now = time.Instant.now();

        var counting_writer = std.io.countingWriter(Debug.writer());

        Debug.writer().writeAll(color_code) catch return;

        const now_ms: u64 = @intFromEnum(now);
        var writer = counting_writer.writer();
        writer.print("{d: >6}.{d:0>3} [{s}] {s}: ", .{
            now_ms / 1000,
            now_ms % 1000,
            level_txt,
            scope_tag,
        }) catch return;

        Debug.indent_writer(counting_writer.bytes_written).print(format, args) catch return;
        Debug.writer().print(postfix ++ "\r\n", .{}) catch return;
    }
}

pub const CodeLocation = struct {
    pointer: usize,

    pub fn format(codeloc: CodeLocation, fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opt;

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
    return CodeLocation{ .pointer = addr };
}

pub fn panic(message: []const u8, maybe_error_trace: ?*std.builtin.StackTrace, maybe_return_address: ?usize) noreturn {
    @setCold(true);

    if (!full_panic) {
        machine.debugWrite("PANIC: ");
        machine.debugWrite(message);
        machine.debugWrite("\r\n");
        Debug.print("last trace: {s}:{}:{} ({s})\r\n", .{
            Debug.trace_loc.file,
            Debug.trace_loc.line,
            Debug.trace_loc.column,
            Debug.trace_loc.fn_name,
        });
        machine.debugWrite("\r\n");
        hang();
    }
    const sp = platform.getStackPointer();

    if (double_panic) {
        Debug.write("\r\nDOUBLE PANIC: ");
        Debug.write(message);
        Debug.write("\r\n");
        hang();
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
        Debug.print("    panic return address: {}\r\n\r\n", .{fmtCodeLocation(return_address)});
    }
    Debug.print(" function return address: {}\r\n\r\n", .{fmtCodeLocation(@returnAddress())});

    if (maybe_error_trace) |error_trace| {
        Debug.write("error return trace:\r\n");
        Debug.printStackTrace("  ", error_trace, Debug.println);
    }

    {
        var stack_end: usize = @intFromPtr(&__kernel_stack_end);
        var stack_start: usize = @intFromPtr(&__kernel_stack_start);

        if (current_thread) |thread| {
            stack_end = @intFromPtr(thread.getBasePointer());
            stack_start = stack_end - thread.stack_size;
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
            Debug.print("  [!] {}\r\n\r\n", .{thread});
        }

        Debug.write("waiting threads:\r\n");
        var index: usize = 0;
        var queue = scheduler.ThreadIterator.init();
        while (queue.next()) |thread| : (index += 1) {
            Debug.print("  [{}] {}\r\n", .{ index, thread });
        }
        Debug.write("\r\n");
    }

    {
        Debug.write("stack trace:\r\n");
        var index: usize = 0;
        var it = std.debug.StackIterator.init(@returnAddress(), null);
        while (it.next()) |addr| : (index += 1) {
            Debug.print("{d: >4}: {}\r\n", .{ index, fmtCodeLocation(addr) });

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

    hang();
}

export fn ashet_lockInterrupts(were_enabled: *bool) void {
    were_enabled.* = platform.areInterruptsEnabled();
    if (were_enabled.*) {
        platform.disableInterrupts();
    }
}

export fn ashet_unlockInterrupts(enable: bool) void {
    if (enable) {
        platform.enableInterrupts();
    }
}

export fn ashet_rand() u32 {
    // TODO: Improve this
    return 4; // chose by a fair dice roll
}

pub const CriticalSection = struct {
    restore: bool,

    pub fn enter() CriticalSection {
        var cs = CriticalSection{ .restore = undefined };
        ashet_lockInterrupts(&cs.restore);
        return cs;
    }

    pub fn leave(cs: *CriticalSection) void {
        ashet_unlockInterrupts(cs.restore);
        cs.* = undefined;
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
