const std = @import("std");
const hal = @import("hal");
const abi = ashet.abi;
const ashet = @import("../main.zig");
const astd = @import("ashet-std");
const logger = std.log.scoped(.network);

const c = @cImport({
    @cInclude("lwip/init.h");
    @cInclude("lwip/tcpip.h");
    @cInclude("lwip/netif.h");
    @cInclude("lwip/dhcp.h");
    @cInclude("lwip/etharp.h");
    @cInclude("lwip/ethip6.h");
    @cInclude("lwip/timeouts.h");
});

pub const Interface = enum {
    ethernet,
    ieee802_11,

    pub fn prefix(i: Interface) u8 {
        return switch (i) {
            .ethernet => 'E',
            .ieee802_11 => 'W',
        };
    }
};

pub const MAC = struct {
    tuple: [6]u8,
    pub fn init(v: [6]u8) MAC {
        return MAC{ .tuple = v };
    }

    pub fn format(mac: MAC, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}", .{
            mac.tuple[0],
            mac.tuple[1],
            mac.tuple[2],
            mac.tuple[3],
            mac.tuple[4],
            mac.tuple[5],
        });
    }
};

pub fn appendToPBUF(pbuf: *c.pbuf, data: []const u8) !void {
    const len = std.math.cast(u16, data.len) orelse return error.OutOfMemory;
    try lwipTry(c.pbuf_take(pbuf, data.ptr, len));
}

pub const IncomingPacket = struct {
    pbuf: *c.pbuf,

    pub fn append(packet: IncomingPacket, data: []const u8) !void {
        try appendToPBUF(packet.pbuf, data);
    }
};

pub const NIC = struct {
    pub const VTable = struct {
        linkIsUp: std.meta.FnPtr(fn (nic: *NIC) bool),
        allocPacket: std.meta.FnPtr(fn (nic: *NIC, size: usize) ?[]u8),
        send: std.meta.FnPtr(fn (nic: *NIC, buffer: []u8) bool),
    };

    interface: Interface,
    address: MAC,
    mtu: u16,

    vtable: *const VTable,
    implementation: ?*anyopaque,

    dhcp: c.dhcp = undefined,
    netif: c.netif = undefined,

    pub fn allocPacket(nic: *NIC, size: usize) !IncomingPacket {
        _ = nic;

        const len = std.math.cast(u16, size) orelse return error.PacketTooBig;

        const pbuf: *c.pbuf = c.pbuf_alloc(c.PBUF_RAW, len, c.PBUF_POOL) orelse return error.OutOfMemory;

        return IncomingPacket{ .pbuf = pbuf };
    }

    pub fn freePacket(nic: *NIC, packet: IncomingPacket) void {
        _ = nic;
        _ = c.pbuf_free(packet.pbuf); // return value is irrelevant for us
    }

    pub fn receive(nic: *NIC, packet: IncomingPacket) void {
        if (nic.netif.input.?(packet.pbuf, &nic.netif) != c.ERR_OK) {
            _ = c.pbuf_free(packet.pbuf); // return value is irrelevant for us
        }
    }
};

const IPFormatter = struct {
    addr: c.ip_addr_t,

    pub fn new(addr: c.ip_addr_t) IPFormatter {
        return IPFormatter{ .addr = addr };
    }

    pub fn format(addr: IPFormatter, comptime fmt: []const u8, opt: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = opt;
        try writer.writeAll(std.mem.sliceTo(c.ip4addr_ntoa(@ptrCast(*const c.ip4_addr_t, &addr.addr)), 0));
    }
};

fn netif_status_callback(netif_c: [*c]c.netif) callconv(.C) void {
    const netif: *c.netif = netif_c;

    logger.info("netif status changed ip to {}", .{IPFormatter.new(netif.ip_addr)});
}

