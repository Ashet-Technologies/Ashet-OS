const std = @import("std");
const ashet = @import("../../main.zig");
const logger = std.log.scoped(.ata);
const x86 = ashet.ports.platforms.x86;

const AT_Attachment = @This();
const Driver = ashet.drivers.Driver;
const BlockDevice = ashet.drivers.BlockDevice;

// const Timer = @import("timer.zig");

driver: Driver,

is_primary: bool,
is_present: bool,
ports: Ports,

pub fn init(index: u3) error{NoAtaController}!AT_Attachment {
    const all_baseports = [_]PortConfig{
        PortConfig.init(0x1F0, true),
        PortConfig.init(0x1F0, false),
        PortConfig.init(0x170, true),
        PortConfig.init(0x170, false),
        PortConfig.init(0x1E8, true),
        PortConfig.init(0x1E8, false),
        PortConfig.init(0x168, true),
        PortConfig.init(0x168, false),
    };

    const config = all_baseports[index];

    var ata = AT_Attachment{
        .driver = .{
            .name = "AT Attachment",
            .class = .{
                .block = .{
                    .name = switch (index) {
                        inline else => |i| std.fmt.comptimePrint("AT{}", .{i}),
                    },
                    .block_size = 512,
                    .num_blocks = 0,
                    .presentFn = present,
                    .readFn = read,
                    .writeFn = write,
                },
            },
        },
        .is_primary = config.is_primary,
        .is_present = false,
        .ports = config.ports,
    };

    ata.is_present = try ata.initialize();

    return ata;
}

fn present(driver: *Driver) bool {
    const device: *AT_Attachment = @fieldParentPtr("driver", driver);
    return device.is_present;
}

fn read(driver: *Driver, block: u64, data: []u8) ashet.storage.BlockDevice.ReadError!void {
    const device: *AT_Attachment = @fieldParentPtr("driver", driver);

    const lba = std.math.cast(u23, block) orelse return error.InvalidBlock;

    // logger.debug("ATA read({}, {})", .{ block, data.len });

    try device.readBlocks(lba, data);
}

fn write(driver: *Driver, block: u64, data: []const u8) ashet.storage.BlockDevice.WriteError!void {
    const device: *AT_Attachment = @fieldParentPtr("driver", driver);

    const lba = std.math.cast(u23, block) orelse return error.InvalidBlock;

    try device.writeBlocks(lba, data);
}

fn status(device: AT_Attachment) Status {
    wait400NS(device.ports.status);
    return @as(Status, @bitCast(x86.in(u8, device.ports.status)));
}

fn isFloating(device: AT_Attachment) bool {
    return x86.in(u8, device.ports.status) == 0xFF;
}

fn initialize(device: *AT_Attachment) error{NoAtaController}!bool {
    if (device.isFloating())
        return error.NoAtaController;

    const ports = device.ports;

    // To use the IDENTIFY command, select a target drive by sending
    // 0xA0 for the master drive, or
    // 0xB0 for the slave, to the "drive select" IO port.
    if (device.is_primary) {
        x86.out(u8, ports.device_select, 0xA0); // Select Master
    } else {
        x86.out(u8, ports.device_select, 0xB0); // Select Slave
    }

    // Then set the Sectorcount, LBAlo, LBAmid, and LBAhi IO ports to 0
    x86.out(u8, ports.sectors, 0);
    x86.out(u8, ports.lba_low, 0);
    x86.out(u8, ports.lba_mid, 0);
    x86.out(u8, ports.lba_high, 0);

    // Then send the IDENTIFY command (0xEC) to the Command IO port.
    x86.out(u8, ports.cmd, 0xEC);

    // Then read the Status port again. If the value read is 0, the drive does not
    // exist.
    const statusByte = x86.in(u8, device.ports.status);
    if (statusByte == 0x00) {
        // hal_debug("IDENTIFY failed with STATUS = 0.\n");
        return false;
    }

    // For any other value: poll the Status port (0x1F7) until bit 7 (BSY, value = 0x80)
    // clears. Because of some ATAPI drives that do not follow spec, at this point you
    // need to check the LBAmid and LBAhi ports (0x1F4 and 0x1F5) to see if they are
    // non-zero. If so, the drive is not ATA, and you should stop polling. Otherwise,
    // continue polling one of the Status ports until bit 3 (DRQ, value = 8) sets,
    // or until bit 0 (ERR, value = 1) sets.
    while (device.status().busy) {
        // hal_debug("devbusy\n");
    }

    if ((x86.in(u8, ports.lba_mid) != 0) or (x86.in(u8, ports.lba_high) != 0)) {
        // hal_debug("%d, %d\n", x86.in(u8, ports.lbaMid), x86.in(u8, ports.lbaHigh));
        // hal_debug("IDENTIFY failed with INVALID ATA DEVICE.\n");
        return false;
    }

    device.waitForErrOrReady(150) catch return false;

    // At that point, if ERR is clear, the data is ready to read from the Data port
    // (0x1F0).
    // Read 256 16-bit values, and store them.

    var ataData: [256]u16 = undefined;
    for (&ataData) |*w| {
        w.* = x86.in(u16, ports.data);
    }

    device.driver.class.block.num_blocks = ((@as(u32, ataData[61]) << 16) | ataData[60]);

    return true;
}

