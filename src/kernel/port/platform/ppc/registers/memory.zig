/// Protected Memory Region 0
pub const protected_region0: *volatile u32 = @ptrFromInt(0xCC004000);
/// Protected Memory Region 1
pub const protected_region1: *volatile u32 = @ptrFromInt(0xCC004004);
/// Protected Memory Region 2
pub const protected_region2: *volatile u32 = @ptrFromInt(0xCC004008);
/// Protected Memory Region 3
pub const protected_region3: *volatile u32 = @ptrFromInt(0xCC00400c);

/// Protected Config
pub const protection_config: *volatile Config = @ptrFromInt(0xCC004010);
const Flags = enum(u2) {
    denied = 0,
    read = 1,
    write = 2,
    all = 3,
};
const Config = packed struct(u16) {
    channel0: Flags = .denied,
    channel1: Flags = .denied,
    channel2: Flags = .denied,
    channel3: Flags = .denied,
    reserved: u8 = 0,
};

/// MI Interrupt mask
pub const interrupt_mask: *volatile InterruptMask = @ptrFromInt(0xCC00401C);
pub const InterruptMask = packed struct(u16) {
    mem0: bool = false,
    mem1: bool = false,
    mem2: bool = false,
    mem3: bool = false,
    all: bool = false,
    reserved: u11 = 0,
};

/// MI Interrupt cause
pub const interrupt_cause: *volatile InterruptCause = @ptrFromInt(0xCC00401e);
pub const InterruptCause = packed struct(u16) {
    mem0: bool = false,
    mem1: bool = false,
    mem2: bool = false,
    mem3: bool = false,
    memaddress: bool = false,
    reserved: u11 = 0,
};

/// MI Interrupt signal
pub const interrupt_signal: *volatile InterruptSignal = @ptrFromInt(0xCC004020);
pub const InterruptSignal = packed struct(u16) {
    reserved1: u1 = 0,
    asserted: bool = false,
    reserved2: u14 = 0,
};

/// MI Fault Address Low
pub const fail_address_low: *volatile u32 = @ptrFromInt(0xCC004022);

/// MI Fault Address High
pub const fail_address_high: *volatile u32 = @ptrFromInt(0xCC004024);
