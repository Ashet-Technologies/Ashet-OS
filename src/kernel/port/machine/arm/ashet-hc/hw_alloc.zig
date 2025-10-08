//!
//! This file contains all definitions and assignments for pins,
//! peripheral usage, ...
//!
//! This way, we can maintain it at a central place.
//!
const std = @import("std");

const machine = @import("ashet-hc.zig");
const rp2350 = @import("rp2350-hal");

pub const clock_config = rp2350.clock_config;

pub const cfg = struct {
    pub const propio_buffer_size = 256;
    pub const propio_buffer_count = 32;

    pub const debug_baud = 2_000_000;
    pub const propeller2_p2boot_baud = 500_000;
    pub const propeller2_propio_baud = 5_000_000;
};

pub const pins = struct {
    pub const debug_tx: rp2350.gpio.Pin = rp2350.gpio.num(0);
    pub const debug_rx: rp2350.gpio.Pin = rp2350.gpio.num(1);

    // 2..5

    pub const i2c_sda: rp2350.gpio.Pin = rp2350.gpio.num(6); // SDA1
    pub const i2c_scl: rp2350.gpio.Pin = rp2350.gpio.num(7); // SCL1

    pub const xip_cs1: rp2350.gpio.Pin = rp2350.gpio.num(8);

    // 9

    pub const system_ready: rp2350.gpio.Pin = rp2350.gpio.num(10);
    pub const eth_irq_pin: rp2350.gpio.Pin = rp2350.gpio.num(11); // yellow

    pub const hdmi_d0_p: rp2350.gpio.Pin = rp2350.gpio.num(12);
    pub const hdmi_d0_n: rp2350.gpio.Pin = rp2350.gpio.num(13);
    pub const hdmi_clk_p: rp2350.gpio.Pin = rp2350.gpio.num(14);
    pub const hdmi_clk_n: rp2350.gpio.Pin = rp2350.gpio.num(15);
    pub const hdmi_d1_p: rp2350.gpio.Pin = rp2350.gpio.num(16);
    pub const hdmi_d1_n: rp2350.gpio.Pin = rp2350.gpio.num(17);
    pub const hdmi_d2_p: rp2350.gpio.Pin = rp2350.gpio.num(18);
    pub const hdmi_d2_n: rp2350.gpio.Pin = rp2350.gpio.num(19);

    pub const eth_miso_pin: rp2350.gpio.Pin = rp2350.gpio.num(20); // purple
    pub const eth_cs_pin: rp2350.gpio.Pin = rp2350.gpio.num(21); // green
    pub const eth_sck_pin: rp2350.gpio.Pin = rp2350.gpio.num(22); // blue
    pub const eth_mosi_pin: rp2350.gpio.Pin = rp2350.gpio.num(23); // white

    // 24...31

    pub const btn_user_2: rp2350.gpio.Pin = rp2350.gpio.num(32); // purple

    // 33...39

    pub const prop_txf: rp2350.gpio.Pin = rp2350.gpio.num(36); // tx frame
    pub const prop_rxf: rp2350.gpio.Pin = rp2350.gpio.num(37); // rx frame
    // 38
    pub const prop_rst: rp2350.gpio.Pin = rp2350.gpio.num(39);
    pub const prop_txd: rp2350.gpio.Pin = rp2350.gpio.num(40); // tx data
    pub const prop_rxd: rp2350.gpio.Pin = rp2350.gpio.num(41); // rx data
    pub const prop_cts: rp2350.gpio.Pin = rp2350.gpio.num(42); //
    pub const prop_rts: rp2350.gpio.Pin = rp2350.gpio.num(43); //

    // 44..47
};

pub const irq = struct {
    pub const propio_dma: machine.IRQ = .DMA_IRQ_0;
    pub const propio_pio: machine.IRQ = .PIO0_IRQ_0;

    pub const video_dma: machine.IRQ = .DMA_IRQ_1;
};

pub const uart = struct {
    pub const debug = rp2350.uart.instance.UART0;
    pub const propeller2: rp2350.uart.UART = rp2350.uart.instance.UART1;
};

pub const pio = struct {
    pub const propio = rp2350.pio.num(0);
};

pub const dma = struct {
    pub const hdmi_ping = rp2350.dma.channel(0);
    pub const hdmi_pong = rp2350.dma.channel(1);

    pub const prop_rx: rp2350.dma.Channel = rp2350.dma.channel(2);
    pub const prop_tx: rp2350.dma.Channel = rp2350.dma.channel(3);
};

pub const spi = struct {
    pub const ethernet = rp2350.spi.instance.num(0);
};

pub const i2c = struct {
    pub const system_bus = rp2350.i2c.instance.I2C1;
};

pub const i2c_addresses = struct {
    pub const i2c_main_mux: rp2350.i2c.Address = .new(0x70);
    pub const expansion_eeprom: rp2350.i2c.Address = .new(0x57);
};
