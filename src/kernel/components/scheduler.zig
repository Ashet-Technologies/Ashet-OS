//! This file implements the thread scheduler.
//! The scheduler starts and suspends threads in a cooperative manner.
//!
//!
//! RISC-V32 ABI:
//!
//!     Register | ABI Name | Description                      Saver
//!     ---------+----------+----------------------------------------
//!     x0       | zero     | Hard-wired zero                  —
//!     x1       | ra       | Return address                   Caller
//!     x2       | sp       | Stack pointer                    Callee
//!     x3       | gp       | Global pointer                   —
//!     x4       | tp       | Thread pointer                   —
//!     x5–7     | t0–2     | Temporaries                      Caller
//!     x8       | s0/fp    | Saved register/frame pointer     Callee
//!     x9       | s1       | Saved register                   Callee
//!     x10–11   | a0–1     | Function arguments/return values Caller
//!     x12–17   | a2–7     | Function arguments               Caller
//!     x18–27   | s2–11    | Saved registers                  Callee
//!     x28–31   | t3–6     | Temporaries                      Caller
//!     ---------+----------+----------------------------------------
//!     f0–7     | ft0–7    | FP temporaries                   Caller
//!     f8–9     | fs0–1    | FP saved registers               Callee
//!     f10–11   | fa0–1    | FP arguments/return values       Caller
//!     f12–17   | fa2–7    | FP arguments                     Caller
//!     f18–27   | fs2–11   | FP saved registers               Callee
//!     f28–31   | ft8–11   | FP temporaries                   Caller
//!
//! x86 ABI:
//!
//!     Saved on stack:
//!     - EAX
//!     - EBX
//!     - ECX
//!     - EDX
//!     - EBP
//!     - ESI
//!     - EDI
//!     - EFLAGS
//!     Externally saved:
//!     - ESP
//!     - EIP
//!
//! Arm/Thumb EABI:
//!     armv8-m uses AAPCS
//!         https://developer.arm.com/documentation/107656/0101/Getting-started-with-Armv8-M-based-systems/Procedure-Call-Standard-for-Arm-Architecture--AAPCS-?lang=en
//!     AAPCS is documented on GitHub
//!         https://github.com/ARM-software/abi-aa/blob/main/aapcs32/aapcs32.rst
//!
//!     Register | ABI Name | ABI Saver   | Saved | Description
//!     ---------+----------+-------------+-------+----------------------------------------
//!     r0, a1   |          | Caller      | yes   | Argument / result / scratch register 1.
//!     r1, a2   |          | Caller      | yes   | Argument / result / scratch register 2.
//!     r2, a3   |          | Caller      | yes   | Argument / scratch register 3.
//!     r3, a4   |          | Caller      | yes   | Argument / scratch register 4.
//!     r4, v1   |          | Callee      | yes   | Variable-register 1.
//!     r5, v2   |          | Callee      | yes   | Variable-register 2.
//!     r6, v3   |          | Callee      | yes   | Variable-register 3.
//!     r7, v4   |          | Callee      | yes   | Variable-register 4.
//!     r8, v5   |          | Callee      | yes   | Variable-register 5.
//!     r9, v6   | TR       | Callee      | yes   | The meaning of this register is defined by the platform standard.
//!              | SB       |             | yes   | Platform register or Variable-register 6.
//!     r10, v7  |          | Callee      | yes   | Variable-register 7.
//!     r11, v8  | FP       | Callee      | yes   | Frame Pointer or Variable-register 8.
//!     r12      | IP       | Special     | yes   | The Intra-Procedure-call scratch register.
//!     r13      | SP       | Special     | no    | The Stack Pointer.
//!     r14      | LR       | Special     | no    | The Link Register.
//!     r15      | PC       | Special     | no    | The Program Counter.
//!
//!
//!
//!
//!

const std = @import("std");
const astd = @import("ashet-std");
const logger = std.log.scoped(.scheduler);
const ashet = @import("../main.zig");
const target = @import("builtin").target.cpu.arch;

const debug_mode = @import("builtin").mode == .Debug;

const canary_size = ashet.memory.page_size;

comptime {
    std.debug.assert(std.mem.isAligned(canary_size, ashet.memory.page_size));
}

