const std = @import("std");

const ashet = @import("../../main.zig");
const logger = std.log.scoped(.enc28j60);

const ENC28J60 = @This();
const Driver = ashet.drivers.Driver;

const vtable = ashet.network.NetworkInterface.VTable{
    .linkIsUpFn = link_is_up,
    .allocOutgoingPacketFn = alloc_packet,
    .sendFn = send,
    .pollFn = fetch_packets,
};

pub const HardwareInterface = struct {
    vtable: *const VTable,
    param: *anyopaque,

    pub const VTable = struct {
        set_chipselect: *const fn (dri: *anyopaque, asserted: bool) void,
        write: *const fn (dri: *anyopaque, input: []const u8) void,
        read: *const fn (dri: *anyopaque, tx_byte: u8, input: []u8) void,
    };
};

const PacketBuf = struct {
    buffer: [ENC28J60_MAX_FRAME_SIZE]u8 align(8),
    length: usize,
};

driver: Driver = .{
    .name = "Virtio Net Device",
    .class = .{
        .network = .{
            .interface = .ethernet,
            .address = undefined,
            .mtu = ENC28J60_MAX_FRAME_SIZE,
            .vtable = &vtable,
        },
    },
},

hw_intf: HardwareInterface,

active_bank: u8 = ~BANK_MASK,
next_packet_pointer: u16 = 0,
tx_size: u16 = 0,

packet_pool: ashet.utils.FixedPool(PacketBuf, 4) = .{},

pub fn init(hw_intf: HardwareInterface, mac_address: ashet.network.MAC, options: InitOptions) !ENC28J60 {
    var dev: ENC28J60 = .{
        .hw_intf = hw_intf,
    };
    dev.driver.class.network.address = mac_address;

    if (!options.skip_self_test) {

        // Use hardware validation to assert the hardware is working and the device is connected
        //
        // This method adds no more than 1 second of latency during init and
        // it is a very good method to determine that the device responds as expected

        errdefer dev.reset();

        logger.debug("perform self test...", .{});
        try dev.built_in_self_test(BIST_ADDRESS_FILL);
    }

    //
    //  Use hardware revision as device validation.
    //
    //  This method is very unreliable. During testing I was able to pass
    //  this test most of the time without a device even being connected.
    //
    //  And with another SPI device (not ENC28J60) connected it passed all of the time
    //
    if (!options.skip_revision_check) {
        const revision = dev.read_register_byte(EREVID);
        logger.debug("chip revision is {}", .{revision});
        if ((0 >= revision) or (revision >= std.math.maxInt(i8))) {
            return error.InvalidRevision;
        }
    }

    errdefer dev.reset();
    try dev.configure(mac_address, options.full_duplex);

    return dev;
}

pub fn get_link_status(dev: *ENC28J60) !LinkStatus {
    const phstat2 = try dev.phy_read(PHSTAT2);

    if ((phstat2 & PHSTAT2_LSTAT) == 0) {
        return .link_down;
    } else if ((phstat2 & PHSTAT2_DPXSTAT) != 0) {
        return .@"10m_full_duplex";
    } else {
        return .@"10m_half_duplex";
    }
}

pub fn get_next_rx_packet(dev: *ENC28J60) ?u16 {
    comptime {
        std.debug.assert(ENC28J60_MAX_RECEIVE_LOOP_COUNT > 0);
        std.debug.assert(ENC28J60_MAX_RECEIVE_LOOP_COUNT <= std.math.maxInt(u8));
    }

    //
    // Try process ENC28J60_MAX_RECEIVE_LOOP_COUNT packets,
    // then return -1 to avoid stealing all the system resources
    //
    for (0..ENC28J60_MAX_RECEIVE_LOOP_COUNT) |_| {
        if (dev.read_register_byte(EPKTCNT) == 0)
            continue;

        if (true) {
            const next_packet_pointer = dev.get_next_packet_pointer();

            //
            // Advance the packet pointer to the start of the next packet
            //
            dev.write_register_word(ERXRDPT, enc28j60_erxrdpt_errata(next_packet_pointer));

            //
            // Set the read pointer to the start of the next packet
            //
            dev.write_register_word(ERDPT, next_packet_pointer);
        }

        //
        // Parse the receive status vector
        //   bytes 1-2: next packet pointer
        //   bytes 3-4: packet length
        //   bytes 5-6: status bits
        //
        var bytes: [RSV_SIZE]u8 = @splat(0);
        dev.buffer_read(&bytes);

        dev.set_next_packet_pointer(u16_from_u8le(bytes[0], bytes[1]));

        //
        // Decrement the packet counter by 1
        //
        dev.set_register_bit(ECON2, ECON2_PKTDEC);

        if ((RSV_RX_OK & bytes[4]) != 0) {
            return u16_from_u8le(bytes[2], bytes[3]);
        }
    }

    return null;
}

pub fn read_rx_packet(dev: *ENC28J60, buffer: []u8) void {
    if (buffer.len == 0)
        return;

    dev.buffer_read(buffer);
}

pub fn send_tx_packet(dev: *ENC28J60, buffer: []const u8) error{ TxBufferEmpty, Overflow, Timeout, Collision, TransmissionFailed }!void {
    std.debug.assert(buffer.len <= ENC28J60_MAX_FRAME_SIZE);
    _ = try dev.write_tx_buffer(buffer);
    try dev.execute_tx();
}

fn link_is_up(driver: *Driver) bool {
    const device = driver.resolve(ENC28J60, "driver");
    const status = device.get_link_status() catch return false;
    return switch (status) {
        .link_down => false,
        .@"10m_full_duplex" => true,
        .@"10m_half_duplex" => true,
    };
}

fn alloc_packet(driver: *Driver, size: usize) ?[]u8 {
    const device = driver.resolve(ENC28J60, "driver");
    if (size > ENC28J60_MAX_FRAME_SIZE)
        return null;

    const pbuf = device.packet_pool.alloc() orelse return null;
    pbuf.* = .{
        .buffer = @splat(0),
        .length = size,
    };
    return pbuf.buffer[0..size];
}

fn send(driver: *Driver, packet: []u8) bool {
    const device = driver.resolve(ENC28J60, "driver");
    std.debug.assert(packet.len <= ENC28J60_MAX_FRAME_SIZE);

    const buffer = packet.ptr[0..ENC28J60_MAX_FRAME_SIZE];

    const pbuf: *PacketBuf = @alignCast(@fieldParentPtr("buffer", buffer));
    defer device.packet_pool.free(pbuf);

    logger.debug("sending {} bytes: '{}'", .{ pbuf.length, std.fmt.fmtSliceHexLower(pbuf.buffer[0..pbuf.length]) });

    device.send_tx_packet(pbuf.buffer[0..pbuf.length]) catch |err| {
        logger.err("failed to send packet: {}", .{err});
        return false;
    };

    return true;
}

