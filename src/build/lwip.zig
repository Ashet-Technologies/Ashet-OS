const std = @import("std");

const flags = [_][]const u8{ "-std=c99", "-fno-sanitize=undefined" };
const files = [_][]const u8{
    // Core files
    "vendor/lwip/src/core/init.c",
    "vendor/lwip/src/core/udp.c",
    "vendor/lwip/src/core/inet_chksum.c",
    "vendor/lwip/src/core/altcp_alloc.c",
    "vendor/lwip/src/core/stats.c",
    "vendor/lwip/src/core/altcp.c",
    "vendor/lwip/src/core/mem.c",
    "vendor/lwip/src/core/ip.c",
    "vendor/lwip/src/core/pbuf.c",
    "vendor/lwip/src/core/netif.c",
    "vendor/lwip/src/core/tcp_out.c",
    "vendor/lwip/src/core/dns.c",
    "vendor/lwip/src/core/tcp_in.c",
    "vendor/lwip/src/core/memp.c",
    "vendor/lwip/src/core/tcp.c",
    "vendor/lwip/src/core/sys.c",
    "vendor/lwip/src/core/def.c",
    "vendor/lwip/src/core/timeouts.c",
    "vendor/lwip/src/core/raw.c",
    "vendor/lwip/src/core/altcp_tcp.c",

    // IPv4 implementation:
    "vendor/lwip/src/core/ipv4/dhcp.c",
    "vendor/lwip/src/core/ipv4/autoip.c",
    "vendor/lwip/src/core/ipv4/ip4_frag.c",
    "vendor/lwip/src/core/ipv4/etharp.c",
    "vendor/lwip/src/core/ipv4/ip4.c",
    "vendor/lwip/src/core/ipv4/ip4_addr.c",
    "vendor/lwip/src/core/ipv4/igmp.c",
    "vendor/lwip/src/core/ipv4/icmp.c",

    // IPv6 implementation:
    "vendor/lwip/src/core/ipv6/icmp6.c",
    "vendor/lwip/src/core/ipv6/ip6_addr.c",
    "vendor/lwip/src/core/ipv6/ip6.c",
    "vendor/lwip/src/core/ipv6/ip6_frag.c",
    "vendor/lwip/src/core/ipv6/mld6.c",
    "vendor/lwip/src/core/ipv6/dhcp6.c",
    "vendor/lwip/src/core/ipv6/inet6.c",
    "vendor/lwip/src/core/ipv6/ethip6.c",
    "vendor/lwip/src/core/ipv6/nd6.c",

    // Interfaces:
    "vendor/lwip/src/netif/bridgeif.c",
    "vendor/lwip/src/netif/ethernet.c",
    "vendor/lwip/src/netif/slipif.c",
    "vendor/lwip/src/netif/bridgeif_fdb.c",

    // sequential APIs
    // "vendor/lwip/src/api/err.c",
    // "vendor/lwip/src/api/api_msg.c",
    // "vendor/lwip/src/api/netifapi.c",
    // "vendor/lwip/src/api/sockets.c",
    // "vendor/lwip/src/api/netbuf.c",
    // "vendor/lwip/src/api/api_lib.c",
    // "vendor/lwip/src/api/tcpip.c",
    // "vendor/lwip/src/api/netdb.c",
    // "vendor/lwip/src/api/if_api.c",

    // 6LoWPAN
    "vendor/lwip/src/netif/lowpan6.c",
    "vendor/lwip/src/netif/lowpan6_ble.c",
    "vendor/lwip/src/netif/lowpan6_common.c",
    "vendor/lwip/src/netif/zepif.c",

    // PPP
    // "vendor/lwip/src/netif/ppp/polarssl/arc4.c",
    // "vendor/lwip/src/netif/ppp/polarssl/des.c",
    // "vendor/lwip/src/netif/ppp/polarssl/md4.c",
    // "vendor/lwip/src/netif/ppp/polarssl/sha1.c",
    // "vendor/lwip/src/netif/ppp/polarssl/md5.c",
    // "vendor/lwip/src/netif/ppp/ipcp.c",
    // "vendor/lwip/src/netif/ppp/magic.c",
    // "vendor/lwip/src/netif/ppp/pppoe.c",
    // "vendor/lwip/src/netif/ppp/mppe.c",
    // "vendor/lwip/src/netif/ppp/multilink.c",
    // "vendor/lwip/src/netif/ppp/chap-new.c",
    // "vendor/lwip/src/netif/ppp/auth.c",
    // "vendor/lwip/src/netif/ppp/chap_ms.c",
    // "vendor/lwip/src/netif/ppp/ipv6cp.c",
    // "vendor/lwip/src/netif/ppp/chap-md5.c",
    // "vendor/lwip/src/netif/ppp/upap.c",
    // "vendor/lwip/src/netif/ppp/pppapi.c",
    // "vendor/lwip/src/netif/ppp/pppos.c",
    // "vendor/lwip/src/netif/ppp/eap.c",
    // "vendor/lwip/src/netif/ppp/pppol2tp.c",
    // "vendor/lwip/src/netif/ppp/demand.c",
    // "vendor/lwip/src/netif/ppp/fsm.c",
    // "vendor/lwip/src/netif/ppp/eui64.c",
    // "vendor/lwip/src/netif/ppp/ccp.c",
    // "vendor/lwip/src/netif/ppp/pppcrypt.c",
    // "vendor/lwip/src/netif/ppp/utils.c",
    // "vendor/lwip/src/netif/ppp/vj.c",
    // "vendor/lwip/src/netif/ppp/lcp.c",
    // "vendor/lwip/src/netif/ppp/ppp.c",
    // "vendor/lwip/src/netif/ppp/ecp.c",
};

pub fn create(b: *std.build.Builder, target: std.zig.CrossTarget, optimize: std.builtin.OptimizeMode) *std.build.LibExeObjStep {
    const lib = b.addStaticLibrary(.{
        .name = "lwip",
        .target = target,
        .optimize = optimize,
    });

    lib.addCSourceFiles(&files, &flags);

    setup(lib);

    return lib;
}

pub fn setup(dst: *std.build.LibExeObjStep) void {
    dst.addIncludePath(.{ .path = "vendor/lwip/src/include" });
    dst.addIncludePath(.{ .path = "src/kernel/components/network/include" });
}
