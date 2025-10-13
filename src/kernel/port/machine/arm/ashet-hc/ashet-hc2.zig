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
    // 0
    pub const trace_clk: rp2350.gpio.Pin = rp2350.gpio.num(1); // => 1
    pub const trace_data0: rp2350.gpio.Pin = rp2350.gpio.num(2); // => 2
    pub const trace_data1: rp2350.gpio.Pin = rp2350.gpio.num(3); // => 3
    pub const trace_data2: rp2350.gpio.Pin = rp2350.gpio.num(4); // => 4
    pub const trace_data3: rp2350.gpio.Pin = rp2350.gpio.num(5); // => 5
    pub const i2s_bclk: rp2350.gpio.Pin = rp2350.gpio.num(6); // => 6
    pub const i2s_lrclk: rp2350.gpio.Pin = rp2350.gpio.num(7); // => 7
    pub const xip_cs1: rp2350.gpio.Pin = rp2350.gpio.num(8); // => 8
    pub const i2s_mclk: rp2350.gpio.Pin = rp2350.gpio.num(9); // => 9
    pub const i2s_sdo: rp2350.gpio.Pin = rp2350.gpio.num(10); // => 10
    pub const i2s_sdi: rp2350.gpio.Pin = rp2350.gpio.num(11); // => 11
    pub const hdmi_d0_p: rp2350.gpio.Pin = rp2350.gpio.num(12); // => 12
    pub const hdmi_d0_n: rp2350.gpio.Pin = rp2350.gpio.num(13); // => 13
    pub const hdmi_clk_p: rp2350.gpio.Pin = rp2350.gpio.num(14); // => 14
    pub const hdmi_clk_n: rp2350.gpio.Pin = rp2350.gpio.num(15); // => 15
    pub const hdmi_d1_p: rp2350.gpio.Pin = rp2350.gpio.num(16); // => 16
    pub const hdmi_d1_n: rp2350.gpio.Pin = rp2350.gpio.num(17); // => 17
    pub const hdmi_d2_p: rp2350.gpio.Pin = rp2350.gpio.num(18); // => 18
    pub const hdmi_d2_n: rp2350.gpio.Pin = rp2350.gpio.num(19); // => 19
    pub const clock_src: rp2350.gpio.Pin = rp2350.gpio.num(20); // => 20
    pub const prop_rst: rp2350.gpio.Pin = rp2350.gpio.num(39); // => 21
    pub const i2c_sda: rp2350.gpio.Pin = rp2350.gpio.num(6); // SDA1 => 22
    pub const i2c_scl: rp2350.gpio.Pin = rp2350.gpio.num(7); // SCL1 => 23
    pub const prop_txd: rp2350.gpio.Pin = rp2350.gpio.num(40); // => 24 tx data
    pub const prop_rxd: rp2350.gpio.Pin = rp2350.gpio.num(41); // => 25 rx data
    pub const prop_cts: rp2350.gpio.Pin = rp2350.gpio.num(42); // => 26
    pub const prop_rts: rp2350.gpio.Pin = rp2350.gpio.num(43); // => 27
    pub const prop_txf: rp2350.gpio.Pin = rp2350.gpio.num(36); // => 28 tx frame
    pub const prop_rxf: rp2350.gpio.Pin = rp2350.gpio.num(37); // => 29 rx frame
    pub const prop_aux0: rp2350.gpio.Pin = rp2350.gpio.num(30); // => 30
    pub const prop_aux1: rp2350.gpio.Pin = rp2350.gpio.num(31); // => 31
    pub const eth_miso_pin: rp2350.gpio.Pin = rp2350.gpio.num(20); // => 32
    pub const eth_cs_pin: rp2350.gpio.Pin = rp2350.gpio.num(21); // => 33
    pub const eth_sck_pin: rp2350.gpio.Pin = rp2350.gpio.num(22); // => 34
    pub const eth_mosi_pin: rp2350.gpio.Pin = rp2350.gpio.num(23); // => 35
    pub const eth_irq_pin: rp2350.gpio.Pin = rp2350.gpio.num(11); // => 36
    pub const eth_rst_pin: rp2350.gpio.Pin = rp2350.gpio.num(37); // => 37
    pub const uart1_tx: rp2350.gpio.Pin = rp2350.gpio.num(38); // => 38
    pub const uart1_rx: rp2350.gpio.Pin = rp2350.gpio.num(39); // => 39
    pub const userport0: rp2350.gpio.Pin = rp2350.gpio.num(40); // => 40
    pub const userport1: rp2350.gpio.Pin = rp2350.gpio.num(41); // => 41
    pub const userport2: rp2350.gpio.Pin = rp2350.gpio.num(42); // => 42
    pub const userport3: rp2350.gpio.Pin = rp2350.gpio.num(43); // => 43
    pub const uart0_tx: rp2350.gpio.Pin = rp2350.gpio.num(44); // => 44
    pub const uart0_rx: rp2350.gpio.Pin = rp2350.gpio.num(45); // => 45
    pub const debug_core1_tx: rp2350.gpio.Pin = rp2350.gpio.num(0); // => 46
    pub const debug_core0_tx: rp2350.gpio.Pin = rp2350.gpio.num(0); // => 47

    // deleted:
    pub const debug_rx: rp2350.gpio.Pin = rp2350.gpio.num(1); // => GONE
    pub const system_ready: rp2350.gpio.Pin = rp2350.gpio.num(10); // => GONE
    pub const btn_user_2: rp2350.gpio.Pin = rp2350.gpio.num(32); // => GONE purple
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
    pub const propio = rp2350.pio.num(0); // High Speed Southbridge Link
    pub const debuglog = rp2350.pio.num(1); // Dual High Speed UART OUT
    pub const userport = rp2350.pio.num(2); // Free for user / Frontpanel
};

pub const dma = struct {
    pub const hdmi_ping = rp2350.dma.channel(0);
    pub const hdmi_pong = rp2350.dma.channel(1);

    pub const prop_rx: rp2350.dma.Channel = rp2350.dma.channel(2);
    pub const prop_tx: rp2350.dma.Channel = rp2350.dma.channel(3);
};

pub const spi = struct {
    pub const ethernet = rp2350.spi.instance.num(0);
    pub const userport = rp2350.spi.instance.num(1);
};

pub const i2c = struct {
    pub const userport = rp2350.i2c.instance.I2C0;
    pub const system_bus = rp2350.i2c.instance.I2C1;
};

pub const i2c_addresses = struct {
    pub const i2c_main_mux: rp2350.i2c.Address = .new(0x70);
    pub const expansion_eeprom: rp2350.i2c.Address = .new(0x57);
};

pub const adc_channels = struct {
    pub const userport0: rp2350.adc.Input = .ain0;
    pub const userport1: rp2350.adc.Input = .ain1;
    pub const userport2: rp2350.adc.Input = .ain2;
    pub const userport3: rp2350.adc.Input = .ain3;
};
