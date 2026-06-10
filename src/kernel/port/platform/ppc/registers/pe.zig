const common = @import("../gx/common.zig");

pub const z_config: *volatile ZConfig = @ptrFromInt(0xCC001000);
const ZConfig = packed struct(u16) {
    comperator_enabled: bool,
    function: common.Compare,
    update_enabled: bool,
    reserved: u11 = 0,
};

pub const color_config: *volatile ColorConfig = @ptrFromInt(0xCC001002);
const ColorConfig = packed struct(u16) {
    boolean_blending: bool,
    arithmetic_blending: bool,
    dither: bool,
    color_update: bool,
    alpha_update: bool,
    dst_factor: u3,
    src_factor: u3,
    subtractive: bool,
    blend_operator: common.BlendLogic,
};

/// Destination Alpha
pub const destination_alpha: *volatile DestinationAlpha = @ptrFromInt(0xCC001004);
pub const DestinationAlpha = packed struct(u16) {
    alpha: u8,
    enable: bool,
    reserved: u7 = 0,
};

/// Alpha Mode
pub const alpha_mode: *volatile AlphaMode = @ptrFromInt(0xCC001006);
pub const AlphaMode = packed struct(u16) {
    threshold: u8,
    mode: common.Compare,
    padding: u5 = 0,
};

/// Alpha Read
pub const alpha_read: *volatile AlphaRead = @ptrFromInt(0xCC001008);
pub const AlphaRead = packed struct(u16) {
    pub const Mode = enum(u2) {
        always_00 = 0,
        always_ff = 1,
        value = 2,
    };

    mode: Mode = .always_00,
    unknown: bool = true, // must be true
    padding: u13 = 0,
};

/// Interrupt Status
pub const interrupt_status: *volatile InterruptStatus = @ptrFromInt(0xCC00100A);
const InterruptStatus = packed struct(u16) {
    token_enable: bool = false,
    finish_enable: bool = false,
    token_acknowledge: bool = false,
    finish_acknowledge: bool = false,
    reserved: u12 = 0,
};

/// PE Token
pub const pe_token: *volatile u16 = @ptrFromInt(0xCC00100E);
