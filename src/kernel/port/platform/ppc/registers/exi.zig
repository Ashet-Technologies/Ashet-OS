pub const Frequency = enum(u3) {
    @"1MHz" = 0,
    @"2MHz" = 1,
    @"4MHz" = 2,
    @"8MHz" = 3,
    @"16MHz" = 4,
    @"32MHz" = 5,
};

pub const DeviceID = enum(u3) {
    none = 0b000,
    device0 = 0b001,
    device1 = 0b010,
    device2 = 0b100,
};

pub const Parameter = packed struct(u32) {
    interrupt_mask: bool,
    interrupt_status: bool,
    transfer_interrupt_mask: bool,
    transfer_interrupt_status: bool,
    clock: Frequency,
    select: DeviceID,
    ext_interrupt_mask: bool,
    ext_interrupt_status: bool,
    ext_connected: bool,
    /// Only valid on EXI0
    rom_descramble: bool,
    reserved: u18 = 0,
};

/// EXI Channel 0 Parameter
pub const parameter0: *volatile Parameter = @ptrFromInt(0xCC006800);
/// EXI Channel 1 Parameter
pub const parameter1: *volatile Parameter = @ptrFromInt(0xCC006814);
/// EXI Channel 2 Parameter
pub const parameter2: *volatile Parameter = @ptrFromInt(0xCC006828);

/// EXI Channel 0 DMA Start Address
/// value must be 32 bytes aligned
pub const dma_start_address0: *volatile [*]align(32) u8 = @ptrFromInt(0xCC006804);
/// EXI Channel 1 DMA Start Address
/// value must be 32 bytes aligned
pub const dma_start_address1: *volatile [*]align(32) u8 = @ptrFromInt(0xCC006818);
/// EXI Channel 2 DMA Start Address
/// value must be 32 bytes aligned
pub const dma_start_address2: *volatile [*]align(32) u8 = @ptrFromInt(0xCC00682C);

/// EXI Channel 0 DMA Length
pub const dma_length0: *volatile u32 = @ptrFromInt(0xCC006808);
/// EXI Channel 1 DMA Length
pub const dma_length1: *volatile u32 = @ptrFromInt(0xCC00681C);
/// EXI Channel 2 DMA Length
pub const dma_length2: *volatile u32 = @ptrFromInt(0xCC006830);

pub const ImmediateTransferLength = enum(u2) {
    @"1byte" = 0,
    @"2byte" = 1,
    @"3byte" = 2,
    @"4byte" = 3,
};

pub const Control = packed struct(u32) {
    transfer_start: bool,
    mode: enum(u1) {
        immediate = 0,
        dma = 1,
    },
    readwrite: enum(u2) {
        read = 0,
        write = 1,
        /// Invalid for DMA
        readwrite = 2,
    },
    immediate_length: ImmediateTransferLength = .@"1byte",
    reserved: u26 = 0,
};

/// EXI Channel 0 Control Register
pub const control0: *volatile Control = @ptrFromInt(0xCC00680C);
/// EXI Channel 1 Control Register
pub const control1: *volatile Control = @ptrFromInt(0xCC006820);
/// EXI Channel 2 Control Register
pub const control2: *volatile Control = @ptrFromInt(0xCC006834);

/// EXI Channel 0 Immediate data
pub const immediate_data0: *volatile u32 = @ptrFromInt(0xCC006810);
/// EXI Channel 1 Immediate data
pub const immediate_data1: *volatile u32 = @ptrFromInt(0xCC006824);
/// EXI Channel 2 Immediate data
pub const immediate_data2: *volatile u32 = @ptrFromInt(0xCC006838);
