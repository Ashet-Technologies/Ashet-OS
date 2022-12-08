//! This file implements the thread scheduler.
//! The scheduler starts and suspends threads in a cooperative manner.
//!
//!
//! Register ABI Name Description Saver
//! x0       zero     Hard-wired zero                  —
//! x1       ra       Return address                   Caller
//! x2       sp       Stack pointer                    Callee
//! x3       gp       Global pointer                   —
//! x4       tp       Thread pointer                   —
//! x5–7     t0–2     Temporaries                      Caller
//! x8       s0/fp    Saved register/frame pointer     Callee
//! x9       s1       Saved register                   Callee
//! x10–11   a0–1     Function arguments/return values Caller
//! x12–17   a2–7     Function arguments               Caller
//! x18–27   s2–11    Saved registers                  Callee
//! x28–31   t3–6     Temporaries                      Caller
//!
//! f0–7     ft0–7    FP temporaries                   Caller
//! f8–9     fs0–1    FP saved registers               Callee
//! f10–11   fa0–1    FP arguments/return values       Caller
//! f12–17   fa2–7    FP arguments                     Caller
//! f18–27   fs2–11   FP saved registers               Callee
//! f28–31   ft8–11   FP temporaries                   Caller

const std = @import("std");
const logger = std.log.scoped(.scheduler);
const ashet = @import("../main.zig");

const debug_mode = @import("builtin").mode == .Debug;

pub fn dumpStats() void {
    logger.info("stat dump:", .{});
    if (current_thread) |thread| {
        if (debug_mode) {
            logger.info("  current thread: ip=0x{X:0>8}, ep=0x{X:0>8}, name={s}", .{ thread.ip, thread.debug_info.entry_point, thread.getName() });
        } else {
            logger.info("  current thread: ip=0x{X:0>8}", .{thread.ip});
        }
    }
    logger.info("  total:     {}", .{stats.total_count});
    logger.info("  waiting:   {}", .{wait_queue.len});
    logger.info("  suspended: {}", .{stats.suspended_count});
    logger.info("  running:   {}", .{stats.running_count});
}

pub const stats = struct {
    var total_count: usize = 0;
    var suspended_count: usize = 0;
    var running_count: usize = 0;
};

pub const ExitCode = ashet.abi.ExitCode;
pub const ThreadFunction = ashet.abi.ThreadFunction;

