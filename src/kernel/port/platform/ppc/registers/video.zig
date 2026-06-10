pub const VideoFormat = enum(u2) {
    ntsc = 0,
    pal = 1,
    mpal = 2,
    debug = 3,
};

pub const VideoMode = enum {
    interlaced,
    doublestrike,
    progressive,
};

/// Vertical Timing Register
pub const vtr: *volatile VTR = @ptrFromInt(0xCC002000);
pub const VTR = packed struct(u16) {
    equalization: u4,
    active_video: u10,
    reserved: u2 = 0,
};

pub const Interlaced = enum(u1) {
    interlaced = 0,
    non_interlaced = 1,
};

/// Display Configuration Register
pub const dcr: *volatile DCR = @ptrFromInt(0xCC002002);
pub const DCR = packed struct(u16) {
    const LatchMode = enum(u2) {
        off = 0,
        on1 = 1,
        on2 = 2,
        always = 3,
    };

    enable: bool = false,
    reset: bool = false,
    interlaced: Interlaced = .interlaced,
    dlr: bool = false, // 3d
    display_latch0: LatchMode = .off,
    display_latch1: LatchMode = .off,
    video_format: VideoFormat = .ntsc,
    reserved: u6 = 0,
};

/// Horizontal Timing 0
pub const htr0: *volatile HTR0 = @ptrFromInt(0xCC002004);
pub const HTR0 = packed struct(u32) {
    hlw: u9,
    reserved1: u7 = 0,
    hce: u7,
    reserved2: u1 = 0,
    hcs: u7,
    reserved3: u1 = 0,
};

/// Horizontal Timing 1
pub const htr1: *volatile HTR1 = @ptrFromInt(0xCC002008);
pub const HTR1 = packed struct(u32) {
    hsy: u7,
    hbe: u10,
    hbs: u10,
    reserved: u5 = 0,
};

/// Odd Field Vertical Timing Register
pub const vto: *volatile FVTR = @ptrFromInt(0xCC00200c);

/// Even Field Vertical Timing Register
pub const vte: *volatile FVTR = @ptrFromInt(0xCC002010);
pub const FVTR = packed struct(u32) {
    prb: u10,
    reserved1: u6 = 0,
    psb: u10,
    reserved2: u6 = 0,
};

// Odd Field Burst Blanking Interval Register
pub const bboi: *volatile BBOI = @ptrFromInt(0xCC002014);
pub const BBOI = packed struct(u32) {
    bs1: u5,
    be1: u11,
    bs3: u5,
    be3: u11,
};

// Even Field Burst Blanking Interval Register
pub const bbei: *volatile BBEI = @ptrFromInt(0xCC002018);
pub const BBEI = packed struct(u32) {
    bs2: u5,
    be2: u11,
    bs4: u5,
    be4: u11,
};

/// Top Field Base Register (L) (External Framebuffer Half 1)
pub const tfbl: *volatile FBR = @ptrFromInt(0xCC00201c);

/// Top Field Base Register (R) (Only valid in 3D Mode)
pub const tfbr: *volatile FBR = @ptrFromInt(0xCC002020);

/// Bottom Field Base Register (L) (External Framebuffer Half 2)
pub const bfbl: *volatile FBR = @ptrFromInt(0xCC002024);

/// Bottom Field Base Register (R) (Only valid in 3D Mode)
pub const bfbr: *volatile FBR = @ptrFromInt(0xCC002028);

// TODO: Double check comments
/// Field Base Register
pub const FBR = packed struct(u32) {
    fbb: u24, // 0x80000000 | (fbb << 9) or 0x80000000 | (fbb << 5) if xof is set?
    xof: u4,
    po: bool,
    unknown2: u3 = 0,
};

/// Current Vertical Position
pub const dpv: *volatile RBP = @ptrFromInt(0xCC00202c);

/// Current Horizontal Position
pub const dph: *volatile RBP = @ptrFromInt(0xCC00202e);
pub const RBP = packed struct(u16) {
    value: u11,
    reserved1: u5,
};

/// Display Interrupt 0
pub const di0: *volatile DI = @ptrFromInt(0xCC002030);

/// Display Interrupt 1
pub const di1: *volatile DI = @ptrFromInt(0xCC002034);

/// Display Interrupt 2
pub const di2: *volatile DI = @ptrFromInt(0xCC002038);

/// Display Interrupt 3
pub const di3: *volatile DI = @ptrFromInt(0xCC00203C);
pub const DI = packed struct(u32) {
    hct: u10,
    reserved1: u6 = 0,
    vct: u10,
    reserved2: u2 = 0,
    interrupt_enabled: bool,
    reserved3: u2 = 0,
    interrupt_status: bool,
};