fn netif_init(netif_c: [*c]c.netif) callconv(.C) c.err_t {
    const netif: *c.netif = netif_c;
    const nic = @fieldParentPtr(NIC, "netif", netif);

    netif.linkoutput = netif_output;
    netif.output = c.etharp_output;
    netif.output_ip6 = c.ethip6_output;
    netif.mtu = nic.mtu; // c.ETHERNET_MTU;
    netif.flags = c.NETIF_FLAG_BROADCAST | c.NETIF_FLAG_ETHARP | c.NETIF_FLAG_ETHERNET | c.NETIF_FLAG_IGMP | c.NETIF_FLAG_MLD6;
    // c.MIB2_INIT_NETIF(netif, c.snmp_ifType_ethernet_csmacd, 100000000);
    std.mem.copy(u8, &netif.hwaddr, &nic.address.tuple);
    netif.hwaddr_len = c.ETH_HWADDR_LEN;
    return c.ERR_OK;
}

fn netif_output(netif_c: [*c]c.netif, pbuf_c: [*c]c.pbuf) callconv(.C) c.err_t {
    const netif: *c.netif = netif_c;
    const pbuf: *c.pbuf = pbuf_c;
    const nic = @fieldParentPtr(NIC, "netif", netif);

    // c.LINK_STATS_INC(lwip_stats.link.xmit);
    // Update SNMP stats (only if you use SNMP)
    // c.MIB2_STATS_NETIF_ADD(netif, ifoutoctets, pbuf.tot_len);
    // const unicast = ((pbuf.payload[0] & 0x01) == 0);
    // if (unicast) {
    //     c.MIB2_STATS_NETIF_INC(netif, ifoutucastpkts);
    // } else {
    //     c.MIB2_STATS_NETIF_INC(netif, ifoutnucastpkts);
    // }

    // TODO: lock_interrupts();

    logger.info("sending {} bytes via {s}...", .{ pbuf.tot_len, netif.name });

    if (nic.vtable.allocPacket(nic, pbuf.tot_len)) |packet| {
        // TODO: Handle length here
        var off: usize = 0;
        while (off < pbuf.tot_len) {
            const cnt = c.pbuf_copy_partial(pbuf, packet.ptr + off, @intCast(u15, pbuf.tot_len - off), @intCast(u15, off));
            if (cnt == 0) {
                logger.err("failed to copy network packet", .{});
                return c.ERR_BUF;
            }
            off += cnt;
        }
        if (!nic.vtable.send(nic, packet)) {
            logger.err("failed to send network packet!", .{});
        }
    } else {
        logger.err("failed to allocate network packet!", .{});
    }

    // TODO: unlock_interrupts();
    return c.ERR_OK;
}

pub fn start() !void {
    c.lwip_init();

    for (hal.network.getNICs()) |*nic, index| {
        std.log.info("initializing NIC '{c}{d}' (MAC={})...", .{ nic.interface.prefix(), index, nic.address });

        const netif = &nic.netif;

        _ = c.netif_add(
            netif,
            @ptrCast(*c.ip4_addr_t, c.IP4_ADDR_ANY), // ipaddr
            @ptrCast(*c.ip4_addr_t, c.IP4_ADDR_ANY), // netmask
            @ptrCast(*c.ip4_addr_t, c.IP4_ADDR_ANY), // gw
            null,
            netif_init,
            c.netif_input,
        ) orelse return error.OutOfMemory;

        _ = try std.fmt.bufPrint(&netif.name, "{c}{d}", .{ nic.interface.prefix(), index });

        c.netif_create_ip6_linklocal_address(netif, 1);
        netif.ip6_autoconfig_enabled = 1;
        c.netif_set_status_callback(netif, netif_status_callback);
        c.netif_set_default(netif);

        c.dhcp_set_struct(netif, &nic.dhcp);

        c.netif_set_up(netif);

        try lwipTry(c.dhcp_start(netif));

        c.netif_set_link_up(netif);
    }

    const network_thread = try ashet.scheduler.Thread.spawn(networkThread, null, .{});
    errdefer network_thread.kill();

    try network_thread.setName("ashet.network");
    try network_thread.start();
    network_thread.detach();
}