pub fn dumpStats() void {
    logger.info("stat dump:", .{});
    if (current_thread) |thread| {
        if (debug_mode) {
            logger.info("  current thread: ip=0x{X:0>8}, ep=0x{X:0>8}, name={s}", .{ thread.ip, thread.debug_info.entry_point, thread.getName() });
        } else {
            logger.info("  current thread: ip=0x{X:0>8}", .{thread.ip});
        }
    }
    logger.info("  total:     {}", .{global_stats.total_count});
    logger.info("  waiting:   {}", .{wait_queue.len});
    logger.info("  suspended: {}", .{global_stats.suspended_count});
    logger.info("  running:   {}", .{global_stats.running_count});
}

pub const global_stats = struct {
    var total_count: usize = 0;
    var suspended_count: usize = 0;
    var running_count: usize = 0;
};

pub const ExitCode = ashet.abi.ExitCode;
pub const ThreadFunction = ashet.abi.ThreadFunction;

pub const Stats = struct {
    times_scheduled: u32 = 0,
    total_execution_time_ms: u64 = 0,

    schedule_time: ?ashet.time.Instant = null,

    pub fn reset(stats: *Stats) void {
        stats.times_scheduled = 0;
        stats.total_execution_time_ms = 0;
    }
};

/// Thread management structure.
/// Is allocated in such a way that is is stored at the end of the last page of thread stack.
pub const Thread = struct {
    pub const Destructor = ashet.resources.Destructor(@This(), kill);

    pub const DebugInfo = if (debug_mode) struct {
        entry_point: usize = 0,
        name: [32]u8 = [1]u8{0} ** 32,
    } else struct {
        entry_point: u0 = 0,
        name: [0]u8 = .{},
    };

    pub const Flags = packed struct(u32) {
        suspended: bool = false,
        started: bool = false,
        finished: bool = false,
        detached: bool = false,
        has_canary: bool = false,
        padding: u27 = 0,
    };

    pub const default_stack_size = 32768;

    system_resource: ashet.resources.SystemResource = .{ .type = .thread },

    stack_memory: []align(ashet.memory.page_size) u8,

    ip: usize,
    sp: usize,
    exit_code: u32,

    /// The queue the thread currently is in.
    queue: ?*ThreadQueue = null,
    /// The queue node we use to enqueue/dequeue the thread between different queues.
    node: ThreadQueue.Node = .{ .data = {} },

    flags: Flags = .{},

    debug_info: DebugInfo = .{},

    /// Stores runtime statistics of this thread.
    stats: Stats = .{},

    process_link: ashet.multi_tasking.ProcessThreadList.Node,

    /// Returns a pointer to the current thread.
    pub fn current() ?*Thread {
        return current_thread;
    }

    pub const ThreadSpawnOptions = struct {
        stack_size: usize = Thread.default_stack_size,
        process: ?*ashet.multi_tasking.Process = null,
    };

    /// Creates a new thread which isn't started yet.
    ///
    /// **NOTE:** When choosing `stack_size`, one should remember that it will also include the management structures
    /// for the thread
    pub fn spawn(func: ThreadFunction, arg: ?*anyopaque, options: ThreadSpawnOptions) error{OutOfMemory}!*Thread {
        const use_canary = ashet.memory.protection.is_enabled();

        // the canary requires a single page at the "bottom" of the stack:
        const additional_stack_size: usize = if (use_canary)
            canary_size
        else
            0;

        const stack_size = std.mem.alignForward(usize, options.stack_size + additional_stack_size, ashet.memory.page_size);

        // Requires the use of `ThreadAllocator`.
        // See `ashet_scheduler_threadExit` and `internalDestroy` for more explanation.
        const stack_memory = try ashet.memory.ThreadAllocator.alloc(stack_size);
        errdefer ashet.memory.ThreadAllocator.free(stack_memory);

        const thread_proc = options.process orelse ashet.multi_tasking.get_kernel_process();

        const thread = try ashet.memory.type_pool(Thread).alloc();
        errdefer ashet.memory.type_pool(Thread).free(thread);

        thread.* = Thread{
            .stack_memory = stack_memory,

            .sp = @intFromPtr(stack_memory.ptr) + stack_memory.len, // sp points to end of stack
            .ip = @intFromPtr(&ashet_scheduler_threadTrampoline),
            .exit_code = 0,
            .process_link = .{ .data = .{
                .thread = thread,
                .process = thread_proc,
            } },
            .flags = .{
                .has_canary = use_canary,
            },
        };

        if (use_canary) {
            // make the stack canary forbidden:
            ashet.memory.protection.change(ashet.memory.Range.from_slice(
                stack_memory[0..canary_size],
            ), .forbidden);
        }
        errdefer comptime @compileError("No failures allowed after setting the stack canary.");

        thread_proc.threads.append(&thread.process_link);

        if (@import("builtin").mode == .Debug) {
            thread.debug_info.entry_point = @intFromPtr(func);
        }
        switch (target) {
            .riscv32 => {
                thread.push(0x0000_0000); //      x3  ; gp Global pointer
                thread.push(0x0000_0000); //      x4  ; tp Thread pointer
                thread.push(0x0000_0000); //      x8  ; s0
                thread.push(0x0000_0000); //      x9  ; s1
                thread.push(@intFromPtr(func)); // x18  ; s2
                thread.push(@intFromPtr(arg)); //  x19  ; s3
                thread.push(0x0000_0000); //     x20
                thread.push(0x0000_0000); //     x21
                thread.push(0x0000_0000); //     x22
                thread.push(0x0000_0000); //     x23
                thread.push(0x0000_0000); //     x24
                thread.push(0x0000_0000); //     x25
                thread.push(0x0000_0000); //     x26
                thread.push(0x0000_0000); //     x27
            },

            .x86 => {
                thread.push(thread.ip); // return address

                // thread.push(0x0000_0000); // EFLAGS
                thread.push(0x0000_0000); // EDI
                thread.push(0x0000_0000); // ESI
                thread.push(0x0000_0000); // EBP
                thread.push(0x0000_0000); // EDX
                thread.push(0x0000_0000); // ECX
                thread.push(@intFromPtr(arg)); // EBX
                thread.push(@intFromPtr(func)); // EAX
            },

            .thumb => {
                // push {r0-r10,fp,ip} pushes "ip" first and "r0" last.
                thread.push(@intFromPtr(func)); // ip
                thread.push(0x0000_0000); // fp
                thread.push(0x0000_0000); // r10
                thread.push(0x0000_0000); // r9
                thread.push(0x0000_0000); // r8
                thread.push(0x0000_0000); // r7
                thread.push(0x0000_0000); // r6
                thread.push(0x0000_0000); // r5
                thread.push(0x0000_0000); // r4
                thread.push(0x0000_0000); // r3
                thread.push(0x0000_0000); // r2
                thread.push(0x0000_0000); // r1
                thread.push(@intFromPtr(arg)); // r0
            },

            else => @compileError(std.fmt.comptimePrint("{s} is not a supported platform", .{@tagName(target)})),
        }

        global_stats.total_count += 1;

        return thread;
    }

    /// Returns true if the thread is currently scheduled,
    /// but not runnig.
    pub fn isScheduled(thread: *Thread) bool {
        return (thread.queue != null);
    }

    /// Returns true if the thread is the currently active thread.
    pub fn isCurrent(thread: *Thread) bool {
        return (current_thread orelse return false) == thread;
    }

    /// Returns true if the thread was detached and must not be killed.
    pub fn isDetached(thread: *Thread) bool {
        return thread.flags.detached;
    }

    /// Returns true if the thread was already started.
    pub fn isStarted(thread: *Thread) bool {
        return thread.flags.started;
    }

    /// Returns true when the thread was started and has
    /// exited already.
    pub fn isFinished(thread: *Thread) bool {
        return thread.flags.finished;
    }

    /// Returns true when the thread is currently running.
    pub fn isRunning(thread: *Thread) bool {
        return thread.isStarted() and !thread.isFinished();
    }

    /// returns the process this thread belongs to.
    pub fn get_process(thread: *Thread) *ashet.multi_tasking.Process {
        return thread.process_link.data.process;
    }

    /// Starts the thread.
    pub fn start(thread: *Thread) error{AlreadyStarted}!void {
        if (thread.isStarted())
            return error.AlreadyStarted;

        logger.info("enqueuing {} with stack size {}", .{ thread, thread.stack_memory.len });

        thread.flags.started = true;
        enqueueThread(&wait_queue, thread);

        global_stats.running_count += 1;
    }

    pub fn detach(thread: *Thread) void {
        if (thread.isRunning()) {
            thread.flags.detached = true;
        } else {
            // thread is already done or not started yet, so we can kill it safely
            internalDestroy(thread);
        }
    }

    /// Removes the thread from the scheduling queue and halts it until `resume` is called.
    pub fn @"suspend"(thread: *Thread) void {
        if (!thread.flags.started or thread.flags.finished or thread.flags.suspended)
            return;

        thread.flags.suspended = true;
        global_stats.suspended_count += 1;

        if (thread.isCurrent()) {
            // current thread will be yielded, and because it's suspended, we won't
            // requeue it into the wait queue.
            yield();
        } else {
            // non-current thread is still in the queue, so we have to dequeue it:
            std.debug.assert(thread.queue == &wait_queue);
            thread.queue = null;
            wait_queue.remove(&thread.node);
        }
    }

    /// Moves the thread back into the scheduling queue. Must be called after `suspend` to
    /// resume code execution.
    pub fn @"resume"(thread: *Thread) void {
        if (!thread.flags.started or thread.flags.finished)
            return;
        if (!thread.flags.suspended)
            return;

        if (thread.isCurrent())
            return; // lol that doesn't make sense at all!

        std.debug.assert(thread.queue == null);
        enqueueThread(&wait_queue, thread);
        thread.flags.suspended = false;
        global_stats.suspended_count -= 1;
    }

    /// Kills the thread and releases all of its resources.
    /// **NOTE:** No cleanup functions are run inside the thread!
    pub fn kill(thread: *Thread) void {
        if (thread.isCurrent()) {
            // Special case when the thread we kill is the thread current
            // executing our code.
            //
            // This is solved by detaching the thread and then immediatly
            // exiting the thread. By this, we can be sure that we have no
            // control flow after this function.
            thread.detach();
            exit(@intFromEnum(ExitCode.killed));
            unreachable;
        }

        internalDestroy(thread);
    }

    fn internalDestroy(thread: *Thread) void {
        if (thread.queue) |queue| {
            // when the thread is still queued,
            // we have to remove it from that queue,
            // otherwise we would accidently requeue the
            // thread even if it is already dead.
            queue.remove(&thread.node);

            global_stats.running_count -= 1;
        }

        logger.info("killing thread {}", .{thread});

        std.debug.assert(thread.process_link.data.thread == thread);
        const proc = thread.process_link.data.process;
        proc.threads.remove(&thread.process_link);

        if (!proc.is_zombie() and proc.stay_resident == false and proc.threads.len == 0) {
            proc.kill(.success);
        }

        if (thread.flags.has_canary) {
            // make the stack canary writable again:
            ashet.memory.protection.change(ashet.memory.Range.from_slice(
                thread.stack_memory[0..canary_size],
            ), .read_write);
        }

        // we have to use the ThreadAlloactor that doesn't invalidate
        // the memory.
        // `ashet_scheduler_threadExit` relies on the assumption that the memory
        // is not changed between the free and the `performSwitch` call.
        ashet.memory.ThreadAllocator.free(thread.stack_memory);
        ashet.memory.type_pool(Thread).free(thread);

        global_stats.total_count -= 1;
    }

    fn push(thread: *Thread, value: u32) void {
        thread.sp -= 4;
        @as(*u32, @ptrFromInt(thread.sp)).* = value;
    }

    fn pop(thread: *Thread) u32 {
        const val = @as(*u32, @ptrFromInt(thread.sp)).*;
        thread.sp += 4;
        return val;
    }

    pub fn setName(thread: *Thread, name: []const u8) !void {
        if (@import("builtin").mode == .Debug) {
            if (name.len > thread.debug_info.name.len)
                return error.Overflow;
            @memset(&thread.debug_info.name, 0);
            std.mem.copyForwards(u8, &thread.debug_info.name, name);
        }
    }

    pub fn getName(thread: *const Thread) []const u8 {
        if (@import("builtin").mode == .Debug) {
            return std.mem.sliceTo(&thread.debug_info.name, 0);
        } else {
            return "<optimized out>";
        }
    }

    pub fn format(self: *const Thread, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (@import("builtin").mode == .Debug) {
            try writer.print("Thread(0x{X:0>8}, name={s}, ep=0x{X:0>8})", .{
                @intFromPtr(self),
                std.mem.sliceTo(&self.debug_info.name, 0),
                self.debug_info.entry_point,
            });
        } else {
            try writer.print("Thread(0x{X:0>8})", .{@intFromPtr(self)});
        }
    }
};

