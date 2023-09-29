#include <minmax.h>
#include <net.h>
#include "pxe.h"
#include "url.h"
#include "tftp.h"

const uint8_t TimeoutTable[] = {
    2, 2, 3, 3, 4, 5, 6, 7, 9, 10, 12, 15, 18, 21, 26, 31, 37, 44,
    53, 64, 77, 92, 110, 132, 159, 191, 229, 255, 255, 255, 255, 0
};
struct tftp_packet {
    uint16_t opcode;
    uint16_t serial;
    char data[];
};

static void tftp_error(struct inode *file, uint16_t errnum,
		       const char *errstr);

static void tftp_close_file(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    if (!socket->tftp_goteof) {
	tftp_error(inode, 0, "No error, file close");
    }
    core_udp_close(socket);
}

/**
 * Send an ERROR packet.  This is used to terminate a connection.
 *
 * @inode:	Inode structure
 * @errnum:	Error number (network byte order)
 * @errstr:	Error string (included in packet)
 */
static void tftp_error(struct inode *inode, uint16_t errnum,
		       const char *errstr)
{
    static struct {
	uint16_t err_op;
	uint16_t err_num;
	char err_msg[64];
    } __packed err_buf;
    int len = min(strlen(errstr), sizeof(err_buf.err_msg)-1);
    struct pxe_pvt_inode *socket = PVT(inode);

    err_buf.err_op  = TFTP_ERROR;
    err_buf.err_num = errnum;
    memcpy(err_buf.err_msg, errstr, len);
    err_buf.err_msg[len] = '\0';

    core_udp_send(socket, &err_buf, 4 + len + 1);
}

/**
 * Send ACK packet. This is a common operation and so is worth canning.
 *
 * @param: inode,   Inode pointer
 * @param: ack_num, Packet # to ack (host byte order)
 *
 */
static void ack_packet(struct inode *inode, uint16_t ack_num)
{
    static uint16_t ack_packet_buf[2];
    struct pxe_pvt_inode *socket = PVT(inode);

    /* Packet number to ack */
    ack_packet_buf[0]     = TFTP_ACK;
    ack_packet_buf[1]     = htons(ack_num);

    core_udp_send(socket, ack_packet_buf, 4);
}

/*
 * Get a fresh packet if the buffer is drained, and we haven't hit
 * EOF yet.  The buffer should be filled immediately after draining!
 */
static void tftp_get_packet(struct inode *inode)
{
    uint16_t last_pkt;
    const uint8_t *timeout_ptr;
    uint8_t timeout;
    uint16_t buffersize;
    uint16_t serial;
    jiffies_t oldtime;
    struct tftp_packet *pkt = NULL;
    uint16_t buf_len;
    struct pxe_pvt_inode *socket = PVT(inode);
    uint16_t src_port;
    uint32_t src_ip;
    int err;

    /*
     * Start by ACKing the previous packet; this should cause
     * the next packet to be sent.
     */
    timeout_ptr = TimeoutTable;
    timeout = *timeout_ptr++;
    oldtime = jiffies();

 ack_again:
    ack_packet(inode, socket->tftp_lastpkt);

    while (timeout) {
	buf_len = socket->tftp_blksize + 4;
	err = core_udp_recv(socket, socket->tftp_pktbuf, &buf_len,
			    &src_ip, &src_port);
	if (err) {
	    jiffies_t now = jiffies();

	    if (now-oldtime >= timeout) {
		oldtime = now;
		timeout = *timeout_ptr++;
		if (!timeout)
		    break;
		goto ack_again;
	    }
            continue;
	}

	if (buf_len < 4)	/* Bad size for a DATA packet */
	    continue;

        pkt = (struct tftp_packet *)(socket->tftp_pktbuf);
        if (pkt->opcode != TFTP_DATA)    /* Not a data packet */
            continue;

        /* If goes here, recevie OK, break */
        break;
    }

    /* time runs out */
    if (timeout == 0)
	kaboom();

    last_pkt = socket->tftp_lastpkt;
    last_pkt++;
    serial = ntohs(pkt->serial);
    if (serial != last_pkt) {
        /*
         * Wrong packet, ACK the packet and try again.
         * This is presumably because the ACK got lost,
         * so the server just resent the previous packet.
         */
#if 0
	printf("Wrong packet, wanted %04x, got %04x\n", \
               htons(last_pkt), htons(*(uint16_t *)(data+2)));
#endif
        goto ack_again;
    }

    /* It's the packet we want.  We're also EOF if the size < blocksize */
    socket->tftp_lastpkt = last_pkt;    /* Update last packet number */
    buffersize = buf_len - 4;		/* Skip TFTP header */
    socket->tftp_dataptr = socket->tftp_pktbuf + 4;
    socket->tftp_filepos += buffersize;
    socket->tftp_bytesleft = buffersize;
    if (buffersize < socket->tftp_blksize) {
        /* it's the last block, ACK packet immediately */
        ack_packet(inode, serial);

        /* Make sure we know we are at end of file */
        inode->size 		= socket->tftp_filepos;
        socket->tftp_goteof	= 1;
        tftp_close_file(inode);
    }
}

