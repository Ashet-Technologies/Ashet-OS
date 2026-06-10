/// Interrupt cause
pub const interrupt_cause: *volatile InterruptCause = @ptrFromInt(0xCC003000);
// TODO: Make this an enum?
pub const InterruptCause = packed struct(u32) {
    gp_error: bool,
    reset_switch: bool,
    dvd: bool,
    serial: bool,
    exi: bool,
    streaming: bool,
    dsp: bool,
    memory: bool,
    video: bool,
    pe_token: bool,
    pe_finish: bool,
    cp: bool,
    debug: bool,
    hsp: bool,
    reserved1: u2 = 0,
    reset_switch_state: bool,
    reserved2: u15 = 0,
};

/// Interrupt mask
pub const interrupt_mask: *volatile InterruptMask = @ptrFromInt(0xCC003004);
pub const InterruptMask = packed struct(u32) {
    gp_error: bool = false,
    reset_switch: bool = false,
    dvd: bool = false,
    serial: bool = false,
    exi: bool = false,
    streaming: bool = false,
    dsp: bool = false,
    memory: bool = false,
    video: bool = false,
    pe_token: bool = false,
    pe_finish: bool = false,
    cp: bool = false,
    debug: bool = false,
    hsp: bool = false,
    reserved: u18 = 0,
};

/// FIFO Base Start
pub const fifo_start: *volatile [*]u32 align(32) = @ptrFromInt(0xCC00300c);

/// FIFO Base End TODO: Unsure
pub const fifo_end: *volatile [*]u32 align(32) = @ptrFromInt(0xCC003010);

/// FIFO Base End TODO: Unsure
pub const fifo_write_ptr: *volatile [*]u32 align(32) = @ptrFromInt(0xCC003014);