pub const ThreadIterator = struct {
    pub const Group = enum { waiting };

    current: ?*ThreadQueue.Node,

    pub fn init() ThreadIterator {
        return ThreadIterator{ .current = wait_queue.first };
    }

    pub fn next(self: *ThreadIterator) ?*Thread {
        const node = self.current orelse return null;
        self.current = node.next;
        return nodeToThread(node);
    }
};

const ThreadQueue = astd.DoublyLinkedList(void, .{ .tag = opaque {} });

var wait_queue: ThreadQueue = .{};

var current_thread: ?*Thread = null;

pub fn initialize() void {
    // nothing to be done here at the moment.
}

export var ashet_scheduler_save_thread: *Thread = undefined;
export var ashet_scheduler_restore_thread: *Thread = undefined;

// Reserve enough storage to save the kernel thread backup from
var kernel_thread_backup: [256]u8 align(4096) = undefined;

var kernel_thread: Thread = .{
    .sp = undefined,
    .ip = undefined,
    .debug_info = if (debug_mode) .{ .name = "kernel".* ++ [1]u8{0} ** 26 } else .{},
    .exit_code = 0,
    .stack_memory = &kernel_thread_backup,
    .process_link = .{ .data = undefined },
};

pub fn getKernelThread() *Thread {
    return &kernel_thread;
}