fn fetch_packets(driver: *Driver) void {
    const device = driver.resolve(ENC28J60, "driver");
    device.fetch_packets_err() catch |err| {
        logger.err("failed to receive packets: {}", .{err});
    };
}

fn fetch_packets_err(device: *ENC28J60) !void {
    const nic = &device.driver.class.network;

    var packet_buffer: [ENC28J60.MAX_FRAMELEN]u8 = @splat(0);
    while (device.get_next_rx_packet()) |next_frame_length| {
        if (next_frame_length >= packet_buffer.len) {
            logger.err("discarding invalid rx packet of size {}", .{next_frame_length});
            continue;
        }

        device.read_rx_packet(packet_buffer[0..next_frame_length]);

        logger.debug("received {} bytes data on nic {s}", .{ next_frame_length, nic.getName() });

        const packet = try nic.allocIncomingPacket(ENC28J60.MAX_FRAMELEN);
        errdefer nic.freeIncomingPacket(packet);

        try packet.append(packet_buffer[0..next_frame_length]);

        nic.receive(packet);
    }
}

inline fn ENC28J60_CS_LOW(dev: *ENC28J60) void {
    dev.hw_intf.vtable.set_chipselect(dev.hw_intf.param, true);
}
inline fn ENC28J60_CS_HIGH(dev: *ENC28J60) void {
    dev.hw_intf.vtable.set_chipselect(dev.hw_intf.param, false);
}

fn ENC28J60_WRITE_BYTE(dev: *ENC28J60, data: u8) void {
    dev.hw_intf.vtable.write(dev.hw_intf.param, &.{data});
}

fn ENC28J60_READ_BYTE(dev: *ENC28J60) u8 {
    var byte: [1]u8 = @splat(0);
    dev.hw_intf.vtable.read(dev.hw_intf.param, 0xFF, &byte);
    return byte[0];
}

fn hardware_platform_sleep_ms(ms: u32) void {
    var deadline: ashet.time.Deadline = .init_rel(ms);
    deadline.wait();
}

fn hardware_platform_sleep_us(us: u32) void {
    hardware_platform_sleep_ms(@divFloor(us + 999, 1000));
}

fn u16_from_u8le(low: u8, high: u8) u16 {
    const Packed = packed struct(u16) {
        low: u8,
        high: u8,
    };
    return @bitCast(Packed{ .low = low, .high = high });
}

fn u8le_from_u16(val: u16) struct { u8, u8 } {
    const Packed = packed struct(u16) {
        low: u8,
        high: u8,
    };
    const pack: Packed = @bitCast(val);
    return .{ pack.low, pack.high };
}

pub const LinkStatus = enum {
    link_down,
    @"10m_half_duplex",
    @"10m_full_duplex",
};

pub const InitOptions = struct {
    skip_revision_check: bool = false,
    skip_self_test: bool = false,
    full_duplex: bool = false,
};

fn get_avail_tx_buffer(dev: *ENC28J60) u16 {
    return ENC28J60_MAX_FRAME_SIZE - dev.get_tx_size();
}

fn write_tx_buffer(dev: *ENC28J60, buffer: []const u8) error{Overflow}!u16 {
    if (buffer.len > 0) {
        const offset = dev.get_tx_size();

        const tx_size: u16 = @intCast(offset + buffer.len);
        if (tx_size > ENC28J60_MAX_FRAME_SIZE) {
            logger.err("overflow: {} + {} > {}", .{ offset, buffer.len, ENC28J60_MAX_FRAME_SIZE });
            return error.Overflow;
        }

        // Set the write pointer to the offset
        dev.write_register_word(EWRPT, (ENC28J60_TXSTART + 1 + offset));

        // Write data into the buffer
        dev.buffer_write(buffer);

        // Update the current write buffer offset
        dev.set_tx_size(tx_size);
    }
    return dev.get_avail_tx_buffer();
}

fn execute_tx(dev: *ENC28J60) error{ TxBufferEmpty, Timeout, Collision, TransmissionFailed }!void {
    const tx_size = dev.get_tx_size();
    if (tx_size == 0)
        return error.TxBufferEmpty;

    //
    // Appropriately program the ETXND Pointer. It should point to the last byte in the data payload.
    //
    dev.write_register_word(ETXST, ENC28J60_TXSTART);
    dev.write_register_word(ETXND, (ENC28J60_TXSTART + 1 + tx_size - 1));

    dev.clear_register_bit(EIR, EIR_TXIF);

    //
    // Start transmission
    //
    const result = dev.tx_start(tx_size);

    //
    // Reset transmit memory for next write
    //
    dev.write_register_word(ETXST, ENC28J60_TXSTART);

    //
    // Set the write pointer
    //
    dev.write_register_word(EWRPT, ENC28J60_TXSTART);

    //
    // Write the per packet control byte
    //
    dev.write_op(ENC28J60_WRITE_BUF_MEM, 0, 0);

    dev.set_tx_size(0);

    return result;
}

fn tx_start(dev: *ENC28J60, tx_size: u16) error{ Timeout, Collision, TransmissionFailed }!void {
    comptime {
        std.debug.assert(ENC28J60_TRANSMIT_TIMEOUT_MS > 0);
    }

    const deadline = ashet.time.Deadline.init_rel(ENC28J60_TRANSMIT_TIMEOUT_MS);

    //
    // Start the transmission process by setting ECON1.TXRTS
    //
    dev.set_register_bit(ECON1, ECON1_TXRTS);

    //
    // Wait for transmit to complete
    //
    const eir_status = while (true) {
        const eir_status = dev.read_register_byte(EIR);
        logger.debug("status: 0x{X:0>2}", .{eir_status});
        if ((eir_status & (EIR_TXIF | EIR_TXERIF)) != 0) {
            break eir_status & (EIR_TXIF | EIR_TXERIF);
        }
        if (deadline.is_reached())
            return error.Timeout;
    };

    //
    // From errata:
    //
    //  Module: Transmit Logic
    //
    //  In Half-Duplex mode, a hardware transmission abort - caused by excessive collisions, a late collision
    //  or excessive deferrals - may stall the internal transmit logic. The next packet transmit initiated by
    //  the host controller may never succeed. That is, ECON1.TXRTS could remain set indefinitely.
    //
    //  Work around
    //  Before attempting to transmit a packet (setting ECON1.TXRTS), reset the internal transmit logic
    //  by setting ECON1.TXRST and then clearing ECON1.TXRST. The host controller may wish to
    //  issue this Reset before any packet is transmitted (for simplicity), or it may wish to conditionally reset
    //  the internal transmit logic based on the Transmit Error Interrupt Flag (EIR.TXERIF), which will
    //  become set whenever a transmit abort occurs.
    //
    //  Clearing ECON1.TXRST may cause a new transmit error interrupt event (with EIR.TXERIF
    //  becoming set). Therefore, the interrupt flag should be cleared after the Reset is completed.
    //
    if ((eir_status & EIR_TXERIF) != 0) {
        dev.reset_tx_logic();
        return error.Collision;
    }

    //
    // Set the read pointer to the end of the transmission buffer.
    // Then read the Transmit Status Vector
    //
    dev.write_register_word(ERDPT, (ENC28J60_TXSTART + 1 + tx_size));

    var tsv: [7]u8 = @splat(0);
    dev.buffer_read(&tsv);
    const decode = std.mem.readInt(u56, &tsv, .little);
    logger.debug("tsv: 0x{X:0>14} | {}", .{ decode, std.fmt.fmtSliceHexLower(&tsv) });

    //
    // Reset the read pointer to the next packet pointer position
    //
    dev.write_register_word(ERDPT, dev.get_next_packet_pointer());

    if ((tsv[2] & TSV_TX_DONE) == 0)
        return error.TransmissionFailed;
}

