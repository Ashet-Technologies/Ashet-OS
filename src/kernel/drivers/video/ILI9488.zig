//!
//! Ported from:
//!     https://github.com/RobertoBenjami/stm32_graphics_display_drivers/blob/master/Drivers/lcd/ili9488/ili9488.c
//!     https://github.com/RobertoBenjami/stm32_graphics_display_drivers/blob/master/Drivers/lcd/ili9488/ili9488.h
//!
const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ili9488);

const ILI9488 = @This();
const Driver = ashet.drivers.Driver;
const ColorIndex = ashet.abi.ColorIndex;
const Color = ashet.abi.Color;
const Resolution = ashet.abi.Size;

const SpiMode = enum(u2) {
    mode0 = 0,
    mode1 = 1,
    mode2 = 2,
    mode3 = 3,
};

const Interface = union(enum) { spi: SpiMode, parallel };

const interface: Interface = .{ .spi = .mode0 };

backbuffer: [320 * 240]ColorIndex align(ashet.memory.page_size) = undefined,
palette: [256]Color = ashet.video.defaults.palette,

driver: Driver = .{
    .name = "LCD (ILI9488)",
    .class = .{
        .video = .{
            .getVideoMemoryFn = getVideoMemory,
            .getPaletteMemoryFn = getPaletteMemory,
            .setBorderFn = setBorder,
            .flushFn = flush,
            .getResolutionFn = getResolution,
            .getMaxResolutionFn = getMaxResolution,
            .getBorderFn = getBorder,
            .setResolutionFn = setResolution,
        },
    },
},

pub fn init() !ILI9488 {
    var vd = ILI9488{};

    const io = vd.get_io();

    io.init();

    io.Delay(105);
    io.write_cmd8(ILI9488_SWRESET);
    io.delay(5);
    // positive gamma control
    io.write_cmd8_multiple_data8(ILI9488_GMCTRP1, "\x00\x03\x09\x08\x16\x0A\x3F\x78\x4C\x09\x0A\x08\x16\x1A\x0F");
    // negative gamma control
    io.write_cmd8_multiple_data8(ILI9488_GMCTRN1, "\x00\x16\x19\x03\x0F\x05\x32\x45\x46\x04\x0E\x0D\x35\x37\x0F");
    // Power Control 1 (Vreg1out, Verg2out)
    io.write_cmd8_multiple_data8(ILI9488_PWCTR1, "\x17\x15");
    io.delay(5);
    // Power Control 2 (VGH,VGL)
    io.write_cmd8(ILI9488_PWCTR2);
    io.write_data8(0x41);
    io.delay(5);
    // Power Control 3 (Vcom)
    io.write_cmd8_multiple_data8(ILI9488_VMCTR1, "\x00\x12\x80");
    io.delay(5);
    switch (interface) {
        .spi => |mode| {
            io.write_cmd8(ILI9488_PIXFMT);
            io.write_data8(0x66); // Interface Pixel Format (24 bit)
            if (mode != .mode2) {
                // LCD_IO_WriteCmd8(0xFB); LCD_IO_WriteData8(0x80);
                io.write_cmd8(ILI9488_IMCTR);
                io.write_data8(0x80); // Interface Mode Control (SDO NOT USE)
            } else {
                io.write_cmd8(ILI9488_IMCTR);
                io.write_data8(0x00); // Interface Mode Control (SDO USE)
            }
        },
        .parallel => {
            io.write_cmd8(ILI9488_PIXFMT);
            io.write_data8(0x55); // Interface Pixel Format (16 bit)
        },
    }
    io.write_cmd8(ILI9488_FRMCTR1);
    io.write_data8(0xA0); // Frame rate (60Hz)
    io.write_cmd8(ILI9488_INVCTR);
    io.write_data8(0x02); // Display Inversion Control (2-dot)
    io.write_cmd8_multiple_data8(ILI9488_DFUNCTR, "\x02\x02"); // Display Function Control RGB/MCU Interface Control
    io.write_cmd8(ILI9488_IMGFUNCT);
    io.write_data8(0x00); // Set Image Functio (Disable 24 bit data)
    io.write_cmd8_multiple_data8(ILI9488_ADJCTR3, "\xA9\x51\x2C\x82"); // Adjust Control (D7 stream, loose)
    io.delay(5);
    io.write_cmd8(ILI9488_SLPOUT); // Exit Sleep
    io.delay(120);
    io.write_cmd8(ILI9488_DISPON); // Display on
    io.delay(5);
    io.write_cmd8(ILI9488_MADCTL);
    io.write_data8(ILI9488_MAD_DATA_RIGHT_THEN_DOWN);

    return vd;
}

fn instance(driver: *Driver) *ILI9488 {
    return driver.resolve(ILI9488, "driver");
}

fn get_io(vd: *ILI9488) IO {
    _ = vd;
    return IO{};
}
//

fn getVideoMemory(driver: *Driver) []align(ashet.memory.page_size) ColorIndex {
    const vd = instance(driver);
    return &vd.backbuffer;
}
fn getPaletteMemory(driver: *Driver) *[256]Color {
    const vd = instance(driver);
    return &vd.palette;
}

fn getResolution(driver: *Driver) Resolution {
    const vd = instance(driver);
    _ = vd;

    return Resolution{
        .width = 320,
        .height = 240,
    };
}

fn getMaxResolution(driver: *Driver) Resolution {
    const vd = instance(driver);
    _ = vd;
    return Resolution{
        .width = 320,
        .height = 240,
    };
}

fn setResolution(driver: *Driver, width: u15, height: u15) void {
    const vd = instance(driver);
    _ = vd;
    _ = width;
    _ = height;
    logger.warn("resize not supported of virtual screen!", .{});
}

