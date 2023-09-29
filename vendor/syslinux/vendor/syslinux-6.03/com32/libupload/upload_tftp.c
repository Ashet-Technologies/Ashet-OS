/*
 * TFTP data output backend
 */

#include <string.h>
#include <stdio.h>
#include <syslinux/pxe.h>
#include <syslinux/config.h>
#include <netinet/in.h>
#include <sys/times.h>
#include "upload_backend.h"

enum tftp_opcode {
    TFTP_RRQ	= 1,
    TFTP_WRQ	= 2,
    TFTP_DATA	= 3,
    TFTP_ACK	= 4,
    TFTP_ERROR	= 5,
};

struct tftp_error {
	uint16_t opcode;
	uint16_t errcode;
	char errmsg[0];
} __attribute__ (( packed ));

struct tftp_state {
    uint32_t my_ip;
    uint32_t srv_ip;
    uint32_t srv_gw;
    uint16_t my_port;
    uint16_t srv_port;
    uint16_t seq;
};

const char *tftp_string_error_message[]={
"",
"File not found",
"Access Denied",
"Disk Full",
"Illegal Operation",
"Unknown Transfert ID",
"File already exists",
"Unknown User",
"Negociation failed",
"Unable to resolve hostname", // not in RFC
"Unable to connect", // not in RFC
"No Error",
};

#define RCV_BUF	2048

static int send_ack_packet(struct tftp_state *tftp,
			   const void *pkt, size_t len)
{
    t_PXENV_UDP_WRITE *uw;
    t_PXENV_UDP_READ  *ur;
    clock_t start;
    static const clock_t timeouts[] = {
	2, 2, 3, 3, 4, 5, 6, 7, 9, 10, 12, 15, 18, 21, 26, 31,
	37, 44, 53, 64, 77, 92, 110, 132, 159, 191, 229, 0
    };
    const clock_t *timeout;
    int err = -1;

    uw = lmalloc(sizeof *uw + len);
    ur = lmalloc(sizeof *ur + RCV_BUF);

    for (timeout = timeouts ; *timeout ; timeout++) {
	memset(uw, 0, sizeof *uw);
	memcpy(uw+1, pkt, len);
	uw->ip = tftp->srv_ip;
	uw->gw = tftp->srv_gw;
	uw->src_port = tftp->my_port;
	uw->dst_port = tftp->srv_port ? tftp->srv_port : htons(69);
	uw->buffer_size = len;
	uw->buffer = FAR_PTR(uw+1);

	pxe_call(PXENV_UDP_WRITE, uw);

	start = times(NULL);

	do {
	    memset(ur, 0, sizeof *ur);
	    ur->src_ip = tftp->srv_ip;
	    ur->dest_ip = tftp->my_ip;
	    ur->s_port = tftp->srv_port;
	    ur->d_port = tftp->my_port;
	    ur->buffer_size = RCV_BUF;
	    ur->buffer = FAR_PTR(ur+1);

	    err = pxe_call(PXENV_UDP_READ, ur);

	    if (!err &&	ur->status == PXENV_STATUS_SUCCESS &&
		tftp->srv_ip == ur->src_ip &&
		(tftp->srv_port == 0 ||
		 tftp->srv_port == ur->s_port)) {
		uint16_t *xb = (uint16_t *)(ur+1);
		if (ntohs(xb[0]) == TFTP_ACK &&
		    ntohs(xb[1]) == tftp->seq) {
		    tftp->srv_port = ur->s_port;
		    err = TFTP_OK;		/* All good! */
		    goto done;
		} else if (ntohs(xb[0]) == TFTP_ERROR) {
		    struct tftp_error *te = (struct tftp_error *)(ur+1);
		    if (te->errcode == TFTP_ERR_UNKNOWN_ERROR) {
		    	tftp_string_error_message[TFTP_ERR_UNKNOWN_ERROR]=strdup(te->errmsg);
		    }
 		    err=-ntohs(te->errcode); // Return the associated error code
		    goto done;
		}
	    }
	} while ((clock_t)(times(NULL) - start) < *timeout);
    }

done:
    lfree(ur);
    lfree(uw);

    return err;
}

static int upload_tftp_write(struct upload_backend *be)
{
    static uint16_t local_port = 0x4000;
    struct tftp_state tftp;
    char buffer[512+4+6];
    int nlen;
    int err=TFTP_OK;
    const union syslinux_derivative_info *sdi =
	syslinux_derivative_info();
    const char *data = be->outbuf;
    size_t len = be->zbytes;
    size_t chunk;

    tftp.my_ip    = sdi->pxe.myip;
    tftp.my_port  = htons(local_port++);
    tftp.srv_gw   = ((tftp.srv_ip ^ tftp.my_ip) & sdi->pxe.ipinfo->netmask)
	? sdi->pxe.ipinfo->gateway : 0;
    tftp.srv_port = 0;
    tftp.seq      = 0;

    if (be->argv[1]) {
	tftp.srv_ip   = pxe_dns(be->argv[1]);
	if (!tftp.srv_ip) {
//	    printf("\nUnable to resolve hostname: %s\n", be->argv[1]);
	    return -TFTP_ERR_UNABLE_TO_RESOLVE;
	}
    } else {
	tftp.srv_ip   = sdi->pxe.ipinfo->serverip;
	if (!tftp.srv_ip) {
//	    printf("\nNo server IP address\n");
	    return -TFTP_ERR_UNABLE_TO_CONNECT;
	}
    }

/*    printf("server %u.%u.%u.%u... ",
	   ((uint8_t *)&tftp.srv_ip)[0],
	   ((uint8_t *)&tftp.srv_ip)[1],
	   ((uint8_t *)&tftp.srv_ip)[2],
	   ((uint8_t *)&tftp.srv_ip)[3]);*/

    buffer[0] = 0;
    buffer[1] = TFTP_WRQ;
    nlen = strlcpy(buffer+2, be->argv[0], 512);
    memcpy(buffer+3+nlen, "octet", 6);

    if ((err=send_ack_packet(&tftp, buffer, 2+nlen+1+6))!=TFTP_OK)
	return err;

    do {
	chunk = len >= 512 ? 512 : len;

	buffer[1] = TFTP_DATA;
	*((uint16_t *)(buffer+2)) = htons(++tftp.seq);
	memcpy(buffer+4, data, chunk);
	data += chunk;
	len -= chunk;

	if ((err=send_ack_packet(&tftp, buffer, chunk+4))!=TFTP_OK)
	    return err;
    } while (chunk == 512);

    return TFTP_OK;
}

struct upload_backend upload_tftp = {
    .name       = "tftp",
    .helpmsg    = "filename [tftp_server]",
    .minargs    = 1,
    .write      = upload_tftp_write,
};
