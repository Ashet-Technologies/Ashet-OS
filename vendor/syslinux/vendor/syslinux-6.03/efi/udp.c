/*
 * Copyright 2013-2014 Intel Corporation - All Rights Reserved
 */

#include <string.h>
#include <minmax.h>
#include "efi.h"
#include "net.h"
#include "fs/pxe/pxe.h"

extern EFI_GUID Udp4ServiceBindingProtocol, Udp4Protocol;

/*
 * This UDP binding is configured to operate in promiscuous mode. It is
 * only used for reading packets. It has no associated state unlike
 * socket->net.efi.binding, which has a remote IP address and port
 * number.
 */
static struct efi_binding *udp_reader;

/** 
 * Try to configure this UDP socket
 *
 * @param:udp, the EFI_UDP4 socket to configure
 * @param:udata, the EFI_UDP4_CONFIG_DATA to use
 * @param:f, the name of the function as a wide string.
 *
 * @out: status as EFI_STATUS
 */

EFI_STATUS core_udp_configure(EFI_UDP4 *udp, EFI_UDP4_CONFIG_DATA *udata,
	short unsigned int *f)
{
    EFI_STATUS status;
    int unmapped = 1;
    jiffies_t start, last, cur;

    last = start = jiffies();
    while (unmapped){
	status = uefi_call_wrapper(udp->Configure, 2, udp, udata);
	if (status != EFI_NO_MAPPING)
		unmapped = 0;
	else {
	    cur = jiffies();
	    if ( (cur - last) >= EFI_NOMAP_PRINT_DELAY ) {
		last = cur;
		Print(L"%s: stalling on configure with no mapping\n", f);
	    } else if ( (cur - start) > EFI_NOMAP_PRINT_DELAY * EFI_NOMAP_PRINT_COUNT) {
		Print(L"%s: aborting on no mapping\n", f);
		unmapped = 0;
	    }
	}
    }
    return status;
}

/**
 * Open a socket
 *
 * @param:socket, the socket to open
 *
 * @out: error code, 0 on success, -1 on failure
 */
int core_udp_open(struct pxe_pvt_inode *socket)
{
    EFI_UDP4_CONFIG_DATA udata;
    struct efi_binding *b;
    EFI_STATUS status;
    EFI_UDP4 *udp;

    (void)socket;

    udp_reader = efi_create_binding(&Udp4ServiceBindingProtocol, &Udp4Protocol);
    if (!udp_reader)
	return -1;

    b = efi_create_binding(&Udp4ServiceBindingProtocol, &Udp4Protocol);
    if (!b)
	goto bail;

    udp = (EFI_UDP4 *)udp_reader->this;

    memset(&udata, 0, sizeof(udata));

    status = core_udp_configure(udp, &udata, L"core_udp_open");
    if (status != EFI_SUCCESS)
	goto bail;

    socket->net.efi.binding = b;

    /*
     * Save the random local port number that the UDPv4 Protocol
     * Driver picked for us. The TFTP protocol uses the local port
     * number as the TID.
     */
    status = uefi_call_wrapper(udp->GetModeData, 5, udp,
			       &udata, NULL, NULL, NULL);
    if (status != EFI_SUCCESS)
	Print(L"Failed to get UDP mode data: %d\n", status);
    else
	socket->net.efi.localport = udata.StationPort;

    return 0;

bail:
    if (b)
	efi_destroy_binding(b, &Udp4ServiceBindingProtocol);

    efi_destroy_binding(udp_reader, &Udp4ServiceBindingProtocol);
    udp_reader = NULL;

    return -1;
}

/**
 * Close a socket
 *
 * @param:socket, the socket to open
 */
void core_udp_close(struct pxe_pvt_inode *socket)
{
    efi_destroy_binding(udp_reader, &Udp4ServiceBindingProtocol);
    udp_reader = NULL;

    if (!socket->net.efi.binding)
	return;

    efi_destroy_binding(socket->net.efi.binding, &Udp4ServiceBindingProtocol);
    socket->net.efi.binding = NULL;
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
    EFI_UDP4_CONFIG_DATA udata;
    EFI_STATUS status;
    EFI_UDP4 *udp;

    udp = (EFI_UDP4 *)socket->net.efi.binding->this;

    memset(&udata, 0, sizeof(udata));

    /* Re-use the existing local port number */
    udata.StationPort = socket->net.efi.localport;

    udata.UseDefaultAddress = TRUE;
    memcpy(&udata.RemoteAddress, &ip, sizeof(ip));
    udata.RemotePort = port;
    udata.AcceptPromiscuous = TRUE;
    udata.TimeToLive = 64;

    status = core_udp_configure(udp, &udata, L"core_udp_connect");
    if (status != EFI_SUCCESS) {
	Print(L"Failed to configure UDP: %d\n", status);
	return;
    }
}

/**
 * Tear down a connection on an open socket
 *
 * @param:socket, the open socket
 */
void core_udp_disconnect(struct pxe_pvt_inode *socket)
{
    EFI_STATUS status;
    EFI_UDP4 *udp;

    udp = (EFI_UDP4 *)socket->net.efi.binding->this;

    /* Reset */
    status = uefi_call_wrapper(udp->Configure, 2, udp, NULL);
    if (status != EFI_SUCCESS)
	Print(L"Failed to reset UDP: %d\n", status);

}

