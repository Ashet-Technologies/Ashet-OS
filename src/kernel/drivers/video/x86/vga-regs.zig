const std = @import("std");
const ashet = @import("../../../main.zig");
const x86 = ashet.ports.platforms.x86;

pub const VgaPort = enum(u16) {
    pub fn read(port: VgaPort) u8 {
        return x86.in(u8, @intFromEnum(port));
    }

    pub fn write(port: VgaPort, value: u8) void {
        x86.out(u8, @intFromEnum(port), value);
    }

    _,

    // Monochrome-compatible CRTC bank.
    pub const crtc_index_monochrome: VgaPort = @enumFromInt(0x03B4);
    pub const crtc_data_monochrome: VgaPort = @enumFromInt(0x03B5);

    pub const feature_control_write_monochrome: VgaPort = @enumFromInt(0x03BA);
    pub const input_status_1_monochrome: VgaPort = @enumFromInt(0x03BA);

    /// Attribute Controller index/data stream.
    pub const attribute_index_data: VgaPort = @enumFromInt(0x03C0);

    /// Read-back port for the currently selected Attribute Controller register.
    pub const attribute_data_read: VgaPort = @enumFromInt(0x03C1);

    pub const miscellaneous_output_write: VgaPort = @enumFromInt(0x03C2);
    pub const input_status_0: VgaPort = @enumFromInt(0x03C2);

    pub const video_subsystem_enable: VgaPort = @enumFromInt(0x03C3);

    pub const sequencer_index: VgaPort = @enumFromInt(0x03C4);
    pub const sequencer_data: VgaPort = @enumFromInt(0x03C5);

    pub const palette_mask: VgaPort = @enumFromInt(0x03C6);

    /// Read: DAC state.
    /// Write: palette read index.
    pub const palette_read_index: VgaPort = @enumFromInt(0x03C7);
    pub const dac_state: VgaPort = @enumFromInt(0x03C7);

    pub const palette_write_index: VgaPort = @enumFromInt(0x03C8);

    /// Streaming DAC palette data.
    pub const palette_data: VgaPort = @enumFromInt(0x03C9);

    pub const feature_control_read: VgaPort = @enumFromInt(0x03CA);

    pub const miscellaneous_output_read: VgaPort = @enumFromInt(0x03CC);

    pub const graphics_controller_index: VgaPort = @enumFromInt(0x03CE);
    pub const graphics_controller_data: VgaPort = @enumFromInt(0x03CF);

    // Color/graphics-compatible CRTC bank.
    pub const crtc_index_color_graphics: VgaPort = @enumFromInt(0x03D4);
    pub const crtc_data_color_graphics: VgaPort = @enumFromInt(0x03D5);

    pub const feature_control_write_color_graphics: VgaPort = @enumFromInt(0x03DA);
    pub const input_status_1_color_graphics: VgaPort = @enumFromInt(0x03DA);
};

pub const IoAddressSelect = enum(u1) {
    monochrome = 0,
    color_graphics = 1,

    pub fn crtcIndexPort(select: IoAddressSelect) VgaPort {
        return switch (select) {
            .monochrome => VgaPort.crtc_index_monochrome,
            .color_graphics => VgaPort.crtc_index_color_graphics,
        };
    }

    pub fn crtcDataPort(select: IoAddressSelect) VgaPort {
        return switch (select) {
            .monochrome => VgaPort.crtc_data_monochrome,
            .color_graphics => VgaPort.crtc_data_color_graphics,
        };
    }

    pub fn inputStatus1Port(select: IoAddressSelect) VgaPort {
        return switch (select) {
            .monochrome => VgaPort.input_status_1_monochrome,
            .color_graphics => VgaPort.input_status_1_color_graphics,
        };
    }

    pub fn featureControlWritePort(select: IoAddressSelect) VgaPort {
        return switch (select) {
            .monochrome => VgaPort.feature_control_write_monochrome,
            .color_graphics => VgaPort.feature_control_write_color_graphics,
        };
    }
};