/// Waits for either an error or that the device is ready.
/// Will error after `timeout` ms have passed.
fn waitForErrOrReady(device: AT_Attachment, timeout: usize) BlockDevice.DeviceError!void {
    const end = ashet.time.milliTimestamp() + timeout;
    while (ashet.time.milliTimestamp() < end) {
        const stat = device.status();
        // logger.debug("{}", .{stat}); // BUG: This is a horrible hack to delay the status polling
        if (stat.has_error or stat.drive_fault)
            return error.Fault;
        if (stat.ready)
            return;

        wait400NS(device.ports.status);
    }
    return error.Timeout;
}

fn setupParameters(device: AT_Attachment, lba: u24, blockCount: u8) void {
    if (device.is_primary) {
        x86.out(u8, device.ports.device_select, 0xE0);
    } else {
        x86.out(u8, device.ports.device_select, 0xF0);
    }
    x86.out(u8, device.ports.sectors, blockCount);
    x86.out(u8, device.ports.lba_low, @as(u8, @truncate(lba)));
    x86.out(u8, device.ports.lba_mid, @as(u8, @truncate(lba >> 8)));
    x86.out(u8, device.ports.lba_high, @as(u8, @truncate(lba >> 16)));
}

fn readData(device: AT_Attachment) u16 {
    while (device.status().busy) {
        asm volatile ("" ::: "memory");
    }
    return x86.in(u16, device.ports.data);
}

fn readBlocks(device: AT_Attachment, lba: u24, buffer: []u8) BlockDevice.ReadError!void {
    if (!device.is_present)
        return error.DeviceNotPresent;

    const block_size = device.driver.class.block.block_size;

    std.debug.assert(std.mem.isAligned(buffer.len, block_size));

    const ports = device.ports;

    const blockCount = @as(u8, @intCast(buffer.len / block_size));

    if (lba + blockCount > device.driver.class.block.num_blocks)
        return error.InvalidBlock;

    device.setupParameters(lba, blockCount);
    x86.out(u8, ports.cmd, 0x20);

    @memset(buffer, undefined);

    var current_block = buffer.ptr;

    var block: usize = 0;
    while (block < blockCount) : (block += 1) {
        try device.waitForErrOrReady(150);

        var i: usize = 0;
        while (i < block_size) : (i += 2) {
            const value = device.readData();

            current_block[0..2].* = @bitCast(value);
            current_block += 2;
        }
    }
}

fn writeBlocks(device: AT_Attachment, lba: u24, buffer: []const u8) BlockDevice.WriteError!void {
    if (!device.is_present)
        return error.DeviceNotPresent;

    const block_size = device.driver.class.block.block_size;

    std.debug.assert(std.mem.isAligned(buffer.len, block_size));

    const ports = device.ports;

    const blockCount = @as(u8, @intCast(buffer.len / block_size));

    if (lba + blockCount > device.driver.class.block.num_blocks)
        return error.InvalidBlock;

    device.setupParameters(lba, blockCount);
    x86.out(u8, ports.cmd, 0x30);

    var block: usize = 0;
    while (block < blockCount) : (block += 1) {
        try device.waitForErrOrReady(150);

        var words: [256]u16 = undefined;

        std.mem.copyForwards(u8, std.mem.sliceAsBytes(&words), buffer[block_size * block ..][0..block_size]);

        for (words) |w| {
            x86.out(u16, ports.data, w);

            // WHY?!
            asm volatile ("nop");
            asm volatile ("nop");
            asm volatile ("nop");
            asm volatile ("nop");
        }

        x86.out(u8, ports.cmd, 0xE7); // Flush
        try device.waitForErrOrReady(150);
    }
}

fn wait400NS(port: u16) void {
    std.mem.doNotOptimizeAway(x86.in(u8, port));
    std.mem.doNotOptimizeAway(x86.in(u8, port));
    std.mem.doNotOptimizeAway(x86.in(u8, port));
    std.mem.doNotOptimizeAway(x86.in(u8, port));
}

const PortConfig = struct {
    ports: Ports,
    is_primary: bool,

    pub fn init(base: u16, primary: bool) PortConfig {
        return PortConfig{
            .is_primary = primary,

            .ports = Ports{
                .data = base + 0,
                .@"error" = base + 1,
                .sectors = base + 2,
                .lba_low = base + 3,
                .lba_mid = base + 4,
                .lba_high = base + 5,
                .device_select = base + 6,
                .status = base + 7,
                .cmd = base + 7,
                .control = base + 518,
            },
        };
    }
};

const Ports = struct {
    data: u16,
    @"error": u16,
    sectors: u16,
    lba_low: u16,
    lba_mid: u16,
    lba_high: u16,
    device_select: u16,
    status: u16,
    cmd: u16,
    control: u16,
};

const Status = packed struct(u8) {
    /// Indicates an error occurred. Send a new command to clear it (or nuke it with a Software Reset).
    has_error: bool,

    /// Index. Always set to zero.
    index: u1 = 0,

    /// Corrected data. Always set to zero.
    corrected_data: bool = false,

    /// Set when the drive has PIO data to transfer, or is ready to accept PIO data.
    data_request: bool,

    /// Overlapped Mode Service Request.
    service_request: bool,

    /// Drive Fault Error (does not set ERR).
    drive_fault: bool,

    /// Bit is clear when drive is spun down, or after an error. Set otherwise.
    ready: bool,

    /// Indicates the drive is preparing to send/receive data (wait for it to clear). In case of 'hang' (it never clears), do a software reset.
    busy: bool,
};