/// Thread management structure.
/// Is allocated in such a way that is is stored at the end of the last page of thread stack.
pub const Thread = struct {
    pub const DebugInfo = if (debug_mode) struct {
        entry_point: usize = 0,
        name: [32]u8 = [1]u8{0} ** 32,
    } else struct {};

    pub const Flags = packed struct(u32) {
        suspended: bool = false,
        started: bool = false,
        finished: bool = false,
        detached: bool = false,
        padding: u28 = 0,
    };

    pub const default_stack_size = 8192;

    ip: usize,
    sp: usize,
    exit_code: u32,

    /// The queue the thread currently is in.
    queue: ?*ThreadQueue = null,
    /// The queue node we use to enqueue/dequeue the thread between different queues.
    node: ThreadQueue.Node = .{ .data = {} },

    flags: Flags = .{},

    /// The number of memory pages allocated for this thread. Is required to free all thread memory later on.
    stack_size: usize,

    debug_info: DebugInfo = .{},

    process: ?*ashet.multi_tasking.Process,

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
        const stack_size = std.mem.alignForward(options.stack_size, ashet.memory.page_size);

        const stack_bottom = try ashet.memory.page_allocator.allocWithOptions(u8, stack_size, ashet.memory.page_size, null);
        errdefer ashet.memory.page_allocator.free(stack_bottom);

        const thread = @intToPtr(*Thread, @ptrToInt(stack_bottom.ptr) + stack_size - @sizeOf(Thread));
        const thread_proc = options.process;

        thread.* = Thread{
            .sp = @ptrToInt(thread),
            .ip = @ptrToInt(&ashet_scheduler_threadTrampoline),
            .exit_code = 0,
            .stack_size = stack_size,
            .process = thread_proc,
        };

        if (thread.process) |proc| {
            proc.thread_count += 1;
        }

        if (@import("builtin").mode == .Debug) {
            thread.debug_info.entry_point = @ptrToInt(func);
        }

        thread.push(0x0000_0000); //      x3  ; gp Global pointer
        thread.push(@ptrToInt(&ashet.syscalls.syscall_table)); //      x4  ; tp Thread pointer
        thread.push(0x0000_0000); //      x8  ; s0
        thread.push(0x0000_0000); //      x9  ; s1
        thread.push(@ptrToInt(func)); // x18  ; s2
        thread.push(@ptrToInt(arg)); //  x19  ; s3
        thread.push(0x0000_0000); //     x20
        thread.push(0x0000_0000); //     x21
        thread.push(0x0000_0000); //     x22
        thread.push(0x0000_0000); //     x23
        thread.push(0x0000_0000); //     x24
        thread.push(0x0000_0000); //     x25
        thread.push(0x0000_0000); //     x26
        thread.push(0x0000_0000); //     x27

        stats.total_count += 1;

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

    /// Starts the thread.
    pub fn start(thread: *Thread) error{AlreadyStarted}!void {
        if (thread.isStarted())
            return error.AlreadyStarted;

        logger.info("enqueuing {}", .{thread});

        thread.flags.started = true;
        enqueueThread(&wait_queue, thread);

        stats.running_count += 1;
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
        stats.suspended_count += 1;

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
        stats.suspended_count -= 1;
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
            exit(ExitCode.killed);
            unreachable;
        }

        internalDestroy(thread);
    }

    /// Returns the pointer to the "stack top"
    pub fn getBasePointer(thread: *Thread) [*]u8 {
        return @intToPtr([*]u8, @ptrToInt(thread) + @sizeOf(Thread));
    }

    fn internalDestroy(thread: *Thread) void {
        if (thread.queue) |queue| {
            // when the thread is still queued,
            // we have to remove it from that queue,
            // otherwise we would accidently requeue the
            // thread even if it is already dead.
            queue.remove(&thread.node);

            stats.running_count -= 1;
        }

        logger.info("killing thread {}", .{thread});

        if (thread.process) |proc| {
            proc.thread_count -= 1;
            if (proc.thread_count == 0) {
                proc.kill();
            }
        }

        const stack_top = thread.getBasePointer();

        const stack_bottom = stack_top - thread.stack_size;

        ashet.memory.page_allocator.free(stack_bottom[0..thread.stack_size]);
        stats.total_count -= 1;
    }

    fn push(thread: *Thread, value: u32) void {
        thread.sp -= 4;
        @intToPtr(*u32, thread.sp).* = value;
    }

    fn pop(thread: *Thread) u32 {
        const val = @intToPtr(*u32, thread.sp).*;
        thread.sp += 4;
        return val;
    }

    pub fn setName(thread: *Thread, name: []const u8) !void {
        if (@import("builtin").mode == .Debug) {
            if (name.len > thread.debug_info.name.len)
                return error.Overflow;
            std.mem.set(u8, &thread.debug_info.name, 0);
            std.mem.copy(u8, &thread.debug_info.name, name);
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
                @ptrToInt(self),
                std.mem.sliceTo(&self.debug_info.name, 0),
                self.debug_info.entry_point,
            });
        } else {
            try writer.print("Thread(0x{X:0>8})", .{@ptrToInt(self)});
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

const ThreadQueue = std.TailQueue(void);

var wait_queue: ThreadQueue = .{};

var current_thread: ?*Thread = null;

pub fn initialize() void {
    // nothing to be done here at the moment.
}

export var ashet_scheduler_save_thread: *Thread = undefined;
export var ashet_scheduler_restore_thread: *Thread = undefined;

// Reserve enough storage to save the kernel thread backup from
var kernel_thread_backup: [std.mem.alignForward(@sizeOf(Thread) + 56, 256)]u8 align(256) = undefined;

pub fn getKernelThread() *Thread {
    return @intToPtr(*Thread, @ptrToInt(&kernel_thread_backup) + kernel_thread_backup.len - @sizeOf(Thread));
}

fn nodeToThread(node: *ThreadQueue.Node) *Thread {
    return @fieldParentPtr(Thread, "node", node);
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

fn performSwitch(from: *Thread, to: *Thread) void {
    std.debug.assert(current_thread.? == from);
    ashet_scheduler_save_thread = from;
    ashet_scheduler_restore_thread = to;
    current_thread = to;

    ashet_scheduler_switchTasks();
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
        //
        // A WORD OF WARNING:
        // This code here assumes that between this point
        // and the restoration of the next stack, no fresh heap allocation
        // is performed. This way, we have the guarantee that our stack memory
        // is still unused by other code!
        //
        // When we start using interrupts, we have to disable them
        // on entering exit() or yield()
        // and restore them shortly before the `ret` in
        // `ashet_scheduler_switchTasks`. This way, we can be sure to have a critical section
        // that cannot be interrupted, thus have no spurious heap allocations.
        old_thread.internalDestroy();
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

    const target = @import("builtin").target.cpu.arch;
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

        .x86 => @compileError("x86 support not implemented yet!"),
        .arm => @compileError("x86 support not implemented yet!"),

        else => @compileError(std.fmt.comptimePrint("{s} is not a supported platform", .{@tagName(target)})),
    }
}