pub fn dumpStats() void {
    for (hal.network.getNICs()) |*nic| {
        logger.info("nic {s}: up={} link={} ip={} netmask={} gateway={} dhcp={}", .{
            nic.netif.name,
            (nic.netif.flags & c.NETIF_FLAG_UP) != 0,
            (nic.netif.flags & c.NETIF_FLAG_LINK_UP) != 0,
            IPFormatter.new(nic.netif.ip_addr),
            IPFormatter.new(nic.netif.netmask),
            IPFormatter.new(nic.netif.gw),
            c.dhcp_supplied_address(&nic.netif) != 0,
        });
    }
}

fn networkThread(_: ?*anyopaque) callconv(.C) u32 {
    while (true) {
        hal.network.fetchNicPackets();
        c.sys_check_timeouts();
        ashet.scheduler.yield();
    }
}

// Returns the current time in milliseconds, may be the same as sys_jiffies or at least based on it.
// Don't care for wraparound, this is only used for time diffs. Not implementing this function means
// you cannot use some modules (e.g. TCP timestamps, internal timeouts for NO_SYS==1).
export fn sys_now() u32 {
    // TODO: Implement system timer/rtc

    const T = struct {
        var oh_god_no: u64 = 0;
    };

    T.oh_god_no += 1;
    const time = @truncate(u32, T.oh_god_no << 4);
    // std.log.info("time = {}", .{time});
    return time;
}

const LwipError = error{
    /// Out of memory error.
    OutOfMemory,
    /// Buffer error.
    BufferError,
    /// Timeout.
    Timeout,
    /// Routing problem.
    Routing,
    /// Operation in progress
    InProgress,
    /// Illegal value.
    IllegalValue,
    /// Operation would block.
    WouldBlock,
    /// Address in use.
    AddressInUse,
    /// Already connecting.
    AlreadyConnecting,
    /// Conn already established.
    AlreadyConnected,
    /// Not connected.
    NotConnected,
    /// Low-level netif error
    LowlevelInterfaceError,
    /// Connection aborted.
    ConnectionAborted,
    /// Connection reset.
    ConnectionReset,
    /// Connection closed.
    ConnectionClosed,
    /// Illegal argument.
    IllegalArgument,

    /// Unexpected error code
    Unexpected,
};

fn lwipTry(err: c.err_t) LwipError!void {
    return switch (err) {
        c.ERR_OK => {},
        c.ERR_MEM => LwipError.OutOfMemory,
        c.ERR_BUF => LwipError.BufferError,
        c.ERR_TIMEOUT => LwipError.Timeout,
        c.ERR_RTE => LwipError.Routing,
        c.ERR_INPROGRESS => LwipError.InProgress,
        c.ERR_VAL => LwipError.IllegalValue,
        c.ERR_WOULDBLOCK => LwipError.WouldBlock,
        c.ERR_USE => LwipError.AddressInUse,
        c.ERR_ALREADY => LwipError.AlreadyConnecting,
        c.ERR_ISCONN => LwipError.AlreadyConnected,
        c.ERR_CONN => LwipError.NotConnected,
        c.ERR_IF => LwipError.LowlevelInterfaceError,
        c.ERR_ABRT => LwipError.ConnectionAborted,
        c.ERR_RST => LwipError.ConnectionReset,
        c.ERR_CLSD => LwipError.ConnectionClosed,
        c.ERR_ARG => LwipError.IllegalArgument,
        else => LwipError.Unexpected,
    };
}

pub const EndPoint = abi.EndPoint;
pub const IP = abi.IP;

fn mapIP(ip: IP) c.ip_addr_t {
    return switch (ip.type) {
        .ipv4 => c.ip_addr_t{
            .type = c.IPADDR_TYPE_V4,
            .u_addr = .{ .ip4 = .{ .addr = @bitCast(u32, ip.addr.v4.addr) } },
        },
        .ipv6 => c.ip_addr_t{
            .type = c.IPADDR_TYPE_V6,
            .u_addr = .{ .ip6 = .{ .addr = @bitCast([4]u32, ip.addr.v6.addr), .zone = ip.addr.v6.zone } },
        },
    };
}

