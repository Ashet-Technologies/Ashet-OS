/// Control Status Register
pub const control_status: *volatile ControlStatus = @ptrFromInt(0xCC00500A);
pub const ControlStatus = packed struct(u16) {
    reset: bool = false,
    interrupt_assert: bool = false,
    halt: bool,
    ai_interrupt_status: bool = false,
    ai_interrupt_mask: bool = false,
    aram_interrupt_status: bool = false,
    aram_interrupt_mask: bool = false,
    dsp_interrupt_status: bool = false,
    dsp_interrupt_mask: bool = false,
    dsp_dma_status: bool = false,
    reserved1: u1 = 0,
    dsp_reset: bool = false,
    reserved2: u4 = 0,
};
