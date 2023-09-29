#include <syslinux/pxe_api.h>
#include <lwip/api.h>
#include <lwip/tcpip.h>
#include <lwip/dns.h>
#include <core.h>
#include <net.h>
#include "pxe.h"

#include <dprintf.h>

const struct url_scheme url_schemes[] = {
    { "tftp", tftp_open, 0 },
    { "http", http_open, O_DIRECTORY },
    { "ftp",  ftp_open,  O_DIRECTORY },
    { NULL, NULL, 0 },
};

/**
 * Open a socket
 *
 * @param:socket, the socket to open
 *
 * @out: error code, 0 on success, -1 on failure
 */
int core_udp_open(struct pxe_pvt_inode *socket)
{
    struct net_private_lwip *priv = &socket->net.lwip;
    int err;

    priv->conn = netconn_new(NETCONN_UDP);
    if (!priv->conn)
	return -1;

    priv->conn->recv_timeout = 15; /* A 15 ms recv timeout... */
    err = netconn_bind(priv->conn, NULL, 0);
    if (err) {
	ddprintf("netconn_bind error %d\n", err);
	return -1;
    }

    return 0;
}

/**
 * Close a socket
 *
 * @param:socket, the socket to open
 */
void core_udp_close(struct pxe_pvt_inode *socket)
{
    struct net_private_lwip *priv = &socket->net.lwip;

    if (priv->conn) {
	netconn_delete(priv->conn);
	priv->conn = NULL;
    }
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
    struct net_private_lwip *priv = &socket->net.lwip;
    struct ip_addr addr;

    dprintf("net_core_connect: %08X %04X\n", ntohl(ip), port);
    addr.addr = ip;
    netconn_connect(priv->conn, &addr, port);
}

/**
 * Tear down a connection on an open socket
 *
 * @param:socket, the open socket
 */
