/// GX Fifo buffer, 32 bytes
pub const fifo: *volatile u32 = @ptrFromInt(0xCC008000);
pub const fifo_f32: *volatile f32 = @ptrFromInt(0xCC008000);
pub const fifo_u8: *volatile u8 = @ptrFromInt(0xCC008000);
pub const fifo_u16: *volatile u16 = @ptrFromInt(0xCC008000);