pub const udp = struct {
    const max_sockets = @intCast(usize, c.MEMP_NUM_UDP_PCB);
    const Socket = abi.UdpSocket;

    var pool: astd.IndexPool(u32, max_sockets) = .{};
    var sockets: [max_sockets]*c.udp_pcb = undefined;

    fn unmap(sock: Socket) error{InvalidHandle}!*c.udp_pcb {
        if (sock == .invalid)
            return error.InvalidHandle;
        const index = @enumToInt(sock);
        if (index >= max_sockets)
            return error.InvalidHandle;
        if (!pool.alive(index))
            return error.InvalidHandle;
        return sockets[index];
    }

    pub fn createSocket() !Socket {
        const index = pool.alloc() orelse return error.SystemResources;
        errdefer pool.free(index);

        const pcb = c.udp_new() orelse return error.SystemResources;
        sockets[index] = pcb;

        c.udp_recv(pcb, handleIncomingPacket, null);

        return @intToEnum(Socket, index);
    }

    fn handleIncomingPacket(arg: ?*anyopaque, pcb_c: [*c]c.udp_pcb, pbuf_c: [*c]c.pbuf, addr_c: [*c]const c.ip_addr_t, port: u16) callconv(.C) void {
        _ = arg;
        _ = pcb_c;
        _ = pbuf_c;
        _ = addr_c;
        _ = port;

        logger.info("received some data via udp!", .{});
    }

    pub fn destroySocket(sock: Socket) void {
        const pcb = unmap(sock) catch return;
        const index = @enumToInt(sock);
        c.udp_remove(pcb);
        sockets[index] = undefined;
        pool.free(index);
    }

    pub fn bind(sock: Socket, ep: EndPoint) !void {
        const pcb = try unmap(sock);
        try lwipTry(c.udp_bind(pcb, &mapIP(ep.ip), ep.port));
    }

    pub fn connect(sock: Socket, ep: EndPoint) !void {
        const pcb = try unmap(sock);
        try lwipTry(c.udp_connect(pcb, &mapIP(ep.ip), ep.port));
    }

    pub fn disconnect(sock: Socket) !void {
        const pcb = try unmap(sock);
        c.udp_disconnect(pcb);
    }

    pub fn send(sock: Socket, data: []const u8) !usize {
        const pcb = try unmap(sock);

        const stripped_len = std.math.cast(u16, data.len) orelse return error.OutOfMemory;

        const pbuf = c.pbuf_alloc(c.PBUF_TRANSPORT, stripped_len, c.PBUF_POOL) orelse return error.OutOfMemory;
        defer _ = c.pbuf_free(pbuf);

        try appendToPBUF(pbuf, data);

        try lwipTry(c.udp_send(pcb, pbuf));

        return data.len;
    }

    pub fn sendTo(sock: Socket, receiver: EndPoint, data: []const u8) !usize {
        const pcb = try unmap(sock);

        const stripped_len = std.math.cast(u16, data.len) orelse return error.OutOfMemory;

        const pbuf = c.pbuf_alloc(c.PBUF_TRANSPORT, stripped_len, c.PBUF_POOL) orelse return error.OutOfMemory;
        defer _ = c.pbuf_free(pbuf);

        try appendToPBUF(pbuf, data);

        try lwipTry(c.udp_sendto(pcb, pbuf, &mapIP(receiver.ip), receiver.port));

        return data.len;
    }

    pub fn receive(sock: Socket, data: []u8) !usize {
        const pcb = try unmap(sock);
        _ = pcb;
        _ = data;
        @panic("not implemented yet!");
    }

    pub fn receiveFrom(sock: Socket, sender: *EndPoint, data: []u8) !usize {
        const pcb = try unmap(sock);
        _ = pcb;
        _ = sender;
        _ = data;
        @panic("not implemented yet!");
    }
};
