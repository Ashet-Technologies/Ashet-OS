/// Status Register
pub const status: *volatile Status = @ptrFromInt(0xCC000000);
pub const Status = packed struct(u16) {
    overflow: bool,
    underflow: bool,
    idle_reading: bool,
    idle_commands: bool,
    breakpoint: bool,
    reserved: u11 = 0,
};

/// Control Register
pub const control: *volatile Control = @ptrFromInt(0xCC000002);
const Control = packed struct(u16) {
    read: bool,
    interrupt: bool,
    overflow: bool,
    underflow: bool,
    /// link cp/pe fifo
    link: bool,
    breakpoint: bool,
    reserved: u10 = 0,
};

/// Clear Register
/// set to true to clear
pub const clear: *volatile Clear = @ptrFromInt(0xCC000004);
const Clear = packed struct(u16) {
    overflow: bool,
    underflow: bool,
    reserved: u14 = 0,
};

/// Unknown register (perf?)
pub const unknown1: *volatile u16 = @ptrFromInt(0xCC000006);

/// Token Register
pub const token: *volatile u16 = @ptrFromInt(0xCC00000E);

/// Bounding Box left Register
pub const bb_left: *volatile u16 = @ptrFromInt(0xCC000010);

/// Bounding Box right Register
pub const bb_right: *volatile u16 = @ptrFromInt(0xCC000012);

/// Bounding Box top Register
pub const bb_top: *volatile u16 = @ptrFromInt(0xCC000014);

/// Bounding Box bottom Register
pub const bb_bottom: *volatile u16 = @ptrFromInt(0xCC000016);

/// FIFO base lo
pub const fifo_base: *volatile u16 = @ptrFromInt(0xCC000020);
pub const fifo_base_lo: *volatile u16 = @ptrFromInt(0xCC000020);
pub const fifo_base_hi: *volatile u16 = @ptrFromInt(0xCC000022);

/// FIFO end lo
pub const fifo_end_lo: *volatile u16 = @ptrFromInt(0xCC000024);
pub const fifo_end_hi: *volatile u16 = @ptrFromInt(0xCC000026);

/// FIFO high watermark
/// Used for overflow interrupt
pub const fifo_watermark_high_lo: *volatile u16 = @ptrFromInt(0xCC000028);
pub const fifo_watermark_high_hi: *volatile u16 = @ptrFromInt(0xCC00002A);

/// FIFO low watermark
/// Used for underflow interrupt
pub const fifo_watermark_low_lo: *volatile u16 = @ptrFromInt(0xCC00002C);
pub const fifo_watermark_low_hi: *volatile u16 = @ptrFromInt(0xCC00002E);

/// FIFO RW distance
pub const fifo_rw_distance_lo: *volatile u16 = @ptrFromInt(0xCC000030);
pub const fifo_rw_distance_hi: *volatile u16 = @ptrFromInt(0xCC000032);

/// FIFO write pointer
pub const fifo_write_ptr_lo: *volatile u16 = @ptrFromInt(0xCC000034);
pub const fifo_write_ptr_hi: *volatile u16 = @ptrFromInt(0xCC000036);

/// FIFO read pointer
pub const fifo_read_ptr_lo: *volatile u16 = @ptrFromInt(0xCC000038);
pub const fifo_read_ptr_hi: *volatile u16 = @ptrFromInt(0xCC00003A);

/// FIFO breakpoint
pub const fifo_breakpoint_lo: *volatile u16 = @ptrFromInt(0xCC00003C);
pub const fifo_breakpoint_hi: *volatile u16 = @ptrFromInt(0xCC00003E);
