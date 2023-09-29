/* ----------------------------------------------------------------------- *
 *   
 *   Copyright 2009-2011 Intel Corporation; author: H. Peter Anvin
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 *   Boston MA 02110-1301, USA; either version 2 of the License, or
 *   (at your option) any later version; incorporated herein by reference.
 *
 * ----------------------------------------------------------------------- */

/*
 * ftp.c
 */
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <minmax.h>
#include <sys/cpu.h>
#include <netinet/in.h>
#include <lwip/api.h>
#include "core.h"
#include "fs.h"
#include "pxe.h"
#include "thread.h"
#include "url.h"
#include "net.h"

static int ftp_cmd_response(struct inode *inode, const char *cmd,
			    const char *cmd_arg,
			    uint8_t *pasv_data, int *pn_ptr)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    int c;
    int pos, code;
    int pb, pn;
    bool ps;
    bool first_line, done;
    char cmd_buf[4096];
    int cmd_len;
    const char *p;
    char *q;
    int err;

    if (cmd) {
	cmd_len = strlcpy(cmd_buf, cmd, sizeof cmd_buf);
	if (cmd_len >= sizeof cmd_buf - 3)
	    return -1;
	q = cmd_buf + cmd_len;

	if (cmd_arg) {
	    p = cmd_arg;

	    *q++ = ' ';
	    cmd_len++;
	    while (*p) {
		if (++cmd_len < sizeof cmd_buf) *q++ = *p;
		if (*p == '\r')
		    if (++cmd_len < sizeof cmd_buf) *q++ = '\0';
		p++;
	    }

	    if (cmd_len >= sizeof cmd_buf - 2)
		return -1;
	}

	*q++ = '\r';
	*q++ = '\n';
	cmd_len += 2;

	err = core_tcp_write(socket, cmd_buf, cmd_len, true);
	if (err)
	    return -1;
    }

    pos = code = pn = pb = 0;
    ps = false;
    first_line = true;
    done = false;

    while ((c = pxe_getc(inode)) >= 0) {
	if (c == '\n') {
	    if (done) {
		if (pn) {
		    pn += ps;
		    if (pn_ptr)
			*pn_ptr = pn;
		}
		return code;
	    }
	    pos = code = 0;
	    first_line = false;
	    continue;
	}

	switch (pos++) {
	case 0:
	case 1:
	case 2:
	    if (c < '0' || c > '9') {
		if (first_line)
		    return -1;
		else
		    pos = 4;	/* Skip this line */
	    } else {
		code = (code*10) + (c - '0');
	    }
	    break;

	case 3:
	    pn = pb = 0;
	    ps = false;
	    if (c == ' ')
		done = true;
	    else if (c == '-')
		done = false;
	    else if (first_line)
		return -1;
	    else
		done = false;
	    break;

	default:
	    if (pasv_data) {
		if (c >= '0' && c <= '9') {
		    pb = (pb*10) + (c-'0');
		    if (pn < 6)
			pasv_data[pn] = pb;
		    ps = true;
		} else if (c == ',') {
		    pn++;
		    pb = 0;
		    ps = false;
		} else if (pn) {
		    pn += ps;
		    if (pn_ptr)
			*pn_ptr = pn;
		    pn = pb = 0;
		    ps = false;
		}
	    }
	    break;
	}
    }

    return -1;
}

static void ftp_free(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);

    if (socket->ctl) {
	core_tcp_close_file(socket->ctl);
	free_socket(socket->ctl);
	socket->ctl = NULL;
    }
    core_tcp_close_file(inode);
}

static void ftp_close_file(struct inode *inode)
{
    struct pxe_pvt_inode *socket  = PVT(inode);
    struct pxe_pvt_inode *ctlsock;
    int resp;

    ctlsock = socket->ctl ? PVT(socket->ctl) : NULL;
    if (core_tcp_is_connected(ctlsock)) {
	resp = ftp_cmd_response(socket->ctl, "QUIT", NULL, NULL, NULL);
	while (resp == 226) {
	    resp = ftp_cmd_response(socket->ctl, NULL, NULL, NULL, NULL);
	}
    }
    ftp_free(inode);
}

static const struct pxe_conn_ops ftp_conn_ops = {
    .fill_buffer	= core_tcp_fill_buffer,
    .close		= ftp_close_file,
    .readdir		= ftp_readdir,
};

void ftp_open(struct url_info *url, int flags, struct inode *inode,
	      const char **redir)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    struct pxe_pvt_inode *ctlsock;
    uint8_t pasv_data[6];
    int pasv_bytes;
    int resp;
    err_t err;

    (void)redir;		/* FTP does not redirect */

    inode->size = 0;

    if (!url->port)
	url->port = 21;

    url_unescape(url->path, 0);

    socket->ops = &ftp_conn_ops;

    /* Set up the control connection */
    socket->ctl = alloc_inode(inode->fs, 0, sizeof(struct pxe_pvt_inode));
    if (!socket->ctl)
	return;
    ctlsock = PVT(socket->ctl);
    ctlsock->ops = &tcp_conn_ops; /* The control connection is just TCP */
    if (core_tcp_open(ctlsock))
	goto err_free;
    err = core_tcp_connect(ctlsock, url->ip, url->port);
    if (err)
	goto err_delete;

    do {
	resp = ftp_cmd_response(socket->ctl, NULL, NULL, NULL, NULL);
    } while (resp == 120);
    if (resp != 220)
	goto err_disconnect;

    if (!url->user)
	url->user = "anonymous";
    if (!url->passwd)
	url->passwd = "syslinux@";

    resp = ftp_cmd_response(socket->ctl, "USER", url->user, NULL, NULL);
    if (resp != 202 && resp != 230) {
	if (resp != 331)
	    goto err_disconnect;

	resp = ftp_cmd_response(socket->ctl, "PASS", url->passwd, NULL, NULL);
	if (resp != 230)
	    goto err_disconnect;
    }

    if (!(flags & O_DIRECTORY)) {
	resp = ftp_cmd_response(socket->ctl, "TYPE", "I", NULL, NULL);
	if (resp != 200)
	    goto err_disconnect;
    }

    resp = ftp_cmd_response(socket->ctl, "PASV", NULL, pasv_data, &pasv_bytes);
    if (resp != 227 || pasv_bytes != 6)
	goto err_disconnect;

    err = core_tcp_open(socket);
    if (err)
	goto err_disconnect;
    err = core_tcp_connect(socket, *(uint32_t*)&pasv_data[0],
			   ntohs(*(uint16_t *)&pasv_data[4]));
    if (err)
	goto err_disconnect;

    resp = ftp_cmd_response(socket->ctl,
			    (flags & O_DIRECTORY) ? "LIST" : "RETR",
			    url->path, NULL, NULL);
    if (resp != 125 && resp != 150)
	goto err_disconnect;

    inode->size = -1;
    return;			/* Sucess! */

err_disconnect:
    core_tcp_write(ctlsock, "QUIT\r\n", 6, false);
    core_tcp_close_file(inode);
err_delete:
    core_tcp_close_file(socket->ctl);
err_free:
    free_socket(socket->ctl);
}