fn nodeToThread(node: *ThreadQueue.Node) *Thread {
    return @alignCast(@fieldParentPtr("node", node));
}

fn fetchThread(queue: *ThreadQueue) ?*Thread {
    if (queue.popFirst()) |node| {
        const thread = nodeToThread(node);
        std.debug.assert(thread.queue == queue);
        thread.queue = null;
        return thread;
    } else {
        return null;
    }
}

fn enqueueThread(queue: *ThreadQueue, thread: *Thread) void {
    std.debug.assert(thread.queue == null);
    thread.queue = queue;
    queue.append(&thread.node);
}

pub fn start() void {
    std.debug.assert(current_thread == null);

    current_thread = getKernelThread();

    // save state to kernel thread and jump into first queued thread
    performSwitch(getKernelThread(), fetchThread(&wait_queue) orelse {
        logger.warn("no threads to schedule, not starting...", .{});
        return;
    });

    // Clean up:
    current_thread = null;
}

var delete_previous_thread: ?*Thread = null;

fn performSwitch(from: *Thread, to: *Thread) void {
    // logger.debug("switch thread from 0x{X:0>8} (esp=0x{X:0>8}) to 0x{X:0>8} (esp=0x{X:0>8})", .{
    //     @ptrToInt(from), from.sp,
    //     @ptrToInt(to),   to.sp,
    // });

    std.debug.assert(current_thread.? == from);

    // Update timings
    const now = ashet.time.Instant.now();
    if (from.stats.schedule_time) |schedule_time| {
        from.stats.total_execution_time_ms += now.ms_since(schedule_time);
    }
    to.stats.schedule_time = now;
    to.stats.times_scheduled += 1;

    // Prepare task switch:
    ashet_scheduler_save_thread = from;
    ashet_scheduler_restore_thread = to;
    current_thread = to;

    ashet_scheduler_switchTasks();

    if (delete_previous_thread) |true_previous| {
        logger.info("delete previous thread ('{s}', {}).", .{ true_previous.getName(), ashet.CodeLocation{ .pointer = true_previous.debug_info.entry_point } });
        delete_previous_thread = null;

        // If the previous thread was marked for deletion, we can
        // now safely assume it won't be resumed ever again, and we've
        // switched the stack to one that won't get deleted.
        //
        // thus, we can free the memory:
        true_previous.internalDestroy();
    }
}

