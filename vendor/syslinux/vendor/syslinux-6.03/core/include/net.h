#ifndef _NET_H
#define _NET_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

void net_core_init(void);
void net_parse_dhcp(void);

struct pxe_pvt_inode;

int core_udp_open(struct pxe_pvt_inode *socket);
void core_udp_close(struct pxe_pvt_inode *socket);

void core_udp_connect(struct pxe_pvt_inode *socket,
		      uint32_t ip, uint16_t port);
void core_udp_disconnect(struct pxe_pvt_inode *socket);

int core_udp_recv(struct pxe_pvt_inode *socket, void *buf, uint16_t *buf_len,
		  uint32_t *src_ip, uint16_t *src_port);

void core_udp_send(struct pxe_pvt_inode *socket,
		   const void *data, size_t len);

void core_udp_sendto(struct pxe_pvt_inode *socket, const void *data, size_t len,
		     uint32_t ip, uint16_t port);

void probe_undi(void);
void pxe_init_isr(void);

struct inode;

int core_tcp_open(struct pxe_pvt_inode *socket);
int core_tcp_connect(struct pxe_pvt_inode *socket, uint32_t ip, uint16_t port);
bool core_tcp_is_connected(struct pxe_pvt_inode *socket);
int core_tcp_write(struct pxe_pvt_inode *socket, const void *data,
		   size_t len, bool copy);
void core_tcp_close_file(struct inode *inode);
void core_tcp_fill_buffer(struct inode *inode);

#endif /* _NET_H */
