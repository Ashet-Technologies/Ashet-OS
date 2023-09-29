#include <syslinux/config.h>
#include <com32.h>

extern far_ptr_t InitStack, StrucPtr;

/*
 * IP information.  Note that the field are in the same order as the
 * Linux kernel expects in the ip= option.
 */
struct syslinux_ipinfo IPInfo;
uint16_t APIVer;		/* PXE API version found */

__export void get_derivative_info(union syslinux_derivative_info *di)
{
	di->pxe.filesystem = SYSLINUX_FS_PXELINUX;
	di->pxe.apiver = APIVer;
	di->pxe.pxenvptr = GET_PTR(StrucPtr);
	di->pxe.pxenv_offs = StrucPtr.offs;
	di->pxe.pxenv_seg = StrucPtr.seg;
	di->pxe.stack = GET_PTR(InitStack);
	di->pxe.stack_offs = InitStack.offs;
	di->pxe.stack_seg = InitStack.seg;
	di->pxe.ipinfo = &IPInfo;
	di->pxe.myip = IPInfo.myip;
}