const struct pxe_conn_ops tftp_conn_ops = {
    .fill_buffer	= tftp_get_packet,
    .close		= tftp_close_file,
};

/**
 * Open a TFTP connection to the server
 *
 * @param:inode, the inode to store our state in
 * @param:ip, the ip to contact to get the file
 * @param:filename, the file we wanna open
 *
 * @out: open_file_t structure, stores in file->open_file
 * @out: the lenght of this file, stores in file->file_len
 *
 */
void tftp_open(struct url_info *url, int flags, struct inode *inode,
	       const char **redir)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    char *buf;
    uint16_t buf_len;
    char *p;
    char *options;
    char *data;
    static const char rrq_tail[] = "octet\0""tsize\0""0\0""blksize\0""1408";
    char rrq_packet_buf[2+2*FILENAME_MAX+sizeof rrq_tail];
    char reply_packet_buf[PKTBUF_SIZE];
    int err;
    int buffersize;
    int rrq_len;
    const uint8_t  *timeout_ptr;
    jiffies_t timeout;
    jiffies_t oldtime;
    uint16_t opcode;
    uint16_t blk_num;
    uint64_t opdata;
    uint16_t src_port;
    uint32_t src_ip;

    (void)redir;		/* TFTP does not redirect */
    (void)flags;

    if (url->type != URL_OLD_TFTP) {
	/*
	 * The TFTP URL specification allows the TFTP to end with a
	 * ;mode= which we just ignore.
	 */
	url_unescape(url->path, ';');
    }

    if (!url->port)
	url->port = TFTP_PORT;

    socket->ops = &tftp_conn_ops;
    if (core_udp_open(socket))
	return;

    buf = rrq_packet_buf;
    *(uint16_t *)buf = TFTP_RRQ;  /* TFTP opcode */
    buf += 2;

    buf = stpcpy(buf, url->path);

    buf++;			/* Point *past* the final NULL */
    memcpy(buf, rrq_tail, sizeof rrq_tail);
    buf += sizeof rrq_tail;

    rrq_len = buf - rrq_packet_buf;

    timeout_ptr = TimeoutTable;   /* Reset timeout */
sendreq:
    timeout = *timeout_ptr++;
    if (!timeout)
	return;			/* No file available... */
    oldtime = jiffies();

    core_udp_sendto(socket, rrq_packet_buf, rrq_len, url->ip, url->port);

    /* If the WRITE call fails, we let the timeout take care of it... */
