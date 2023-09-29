#include <syslinux/pxe_api.h>
#include <com32.h>
#include <core.h>
#include <net.h>
#include <pxe.h>
#include <minmax.h>

/* Common receive buffer */
static __lowmem char packet_buf[PKTBUF_SIZE] __aligned(16);

extern uint16_t get_port(void);
extern void free_port(uint16_t);

const struct url_scheme url_schemes[] = {
    { "tftp", tftp_open, 0 },
    { NULL, NULL, 0 }
};

/**
 * Open a socket
 *
 * @param:socket, the socket to open
 *
 * @out: error code, 0 on success, -1 on failure
 */
int core_udp_open(struct pxe_pvt_inode *socket __unused)
{
    struct net_private_tftp *priv = &socket->net.tftp;

    /* Allocate local UDP port number */
    priv->localport = get_port();

    return 0;
}

/**
 * Close a socket
 *
 * @param:socket, the socket to open
 */
void core_udp_close(struct pxe_pvt_inode *socket)
{
    struct net_private_tftp *priv = &socket->net.tftp;

    if (priv->localport)
	free_port(priv->localport);
}

/**
 * Establish a connection on an open socket
 *
 * @param:socket, the open socket
 * @param:ip, the ip address
 * @param:port, the port number, host-byte order
 */
void core_udp_connect(struct pxe_pvt_inode *socket, uint32_t ip,
		      uint16_t port)
{
    struct net_private_tftp *priv = &socket->net.tftp;

    socket->tftp_remoteport = htons(port);
    priv->remoteip = ip;

}

/**
 * Tear down a connection on an open socket
 *
 * @param:socket, the open socket
 */
void core_udp_disconnect(struct pxe_pvt_inode *socket __unused)
{
}

/**
 * Read data from the network stack
 *
 * @param:socket, the open socket
 * @param:buf, location of buffer to store data
 * @param:buf_len, size of buffer

 * @out: src_ip, ip address of the data source
 * @out: src_port, port number of the data source, host-byte order
 */
int core_udp_recv(struct pxe_pvt_inode *socket, void *buf, uint16_t *buf_len,
		  uint32_t *src_ip, uint16_t *src_port)
{
    static __lowmem struct s_PXENV_UDP_READ  udp_read;
    struct net_private_tftp *priv = &socket->net.tftp;
    uint16_t bytes;
    int err;

    udp_read.status      = 0;
    udp_read.buffer      = FAR_PTR(packet_buf);
    udp_read.buffer_size = PKTBUF_SIZE;
    udp_read.dest_ip     = IPInfo.myip;
    udp_read.d_port      = priv->localport;

    err = pxe_call(PXENV_UDP_READ, &udp_read);
    if (err)
	return err;

    if (udp_read.status)
	return udp_read.status;

    bytes = min(udp_read.buffer_size, *buf_len);
    memcpy(buf, packet_buf, bytes);

    *src_ip = udp_read.src_ip;
    *src_port = ntohs(udp_read.s_port);
    *buf_len = bytes;

    return 0;
}

/**
 * Send a UDP packet.
 *
 * @param:socket, the open socket
 * @param:data, data buffer to send
 * @param:len, size of data bufer
 */
void core_udp_send(struct pxe_pvt_inode *socket, const void *data, size_t len)
{
    static __lowmem struct s_PXENV_UDP_WRITE udp_write;
    struct net_private_tftp *priv = &socket->net.tftp;
    void *lbuf;
    uint16_t tid;

    lbuf = lmalloc(len);
    if (!lbuf)
	return;

    memcpy(lbuf, data, len);

    tid = priv->localport;   /* TID(local port No) */
    udp_write.buffer    = FAR_PTR(lbuf);
    udp_write.ip        = priv->remoteip;
    udp_write.gw        = gateway(udp_write.ip);
    udp_write.src_port  = tid;
    udp_write.dst_port  = socket->tftp_remoteport;
    udp_write.buffer_size = len;

    pxe_call(PXENV_UDP_WRITE, &udp_write);

    lfree(lbuf);
}

/**
 * Send a UDP packet to a destination
 *
 * @param:socket, the open socket
 * @param:data, data buffer to send
 * @param:len, size of data bufer
 * @param:ip, the ip address
 * @param:port, the port number, host-byte order
 */
void core_udp_sendto(struct pxe_pvt_inode *socket, const void *data, size_t len,
		     uint32_t ip, uint16_t port)
{
    static __lowmem struct s_PXENV_UDP_WRITE udp_write;
    struct net_private_tftp *priv = &socket->net.tftp;
    void *lbuf;
    uint16_t tid;

    lbuf = lmalloc(len);
    if (!lbuf)
	return;

    memcpy(lbuf, data, len);

    tid = priv->localport;   /* TID(local port No) */
    udp_write.buffer    = FAR_PTR(lbuf);
    udp_write.ip        = ip;
    udp_write.gw        = gateway(udp_write.ip);
    udp_write.src_port  = tid;
    udp_write.dst_port  = htons(port);
    udp_write.buffer_size = len;

    pxe_call(PXENV_UDP_WRITE, &udp_write);

    lfree(lbuf);
}


/**
 * Network stack-specific initialization
 *
 * Initialize UDP stack
 */
void net_core_init(void)
{
    int err;
    static __lowmem struct s_PXENV_UDP_OPEN udp_open;
    udp_open.src_ip = IPInfo.myip;
    err = pxe_call(PXENV_UDP_OPEN, &udp_open);
    if (err || udp_open.status) {
        printf("Failed to initialize UDP stack ");
        printf("%d\n", udp_open.status);
	kaboom();
    }
}

void probe_undi(void)
{
}

void pxe_init_isr(void)
{
}

int reset_pxe(void)
{
    static __lowmem struct s_PXENV_UDP_CLOSE udp_close;
    int err = 0;

    pxe_idle_cleanup();

    pxe_call(PXENV_UDP_CLOSE, &udp_close);

    return err;
}
