#include "pxe.h"
#if GPXE

static void gpxe_close_file(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    static __lowmem struct s_PXENV_FILE_CLOSE file_close;

    file_close.FileHandle = socket->tftp_remoteport;
    pxe_call(PXENV_FILE_CLOSE, &file_close);
}

/**
 * Get a fresh packet from a gPXE socket
 * @param: inode -> Inode pointer
 *
 */
static void gpxe_get_packet(struct inode *inode)
{
    struct pxe_pvt_inode *socket = PVT(inode);
    static __lowmem struct s_PXENV_FILE_READ file_read;
    int err;

    while (1) {
        file_read.FileHandle  = socket->tftp_remoteport;
        file_read.Buffer      = FAR_PTR(packet_buf);
        file_read.BufferSize  = PKTBUF_SIZE;
        err = pxe_call(PXENV_FILE_READ, &file_read);
        if (!err)  /* successed */
            break;

        if (file_read.Status != PXENV_STATUS_TFTP_OPEN)
	    kaboom();
    }

    memcpy(socket->tftp_pktbuf, packet_buf, file_read.BufferSize);

    socket->tftp_dataptr   = socket->tftp_pktbuf;
    socket->tftp_bytesleft = file_read.BufferSize;
    socket->tftp_filepos  += file_read.BufferSize;

    if (socket->tftp_bytesleft == 0)
        inode->size = socket->tftp_filepos;

    /* if we're done here, close the file */
    if (inode->size > socket->tftp_filepos)
        return;

    /* Got EOF, close it */
    socket->tftp_goteof = 1;
    gpxe_close_file(inode);
}

/**
 * Open a url using gpxe
 *
 * @param:inode, the inode to store our state in
 * @param:url, the url we want to open
 *
 * @out: open_file_t structure, stores in file->open_file
 * @out: the lenght of this file, stores in file->file_len
 *
 */
void gpxe_open(struct inode *inode, const char *url)
{
    static __lowmem struct s_PXENV_FILE_OPEN file_open;
    static char lowurl[2*FILENAME_MAX];
    struct pxe_pvt_inode *socket = PVT(inode);
    int err;

    socket->tftp_pktbuf = malloc(PKTBUF_SIZE);
    if (!socket->tftp_pktbuf)
	return;

    snprintf(lowurl, sizeof lowurl, "%s", url);
    file_open.Status        = PXENV_STATUS_BAD_FUNC;
    file_open.FileName      = FAR_PTR(lowurl);
    err = pxe_call(PXENV_FILE_OPEN, &file_open);
    if (err)
	return; 

    socket->fill_buffer = gpxe_get_packet;
    socket->close = gpxe_close_file;
    socket->tftp_remoteport = file_open.FileHandle;
    inode->size = -1; /* This is not an error */
}

#endif /* GPXE */