fn setBorder(driver: *Driver, color: ColorIndex) void {
    const vd = instance(driver);
    _ = vd;
    _ = color;
}

fn getBorder(driver: *Driver) ColorIndex {
    const vd = instance(driver);
    _ = vd;
    return ColorIndex.get(0);
}

fn flush(driver: *Driver) void {
    const vd = instance(driver);
    _ = vd;
}

pub const IO = struct {
    extern fn delay(io: *IO, _delay: u32) void;
    extern fn init(io: *IO) void;
    extern fn bl_on_off(io: *IO, Bl: u8) void;

    extern fn write_cmd8(io: *IO, Cmd: u8) void;
    extern fn write_data8(io: *IO, Data: u8) void;
    extern fn write_data16(io: *IO, Data: u16) void;
    extern fn write_cmd8_data_fill16(io: *IO, Cmd: u8, Data: []u16) void;
    extern fn write_cmd8_multiple_data8(io: *IO, Cmd: u8, pData: []u8) void;
    extern fn write_cmd8_multiple_data16(io: *IO, Cmd: u8, pData: []u16) void;
    extern fn read_cmd8_multiple_data8(io: *IO, Cmd: u8, pData: []u8, DummySize: u32) void;
    extern fn read_cmd8_multiple_data16(io: *IO, Cmd: u8, pData: []u16, DummySize: u32) void;
    extern fn read_cmd8_multiple_data24to16(io: *IO, Cmd: u8, pData: []u16, DummySize: u32) void;

    // void WriteData16_to_2x8(dt)    {LCD_IO_WriteData8((dt) >> 8); LCD_IO_WriteData8(dt); }

};

const ILI9488_NOP = 0x00;
const ILI9488_SWRESET = 0x01;
const ILI9488_RDDID = 0x04;
const ILI9488_RDDST = 0x09;

const ILI9488_SLPIN = 0x10;
const ILI9488_SLPOUT = 0x11;
const ILI9488_PTLON = 0x12;
const ILI9488_NORON = 0x13;

const ILI9488_RDMODE = 0x0A;
const ILI9488_RDMADCTL = 0x0B;
const ILI9488_RDPIXFMT = 0x0C;
const ILI9488_RDIMGFMT = 0x0D;
const ILI9488_RDSELFDIAG = 0x0F;

const ILI9488_INVOFF = 0x20;
const ILI9488_INVON = 0x21;
const ILI9488_GAMMASET = 0x26;
const ILI9488_DISPOFF = 0x28;
const ILI9488_DISPON = 0x29;

const ILI9488_CASET = 0x2A;
const ILI9488_PASET = 0x2B;
const ILI9488_RAMWR = 0x2C;
const ILI9488_RAMRD = 0x2E;

const ILI9488_PTLAR = 0x30;
const ILI9488_VSCRDEF = 0x33;
const ILI9488_MADCTL = 0x36;
const ILI9488_VSCRSADD = 0x37;
const ILI9488_PIXFMT = 0x3A;
const ILI9488_RAMWRCONT = 0x3C;
const ILI9488_RAMRDCONT = 0x3E;

const ILI9488_IMCTR = 0xB0;
const ILI9488_FRMCTR1 = 0xB1;
const ILI9488_FRMCTR2 = 0xB2;
const ILI9488_FRMCTR3 = 0xB3;
const ILI9488_INVCTR = 0xB4;
const ILI9488_DFUNCTR = 0xB6;

const ILI9488_PWCTR1 = 0xC0;
const ILI9488_PWCTR2 = 0xC1;
const ILI9488_PWCTR3 = 0xC2;
const ILI9488_PWCTR4 = 0xC3;
const ILI9488_PWCTR5 = 0xC4;
const ILI9488_VMCTR1 = 0xC5;
const ILI9488_VMCTR2 = 0xC7;

const ILI9488_RDID1 = 0xDA;
const ILI9488_RDID2 = 0xDB;
const ILI9488_RDID3 = 0xDC;
const ILI9488_RDID4 = 0xDD;

const ILI9488_GMCTRP1 = 0xE0;
const ILI9488_GMCTRN1 = 0xE1;
const ILI9488_IMGFUNCT = 0xE9;

const ILI9488_ADJCTR3 = 0xF7;

const ILI9488_MAD_RGB = 0x08;
const ILI9488_MAD_BGR = 0x00;

const ILI9488_MAD_VERTICAL = 0x20;
const ILI9488_MAD_X_LEFT = 0x00;
const ILI9488_MAD_X_RIGHT = 0x40;
const ILI9488_MAD_Y_UP = 0x80;
const ILI9488_MAD_Y_DOWN = 0x00;

const ILI9488_MAX_X = (ILI9488_LCD_PIXEL_WIDTH - 1);
const ILI9488_MAX_Y = (ILI9488_LCD_PIXEL_HEIGHT - 1);
const ILI9488_MAD_DATA_RIGHT_THEN_UP = ILI9488_MAD_COLORMODE | ILI9488_MAD_X_RIGHT | ILI9488_MAD_Y_UP;
const ILI9488_MAD_DATA_RIGHT_THEN_DOWN = ILI9488_MAD_COLORMODE | ILI9488_MAD_X_RIGHT | ILI9488_MAD_Y_DOWN;

const ILI9488_MAD_COLORMODE = if (ILI9488_COLORMODE == 0)
    ILI9488_MAD_RGB
else
    ILI9488_MAD_BGR;

const ILI9488_LCD_PIXEL_WIDTH = 480;
const ILI9488_LCD_PIXEL_HEIGHT = 320;
const ILI9488_COLORMODE = 0;
