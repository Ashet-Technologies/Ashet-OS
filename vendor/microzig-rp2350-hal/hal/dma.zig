const std = @import("std");
const assert = std.debug.assert;

const microzig = @import("microzig");
const chip = microzig.chip;
const DMA = chip.peripherals.DMA;

const hw = @import("hw.zig");
const compat = @import("compatibility.zig");

const num_channels = compat.dma_channel_count;

// "Marked bit" is "free"
var claimed_channels = std.bit_set.IntegerBitSet(num_channels).initFull();

pub const Dreq = enum(u6) {
    uart0_tx = 20,
    uart1_tx = 21,
    _,
};

pub fn channel(n: u4) Channel {
    assert(n < num_channels);
    return @as(Channel, @enumFromInt(n));
}

pub fn claim_unused_channel() ?Channel {
    return if (claimed_channels.toggleFirstSet()) |cid|
        channel(@intCast(cid))
    else
        null;
}

pub const Channel = enum(u4) {
    _,

    /// panics if the channel is already claimed
    pub fn claim(chan: Channel) void {
        if (chan.is_claimed())
            @panic("channel is already claimed!");
        claimed_channels.unset(@intFromEnum(chan));
    }

    pub fn unclaim(chan: Channel) void {
        claimed_channels.set(@intFromEnum(chan));
    }

    pub fn is_claimed(chan: Channel) bool {
        return !claimed_channels.isSet(@intFromEnum(chan));
    }

    pub const Regs = extern struct {
        read_addr: u32,
        write_addr: u32,
        trans_count: @TypeOf(DMA.CH0_TRANS_COUNT),
        ctrl_trig: @TypeOf(DMA.CH0_CTRL_TRIG),

        // alias 1
        al1_ctrl: @TypeOf(DMA.CH0_CTRL_TRIG),
        al1_read_addr: u32,
        al1_write_addr: u32,
        al1_trans_count: @TypeOf(DMA.CH0_TRANS_COUNT),

        // alias 2
        al2_ctrl: @TypeOf(DMA.CH0_CTRL_TRIG),
        al2_read_addr: u32,
        al2_write_addr: u32,
        al2_trans_count: @TypeOf(DMA.CH0_TRANS_COUNT),

        // alias 3
        al3_ctrl: @TypeOf(DMA.CH0_CTRL_TRIG),
        al3_read_addr: u32,
        al3_write_addr: u32,
        al3_trans_count: @TypeOf(DMA.CH0_TRANS_COUNT),
    };

    pub fn get_regs(chan: Channel) *volatile Regs {
        const regs = @as(*volatile [12]Regs, @ptrCast(&DMA.CH0_READ_ADDR));
        return &regs[@intFromEnum(chan)];
    }

    pub const TransferConfig = struct {
        transfer_size_bytes: u3,
        enable: bool,
        read_increment: bool,
        write_increment: bool,
        dreq: Dreq,

        // TODO:
        // chain to
        // ring
        // byte swapping
    };

    pub fn trigger_transfer(
        chan: Channel,
        write_addr: u32,
        read_addr: u32,
        count: u32,
        config: TransferConfig,
    ) void {
        const regs = chan.get_regs();
        regs.read_addr = read_addr;
        regs.write_addr = write_addr;
        regs.trans_count = count;
        regs.ctrl_trig.modify(.{
            .EN = @intFromBool(config.enable),
            .DATA_SIZE = switch (config.transfer_size_bytes) {
                1 => @TypeOf(regs.ctrl_trig.read().DATA_SIZE.value).SIZE_BYTE,
                2 => .SIZE_HALFWORD,
                4 => .SIZE_WORD,
                else => unreachable,
            },
            .INCR_READ = @intFromBool(config.read_increment),
            .INCR_WRITE = @intFromBool(config.write_increment),
            .TREQ_SEL = .{
                .raw = @intFromEnum(config.dreq),
            },
        });
    }

    pub fn set_irq0_enabled(chan: Channel, enabled: bool) void {
        if (enabled) {
            const inte0_set = hw.set_alias_raw(&DMA.INTE0);
            inte0_set.* = @as(u32, 1) << @intFromEnum(chan);
        } else {
            const inte0_clear = hw.clear_alias_raw(&DMA.INTE0);
            inte0_clear.* = @as(u32, 1) << @intFromEnum(chan);
        }
    }

    pub fn acknowledge_irq0(chan: Channel) void {
        const ints0_set = hw.set_alias_raw(&DMA.INTS0);
        ints0_set.* = @as(u32, 1) << @intFromEnum(chan);
    }

    pub fn is_busy(chan: Channel) bool {
        const regs = chan.get_regs();
        return regs.ctrl_trig.read().BUSY == 1;
    }
};