fn reset_tx_logic(dev: *ENC28J60) void {
    dev.set_register_bit(ECON1, ECON1_TXRST);
    hardware_platform_sleep_us(14);

    dev.clear_register_bit(ECON1, ECON1_TXRST | ECON1_TXRTS);
    dev.clear_register_bit(EIR, EIR_TXERIF | EIR_TXIF);
}

fn reset(dev: *ENC28J60) void {
    logger.debug("reset chip", .{});
    //
    // Rev. B7 Silicon Errata:
    //
    // After sending an SPI Reset command, the PHY clock is stopped
    // but the ESTAT.CLKRDY bit is not cleared. Therefore,
    // polling the CLKRDY bit will not work to detect if
    // the PHY is ready.
    //
    // Additionally, the hardware start-up time of 300 μs
    // may expire before the device is ready to operate.
    //
    // Work around:
    // After issuing the Reset command, wait for at least
    // 1 ms in firmware for the device to be ready.
    //

    ENC28J60_CS_LOW(dev);
    ENC28J60_WRITE_BYTE(dev, ENC28J60_SOFT_RESET);
    ENC28J60_CS_HIGH(dev);

    hardware_platform_sleep_ms(2);

    //
    // Whenever a reset is done, ECON1 will inevitable need to be cleared next
    //
    dev.write_register_byte(ECON1, 0);
}

fn configure(dev: *ENC28J60, mac_address: ashet.network.MAC, full_duplex: bool) error{PhyTimeout}!void {
    dev.reset();

    //
    // Auto increment the buffer pointer
    //
    dev.write_register_byte(ECON2, ECON2_AUTOINC);

    comptime {
        std.debug.assert(ENC28J60_RXSTART >= 0);
        std.debug.assert(ENC28J60_RXSTART < ENC28J60_RXEND);
        if ((ENC28J60_RXEND % 2) == 0)
            @compileError("ENC28J60_RXEND must be an uneven number; see ENC28J60 errata");
    }

    //
    // Set the ENC28J60 receive buffer start and end address
    //
    dev.write_register_word(ERXST, ENC28J60_RXSTART);
    dev.write_register_word(ERXND, ENC28J60_RXEND);

    //
    // Set the next packet pointer
    //
    dev.set_next_packet_pointer(ENC28J60_RXSTART);
    dev.write_register_word(ERXRDPT, ENC28J60_RXSTART);

    comptime {
        std.debug.assert(ENC28J60_TXSTART >= 0);
        std.debug.assert(ENC28J60_TXSTART < ENC28J60_TXEND);
        std.debug.assert(ENC28J60_TXEND <= ENC28J60_MEMORY_SIZE);
        if ((ENC28J60_RXEND % 2) == 0)
            @compileError("ENC28J60_RXEND must be an uneven number; see ENC28J60 errata");
    }

    //
    // Set the ENC28J60 transmit buffer start and end address
    //
    dev.write_register_word(ETXST, ENC28J60_TXSTART);
    dev.write_register_word(ETXND, ENC28J60_TXEND);

    //
    // ERXFCON: Receive filter
    //
    // UCEN: Unicast Filter Enable bit
    //   1 = Packets with a destination address matching the local MAC address will be accepted
    //   0 = Filter disabled
    //
    // ANDOR: AND/OR Filter Select bit
    //   1 = AND: Packets will be rejected unless all enabled filters accept the packet
    //   0 = OR: Packets will be accepted unless all enabled filters reject the packet
    //
    // CRCEN: Post-Filter CRC Check Enable bit
    //   1 = All packets with an invalid CRC will be discarded
    //   0 = The CRC validity will be ignored
    //
    // PMEN: Pattern Match Filter Enable bit
    //   1 = Packets which meet the Pattern Match criteria will be accepted
    //   0 = Filter disabled
    //
    // MPEN: Magic Packetô Filter Enable bit
    //   1 = Magic Packets for the local MAC address will be accepted
    //   0 = Filter disabled
    //
    // HTEN: Hash Table Filter Enable bit
    //   1 = Packets which meet the Hash Table criteria will be accepted
    //   0 = Filter disabled
    //
    // MCEN: Multicast Filter Enable bit
    //   1 = Packets which have the Least Significant bit set in the destination address will be accepted
    //   0 = Filter disabled
    //
    // BCEN: Broadcast Filter Enable bit
    //   1 = Packets which have a destination address of FF-FF-FF-FF-FF-FF will be accepted
    //   0 = Filter disabled
    //
    dev.write_register_byte(ERXFCON, (ERXFCON_UCEN | ERXFCON_CRCEN | ERXFCON_BCEN));

    //
    // Initialize MAC
    //

    //
    // 1. Set the MARXEN bit in MACON1 to enable the MAC to receive frames. If using full duplex, most
    // applications should also set TXPAUS and RXPAUS to allow IEEE defined flow control to
    // function.
    //
    dev.write_register_byte(MACON1, (MACON1_MARXEN | MACON1_TXPAUS | MACON1_RXPAUS));

    //
    // 2. Configure the PADCFG, TXCRCEN and FULDPX bits of MACON3. Most applications
    // should enable automatic padding to at least 60 bytes and always append a valid CRC. For
    // convenience, many applications may wish to set the FRMLNEN bit as well to enable frame length
    // status reporting. The FULDPX bit should be set if the application will be connected to a
    // full-duplex configured remote node; otherwise, it should be left clear.
    //
    if (full_duplex) {
        dev.write_register_byte(MACON3, (MACON3_PADCFG0 | MACON3_TXCRCEN | MACON3_FRMLNEN | MACON3_FULDPX));
    } else {
        dev.write_register_byte(MACON3, (MACON3_PADCFG0 | MACON3_TXCRCEN | MACON3_FRMLNEN));

        //
        // 3. Configure the bits in MACON4. For conformance to the IEEE 802.3 standard, set the DEFER bit.
        //
        dev.write_register_byte(MACON4, MACON4_DEFER);
    }

    //
    // 4. Program the MAMXFL registers with the maximum frame length to be permitted to be received
    // or transmitted. Normal network nodes are designed to handle packets that are 1518 bytes
    // or less.
    //
    dev.write_register_word(MAMXFLL, ENC28J60_MAX_FRAME_SIZE);

    //
    // 5. Configure the Back-to-Back Inter-Packet Gap register, MABBIPG. Most applications will program
    // this register with 15h when Full-Duplex mode is used and 12h when Half-Duplex mode is used.
    //
    // 6. Configure the Non-Back-to-Back Inter-Packet Gap register low byte, MAIPGL.
    // Most applications will program this register with 12h.
    //
    // 7. If half duplex is used, the Non-Back-to-Back Inter-Packet Gap register high byte, MAIPGH,
    // should be programmed. Most applications will program this register to 0Ch.
    //
    if (full_duplex) {
        dev.write_register_word(MAIPG, 0x0012);
        dev.write_register_byte(MABBIPG, 0x15);
    } else {
        dev.write_register_word(MAIPGL, 0x0C12);
        dev.write_register_byte(MABBIPG, 0x12);
    }

    //
    // 8. If Half-Duplex mode is used, program the Retransmission and Collision Window registers,
    // MACLCON1 and MACLCON2. Most applications will not need to change the default Reset values.
    // If the network is spread over exceptionally long cables, the default value of MACLCON2 may
    // need to be increased.
    //
    dev.write_register_byte(MACON2, 0);

    //
    // 9. Program the local MAC address into the MAADR1:MAADR6 registers.
    //
    dev.write_register_byte(MAADR5, mac_address.tuple[0]);
    dev.write_register_byte(MAADR4, mac_address.tuple[1]);
    dev.write_register_byte(MAADR3, mac_address.tuple[2]);
    dev.write_register_byte(MAADR2, mac_address.tuple[3]);
    dev.write_register_byte(MAADR1, mac_address.tuple[4]);
    dev.write_register_byte(MAADR0, mac_address.tuple[5]);

    errdefer dev.reset();

    try dev.phy_write(PHLCON, ENC28J60_LAMPS_MODE);

    if (full_duplex) {
        try dev.phy_write(PHCON1, PHCON1_PDPXMD);
        try dev.phy_write(PHCON2, 0);
    } else {
        try dev.phy_write(PHCON1, 0);
        try dev.phy_write(PHCON2, PHCON2_HDLDIS);
    }

    try dev.phy_write(PHIE, 0);

    dev.clear_register_bit(EIR, (EIR_DMAIF | EIR_LINKIF | EIR_TXIF | EIR_TXERIF | EIR_RXERIF | EIR_PKTIF));
    dev.clear_register_bit(EIE, (EIE_INTIE | EIE_PKTIE | EIE_DMAIE | EIE_LINKIE | EIE_TXIE | EIE_TXERIE | EIE_RXERIE));

    //
    // RXEN: Receive Enable bit
    //   1 = Packets which pass the current filter configuration will be written into the receive buffer
    //   0 = All packets received will be ignored
    //
    dev.set_register_bit(ECON1, ECON1_RXEN);

    //
    // Set the transmit start pointer and write the initial header byte
    //
    dev.write_register_word(EWRPT, ENC28J60_TXSTART);
    dev.write_op(ENC28J60_WRITE_BUF_MEM, 0, 0);
    dev.set_tx_size(0);

    //
    // Wait time for the link to become active
    //
    hardware_platform_sleep_ms(100);
}

