/// Control Status Register
pub const control_status: *volatile ControlStatus = @ptrFromInt(0xCC006C00);
pub const ControlStatus = packed struct(u32) {
    pub const SampleRate = enum(u1) {
        @"48kHz" = 0,
        @"32kHz" = 1,
    };

    playing_status: bool = false,
    aux_frequency: SampleRate = .@"48kHz",
    interrupt_mask: bool = false,
    interrupt_status: bool = false,
    interrupt_valid: bool = false,
    sample_cntr_reset: bool = false,
    dsp_sample_rate: SampleRate = .@"48kHz",
    reserved: u25 = 0,
};

/// Volume Register
pub const volume: *volatile Volume = @ptrFromInt(0xCC006C04);
pub const Volume = packed struct(u32) {
    left: u8 = 0,
    right: u8 = 0,
    reserved: u16 = 0,
};

/// Sample Counter
pub const sample_counter: *volatile u32 = @ptrFromInt(0xCC006C08);

/// Interrupt Timing
pub const interrupt_timing: *volatile u32 = @ptrFromInt(0xCC006C0C);

// TODO Are these really 16 bits? or can they be combined
// TODO These 4 below are TECHNICALLY in dsp memory space, likely why it's 16bit!
// DMA High address
pub const dma_address_high: *volatile u16 = @ptrFromInt(0xCC005030);

// DMA Low address
pub const dma_address_low: *volatile u16 = @ptrFromInt(0xCC005032);

// DMA Control and Sample Count
pub const dma_control_count: *volatile ControlSampleCount = @ptrFromInt(0xCC005036);
pub const ControlSampleCount = packed struct(u16) {
    length: u15 = 0,
    enabled: bool = false,
};

// DMA Control Length
pub const dma_samples_remaining: *volatile u16 = @ptrFromInt(0xCC00503A);
