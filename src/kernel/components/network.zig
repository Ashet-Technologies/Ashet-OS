const std = @import("std");
const ashet = @import("../main.zig");

const c = @cImport({
    @cInclude("lwip/init.h");
    @cInclude("lwip/tcpip.h");
    @cInclude("lwip/netif.h");
    @cInclude("lwip/timeouts.h");
});

pub fn start() !void {
    c.lwip_init();

    const network_thread = try ashet.scheduler.Thread.spawn(networkThread, null, .{});
    errdefer network_thread.kill();

    try network_thread.setName("ashet.network");

    network_thread.detach();
}

fn networkThread(_: ?*anyopaque) callconv(.C) u32 {
    while (true) {
        c.sys_check_timeouts();
        ashet.scheduler.yield();
    }
}

export fn sys_now() u32 {
    // TODO: Implement system timer/rtc
    return 0;
}
