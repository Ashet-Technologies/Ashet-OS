#include <string.h>

#include <sys/gpxe.h>
#include <syslinux/config.h>
#include <syslinux/pxe_api.h>

bool is_gpxe(void)
{
    const struct syslinux_version *sv;
    struct s_PXENV_FILE_CHECK_API *fca;
    bool gpxe;
    int err;

    sv = syslinux_version();
    if (sv->filesystem != SYSLINUX_FS_PXELINUX)
        return false;           /* Not PXELINUX */

    fca = lzalloc(sizeof *fca);
    if (!fca)
	return false;

    fca->Size = sizeof *fca;
    fca->Magic = 0x91d447b2;

    err = pxe_call(PXENV_FILE_API_CHECK, fca);

    gpxe = true;

    if (err)
	gpxe = false;           /* Cannot invoke PXE stack */

    if (fca->Status)
        gpxe = false;           /* PXE failure */

    if (fca->Magic != 0xe9c17b20)
        gpxe = false;           /* Incorrect magic */

    if (fca->Size < sizeof *fca)
        gpxe = false;           /* Short return */

    /* XXX: The APIs to test for should be a passed-in option */
    if (!(fca->APIMask & (1 << 5)))
	gpxe = false;           /* No FILE EXEC */

    lfree(fca);
    return gpxe;
}