wait_pkt:
    for (;;) {
	buf_len = sizeof(reply_packet_buf);

	err = core_udp_recv(socket, reply_packet_buf, &buf_len,
			    &src_ip, &src_port);
	if (err) {
	    jiffies_t now = jiffies();
	    if (now - oldtime >= timeout)
		 goto sendreq;
	} else {
	    /* Make sure the packet actually came from the server and
	       is long enough for a TFTP opcode */
	    dprintf("tftp_open: got packet buflen=%d\n", buf_len);
	    if ((src_ip == url->ip) && (buf_len >= 2))
		break;
	}
    }

    core_udp_disconnect(socket);
    core_udp_connect(socket, src_ip, src_port);

    /* filesize <- -1 == unknown */
    inode->size = -1;
    socket->tftp_blksize = TFTP_BLOCKSIZE;
    buffersize = buf_len - 2;	  /* bytes after opcode */

    /*
     * Get the opcode type, and parse it
     */
    opcode = *(uint16_t *)reply_packet_buf;
    switch (opcode) {
    case TFTP_ERROR:
        inode->size = 0;
	goto done;        /* ERROR reply; don't try again */

    case TFTP_DATA:
        /*
         * If the server doesn't support any options, we'll get a
         * DATA reply instead of OACK. Stash the data in the file
         * buffer and go with the default value for all options...
         *
         * We got a DATA packet, meaning no options are
         * suported. Save the data away and consider the
         * length undefined, *unless* this is the only
         * data packet...
         */
        buffersize -= 2;
        if (buffersize < 0)
            goto wait_pkt;
        data = reply_packet_buf + 2;
        blk_num = ntohs(*(uint16_t *)data);
        data += 2;
        if (blk_num != 1)
            goto wait_pkt;
        socket->tftp_lastpkt = blk_num;
        if (buffersize > TFTP_BLOCKSIZE)
            goto err_reply;	/* Corrupt */

	socket->tftp_pktbuf = malloc(TFTP_BLOCKSIZE + 4);
	if (!socket->tftp_pktbuf)
	    goto err_reply;	/* Internal error */

        if (buffersize < TFTP_BLOCKSIZE) {
            /*
             * This is the final EOF packet, already...
             * We know the filesize, but we also want to
             * ack the packet and set the EOF flag.
             */
            inode->size = buffersize;
            socket->tftp_goteof = 1;
            ack_packet(inode, blk_num);
        }

        socket->tftp_bytesleft = buffersize;
        socket->tftp_dataptr = socket->tftp_pktbuf;
        memcpy(socket->tftp_pktbuf, data, buffersize);
	goto done;

    case TFTP_OACK:
        /*
         * Now we need to parse the OACK packet to get the transfer
         * and packet sizes.
         */

        options = reply_packet_buf + 2;
	p = options;

	while (buffersize) {
	    const char *opt = p;

	    /*
	     * If we find an option which starts with a NUL byte,
	     * (a null option), we're either seeing garbage that some
	     * TFTP servers add to the end of the packet, or we have
	     * no clue how to parse the rest of the packet (what is
	     * an option name and what is a value?)  In either case,
	     * discard the rest.
	     */
	    if (!*opt)
		goto done;

            while (buffersize) {
                if (!*p)
                    break;	/* Found a final null */
                *p++ |= 0x20;
		buffersize--;
            }
	    if (!buffersize)
		break;		/* Unterminated option */

	    /* Consume the terminal null */
	    p++;
	    buffersize--;

	    if (!buffersize)
		break;		/* No option data */

	    opdata = 0;

            /* do convert a number-string to decimal number, just like atoi */
            while (buffersize--) {
		uint8_t d = *p++;
                if (d == '\0')
                    break;              /* found a final null */
		d -= '0';
                if (d > 9)
                    goto err_reply;     /* Not a decimal digit */
                opdata = opdata*10 + d;
            }

	    if (!strcmp(opt, "tsize"))
		inode->size = opdata;
	    else if (!strcmp(opt, "blksize"))
		socket->tftp_blksize = opdata;
	    else
		goto err_reply; /* Non-negotitated option returned,
				   no idea what it means ...*/


	}

	if (socket->tftp_blksize < 64 || socket->tftp_blksize > PKTBUF_SIZE)
	    goto err_reply;

	/* Parsing successful, allocate buffer */
	socket->tftp_pktbuf = malloc(socket->tftp_blksize + 4);
	if (!socket->tftp_pktbuf)
	    goto err_reply;
	else
	    goto done;

    default:
	printf("TFTP unknown opcode %d\n", ntohs(opcode));
	goto err_reply;
    }

err_reply:
    /* Build the TFTP error packet */
    tftp_error(inode, TFTP_EOPTNEG, "TFTP protocol error");
    inode->size = 0;

done:
    if (!inode->size)
	core_udp_close(socket);

    return;
}