pub fn yield() void {
    ashet.stackCheck(); // check if we're doing a sane yield or if we violated the stack boundary

    const old_thread = current_thread orelse @panic("called scheduler.exit() from outside a thread!");
    std.debug.assert(old_thread.queue == null); // thread must not be in a queue right now

    if (!old_thread.flags.suspended) {
        // we must enqueue old thread again before popping new_thread, so we can execute a single thread as well:
        enqueueThread(&wait_queue, old_thread);
    } else if (wait_queue.len == 0) {
        @panic("kernel panic: no thread active anymore, we can't resume. this is a critical failure!");
    }

    const new_thread = fetchThread(&wait_queue) orelse unreachable; // we can be sure that we have a thread as we enqueue one a moment before
    std.debug.assert(new_thread.queue == null); // thread must not be in a queue right now

    performSwitch(old_thread, new_thread);
}

// Export `exit` as an alias as well
pub const exit = ashet_scheduler_threadExit;

/// Exits the current thread and writes it `exit_code`.
export fn ashet_scheduler_threadExit(code: u32) callconv(.C) noreturn {
    const old_thread = current_thread orelse @panic("called scheduler.exit() from outside a thread!");
    std.debug.assert(old_thread.queue == null); // thread must not be in a queue right now
    old_thread.exit_code = code;
    old_thread.flags.finished = true;

    const new_thread = fetchThread(&wait_queue) orelse getKernelThread(); // we can either schedule the next thread or we return control to the kernel
    std.debug.assert(new_thread.queue == null); // thread must not be in a queue right now

    if (old_thread.isDetached()) {
        // Destroy detached threads when they're finished. We don't need them anymore.
        // We have to delay deletion though, for a short period of time until after the
        // task switch.
        // Otherwise, memory protection will kill our stack and we will triple-fault.
        std.debug.assert(delete_previous_thread == null);
        delete_previous_thread = old_thread;
    }

    // We save the thread we switch to into dummy storage
    performSwitch(old_thread, new_thread);

    @panic("resumed dead thread. implementation bug in the scheduler.");
}