///
/// There is a lot of "magic" here that is blindly implemented from the datasheet.
/// This function however is a really good test to determine if the ENC28J60
/// is working as expected
///
fn built_in_self_test(dev: *ENC28J60, mode: u8) !void {
    dev.reset();

    //
    // From the datasheet.

    // To use the BIST:
    //

    //
    // 1. Program the EDMAST register pair to 0000h.
    //
    dev.write_register_word(EDMAST, 0);

    //
    // 2. Program EDMAND and ERXND register pairs to 1FFFh.
    //
    dev.write_register_word(EDMAND, ENC28J60_MEMORY_SIZE);
    dev.write_register_word(ERXND, ENC28J60_MEMORY_SIZE);

    //
    // 3. Configure the DMA for checksum generation by setting CSUMEN in ECON1.
    //
    dev.set_register_bit(ECON1, ECON1_CSUMEN);

    //
    // 5. Enable Test mode, select the desired test, select the desired port configuration for the test.
    // 6. Start the BIST by setting EBSTCON.BISTST
    //
    // Additionally further down:
    //
    // To ensure full testing, the test should be redone with the Port Select bit, PSEL, altered.
    // When not using Address Fill mode, additional tests may be done with different seed values
    // to gain greater confidence that the memory is working as expected
    //
    if (mode == BIST_ADDRESS_FILL) {
        // In Address Fill mode, the BIST controller will write the low byte of each memory address
        // into the associated buffer location. As an example, after the BIST is operated,
        // the location 0000h should have 00h in it, location 0001h should have 01h in it,
        // location 0E2Ah should have 2Ah in it and so on. With this fixed memory pattern, the BIST
        // and DMA modules should always generate a checksum of F807h. The host controller
        // may use Address Fill mode to confirm that the BIST and DMA modules themselves are both
        // operating as intended.
        dev.write_register_byte(EBSTCON, (EBSTCON_TME | EBSTCON_BISTST | mode));
    } else {

        // 4. Write the seed/initial shift value byte to the EBSTSD register
        // (this is not necessary if Address Fill mode is used).
        dev.write_register_byte(EBSTSD, 0b10101010);

        if (mode == BIST_RANDOM_FILL) {

            // In Random Data Fill mode, the BIST controller will write pseudo-random data into the buffer.
            // The random data is generated by a Linear Feedback Shift Register (LFSR) implementation.
            // The random number generator is seeded by the initial contents of the EBSTSD register and
            // the register will have new contents when the BIST is finished.
            //
            // Because of the LFSR implementation, an initial seed of zero will generate a continuous pattern of zeros.
            // As a result, a non-zero seed value will likely perform a more extensive memory test.
            //
            // Selecting the same seed for two separate trials will allow a repeat of the same test.

            dev.write_register_byte(EBSTCON, (EBSTCON_TME | EBSTCON_PSEL | EBSTCON_BISTST | mode));
        } else {
            return error.FailZero;
        }
    }

    for (0..16) |_| {
        hardware_platform_sleep_us(100);

        const op = dev.read_op(ENC28J60_READ_CTRL_REG, EBSTCON);
        if ((op & EBSTCON_BISTST) == 0)
            break;
    } else return error.SelfTestFailed;

    dev.clear_register_bit(EBSTCON, EBSTCON_TME);

    //
    // 7. Start the DMA checksum by setting DMAST in ECON1. The DMA controller will read the
    // memory at the same rate the BIST controller will write to it, so the DMA can be
    // started any time after the BIST is started.
    //
    dev.set_register_bit(ECON1, ECON1_DMAST);

    //
    // 8. Wait for the DMA to complete by polling the DMAST bit or receiving the DMA interrupt (if enabled).
    //
    // But further down:
    //
    // At any time during a test, the test can be canceled by clearing the BISTST, DMAST and TME bits.
    // While the BIST is filling memory, the EBSTSD register should not be accessed, nor should any
    // configuration changes occur.
    //
    // When the BIST completes its memory fill and checksum generation,
    // the BISTST bit will automatically be cleared.
    //
    // The BIST module requires one main clock cycle for each byte that it writes into the RAM.
    // The DMA module's checksum implementation requires the same
    // time but it can be started immediately after the BIST is started. As a result, the minimum time
    // required to do one test pass is slightly greater than 327.68 μs.
    //
    {
        for (0..8) |_| {
            hardware_platform_sleep_us(100);
            if ((dev.read_op(ENC28J60_READ_CTRL_REG, ECON1) & ECON1_DMAST) == 0)
                break;
        } else return error.DmaTestTimedOut;
    }

    dev.write_register_byte(EBSTCON, 0);
    dev.set_register_bit(ECON1, 0);

    //
    // 9. Compare the EDMACS registers with the EBSTCS registers
    //
    const edmacs = dev.read_register_word(EDMACS);
    const ebstcs = dev.read_register_word(EBSTCS);

    if (edmacs != ebstcs)
        return error.DmaTestFailed;

    if ((mode == BIST_ADDRESS_FILL) and (0xF807 != edmacs))
        return error.DmaTestCheckoutMismatch;
}

