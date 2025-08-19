const std = @import("std");
const microzig = @import("microzig");

const logger = std.log.scoped(.propio);

pub const lowlevel = @import("lowlevel.zig");
pub const types = @import("types.zig");

pub const Module = types.Module;
pub const ModuleID = types.ModuleID;
pub const FifoId = types.FifoId;
pub const FifoConfig = types.FifoConfig;
pub const FrameType = types.FrameType;

pub fn init() !void {
    try lowlevel.init();
}

pub fn receive_one_blocking(buffer: []u8) error{Overflow}!usize {
    while (true) {
        if (try try_receive_one(buffer)) |len| {
            return len;
        }
        asm volatile ("wfe");
        continue;
    }
}

pub fn try_receive_one(buffer: []u8) error{Overflow}!?usize {
    const frame = lowlevel.get_available_frame_raw() orelse {
        return null;
    };

    if (frame.len > buffer.len) {
        return error.Overflow;
    }
    @memcpy(buffer[0..frame.len], frame);
    lowlevel.return_frame_raw(frame);
    return frame.len;
}

pub fn launch_module(slot: ModuleID, mod: Module) !void {
    logger.info("upload ram", .{});
    try write_ram(
        slot.get_code_address(),
        mod.code,
    );

    {
        var config_buf: [64]u8 = @splat(0);
        for (std.enums.values(FifoId)) |fifo| {
            if (mod.config.get_fifo_config(fifo)) |config| {
                const offset = fifo.get_config_offset();

                std.mem.writeInt(u16, config_buf[offset..][0..2], config.base, .little);
                std.mem.writeInt(u8, config_buf[offset..][4..5], config.wptr, .little);
                std.mem.writeInt(u8, config_buf[offset..][5..6], config.rptr, .little);
                std.mem.writeInt(u16, config_buf[offset..][6..8], config.limit, .little);
            }
        }

        logger.info("upload config", .{});
        try write_ram(
            slot.get_conf_address(),
            &config_buf,
        );
    }

    logger.info("start code", .{});
    try start_core(slot);
}

pub fn write_ram(offset: u24, data: []const u8) !void {
    logger.debug("write ram(0x{X:0>6}, {} bytes)", .{ offset, data.len });
    var buf: [3]u8 = undefined;
    std.mem.writeInt(u24, &buf, offset, .little);

    try lowlevel.writev_frame_blocking(&.{
        &header(.write_ram, 4 + data.len),
        &buf,
        data,
    });
}

pub fn start_core(core: ModuleID) !void {
    try lowlevel.writev_frame_blocking(&.{
        &header(.start_module, 1),
        &.{@intFromEnum(core) - 1},
    });
}

pub fn stop_core(core: ModuleID) !void {
    try lowlevel.writev_frame_blocking(&.{
        &header(.stop_module, 1),
        &.{@intFromEnum(core) - 1},
    });
}

pub fn write_fifo(slot: ModuleID, fifo: FifoId, data: []const u8) !void {
    const SlotFifo = packed struct(u8) {
        fifo: u3,
        _reserved0: u1 = 0,
        slot: u3,
        _reserved7: u1 = 0,
    };
    const opcode: u8 = @bitCast(SlotFifo{
        .slot = @intFromEnum(slot) - 1,
        .fifo = @intFromEnum(fifo),
    });

    try lowlevel.writev_frame_blocking(&.{
        &header(.write_fifo, 1 + data.len),
        &.{opcode},
        data,
    });
}

fn header(ft: types.FrameType, total_len: usize) [1]u8 {
    _ = total_len;
    var buf: [1]u8 = @splat(0);
    buf[0] = @intFromEnum(ft);
    // std.mem.writeInt(u32, buf[1..5], @intCast(total_len + 1), .little);
    return buf;
}