pub const MiscellaneousOutputRegister = packed struct(u8) {
    pub const read_addr = VgaPort.miscellaneous_output_read;
    pub const write_addr = VgaPort.miscellaneous_output_write;

    pub const SyncPolarity = enum(u1) {
        positive = 0,
        negative = 1,
    };

    /// This bit selects the CRT controller addresses.
    io_address_select: IoAddressSelect,

    /// Controls system access to display memory.
    ram_enable: bool,

    /// Selects the dot clock used to drive display timing.
    clock_select: enum(u2) {
        @"25 MHz" = 0b00,
        @"28 MHz" = 0b01,
        reserved_2 = 0b10,
        reserved_3 = 0b11,
    },

    _reserved0: u1 = 0,

    /// Selects the upper/lower 64 KiB page when operating in odd/even mode.
    odd_even_page_select: enum(u1) {
        low = 0,
        high = 1,
    },

    /// Determines the polarity of the horizontal sync pulse.
    hsync_polarity: SyncPolarity,

    /// Determines the polarity of the vertical sync pulse.
    vsync_polarity: SyncPolarity,

    pub fn read() MiscellaneousOutputRegister {
        return @bitCast(read_addr.read());
    }

    pub fn write(reg: MiscellaneousOutputRegister) void {
        write_addr.write(@bitCast(reg));
    }
};

pub const InputStatus0Register = packed struct(u8) {
    pub const read_addr = VgaPort.input_status_0;

    _reserved0: u4,

    /// Hardware monitor/configuration sense input.
    switch_sense: bool,

    _reserved1: u2,

    /// Set while a vertical-retrace interrupt is pending.
    crt_interrupt_pending: bool,

    pub fn read() InputStatus0Register {
        return @bitCast(read_addr.read());
    }
};

pub const VideoSubsystemEnableRegister = packed struct(u8) {
    pub const read_addr = VgaPort.video_subsystem_enable;
    pub const write_addr = VgaPort.video_subsystem_enable;

    /// Enables VGA I/O and memory address decoding.
    enabled: bool,

    _reserved0: u7 = 0,

    pub fn read() VideoSubsystemEnableRegister {
        return @bitCast(read_addr.read());
    }

    pub fn write(reg: VideoSubsystemEnableRegister) void {
        write_addr.write(@bitCast(reg));
    }
};

pub const PaletteMaskRegister = packed struct(u8) {
    pub const read_addr = VgaPort.palette_mask;
    pub const write_addr = VgaPort.palette_mask;

    /// Bits set here enable the corresponding palette-index bits.
    mask: u8,

    pub fn read() PaletteMaskRegister {
        return @bitCast(read_addr.read());
    }

    pub fn write(reg: PaletteMaskRegister) void {
        write_addr.write(@bitCast(reg));
    }
};

pub const DacStateRegister = packed struct(u8) {
    pub const read_addr = VgaPort.dac_state;

    pub const State = enum(u2) {
        read = 0b00,
        write = 0b11,
        _,
    };

    state: State,

    _reserved0: u6,

    pub fn read() DacStateRegister {
        return @bitCast(read_addr.read());
    }
};

pub const FeatureControlRegister = packed struct(u8) {
    pub const read_addr = VgaPort.feature_control_read;

    _reserved0: u3 = 0,

    vertical_sync_select: enum(u1) {
        normal = 0,
        sync_or_display_enable = 1,
    } = .normal,

    _reserved1: u4 = 0,

    pub fn read() FeatureControlRegister {
        return @bitCast(read_addr.read());
    }

    pub fn write(
        io_address_select: IoAddressSelect,
        reg: FeatureControlRegister,
    ) void {
        io_address_select.featureControlWritePort().write(@bitCast(reg));
    }
};

pub const InputStatus1Register = packed struct(u8) {
    /// Set while active display output is disabled.
    ///
    /// This includes horizontal and vertical blanking/retrace periods.
    display_disabled: bool,

    _reserved0: u2,

    /// Set while vertical retrace is active.
    vertical_retrace: bool,

    /// Diagnostic video-data feedback.
    diagnostic: u2,

    _reserved1: u2,

    /// Reading this register also resets the Attribute Controller
    /// index/data flip-flop to the index state.
    pub fn read(io_address_select: IoAddressSelect) InputStatus1Register {
        return @bitCast(io_address_select.inputStatus1Port().read());
    }
};