fn phy_write(dev: *ENC28J60, address: u8, value: u16) error{PhyTimeout}!void {
    dev.write_register_byte(MIREGADR, address);
    dev.write_register_word(MIWR, value);

    try dev.phy_wait();
}

fn phy_read(dev: *ENC28J60, address: u8) error{PhyTimeout}!u16 {
    dev.write_register_byte(MIREGADR, address);
    dev.write_register_byte(MICMD, MICMD_MIIRD);

    try dev.phy_wait();

    dev.write_register_byte(MICMD, 0);
    return dev.read_register_word(MIRD);
}

fn phy_wait(dev: *ENC28J60) error{PhyTimeout}!void {
    for (0..3) |_| {
        //
        // From datasheet: Wait 10.24 μs.
        // Poll the MISTAT.BUSY bit to be certain that the operation is complete.
        //
        // Adding a safety margin
        //
        hardware_platform_sleep_us(14);

        const mistat = dev.read_register_byte(MISTAT);
        if ((mistat & MISTAT_BUSY) == 0) {
            return;
        }
    }

    return error.PhyTimeout;
}

fn read_register_byte(dev: *ENC28J60, address: u8) u8 {
    dev.set_bank(address);
    const value = dev.read_op(ENC28J60_READ_CTRL_REG, address);
    logger.debug("read reg 0x{X:0>8} => 0x{X:0>2}", .{ address, value });
    return value;
}

fn read_register_word(dev: *ENC28J60, address: u8) u16 {
    dev.set_bank(address);

    const low = dev.read_op(ENC28J60_READ_CTRL_REG, address + 0);
    const high = dev.read_op(ENC28J60_READ_CTRL_REG, address + 1);

    const value = u16_from_u8le(low, high);
    logger.debug("read reg 0x{X:0>8} => 0x{X:0>4}", .{ address, value });
    return value;
}

fn write_register_byte(dev: *ENC28J60, address: u8, value: u8) void {
    logger.debug("write reg 0x{X:0>8} = 0x{X:0>2}", .{ address, value });
    dev.set_bank(address);
    dev.write_op(ENC28J60_WRITE_CTRL_REG, address, value);
}

fn write_register_word(dev: *ENC28J60, address: u8, value: u16) void {
    logger.debug("write reg 0x{X:0>8} = 0x{X:0>4}", .{ address, value });
    const low, const high = u8le_from_u16(value);

    dev.set_bank(address);
    dev.write_op(ENC28J60_WRITE_CTRL_REG, address + 0, low);
    dev.write_op(ENC28J60_WRITE_CTRL_REG, (address + 1), high);
}

fn set_bank(dev: *ENC28J60, address: u8) void {
    const bank_id = address & BANK_MASK;

    //
    // Registers EIE, EIR, ESTAT, ECON2, ECON1
    // are present in all banks, no need to switch bank
    //
    if (bank_id == ALL_BANKS)
        return;

    // No need to bank switch if we're currently having the active bank.
    if (bank_id == dev.active_bank)
        return;

    ENC28J60_CS_LOW(dev);
    ENC28J60_WRITE_BYTE(dev, (ENC28J60_BIT_FIELD_CLR | ADDR_MASK));
    ENC28J60_WRITE_BYTE(dev, (ECON1_BSEL1 | ECON1_BSEL0));
    ENC28J60_CS_HIGH(dev);

    ENC28J60_CS_LOW(dev);
    ENC28J60_WRITE_BYTE(dev, (ENC28J60_BIT_FIELD_SET | ADDR_MASK));
    ENC28J60_WRITE_BYTE(dev, (address >> 5));
    ENC28J60_CS_HIGH(dev);

    dev.active_bank = bank_id;
}

fn read_op(dev: *ENC28J60, op: u8, address: u8) u8 {
    ENC28J60_CS_LOW(dev);

    ENC28J60_WRITE_BYTE(dev, (op | (address & ADDR_MASK)));
    if ((address & SPRD_MASK) != 0) {
        ENC28J60_WRITE_BYTE(dev, 0);
    }
    const value = ENC28J60_READ_BYTE(dev);

    ENC28J60_CS_HIGH(dev);

    return value;
}

fn write_op(dev: *ENC28J60, op: u8, address: u8, value: u8) void {
    ENC28J60_CS_LOW(dev);
    ENC28J60_WRITE_BYTE(dev, op | (address & ADDR_MASK));
    ENC28J60_WRITE_BYTE(dev, value);
    ENC28J60_CS_HIGH(dev);
}

fn clear_register_bit(dev: *ENC28J60, address: u8, mask: u8) void {
    dev.set_bank(address);
    dev.write_op(ENC28J60_BIT_FIELD_CLR, address, mask);
}

fn set_register_bit(dev: *ENC28J60, address: u8, mask: u8) void {
    dev.set_bank(address);
    dev.write_op(ENC28J60_BIT_FIELD_SET, address, mask);
}