extern fn ashet_scheduler_switchTasks() callconv(.C) void;
extern fn ashet_scheduler_threadTrampoline() callconv(.C) void;

comptime {
    const preamble =
        std.fmt.comptimePrint(
        \\.equ THREAD_SP_OFFSET, {}
        \\.equ THREAD_IP_OFFSET, {}
        \\
    , .{ @offsetOf(Thread, "sp"), @offsetOf(Thread, "ip") });

    switch (target) {
        .riscv32 => asm (preamble ++
                \\
                \\ashet_scheduler_threadTrampoline:
                //
                //  we just restored the thread state from scheduler.createThread,
                //  so s1 contains the argument to our thread entry point.
                \\  mv a0,s3
                //
                //  after we successfully restored the argument, just call the actual
                //  thread entry point
                \\  jalr s2
                //
                //  then kill the thread by jumping into the exit function.
                //  leaving a0 unchanged. This means that the return value of the
                //  thread function will be retained into the exit() call.
                //  There's no need to use call/jalr here, as the exit() call won't
                //  ever return here in the first place.
                \\  j ashet_scheduler_threadExit
                \\
                \\ashet_scheduler_switchTasks:
                //
                //  save all registers that are callee-saved to the stack
                \\  addi sp, sp, -56 // push stack frame
                \\  sw  x3, 52(sp)
                \\  sw  x4, 48(sp)
                \\  sw  x8, 44(sp)
                \\  sw  x9, 40(sp)
                \\  sw x18, 36(sp)
                \\  sw x19, 32(sp)
                \\  sw x20, 28(sp)
                \\  sw x21, 24(sp)
                \\  sw x22, 20(sp)
                \\  sw x23, 16(sp)
                \\  sw x24, 12(sp)
                \\  sw x25, 8(sp)
                \\  sw x26, 4(sp)
                \\  sw x27, 0(sp)
                //
                //  load the current thread pointer into a0
                \\  lui     a0, %hi(ashet_scheduler_save_thread)
                \\  lw      a0, %lo(ashet_scheduler_save_thread)(a0)
                //
                //  then create a backup of the current state:
                \\  sw sp, THREAD_SP_OFFSET(a0)
                \\  sw ra, THREAD_IP_OFFSET(a0)
                //
                // then load the new thread pointer
                \\  lui     a0, %hi(ashet_scheduler_restore_thread)
                \\  lw      a0, %lo(ashet_scheduler_restore_thread)(a0)
                //
                //  and restore the previously saved state:
                \\  lw sp, THREAD_SP_OFFSET(a0)
                \\  lw ra, THREAD_IP_OFFSET(a0)
                \\
                //  then restore all registers from the stack
                //  in the same order we saved them above
                \\  lw  x3, 52(sp)
                \\  lw  x4, 48(sp)
                \\  lw  x8, 44(sp)
                \\  lw  x9, 40(sp)
                \\  lw x18, 36(sp)
                \\  lw x19, 32(sp)
                \\  lw x20, 28(sp)
                \\  lw x21, 24(sp)
                \\  lw x22, 20(sp)
                \\  lw x23, 16(sp)
                \\  lw x24, 12(sp)
                \\  lw x25,  8(sp)
                \\  lw x26,  4(sp)
                \\  lw x27,  0(sp)
                \\  addi sp, sp, 56
                //
                //  and jump into the new thread function
                \\  ret
        ),

        .x86 => asm (preamble ++
                \\
                \\ashet_scheduler_threadTrampoline:
                //  in x86, the SYS-V ABI says that the stack has to be
                //  aligned to 16 when `call` is invoked, so let's do that:
                \\  and $0xfffffff0, %esp
                \\  sub $0x0C, %esp
                //
                //  we just restored the thread state from scheduler.createThread,
                //  so %ebx contains the argument,
                \\  push %ebx
                //
                //  and %eax contains the function to be called.
                \\  call *%eax
                //
                //  remove argument from the stack again:
                \\  addl    $4, %esp
                //
                //  and push the result of the function into the exit code argument.
                \\  push %eax
                //
                //  then kill the thread by jumping into the exit function.
                //  There's no need to use call here, as the exit() call won't
                //  ever return here in the first place.
                \\  jmp ashet_scheduler_threadExit
                \\
                \\ashet_scheduler_switchTasks:
                //
                //  save all registers that are callee-saved to the stack
                // \\  pushf
                \\  push %edi
                \\  push %esi
                \\  push %ebp
                \\  push %edx
                \\  push %ecx
                \\  push %ebx
                \\  push %eax
                //
                //  backup the current state:
                \\  mov ashet_scheduler_save_thread, %eax
                \\  mov %esp, THREAD_SP_OFFSET(%eax)
                // \\  movl    %eip, THREAD_IP_OFFSET(%eax) // is stored on the stack on x86
                //
                // restore the new state:
                \\  mov ashet_scheduler_restore_thread, %eax
                \\  mov THREAD_SP_OFFSET(%eax), %esp
                // \\  movl THREAD_IP_OFFSET(%eax), %eip // lol nope
                \\
                //  then restore all registers from the stack
                //  in the same order we saved them above
                \\  pop %eax
                \\  pop %ebx
                \\  pop %ecx
                \\  pop %edx
                \\  pop %ebp
                \\  pop %esi
                \\  pop %edi
                // \\  popf
                //
                //  and jump into the new thread function
                \\  ret
        ),

        .thumb => asm (preamble ++
                \\
                // \\.thumb
                \\.thumb_func
                \\.global ashet_scheduler_threadTrampoline
                \\.type ashet_scheduler_threadTrampoline, %function
                \\ashet_scheduler_threadTrampoline:
                //
                //  we just restored the thread state from scheduler.createThread,
                //  so a0 already contains the argument to our thread entry point.
                //
                //  after we successfully restored the argument, just call the actual
                //  thread entry point currently stored in the IP register.
                \\  blx ip
                //
                //  then kill the thread by jumping into the exit function.
                //  leaving a0 unchanged. This means that the return value of the
                //  thread function will be retained into the exit() call.
                //  There's no need to use call/jalr here, as the exit() call won't
                //  ever return here in the first place.
                \\  b ashet_scheduler_threadExit
                \\
                \\.thumb_func
                \\.global ashet_scheduler_switchTasks
                \\.type ashet_scheduler_switchTasks, %function
                \\ashet_scheduler_switchTasks:
                //
                //  save all registers that to the stack
                \\  push {r0-r10,fp,ip}
                //
                //  load the current thread pointer into a0
                \\  ldr a1, .save_thread
                \\  ldr a1, [a1]
                //
                //  then create a backup of the current state:
                \\  str sp, [a1, #THREAD_SP_OFFSET]
                \\  str lr, [a1, #THREAD_IP_OFFSET]
                //
                // then load the new thread pointer
                \\  ldr a1, .restore_thread
                \\  ldr a1, [a1]
                //
                //  and restore the previously saved state:
                \\  ldr sp, [a1, #THREAD_SP_OFFSET]
                \\  ldr lr, [a1, #THREAD_IP_OFFSET]
                \\
                //  then restore all registers from the stack:
                \\  pop {r0-r10,fp,ip}
                //
                //  and jump into the new thread function
                \\  bx lr
                \\.save_thread:
                \\  .word ashet_scheduler_save_thread
                \\.restore_thread:
                \\  .word ashet_scheduler_restore_thread
        ),

        else => @compileError(std.fmt.comptimePrint("{s} is not a supported platform", .{@tagName(target)})),
    }
}