static int volatile cb_status = -1;
static EFIAPI void udp4_cb(EFI_EVENT event, void *context)
{
    (void)event;

    EFI_UDP4_COMPLETION_TOKEN *token = context;

    if (token->Status == EFI_SUCCESS)
	cb_status = 0;
    else
	cb_status = 1;
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
    EFI_UDP4_COMPLETION_TOKEN token;
    EFI_UDP4_FRAGMENT_DATA *frag;
    EFI_UDP4_RECEIVE_DATA *rxdata;
    struct efi_binding *b;
    EFI_STATUS status;
    EFI_UDP4 *udp;
    size_t size;
    int rv = -1;
    jiffies_t start;

    (void)socket;

    b = udp_reader;
    udp = (EFI_UDP4 *)b->this;
    memset(&token, 0, sizeof(token));

    status = efi_setup_event(&token.Event, (EFI_EVENT_NOTIFY)udp4_cb,
			     &token);
    if (status != EFI_SUCCESS)
	return -1;

    status = uefi_call_wrapper(udp->Receive, 2, udp, &token);
    if (status != EFI_SUCCESS)
	goto bail;

    start = jiffies();
    while (cb_status == -1) {
	/* 15ms receive timeout... */
	if (jiffies() - start >= 15) {
	    if (jiffies() - start >= 30)
		dprintf("Failed to cancel UDP\n");

	    uefi_call_wrapper(udp->Cancel, 2, udp, &token);
	    dprintf("core_udp_recv: timed out\n");
	}

	uefi_call_wrapper(udp->Poll, 1, udp);
    }

    if (cb_status == 0)
	rv = 0;

    /* Reset */
    cb_status = -1;

    if (rv)
	goto bail;

    rxdata = token.Packet.RxData;
    frag = &rxdata->FragmentTable[0];

    size = min(frag->FragmentLength, *buf_len);
    memcpy(buf, frag->FragmentBuffer, size);
    *buf_len = size;

    memcpy(src_port, &rxdata->UdpSession.SourcePort, sizeof(*src_port));
    memcpy(src_ip, &rxdata->UdpSession.SourceAddress, sizeof(*src_ip));

    uefi_call_wrapper(BS->SignalEvent, 1, rxdata->RecycleSignal);

bail:
    uefi_call_wrapper(BS->CloseEvent, 1, token.Event);
    return rv;
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
    EFI_UDP4_COMPLETION_TOKEN *token;
    EFI_UDP4_TRANSMIT_DATA *txdata;
    EFI_UDP4_FRAGMENT_DATA *frag;
    struct efi_binding *b = socket->net.efi.binding;
    EFI_STATUS status;
    EFI_UDP4 *udp = (EFI_UDP4 *)b->this;

    token = zalloc(sizeof(*token));
    if (!token)
	return;

    txdata = zalloc(sizeof(*txdata));
    if (!txdata) {
	free(token);
	return;
    }

    status = efi_setup_event(&token->Event, (EFI_EVENT_NOTIFY)udp4_cb,
			     token);
    if (status != EFI_SUCCESS)
	goto bail;

    txdata->DataLength = len;
    txdata->FragmentCount = 1;
    frag = &txdata->FragmentTable[0];

    frag->FragmentLength = len;
    frag->FragmentBuffer = (void *)data;

    token->Packet.TxData = txdata;

    status = uefi_call_wrapper(udp->Transmit, 2, udp, token);
    if (status != EFI_SUCCESS)
	goto close;

    while (cb_status == -1)
	uefi_call_wrapper(udp->Poll, 1, udp);

    /* Reset */
    cb_status = -1;

close:
    uefi_call_wrapper(BS->CloseEvent, 1, token->Event);

bail:
    free(txdata);
    free(token);
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
    EFI_UDP4_COMPLETION_TOKEN *token;
    EFI_UDP4_TRANSMIT_DATA *txdata;
    EFI_UDP4_FRAGMENT_DATA *frag;
    EFI_UDP4_CONFIG_DATA udata;
    EFI_STATUS status;
    struct efi_binding *b;
    EFI_UDP4 *udp;

    (void)socket;

    b = efi_create_binding(&Udp4ServiceBindingProtocol, &Udp4Protocol);
    if (!b)
	return;

    udp = (EFI_UDP4 *)b->this;

    token = zalloc(sizeof(*token));
    if (!token)
	goto out;

    txdata = zalloc(sizeof(*txdata));
    if (!txdata)
	goto bail;

    memset(&udata, 0, sizeof(udata));

    /* Re-use the existing local port number */
    udata.StationPort = socket->net.efi.localport;

    udata.UseDefaultAddress = TRUE;
    memcpy(&udata.RemoteAddress, &ip, sizeof(ip));
    udata.RemotePort = port;
    udata.AcceptPromiscuous = TRUE;
    udata.TimeToLive = 64;

    status = core_udp_configure(udp, &udata, L"core_udp_sendto");
    if (status != EFI_SUCCESS)
	goto bail;

    status = efi_setup_event(&token->Event, (EFI_EVENT_NOTIFY)udp4_cb,
			     token);
    if (status != EFI_SUCCESS)
	goto bail;

    txdata->DataLength = len;
    txdata->FragmentCount = 1;
    frag = &txdata->FragmentTable[0];

    frag->FragmentLength = len;
    frag->FragmentBuffer = (void *)data;

    token->Packet.TxData = txdata;

    status = uefi_call_wrapper(udp->Transmit, 2, udp, token);
    if (status != EFI_SUCCESS)
	goto close;

    while (cb_status == -1)
	uefi_call_wrapper(udp->Poll, 1, udp);

    /* Reset */
    cb_status = -1;

close:
    uefi_call_wrapper(BS->CloseEvent, 1, token->Event);

bail:
    free(txdata);
    free(token);
out:
    efi_destroy_binding(b, &Udp4ServiceBindingProtocol);
}