fn buffer_read(dev: *ENC28J60, buffer: []u8) void {
    ENC28J60_CS_LOW(dev);
    ENC28J60_WRITE_BYTE(dev, ENC28J60_READ_BUF_MEM);
    for (buffer) |*byte| {
        byte.* = ENC28J60_READ_BYTE(dev);
    }
    ENC28J60_CS_HIGH(dev);
}

fn buffer_write(dev: *ENC28J60, buffer: []const u8) void {
    ENC28J60_CS_LOW(dev);
    ENC28J60_WRITE_BYTE(dev, ENC28J60_WRITE_BUF_MEM);

    for (buffer) |byte| {
        ENC28J60_WRITE_BYTE(dev, byte);
    }

    ENC28J60_CS_HIGH(dev);
}

fn set_next_packet_pointer(dev: *ENC28J60, ptr: u16) void {
    dev.next_packet_pointer = ptr;
}

fn get_next_packet_pointer(dev: *ENC28J60) u16 {
    return dev.next_packet_pointer;
}

fn set_tx_size(dev: *ENC28J60, size: u16) void {
    dev.tx_size = size;
}

fn get_tx_size(dev: *ENC28J60) u16 {
    return dev.tx_size;
}

//
// From errata:
//
// Module: Memory (Ethernet Buffer)
//
// The receive hardware may corrupt the circular receive buffer (including the
// Next Packet Pointer and receive status vector fields) when an even value
// is programmed into the ERXRDPTH:ERXRDPTL registers.
//
// Work around:
//
// Ensure that only odd addresses are written to the ERXRDPT registers.
// Assuming that ERXND contains an odd value, many applications can derive
// a suitable value to write to ERXRDPT by subtracting one from the
// Next Packet Pointer (a value always ensured to be even because of hardware padding)
// and then compensating for a potential ERXST to ERXND wraparound.
//
// Assuming that the receive buffer area does not span the 1FFFh to 0000h memory
// boundary, the logic in Example 1 will ensure that ERXRDPT is programmed with an odd value:
//
// EXAMPLE1:
//
// if (Next Packet Pointer - 1 < ERXST) or (Next Packet Pointer - 1 > ERXND)
//  then:
//    ERXRDPT = ERXND
//  else:
//    ERXRDPT = Next Packet Pointer - 1
//
inline fn enc28j60_erxrdpt_errata(value: u16) u16 {
    if ((value <= ENC28J60_RXSTART) or (value >= ENC28J60_RXEND)) {
        return ENC28J60_RXEND;
    } else {
        return value - 1;
    }
}

//
// Most of the constants here are a rehash of dev.hw.h
// Mostly for readability or my own sanity
//

const ENC28J60_MEMORY_SIZE = 0x1FFF;
const ENC28J60_MAX_FRAME_SIZE = 1518;

const ENC28J60_TXEND = ENC28J60_MEMORY_SIZE;
const ENC28J60_TXSTART = (ENC28J60_TXEND - ENC28J60_MAX_FRAME_SIZE);

//
// From errata:
//
// Module: Memory (Ethernet Buffer)
// The receive hardware maintains an internal Write Pointer that defines the area in the receive buffer
// where bytes arriving over the Ethernet are written. This internal Write Pointer should be updated with
// the value stored in ERXST whenever the Receive Buffer Start Pointer, ERXST, or the Receive Buffer
// End Pointer, ERXND, is written to by the host microcontroller. Sometimes, when ERXST or ERXND is written to,
// the exact value, 0000h, is stored in the Internal Receive Write Pointer instead of the ERXST address.
//
// Work around
// Use the lower segment of the buffer memory for the receive buffer, starting at address 0000h. For
// example, use the range (0000h to n) for the receive buffer, and ((n + 1) – 8191) for the transmit
// buffer.
//
const ENC28J60_RXSTART = 0;
const ENC28J60_RXEND = (ENC28J60_TXSTART - 2);

//
// Word registers. Each has a L and H, L being the lower address and H the upper.
// H is always L + 1. Thus the write_register_word simply writes address and address + 1
//
// Here the L is dropped to make it consistent with the datasheet naming
//
const EDMAST = EDMASTL;
const EDMAND = EDMANDL;
const ERXND = ERXNDL;
const EDMACS = EDMACSL;
const EBSTCS = EBSTCSL;
const MIWR = MIWRL;
const MIRD = MIRDL;
const ERDPT = ERDPTL;
const EWRPT = EWRPTL;
const ERXWRPT = ERXWRPTL;
const ERXST = ERXSTL;
const ERXRDPT = ERXRDPTL;
const ETXST = ETXSTL;
const ETXND = ETXNDL;
const MAIPG = MAIPGL;
const MAMXFL = MAMXFLL;

const MACON2 = (0x01 | 0x40 | SPRD_MASK);
const MACON4_DEFER = 0x40;

const ALL_BANKS = 0xE0;

const RSV_RX_OK = 0b010000000;
const TSV_TX_DONE = 0b010000000;

// Built-in self test (BIST) bits
const EBSTCON_PSV2 = 0x80;
const EBSTCON_PSV1 = 0x40;
const EBSTCON_PSV0 = 0x20;
const EBSTCON_PSEL = 0x10;
const EBSTCON_TMSEL1 = 0x08;
const EBSTCON_TMSEL0 = 0x04;
const EBSTCON_TME = 0x02;
const EBSTCON_BISTST = 0x01;

const BIST_RANDOM_FILL = 0x00;
const BIST_ADDRESS_FILL = EBSTCON_TMSEL0;
const BIST_PATTERN_SHIFT = EBSTCON_TMSEL1;

const ENC28J60_TRANSMIT_TIMEOUT_MS = 500;