void core_udp_disconnect(struct pxe_pvt_inode *socket)
{
    struct net_private_lwip *priv = &socket->net.lwip;
    netconn_disconnect(priv->conn);
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
    struct net_private_lwip *priv = &socket->net.lwip;
    struct netbuf *nbuf;
    u16_t nbuf_len;
    int err;

    err = netconn_recv(priv->conn, &nbuf);
    if (err)
	return err;

    if (!nbuf)
	return -1;

    *src_ip = netbuf_fromaddr(nbuf)->addr;
    *src_port = netbuf_fromport(nbuf);

    netbuf_first(nbuf);		/* XXX needed? */
    nbuf_len = netbuf_len(nbuf);
    if (nbuf_len <= *buf_len)
	netbuf_copy(nbuf, buf, nbuf_len);
    else
	nbuf_len = 0; /* impossible mtu < PKTBUF_SIZE */
    netbuf_delete(nbuf);

    *buf_len = nbuf_len;
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
    struct netconn *conn = socket->net.lwip.conn;
    struct netbuf *nbuf;
    void *pbuf;
    int err;

    nbuf = netbuf_new();
    if (!nbuf) {
	ddprintf("netbuf allocation error\n");
	return;
    }

    pbuf = netbuf_alloc(nbuf, len);
    if (!pbuf) {
	ddprintf("pbuf allocation error\n");
	goto out;
    }

    memcpy(pbuf, data, len);

    err = netconn_send(conn, nbuf);
    if (err) {
	ddprintf("netconn_send error %d\n", err);
	goto out;
    }

out:
    netbuf_delete(nbuf);
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
void core_udp_sendto(struct pxe_pvt_inode *socket, const void *data,
		     size_t len, uint32_t ip, uint16_t port)
{
    struct netconn *conn = socket->net.lwip.conn;
    struct ip_addr addr;
    struct netbuf *nbuf;
    void *pbuf;
    int err;

    nbuf = netbuf_new();
    if (!nbuf) {
	ddprintf("netbuf allocation error\n");
	return;
    }

    pbuf = netbuf_alloc(nbuf, len);
    if (!pbuf) {
	ddprintf("pbuf allocation error\n");
	goto out;
    }

    memcpy(pbuf, data, len);

    dprintf("core_udp_sendto: %08X %04X\n", ntohl(ip), port);
    addr.addr = ip;

    err = netconn_sendto(conn, nbuf, &addr, port);
    if (err) {
	ddprintf("netconn_sendto error %d\n", err);
	goto out;
    }

out:
    netbuf_delete(nbuf);
}

/**
 * Network stack-specific initialization
 */
void net_core_init(void)
{
    int err;
    int i;

    http_bake_cookies();

    /* Initialize lwip */
    tcpip_init(NULL, NULL);

    /* Start up the undi driver for lwip */
    err = undiif_start(IPInfo.myip, IPInfo.netmask, IPInfo.gateway);
    if (err) {
       ddprintf("undiif driver failed to start: %d\n", err);
       kaboom();
    }

    for (i = 0; i < DNS_MAX_SERVERS; i++) {
	/* Transfer the DNS information to lwip */
	dns_setserver(i, (struct ip_addr *)&dns_server[i]);
    }
}

void probe_undi(void)
{
    /* Probe UNDI information */
    pxe_call(PXENV_UNDI_GET_INFORMATION, &pxe_undi_info);
    pxe_call(PXENV_UNDI_GET_IFACE_INFO,  &pxe_undi_iface);

    ddprintf("UNDI: baseio %04x int %d MTU %d type %d \"%s\" flags 0x%x\n",
	   pxe_undi_info.BaseIo, pxe_undi_info.IntNumber,
	   pxe_undi_info.MaxTranUnit, pxe_undi_info.HwType,
	   pxe_undi_iface.IfaceType, pxe_undi_iface.ServiceFlags);
}

int core_tcp_open(struct pxe_pvt_inode *socket)
{
    socket->net.lwip.conn = netconn_new(NETCONN_TCP);
    if (!socket->net.lwip.conn)
	return -1;

    return 0;
}
int core_tcp_connect(struct pxe_pvt_inode *socket, uint32_t ip, uint16_t port)
{
    struct ip_addr addr;
    err_t err;

    addr.addr = ip;
    err = netconn_connect(socket->net.lwip.conn, &addr, port);
    if (err) {
	printf("netconn_connect error %d\n", err);
	return -1;
    }

    return 0;
}

int core_tcp_write(struct pxe_pvt_inode *socket, const void *data, size_t len,
		   bool copy)
{
    err_t err;
    u8_t flags = copy ? NETCONN_COPY : NETCONN_NOCOPY;

    err = netconn_write(socket->net.lwip.conn, data, len, flags);
    if (err) {
	printf("netconn_write failed: %d\n", err);
	return -1;
    }

    return 0;
}

void core_tcp_close_file(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);

    if (socket->net.lwip.conn) {
	netconn_delete(socket->net.lwip.conn);
	socket->net.lwip.conn = NULL;
    }
    if (socket->net.lwip.buf) {
	netbuf_delete(socket->net.lwip.buf);
        socket->net.lwip.buf = NULL;
    }
}

bool core_tcp_is_connected(struct pxe_pvt_inode *socket)
{
    if (socket->net.lwip.conn)
	return true;

    return false;
}

void core_tcp_fill_buffer(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    void *data;
    u16_t len;
    err_t err;

    /* Clean up or advance an inuse netbuf */
    if (socket->net.lwip.buf) {
	if (netbuf_next(socket->net.lwip.buf) < 0) {
	    netbuf_delete(socket->net.lwip.buf);
	    socket->net.lwip.buf = NULL;
	}
    }
    /* If needed get a new netbuf */
    if (!socket->net.lwip.buf) {
	err = netconn_recv(socket->net.lwip.conn, &(socket->net.lwip.buf));
	if (!socket->net.lwip.buf || err) {
	    socket->tftp_goteof = 1;
	    if (inode->size == -1)
		inode->size = socket->tftp_filepos;
	    socket->ops->close(inode);
	    return;
	}
    }
    /* Report the current fragment of the netbuf */
    err = netbuf_data(socket->net.lwip.buf, &data, &len);
    if (err) {
	printf("netbuf_data err: %d\n", err);
	kaboom();
    }
    socket->tftp_dataptr = data;
    socket->tftp_filepos += len;
    socket->tftp_bytesleft = len;
    return;
}