/// Display Latch 0
pub const dl0: *volatile DL = @ptrFromInt(0xCC002040);

/// Display Latch 1
pub const dl1: *volatile DL = @ptrFromInt(0xCC002044);
pub const DL = packed struct(u32) {
    hct: u11,
    reserved1: u5 = 0,
    vct: u11,
    reserved2: u4 = 0,
    trg: bool,
};

/// Scaling Width Register
pub const hsw: *volatile HSW = @ptrFromInt(0xCC002048);

// TODO: The docs for this make no sense
pub const HSW = packed struct(u16) {
    halfWidthWords: u8 = 40,
    unknown1: u8 = 40,
};

/// Horizontal Scaling Register
pub const hsr: *volatile HSR = @ptrFromInt(0xCC00204A);
pub const HSR = packed struct(u16) {
    stp: u9,
    reserved1: u3 = 0,
    enabled: bool,
    reserved2: u3 = 0,
};

/// Filter Coefficient Table 0
pub const ftc0: *volatile FCT0 = @ptrFromInt(0xCC00204C);
pub const FCT0 = packed struct(u32) {
    tap0: u10 = 496,
    tap1: u10 = 476,
    tap2: u10 = 430,
    reserved: u2 = 0,
};

/// Filter Coefficient Table 1
pub const ftc1: *volatile FCT1 = @ptrFromInt(0xCC002050);
pub const FCT1 = packed struct(u32) {
    tap3: u10 = 372,
    tap4: u10 = 297,
    tap5: u10 = 219,
    reserved: u2 = 0,
};

/// Filter Coefficient Table 2
pub const ftc2: *volatile FCT2 = @ptrFromInt(0xCC002054);
pub const FCT2 = packed struct(u32) {
    tap6: u10 = 142,
    tap7: u10 = 70,
    tap8: u10 = 193,
    reserved: u2 = 0,
};

/// Filter Coefficient Table 3
pub const ftc3: *volatile FCT3 = @ptrFromInt(0xCC002058);
pub const FCT3 = packed struct(u32) {
    tap9: u8 = 226,
    tap10: u8 = 203,
    tap11: u8 = 192,
    tap12: u8 = 196,
};

/// Filter Coefficient Table 4
pub const ftc4: *volatile FCT4 = @ptrFromInt(0xCC00205C);
pub const FCT4 = packed struct(u32) {
    tap13: u8 = 207,
    tap14: u8 = 222,
    tap15: u8 = 236,
    tap16: u8 = 252,
};

/// Filter Coefficient Table 5
pub const ftc5: *volatile FCT5 = @ptrFromInt(0xCC002060);
pub const FCT5 = packed struct(u32) {
    tap17: u8 = 8,
    tap18: u8 = 15,
    tap19: u8 = 19,
    tap20: u8 = 19,
};

/// Filter Coefficient Table 6
pub const ftc6: *volatile FCT6 = @ptrFromInt(0xCC002064);
pub const FCT6 = packed struct(u32) {
    tap21: u8 = 15,
    tap22: u8 = 12,
    tap23: u8 = 8,
    tap24zero: u8 = 0,
};

/// Unkown Lowpass Register
// TODO: Name
pub const ftc7: *volatile FTC7 = @ptrFromInt(0xCC002068);
pub const FTC7 = packed struct(u32) {
    unknown: u32 = 0x00FF0000,
};

/// VI Clock Select Register
pub const viclk: *volatile VICLK = @ptrFromInt(0xCC00206C);
pub const VICLK = packed struct(u16) {
    clock: enum(u1) {
        @"27MHz" = 0,
        @"54MHz" = 1,
    } = .@"27MHz",
    reserved: u15 = 0,
};

/// VI DTV Status Register
pub const visel: *volatile VISEL = @ptrFromInt(0xCC00206e);
pub const VISEL = packed struct(u16) {
    enabled: u1,
    unknown: u15 = 0,
};

/// Unknown
pub const ukn1: *volatile UNKNOWN1 = @ptrFromInt(0xCC002070);
pub const UNKNOWN1 = packed struct(u16) {
    unknown: u16 = 640,
};

/// Border HBE
pub const hbe: *volatile HBE = @ptrFromInt(0xCC002072);
pub const HBE = packed struct(u16) {
    hbe656: u10,
    reserved: u5 = 0,
    enabled: bool,
};

/// Border HBS
pub const hbs: *volatile HBS = @ptrFromInt(0xCC002074);
pub const HBS = packed struct(u16) {
    HBS656: u10,
    reserved: u6 = 0,
};
