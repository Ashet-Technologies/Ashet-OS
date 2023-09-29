/*
 * Copyright 2013-2014 Intel Corporation - All Rights Reserved
 */

#include "efi.h"
#include "net.h"
#include "fs/pxe/pxe.h"

extern EFI_GUID Tcp4ServiceBindingProtocol;
extern EFI_GUID Tcp4Protocol;


extern struct efi_binding *efi_create_binding(EFI_GUID *, EFI_GUID *);
extern void efi_destroy_binding(struct efi_binding *, EFI_GUID *);
int core_tcp_open(struct pxe_pvt_inode *socket)
{
    struct efi_binding *b;

    b = efi_create_binding(&Tcp4ServiceBindingProtocol, &Tcp4Protocol);
    if (!b)
	return -1;

    socket->net.efi.binding = b;

    return 0;
}

static EFIAPI void null_cb(EFI_EVENT ev, void *context)
{
    EFI_TCP4_COMPLETION_TOKEN *token = context;

    (void)ev;

    uefi_call_wrapper(BS->CloseEvent, 1, token->Event);
}

static int volatile cb_status = -1;
static EFIAPI void tcp_cb(EFI_EVENT ev, void *context)
{
    EFI_TCP4_COMPLETION_TOKEN *token = context;

    (void)ev;

    if (token->Status == EFI_SUCCESS)
	cb_status = 0;
    else
	cb_status = 1;
}

int core_tcp_connect(struct pxe_pvt_inode *socket, uint32_t ip, uint16_t port)
{
    EFI_TCP4_CONNECTION_TOKEN token;
    EFI_TCP4_ACCESS_POINT *ap;
    EFI_TCP4_CONFIG_DATA tdata;
    struct efi_binding *b = socket->net.efi.binding;
    EFI_STATUS status;
    EFI_TCP4 *tcp = (EFI_TCP4 *)b->this;
    int rv = -1;
    int unmapped = 1;
    jiffies_t start, last, cur;

    memset(&tdata, 0, sizeof(tdata));

    ap = &tdata.AccessPoint;
    ap->UseDefaultAddress = TRUE;
    memcpy(&ap->RemoteAddress, &ip, sizeof(ip));
    ap->RemotePort = port;
    ap->ActiveFlag = TRUE; /* Initiate active open */

    tdata.TimeToLive = 64;

    last = start = jiffies();
    while (unmapped){
	status = uefi_call_wrapper(tcp->Configure, 2, tcp, &tdata);
	if (status != EFI_NO_MAPPING)
		unmapped = 0;
	else {
	    cur = jiffies();
	    if ( (cur - last) >= EFI_NOMAP_PRINT_DELAY ) {
		last = cur;
		Print(L"core_tcp_connect: stalling on configure with no mapping\n");
	    } else if ( (cur - start) > EFI_NOMAP_PRINT_DELAY * EFI_NOMAP_PRINT_COUNT) {
		Print(L"core_tcp_connect: aborting on no mapping\n");
		unmapped = 0;
	    }
	}
    }
    if (status != EFI_SUCCESS)
	return -1;

    status = efi_setup_event(&token.CompletionToken.Event,
			    (EFI_EVENT_NOTIFY)tcp_cb, &token.CompletionToken);
    if (status != EFI_SUCCESS)
	return -1;

    status = uefi_call_wrapper(tcp->Connect, 2, tcp, &token);
    if (status != EFI_SUCCESS) {
	Print(L"Failed to connect: %d\n", status);
	goto out;
    }

    while (cb_status == -1)
	uefi_call_wrapper(tcp->Poll, 1, tcp);

    if (cb_status == 0)
	rv = 0;

    /* Reset */
    cb_status = -1;

out:
    uefi_call_wrapper(BS->CloseEvent, 1, token.CompletionToken.Event);
    return rv;
}

bool core_tcp_is_connected(struct pxe_pvt_inode *socket)
{
    if (socket->net.efi.binding)
	return true;

    return false;
}