//
// ENC28J60 Control Registers
// Control register definitions are a combination of address,
// bank number, and Ethernet/MAC/PHY indicator bits.
// - Register address    (bits 0-4)
// - Bank number    (bits 5-6)
// - MAC/MII indicator    (bit 7)
//
const ADDR_MASK: u8 = 0x1F;
const BANK_MASK: u8 = 0x60;
const SPRD_MASK: u8 = 0x80;
// All-bank registers
const EIE = 0x1B;
const EIR = 0x1C;
const ESTAT = 0x1D;
const ECON2 = 0x1E;
const ECON1 = 0x1F;
// Bank 0 registers
const ERDPTL = (0x00 | 0x00);
const ERDPTH = (0x01 | 0x00);
const EWRPTL = (0x02 | 0x00);
const EWRPTH = (0x03 | 0x00);
const ETXSTL = (0x04 | 0x00);
const ETXSTH = (0x05 | 0x00);
const ETXNDL = (0x06 | 0x00);
const ETXNDH = (0x07 | 0x00);
const ERXSTL = (0x08 | 0x00);
const ERXSTH = (0x09 | 0x00);
const ERXNDL = (0x0A | 0x00);
const ERXNDH = (0x0B | 0x00);
const ERXRDPTL = (0x0C | 0x00);
const ERXRDPTH = (0x0D | 0x00);
const ERXWRPTL = (0x0E | 0x00);
const ERXWRPTH = (0x0F | 0x00);
const EDMASTL = (0x10 | 0x00);
const EDMASTH = (0x11 | 0x00);
const EDMANDL = (0x12 | 0x00);
const EDMANDH = (0x13 | 0x00);
const EDMADSTL = (0x14 | 0x00);
const EDMADSTH = (0x15 | 0x00);
const EDMACSL = (0x16 | 0x00);
const EDMACSH = (0x17 | 0x00);
// Bank 1 registers
const EHT0 = (0x00 | 0x20);
const EHT1 = (0x01 | 0x20);
const EHT2 = (0x02 | 0x20);
const EHT3 = (0x03 | 0x20);
const EHT4 = (0x04 | 0x20);
const EHT5 = (0x05 | 0x20);
const EHT6 = (0x06 | 0x20);
const EHT7 = (0x07 | 0x20);
const EPMM0 = (0x08 | 0x20);
const EPMM1 = (0x09 | 0x20);
const EPMM2 = (0x0A | 0x20);
const EPMM3 = (0x0B | 0x20);
const EPMM4 = (0x0C | 0x20);
const EPMM5 = (0x0D | 0x20);
const EPMM6 = (0x0E | 0x20);
const EPMM7 = (0x0F | 0x20);
const EPMCSL = (0x10 | 0x20);
const EPMCSH = (0x11 | 0x20);
const EPMOL = (0x14 | 0x20);
const EPMOH = (0x15 | 0x20);
const EWOLIE = (0x16 | 0x20);
const EWOLIR = (0x17 | 0x20);
const ERXFCON = (0x18 | 0x20);
const EPKTCNT = (0x19 | 0x20);
// Bank 2 registers
const MACON1 = (0x00 | 0x40 | SPRD_MASK);
// const MACON2 = (0x01|0x40|SPRD_MASK);
const MACON3 = (0x02 | 0x40 | SPRD_MASK);
const MACON4 = (0x03 | 0x40 | SPRD_MASK);
const MABBIPG = (0x04 | 0x40 | SPRD_MASK);
const MAIPGL = (0x06 | 0x40 | SPRD_MASK);
const MAIPGH = (0x07 | 0x40 | SPRD_MASK);
const MACLCON1 = (0x08 | 0x40 | SPRD_MASK);
const MACLCON2 = (0x09 | 0x40 | SPRD_MASK);
const MAMXFLL = (0x0A | 0x40 | SPRD_MASK);
const MAMXFLH = (0x0B | 0x40 | SPRD_MASK);
const MAPHSUP = (0x0D | 0x40 | SPRD_MASK);
const MICON = (0x11 | 0x40 | SPRD_MASK);
const MICMD = (0x12 | 0x40 | SPRD_MASK);
const MIREGADR = (0x14 | 0x40 | SPRD_MASK);
const MIWRL = (0x16 | 0x40 | SPRD_MASK);
const MIWRH = (0x17 | 0x40 | SPRD_MASK);
const MIRDL = (0x18 | 0x40 | SPRD_MASK);
const MIRDH = (0x19 | 0x40 | SPRD_MASK);
// Bank 3 registers
const MAADR1 = (0x00 | 0x60 | SPRD_MASK);
const MAADR0 = (0x01 | 0x60 | SPRD_MASK);
const MAADR3 = (0x02 | 0x60 | SPRD_MASK);
const MAADR2 = (0x03 | 0x60 | SPRD_MASK);
const MAADR5 = (0x04 | 0x60 | SPRD_MASK);
const MAADR4 = (0x05 | 0x60 | SPRD_MASK);
const EBSTSD = (0x06 | 0x60);
const EBSTCON = (0x07 | 0x60);
const EBSTCSL = (0x08 | 0x60);
const EBSTCSH = (0x09 | 0x60);
const MISTAT = (0x0A | 0x60 | SPRD_MASK);
const EREVID = (0x12 | 0x60);
const ECOCON = (0x15 | 0x60);
const EFLOCON = (0x17 | 0x60);
const EPAUSL = (0x18 | 0x60);
const EPAUSH = (0x19 | 0x60);
// PHY registers
const PHCON1 = 0x00;
const PHSTAT1 = 0x01;
const PHHID1 = 0x02;
const PHHID2 = 0x03;
const PHCON2 = 0x10;
const PHSTAT2 = 0x11;
const PHIE = 0x12;
const PHIR = 0x13;
const PHLCON = 0x14;

// ENC28J60 EIE Register Bit Definitions
const EIE_INTIE = 0x80;
const EIE_PKTIE = 0x40;
const EIE_DMAIE = 0x20;
const EIE_LINKIE = 0x10;
const EIE_TXIE = 0x08;
// const EIE_WOLIE = 0x04 (reserved);
const EIE_TXERIE = 0x02;
const EIE_RXERIE = 0x01;
// ENC28J60 EIR Register Bit Definitions
const EIR_PKTIF = 0x40;
const EIR_DMAIF = 0x20;
const EIR_LINKIF = 0x10;
const EIR_TXIF = 0x08;
// const EIR_WOLIF = 0x04 (reserved);
const EIR_TXERIF = 0x02;
const EIR_RXERIF = 0x01;
// ENC28J60 ESTAT Register Bit Definitions
const ESTAT_INT = 0x80;
const ESTAT_LATECOL = 0x10;
const ESTAT_RXBUSY = 0x04;
const ESTAT_TXABRT = 0x02;
const ESTAT_CLKRDY = 0x01;
// ENC28J60 ECON2 Register Bit Definitions
const ECON2_AUTOINC = 0x80;
const ECON2_PKTDEC = 0x40;
const ECON2_PWRSV = 0x20;
const ECON2_VRPS = 0x08;
// ENC28J60 ECON1 Register Bit Definitions
const ECON1_TXRST = 0x80;
const ECON1_RXRST = 0x40;
const ECON1_DMAST = 0x20;
const ECON1_CSUMEN = 0x10;
const ECON1_TXRTS = 0x08;
const ECON1_RXEN = 0x04;
const ECON1_BSEL1 = 0x02;
const ECON1_BSEL0 = 0x01;
// ENC28J60 MACON1 Register Bit Definitions
const MACON1_LOOPBK = 0x10;
const MACON1_TXPAUS = 0x08;
const MACON1_RXPAUS = 0x04;
const MACON1_PASSALL = 0x02;
const MACON1_MARXEN = 0x01;
// ENC28J60 MACON2 Register Bit Definitions
const MACON2_MARST = 0x80;
const MACON2_RNDRST = 0x40;
const MACON2_MARXRST = 0x08;
const MACON2_RFUNRST = 0x04;
const MACON2_MATXRST = 0x02;
const MACON2_TFUNRST = 0x01;
// ENC28J60 MACON3 Register Bit Definitions
const MACON3_PADCFG2 = 0x80;
const MACON3_PADCFG1 = 0x40;
const MACON3_PADCFG0 = 0x20;
const MACON3_TXCRCEN = 0x10;
const MACON3_PHDRLEN = 0x08;
const MACON3_HFRMLEN = 0x04;
const MACON3_FRMLNEN = 0x02;
const MACON3_FULDPX = 0x01;
// ENC28J60 MICMD Register Bit Definitions
const MICMD_MIISCAN = 0x02;
const MICMD_MIIRD = 0x01;
// ENC28J60 MISTAT Register Bit Definitions
const MISTAT_NVALID = 0x04;
const MISTAT_SCAN = 0x02;
const MISTAT_BUSY = 0x01;
// ENC28J60 ERXFCON Register Bit Definitions
const ERXFCON_UCEN = 0x80;
const ERXFCON_ANDOR = 0x40;
const ERXFCON_CRCEN = 0x20;
const ERXFCON_PMEN = 0x10;
const ERXFCON_MPEN = 0x08;
const ERXFCON_HTEN = 0x04;
const ERXFCON_MCEN = 0x02;
const ERXFCON_BCEN = 0x01;

