const std = @import("std");
const ashet = @import("root");
const logger = std.log.scoped(.@"platform-virt");

const virtio = @import("virtio");

pub const serial = @import("serial.zig");

noinline fn readHwCounter() u64 {
    var res: u64 = undefined;
    asm volatile (
        \\read_hwcnt_loop:
        \\  rdcycleh t0 // hi
        \\  rdcycle  t1 // lo
        \\  rdcycleh t2 // check
        \\  bne t0, t2, read_hwcnt_loop
        \\  sw t0, 4(%[ptr])
        \\  sw t1, 0(%[ptr])
        :
        : [ptr] "r" (&res),
        : "{t0}", "{t1}", "{t2}"
    );
    return res;
}

pub fn initialize() void {

    // Initialize all virtio devices:
    {
        const virtio_base = @intToPtr([*]align(4096) volatile virtio.ControlRegs, @import("regs.zig").VPBA_VIRTIO_BASE);

        if (virtio_base[0].magic != virtio.ControlRegs.magic) {
            @panic("not virt platform!");
        }

        var i: usize = 0;

        while (i < 8 and virtio_base[i].magic == virtio.ControlRegs.magic) : (i += 1) {
            const regs = &virtio_base[i];

            if (regs.version != 1 and regs.version != 2) {
                continue;
            }

            switch (regs.device_id) {
                .reserved => continue,
                .gpu => gpu.initialize(regs) catch |err| @panic(@errorName(err)),
                .input => input.initialize(regs) catch |err| @panic(@errorName(err)),
                .network => network.initialize(regs) catch |err| @panic(@errorName(err)),
                else => logger.info("Found unsupported virtio device: {s}", .{@tagName(regs.device_id)}),
            }
        }
    }

    video.flush(); // force the gpu to show the splash screen

    storage.initialize();

    time.init();
}


pub const storage = struct {
    const BlockDevice = ashet.storage.BlockDevice;

    var pflash1: ashet.drivers.block_device.CFI = undefined;

    var devices_backing = std.BoundedArray(ashet.storage.BlockDevice, 8){};
    pub var devices: []ashet.storage.BlockDevice = undefined;

    pub fn initialize() void {
        pflash1 = ashet.drivers.block_device.CFI.init(0x2200_0000, 0x0200_0000) catch @panic("pflash1 not present!");

        devices_backing.appendAssumeCapacity(.{
            .name = "PF0",
            .interface = pflash1.interface(),
        });
        devices = devices_backing.slice();
    }
};