int core_tcp_write(struct pxe_pvt_inode *socket, const void *data,
		   size_t len, bool copy)
{
    EFI_TCP4_TRANSMIT_DATA txdata;
    EFI_TCP4_FRAGMENT_DATA *frag;
    struct efi_binding *b = socket->net.efi.binding;
    EFI_TCP4_IO_TOKEN iotoken;
    EFI_STATUS status;
    EFI_TCP4 *tcp = (EFI_TCP4 *)b->this;
    int rv = -1;

    (void)copy;

    memset(&iotoken, 0, sizeof(iotoken));
    memset(&txdata, 0, sizeof(txdata));

    txdata.DataLength = len;
    txdata.FragmentCount = 1;

    frag = &txdata.FragmentTable[0];
    frag->FragmentLength = len;
    frag->FragmentBuffer = (void *)data;

    iotoken.Packet.TxData = &txdata;

    status = efi_setup_event(&iotoken.CompletionToken.Event,
			     (EFI_EVENT_NOTIFY)tcp_cb, &iotoken.CompletionToken);
    if (status != EFI_SUCCESS)
	return -1;

    status = uefi_call_wrapper(tcp->Transmit, 2, tcp, &iotoken);
    if (status != EFI_SUCCESS) {
	Print(L"tcp transmit failed, %d\n", status);
	goto out;
    }

    while (cb_status == -1)
	uefi_call_wrapper(tcp->Poll, 1, tcp);

    if (cb_status == 0)
	rv = 0;

    /* Reset */
    cb_status = -1;

out:
    uefi_call_wrapper(BS->CloseEvent, 1, iotoken.CompletionToken.Event);
    return rv;
}

void core_tcp_close_file(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    struct efi_binding *b = socket->net.efi.binding;
    EFI_TCP4_CLOSE_TOKEN token;
    EFI_STATUS status;
    EFI_TCP4 *tcp = (EFI_TCP4 *)b->this;

  if (!socket->tftp_goteof) {
	memset(&token, 0, sizeof(token));

	status = efi_setup_event(&token.CompletionToken.Event,
				 (EFI_EVENT_NOTIFY)null_cb,
				 &token.CompletionToken);
	if (status != EFI_SUCCESS)
	    return;

	status = uefi_call_wrapper(tcp->Close, 2, tcp, &token);
	if (status != EFI_SUCCESS)
	    Print(L"tcp close failed: %d\n", status);
    }

    efi_destroy_binding(b, &Tcp4ServiceBindingProtocol);
    socket->net.efi.binding = NULL;
}

static char databuf[8192];

void core_tcp_fill_buffer(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    struct efi_binding *b = socket->net.efi.binding;
    EFI_TCP4_IO_TOKEN iotoken;
    EFI_TCP4_RECEIVE_DATA rxdata;
    EFI_TCP4_FRAGMENT_DATA *frag;
    EFI_STATUS status;
    EFI_TCP4 *tcp = (EFI_TCP4 *)b->this;
    void *data;
    size_t len;

    memset(&iotoken, 0, sizeof(iotoken));
    memset(&rxdata, 0, sizeof(rxdata));

    status = efi_setup_event(&iotoken.CompletionToken.Event,
		      (EFI_EVENT_NOTIFY)tcp_cb, &iotoken.CompletionToken);
    if (status != EFI_SUCCESS)
	return;

    iotoken.Packet.RxData = &rxdata;
    rxdata.FragmentCount = 1;
    rxdata.DataLength = sizeof(databuf);
    frag = &rxdata.FragmentTable[0];
    frag->FragmentBuffer = databuf;
    frag->FragmentLength = sizeof(databuf);

    status = uefi_call_wrapper(tcp->Receive, 2, tcp, &iotoken);
    if (status == EFI_CONNECTION_FIN) {
	socket->tftp_goteof = 1;
	if (inode->size == (uint64_t)-1)
	    inode->size = socket->tftp_filepos;
	socket->ops->close(inode);
	goto out;
    }

    while (cb_status == -1)
	uefi_call_wrapper(tcp->Poll, 1, tcp);

    /* Reset */
    cb_status = -1;

    len = frag->FragmentLength;
    memcpy(databuf, frag->FragmentBuffer, len);
    data = databuf;

    socket->tftp_dataptr = data;
    socket->tftp_filepos += len;
    socket->tftp_bytesleft = len;

out:
    uefi_call_wrapper(BS->CloseEvent, 1, iotoken.CompletionToken.Event);
}