// ENC28J60 PHY PHCON1 Register Bit Definitions
const PHCON1_PRST = 0x8000;
const PHCON1_PLOOPBK = 0x4000;
const PHCON1_PPWRSV = 0x0800;
const PHCON1_PDPXMD = 0x0100;
// ENC28J60 PHY PHSTAT1 Register Bit Definitions
const PHSTAT1_PFDPX = 0x1000;
const PHSTAT1_PHDPX = 0x0800;
const PHSTAT1_LLSTAT = 0x0004;
const PHSTAT1_JBSTAT = 0x0002;
// ENC28J60 PHY PHSTAT2 Register Bit Definitions
const PHSTAT2_TXSTAT = (1 << 13);
const PHSTAT2_RXSTAT = (1 << 12);
const PHSTAT2_COLSTAT = (1 << 11);
const PHSTAT2_LSTAT = (1 << 10);
const PHSTAT2_DPXSTAT = (1 << 9);
const PHSTAT2_PLRITY = (1 << 5);
// ENC28J60 PHY PHCON2 Register Bit Definitions
const PHCON2_FRCLINK = 0x4000;
const PHCON2_TXDIS = 0x2000;
const PHCON2_JABBER = 0x0400;
const PHCON2_HDLDIS = 0x0100;
// ENC28J60 PHY PHIE Register Bit Definitions
const PHIE_PLNKIE = (1 << 4);
const PHIE_PGEIE = (1 << 1);
// ENC28J60 PHY PHIR Register Bit Definitions
const PHIR_PLNKIF = (1 << 4);
const PHIR_PGEIF = (1 << 1);

// ENC28J60 Packet Control Byte Bit Definitions
const PKTCTRL_PHUGEEN = 0x08;
const PKTCTRL_PPADEN = 0x04;
const PKTCTRL_PCRCEN = 0x02;
const PKTCTRL_POVERRIDE = 0x01;

// ENC28J60 Transmit Status Vector
const TSV_TXBYTECNT = 0;
const TSV_TXCOLLISIONCNT = 16;
const TSV_TXCRCERROR = 20;
const TSV_TXLENCHKERROR = 21;
const TSV_TXLENOUTOFRANGE = 22;
const TSV_TXDONE = 23;
const TSV_TXMULTICAST = 24;
const TSV_TXBROADCAST = 25;
const TSV_TXPACKETDEFER = 26;
const TSV_TXEXDEFER = 27;
const TSV_TXEXCOLLISION = 28;
const TSV_TXLATECOLLISION = 29;
const TSV_TXGIANT = 30;
const TSV_TXUNDERRUN = 31;
const TSV_TOTBYTETXONWIRE = 32;
const TSV_TXCONTROLFRAME = 48;
const TSV_TXPAUSEFRAME = 49;
const TSV_BACKPRESSUREAPP = 50;
const TSV_TXVLANTAGFRAME = 51;

const TSV_SIZE = 7;
// inline fn  TSV_BYTEOF(x)        ((x) / 8)
// inline fn  TSV_BITMASK(x)        (1 << ((x) % 8))
// inline fn  TSV_GETBIT(x, y)    (((x)[TSV_BYTEOF(y)] & TSV_BITMASK(y)) ? 1 : 0)

// ENC28J60 Receive Status Vector
const RSV_RXLONGEVDROPEV = 16;
const RSV_CARRIEREV = 18;
const RSV_CRCERROR = 20;
const RSV_LENCHECKERR = 21;
const RSV_LENOUTOFRANGE = 22;
const RSV_RXOK = 23;
const RSV_RXMULTICAST = 24;
const RSV_RXBROADCAST = 25;
const RSV_DRIBBLENIBBLE = 26;
const RSV_RXCONTROLFRAME = 27;
const RSV_RXPAUSEFRAME = 28;
const RSV_RXUNKNOWNOPCODE = 29;
const RSV_RXTYPEVLAN = 30;

const RSV_SIZE = 6;

// #define RSV_BITMASK(x)        (1 << ((x) - 16))
// #define RSV_GETBIT(x, y)    (((x) & RSV_BITMASK(y)) ? 1 : 0)

// SPI operation codes
const ENC28J60_READ_CTRL_REG = 0x00;
const ENC28J60_READ_BUF_MEM = 0x3A;
const ENC28J60_WRITE_CTRL_REG = 0x40;
const ENC28J60_WRITE_BUF_MEM = 0x7A;
const ENC28J60_BIT_FIELD_SET = 0x80;
const ENC28J60_BIT_FIELD_CLR = 0xA0;
const ENC28J60_SOFT_RESET = 0xFF;

// buffer boundaries applied to internal 8K ram
// entire available packet buffer space is allocated.
// Give TX buffer space for one full ethernet frame (~1500 bytes)
// receive buffer gets the rest
const TXSTART_INIT = 0x1A00;
const TXEND_INIT = 0x1FFF;

// Put RX buffer at 0 as suggested by the Errata datasheet
const RXSTART_INIT = 0x0000;
const RXEND_INIT = 0x19FF;

// maximum ethernet frame length */
pub const MAX_FRAMELEN = 1518;

// Preferred half duplex: LEDA: Link status LEDB: Rx/Tx activity
const ENC28J60_LAMPS_MODE = 0x3476;

const ENC28J60_MAX_RECEIVE_LOOP_COUNT = 32;
