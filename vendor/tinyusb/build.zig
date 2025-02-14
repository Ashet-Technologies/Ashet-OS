const std = @import("std");

pub fn build(b: *std.Build) void {
    const upstream = b.dependency("upstream", .{});
    const src_folder = upstream.path("src");
    const tinyusb_mod = b.addModule("tinyusb", .{});

    const tinyusb_config_h = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "tusb_config.h",
    }, .{
        .CFG_TUSB_MCU = "",
        .CFG_TUSB_OS = "OPT_OS_NONE",
        .CFG_TUSB_DEBUG = "0", // "1"

        .CFG_TUH_MEM_SECTION = "", // __attribute__ (( section(".usb_ram") ))
        .CFG_TUH_MEM_ALIGN = "__attribute__ ((aligned(4)))",

        .CFG_TUH_ENABLED = "1",
        .CFG_TUH_MAX_SPEED = "BOARD_TUH_MAX_SPEED",

        .BOARD_TUH_RHPORT = "0",
        .BOARD_TUH_MAX_SPEED = "OPT_MODE_DEFAULT_SPEED",

        .CFG_TUH_ENUMERATION_BUFSIZE = "256",
        .CFG_TUH_HUB = "1", // number of supported hubs
        .CFG_TUH_CDC = "1", // CDC ACM
        .CFG_TUH_CDC_FTDI = "1", // FTDI Serial.  FTDI is not part of CDC class, only to re-use CDC driver API
        .CFG_TUH_CDC_CP210X = "1", // CP210x Serial. CP210X is not part of CDC class, only to re-use CDC driver API
        .CFG_TUH_CDC_CH34X = "1", // CH340 or CH341 Serial. CH34X is not part of CDC class, only to re-use CDC driver API
        .CFG_TUH_HID = "4", // typical keyboard + mouse device can have 3-4 HID interfaces
        .CFG_TUH_MSC = "2",
        .CFG_TUH_VENDOR = "0",
        .CFG_TUH_DEVICE_MAX = "8",

        .CFG_TUH_HID_EPIN_BUFSIZE = 64,
        .CFG_TUH_HID_EPOUT_BUFSIZE = 64,

        .CFG_TUH_CDC_LINE_CONTROL_ON_ENUM = "0x03",
        .CFG_TUH_CDC_LINE_CODING_ON_ENUM = "{ 115200, CDC_LINE_CODING_STOP_BITS_1, CDC_LINE_CODING_PARITY_NONE, 8 }",
    });

    tinyusb_mod.addIncludePath(src_folder);
    tinyusb_mod.addIncludePath(tinyusb_config_h.getOutput().dirname());

    tinyusb_mod.addCSourceFiles(.{
        .root = src_folder,
        .files = &tinyusb_sources,
    });
}

const tinyusb_sources = [_][]const u8{
    "class/audio/audio_device.c",
    "class/cdc/cdc_device.c",
    "class/cdc/cdc_host.c",
    "class/dfu/dfu_device.c",
    "class/dfu/dfu_rt_device.c",
    "class/hid/hid_device.c",
    "class/hid/hid_host.c",
    "class/midi/midi_device.c",
    "class/msc/msc_device.c",
    "class/msc/msc_host.c",
    "class/net/ecm_rndis_device.c",
    "class/net/ncm_device.c",
    "class/usbtmc/usbtmc_device.c",
    "class/vendor/vendor_device.c",
    "class/vendor/vendor_host.c",
    "class/video/video_device.c",
    "common/tusb_fifo.c",
    "device/usbd_control.c",
    "device/usbd.c",
    "host/hub.c",
    "host/usbh.c",
    "tusb.c",
    "typec/usbc.c",
};
