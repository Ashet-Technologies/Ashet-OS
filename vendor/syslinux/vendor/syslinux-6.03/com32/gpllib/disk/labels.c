/* ----------------------------------------------------------------------- *
 *
 *   Copyright 2009 Pierre-Alexandre Meyer
 *
 *   This file is part of Syslinux, and is made available under
 *   the terms of the GNU General Public License version 2.
 *
 * ----------------------------------------------------------------------- */

#include <stdlib.h>
#include <string.h>

void get_label(int label, char **buffer_label)
{
    int buffer_size = (80 * sizeof(char));
    char *buffer = malloc(buffer_size);
    *buffer_label = buffer;

    switch (label) {
    case 0x01:
	strlcpy(buffer, "DOS 12-bit fat", buffer_size);
	break;
    case 0x02:
	strlcpy(buffer, "XENIX root", buffer_size);
	break;
    case 0x03:
	strlcpy(buffer, "XENIX /usr", buffer_size);
	break;
    case 0x04:
	strlcpy(buffer, "DOS 3.0+ 16-bit FAT (up to 32M)", buffer_size);
	break;
    case 0x05:
	strlcpy(buffer, "DOS 3.3+ Extended Partition", buffer_size);
	break;
    case 0x06:
	strlcpy(buffer, "DOS 3.31+ 16-bit FAT (over 32M)", buffer_size);
	break;
    case 0x07:
	strlcpy(buffer, "NTFS/exFAT/HPFS", buffer_size);
	//case 0x07: strlcpy(buffer, "Advanced Unix", buffer_size); break;
	//case 0x07: strlcpy(buffer, "Windows NT NTFS", buffer_size); break;
	//case 0x07: strlcpy(buffer, "QNX2.x (pre-1988)", buffer_size); break;
	break;
    case 0x08:
	strlcpy(buffer, "AIX", buffer_size);
	//case 0x08: strlcpy(buffer, "AIX boot partition", buffer_size); break;
	//case 0x08: strlcpy(buffer, "SplitDrive", buffer_size); break;
	//case 0x08: strlcpy(buffer, "DELL partition spanning multiple drives", buffer_size); break;
	//case 0x08: strlcpy(buffer, "Commodore DOS", buffer_size); break;
	//case 0x08: strlcpy(buffer, "QNX 1.x and 2.x ("qny")", buffer_size); break;
	break;
    case 0x09:
	strlcpy(buffer, "AIX bootable partition", buffer_size);
	//case 0x09: strlcpy(buffer, "Coherent filesystem", buffer_size); break;
	//case 0x09: strlcpy(buffer, "QNX 1.x and 2.x ("qnz")", buffer_size); break;
	break;
    case 0x0a:
	strlcpy(buffer, "OS/2 Boot Manager", buffer_size);
	//case 0x0a: strlcpy(buffer, "Coherent swap partition", buffer_size); break;
	//case 0x0a: strlcpy(buffer, "OPUS", buffer_size); break;
	break;
    case 0x0b:
	strlcpy(buffer, "WIN95 OSR2 32-bit FAT", buffer_size);
	break;
    case 0x0c:
	strlcpy(buffer, "WIN95 OSR2 32-bit FAT, LBA-mapped", buffer_size);
	break;
    case 0x0e:
	strlcpy(buffer, "WIN95: DOS 16-bit FAT, LBA-mapped", buffer_size);
	break;
    case 0x0f:
	strlcpy(buffer, "WIN95: Extended partition, LBA-mapped", buffer_size);
	break;
    case 0x10:
	strlcpy(buffer, "OPUS", buffer_size);
	break;
    case 0x11:
	strlcpy(buffer, "Hidden DOS 12-bit FAT", buffer_size);
	break;
    case 0x12:
	strlcpy(buffer, "Compaq diagnostic partition", buffer_size);
	break;
    case 0x14:
	strlcpy(buffer, "Hidden DOS 16-bit FAT <32M", buffer_size);
	break;
    case 0x16:
	strlcpy(buffer, "Hidden DOS 16-bit FAT >=32M", buffer_size);
	break;
    case 0x17:
	strlcpy(buffer, "Hidden HPFS/exFAT/NTFS", buffer_size);
	break;
    case 0x18:
	strlcpy(buffer, "AST SmartSleep Partition", buffer_size);
	break;
    case 0x19:
	strlcpy(buffer, "Unused (Claimed for Willowtech Photon COS)",
		buffer_size);
	break;
    case 0x1b:
	strlcpy(buffer, "Hidden WIN95 OSR2 32-bit FAT", buffer_size);
	break;
    case 0x1c:
	strlcpy(buffer, "Hidden WIN95 OSR2 32-bit FAT, LBA-mapped",
		buffer_size);
	break;
    case 0x1e:
	strlcpy(buffer, "Hidden WIN95 16-bit FAT, LBA-mapped", buffer_size);
	break;
    case 0x20:
	strlcpy(buffer, "Unused", buffer_size);
	break;
    case 0x21:
	strlcpy(buffer, "Reserved", buffer_size);
	//case 0x21: strlcpy(buffer, "Unused", buffer_size); break;
	break;
    case 0x22:
	strlcpy(buffer, "Unused", buffer_size);
	break;
    case 0x23:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x24:
	strlcpy(buffer, "NEC DOS 3.x", buffer_size);
	break;
    case 0x26:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x27:
	strlcpy(buffer, "PQService (Acer laptop hidden rescue partition)", buffer_size);
	//Windows RE hidden partition
	//MirOS BSD partition
	//RouterBOOT kernel partition
	break;
    case 0x2a:
	strlcpy(buffer, "AtheOS File System (AFS)", buffer_size);
	break;
    case 0x2b:
	strlcpy(buffer, "SyllableSecure (SylStor)", buffer_size);
	break;
    case 0x31:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x32:
	strlcpy(buffer, "NOS", buffer_size);
	break;
    case 0x33:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x34:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x35:
	strlcpy(buffer, "JFS on OS/2 or eCS", buffer_size);
	break;
    case 0x36:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x38:
	strlcpy(buffer, "THEOS ver 3.2 2gb partition", buffer_size);
	break;
    case 0x39:
	strlcpy(buffer, "Plan 9 partition", buffer_size);
	//case 0x39: strlcpy(buffer, "THEOS ver 4 spanned partition", buffer_size); break;
	break;
    case 0x3a:
	strlcpy(buffer, "THEOS ver 4 4gb partition", buffer_size);
	break;
    case 0x3b:
	strlcpy(buffer, "THEOS ver 4 extended partition", buffer_size);
	break;
    case 0x3c:
	strlcpy(buffer, "PartitionMagic recovery partition", buffer_size);
	break;
    case 0x3d:
	strlcpy(buffer, "Hidden NetWare", buffer_size);
	break;
    case 0x40:
	strlcpy(buffer, "Venix 80286", buffer_size);
	break;
    case 0x41:
	strlcpy(buffer, "PPC PReP Boot", buffer_size); break;
	//case 0x41: strlcpy(buffer, "Personal RISC Boot", buffer_size); break;
	// strlcpy(buffer, "Linux/MINIX (sharing disk with DRDOS)", buffer_size);
	break;
    case 0x42:
	strlcpy(buffer, "SFS (Secure Filesystem)", buffer_size); break;
	// strlcpy(buffer, "Linux swap (sharing disk with DRDOS)", buffer_size);
	//case 0x42: strlcpy(buffer, "Windows 2000 marker", buffer_size); break;
	break;
    case 0x43:
	strlcpy(buffer, "Linux native (sharing disk with DRDOS)", buffer_size);
	break;
    case 0x44:
	strlcpy(buffer, "GoBack partition", buffer_size);
	break;
    case 0x45:
	strlcpy(buffer, "Boot-US boot manager", buffer_size);
	//case 0x45: strlcpy(buffer, "Priam", buffer_size); break;
	//case 0x45: strlcpy(buffer, "EUMEL/Elan", buffer_size); break;
	break;
    case 0x46:
	strlcpy(buffer, "EUMEL/Elan", buffer_size);
	break;
    case 0x47:
	strlcpy(buffer, "EUMEL/Elan", buffer_size);
	break;
    case 0x48:
	strlcpy(buffer, "EUMEL/Elan", buffer_size);
	break;
    case 0x4a:
	strlcpy(buffer, "AdaOS Aquila (Default)", buffer_size);
	//case 0x4a: strlcpy(buffer, "ALFS/THIN lightweight filesystem for DOS", buffer_size); break;
	break;
    case 0x4c:
	strlcpy(buffer, "Oberon partition", buffer_size);
	break;
    case 0x4d:
	strlcpy(buffer, "QNX4.x", buffer_size);
	break;
    case 0x4e:
	strlcpy(buffer, "QNX4.x 2nd part", buffer_size);
	break;
    case 0x4f:
	strlcpy(buffer, "QNX4.x 3rd part", buffer_size);
	//case 0x4f: strlcpy(buffer, "Oberon partition", buffer_size); break;
	break;
    case 0x50:
	strlcpy(buffer, "OnTrack Disk Manager (older versions) RO",
		buffer_size);
	//case 0x50: strlcpy(buffer, "Lynx RTOS", buffer_size); break;
	//case 0x50: strlcpy(buffer, "Native Oberon (alt)", buffer_size); break;
	break;
    case 0x51:
	strlcpy(buffer, "OnTrack Disk Manager RW (DM6 Aux1)", buffer_size);
	//case 0x51: strlcpy(buffer, "Novell", buffer_size); break;
	break;
    case 0x52:
	strlcpy(buffer, "CP/M", buffer_size);
	//case 0x52: strlcpy(buffer, "Microport SysV/AT", buffer_size); break;
	break;
    case 0x53:
	strlcpy(buffer, "Disk Manager 6.0 Aux3", buffer_size);
	break;
    case 0x54:
	strlcpy(buffer, "Disk Manager 6.0 Dynamic Drive Overlay", buffer_size);
	break;
    case 0x55:
	strlcpy(buffer, "EZ-Drive", buffer_size);
	break;
    case 0x56:
	strlcpy(buffer, "Golden Bow VFeature Partitioned Volume.", buffer_size);
	//case 0x56: strlcpy(buffer, "DM converted to EZ-BIOS", buffer_size); break;
	break;
    case 0x57:
	strlcpy(buffer, "DrivePro", buffer_size);
	//case 0x57: strlcpy(buffer, "VNDI Partition", buffer_size); break;
	break;
    case 0x5c:
	strlcpy(buffer, "Priam EDisk", buffer_size);
	break;
    case 0x61:
	strlcpy(buffer, "SpeedStor", buffer_size);
	break;
    case 0x63:
	strlcpy(buffer,
		"Unix System V (SCO, ISC Unix, UnixWare, ...), Mach, GNU Hurd",
		buffer_size);
	break;
    case 0x64:
	strlcpy(buffer, "Novell Netware 286, 2.xx", buffer_size); break;
	//strlcpy(buffer, "PC-ARMOUR protected partition", buffer_size);
	break;
    case 0x65:
	strlcpy(buffer, "Novell Netware 386, 3.xx or 4.xx", buffer_size);
	break;
    case 0x66:
	strlcpy(buffer, "Novell Netware SMS Partition", buffer_size);
	break;
    case 0x67:
	strlcpy(buffer, "Novell", buffer_size);
	break;
    case 0x68:
	strlcpy(buffer, "Novell", buffer_size);
	break;
    case 0x69:
	strlcpy(buffer, "Novell Netware 5+, Novell Netware NSS Partition",
		buffer_size);
	break;
    case 0x70:
	strlcpy(buffer, "DiskSecure Multi-Boot", buffer_size);
	break;
    case 0x71:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x72:
	strlcpy(buffer, "V7/x86", buffer_size);
	break;
    case 0x73:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x74:
	//strlcpy(buffer, "Reserved", buffer_size);
	strlcpy(buffer, "Scramdisk partition", buffer_size); break;
    case 0x75:
	strlcpy(buffer, "IBM PC/IX", buffer_size);
	break;
    case 0x76:
	strlcpy(buffer, "Reserved", buffer_size);
	break;
    case 0x77:
	strlcpy(buffer, "M2FS/M2CS partition", buffer_size);
	break;
	//case 0x77: strlcpy(buffer, "VNDI Partition", buffer_size); break;
    case 0x78:
	strlcpy(buffer, "XOSL FS", buffer_size);
	break;
    case 0x7E:
	strlcpy(buffer, "Unused", buffer_size);
	break;
    case 0x80:
	strlcpy(buffer, "MINIX until 1.4a", buffer_size);
	break;
    case 0x81:
	strlcpy(buffer, "MINIX since 1.4b, early Linux", buffer_size);
	//case 0x81: strlcpy(buffer, "Mitac disk manager", buffer_size); break;
	break;
    case 0x82:
	strlcpy(buffer, "Linux swap", buffer_size);
	//case 0x82: strlcpy(buffer, "Prime", buffer_size); break;
	//case 0x82: strlcpy(buffer, "Solaris x86", buffer_size); break;
	break;
    case 0x83:
	strlcpy(buffer, "Linux native (usually ext2fs)", buffer_size);
	break;
    case 0x84:
	strlcpy(buffer, "OS/2 hidden C: drive", buffer_size);
	//case 0x84: strlcpy(buffer, "Hibernation partition", buffer_size); break;
	break;
    case 0x85:
	strlcpy(buffer, "Linux extended partition", buffer_size);
	break;
    case 0x86:
	strlcpy(buffer, "NTFS volume set", buffer_size);
	//case 0x86: strlcpy(buffer, "Old Linux RAID partition superblock", buffer_size); break;
	break;
    case 0x87:
	strlcpy(buffer, "NTFS volume set", buffer_size);
	break;
    case 0x88:
	strlcpy(buffer, "Linux Plaintext", buffer_size);
	break;
    case 0x8a:
	strlcpy(buffer, "Linux Kernel Partition (used by AiR-BOOT)",
		buffer_size);
	break;
    case 0x8b:
	strlcpy(buffer, "Legacy Fault Tolerant FAT32 volume", buffer_size);
	break;
    case 0x8c:
	strlcpy(buffer,
		"Legacy Fault Tolerant FAT32 volume using BIOS extd INT 13h",
		buffer_size);
	break;
    case 0x8d:
	strlcpy(buffer, "Free FDISK hidden Primary DOS FAT12 partitition",
		buffer_size);
	break;
    case 0x8e:
	strlcpy(buffer, "Linux LVM partition", buffer_size);
	break;
    case 0x90:
	strlcpy(buffer, "Free FDISK hidden Primary DOS FAT16 partitition",
		buffer_size);
	break;
    case 0x91:
	strlcpy(buffer, "Free FDISK hidden DOS extended partitition",
		buffer_size);
	break;
    case 0x92:
	strlcpy(buffer, "Free FDISK hidden Primary DOS large FAT16 partitition",
		buffer_size);
	break;
    case 0x93:
	strlcpy(buffer, "Hidden Linux native partition", buffer_size);
	//case 0x93: strlcpy(buffer, "Amoeba", buffer_size); break;
	break;
    case 0x94:
	strlcpy(buffer, "Amoeba bad block table", buffer_size);
	break;
    case 0x95:
	strlcpy(buffer, "MIT EXOPC native partitions", buffer_size);
	break;
    case 0x96:
	strlcpy(buffer, "CHRP ISO-9660 filesystem", buffer_size);
	break;
    case 0x97:
	strlcpy(buffer, "Free FDISK hidden Primary DOS FAT32 partitition",
		buffer_size);
	break;
    case 0x98:
	strlcpy(buffer, "Free FDISK hidden Primary DOS FAT32 partitition (LBA)",
		buffer_size);
	break;
    case 0x99:
	strlcpy(buffer, "DCE376 logical drive", buffer_size);
	break;
    case 0x9a:
	strlcpy(buffer, "Free FDISK hidden Primary DOS FAT16 partitition (LBA)",
		buffer_size);
	break;
    case 0x9b:
	strlcpy(buffer, "Free FDISK hidden DOS extended partitition (LBA)",
		buffer_size);
	break;
    case 0x9e:
	strlcpy(buffer, "ForthOS partition", buffer_size);
	break;
    case 0x9f:
	strlcpy(buffer, "BSD/OS", buffer_size);
	break;
    case 0xa0:
	strlcpy(buffer, "Laptop hibernation partition", buffer_size);
	break;
    case 0xa1:
	strlcpy(buffer, "Laptop hibernation partition", buffer_size);
	//case 0xa1: strlcpy(buffer, "HP Volume Expansion (SpeedStor variant)", buffer_size); break;
	break;
    case 0xa3:
	strlcpy(buffer, "HP Volume Expansion (SpeedStor variant)", buffer_size);
	break;
    case 0xa4:
	strlcpy(buffer, "HP Volume Expansion (SpeedStor variant)", buffer_size);
	break;
    case 0xa5:
	strlcpy(buffer, "BSD/386, 386BSD, NetBSD, FreeBSD", buffer_size);
	break;
    case 0xa6:
	strlcpy(buffer, "OpenBSD", buffer_size);
	break;
    case 0xa7:
	strlcpy(buffer, "NeXTSTEP", buffer_size);
	break;
    case 0xa8:
	strlcpy(buffer, "Mac OS-X", buffer_size);
	break;
    case 0xa9:
	strlcpy(buffer, "NetBSD", buffer_size);
	break;
    case 0xaa:
	strlcpy(buffer, "Olivetti Fat 12 1.44Mb Service Partition",
		buffer_size);
	break;
    case 0xab:
	strlcpy(buffer, "Mac OS-X Boot partition", buffer_size);
	//case 0xab: strlcpy(buffer, "GO! partition", buffer_size); break;
	break;
    case 0xae:
	strlcpy(buffer, "ShagOS filesystem", buffer_size);
	break;
    case 0xaf:
	strlcpy(buffer, "ShagOS swap partition", buffer_size);
	break;
    case 0xb0:
	strlcpy(buffer, "BootStar Dummy", buffer_size);
	break;
    case 0xb1:
	strlcpy(buffer, "HP Volume Expansion (SpeedStor variant)", buffer_size);
	break;
    case 0xb2:
	strlcpy(buffer, "QNX Neutrino Power-Safe filesystem", buffer_size);
	break;
    case 0xb3:
	strlcpy(buffer, "HP Volume Expansion (SpeedStor variant)", buffer_size);
	break;
    case 0xb4:
	strlcpy(buffer, "HP Volume Expansion (SpeedStor variant)", buffer_size);
	break;
    case 0xb6:
	strlcpy(buffer, "HP Volume Expansion (SpeedStor variant)", buffer_size);
	break;
    case 0xb7:
	strlcpy(buffer, "BSDI BSD/386 filesystem", buffer_size);
	break;
    case 0xb8:
	strlcpy(buffer, "BSDI BSD/386 swap partition", buffer_size);
	break;
    case 0xbb:
	strlcpy(buffer, "Boot Wizard hidden", buffer_size);
	break;
    case 0xbc:
	strlcpy(buffer, "Acronis backup partition", buffer_size);
	break;
    case 0xbe:
	strlcpy(buffer, "Solaris 8 boot partition", buffer_size);
	break;
    case 0xbf:
	strlcpy(buffer, "Solaris partition", buffer_size);
	break;
    case 0xc0:
	strlcpy(buffer, "CTOS", buffer_size);
	//case 0xc0: strlcpy(buffer, "REAL/32 secure small partition", buffer_size); break;
	//case 0xc0: strlcpy(buffer, "NTFT Partition", buffer_size); break;
	break;
    case 0xc1:
	strlcpy(buffer, "DRDOS/secured (FAT-12)", buffer_size);
	break;
    case 0xc2:
	strlcpy(buffer, "Hidden Linux", buffer_size); break;
	//strlcpy(buffer, "Reserved for DR-DOS 7+", buffer_size);
	break;
    case 0xc3:
	strlcpy(buffer, "Hidden Linux swap", buffer_size);
	break;
    case 0xc4:
	strlcpy(buffer, "DRDOS/secured (FAT-16, < 32M)", buffer_size);
	break;
    case 0xc5:
	strlcpy(buffer, "DRDOS/secured (extended)", buffer_size);
	break;
    case 0xc6:
	strlcpy(buffer, "DRDOS/secured (FAT-16, >= 32M)", buffer_size);
	//case 0xc6: strlcpy(buffer, "Windows NT corrupted FAT16 volume/stripe set", buffer_size); break;
	break;
    case 0xc7:
	strlcpy(buffer, "Windows NT corrupted NTFS volume/stripe set",
		buffer_size);
	//case 0xc7: strlcpy(buffer, "Syrinx boot", buffer_size); break;
	break;
    case 0xc8:
	strlcpy(buffer, "Reserved for DR-DOS 8.0+", buffer_size);
	break;
    case 0xc9:
	strlcpy(buffer, "Reserved for DR-DOS 8.0+", buffer_size);
	break;
    case 0xca:
	strlcpy(buffer, "Reserved for DR-DOS 8.0+", buffer_size);
	break;
    case 0xcb:
	strlcpy(buffer, "reserved for DRDOS/secured (FAT32)", buffer_size);
	break;
    case 0xcc:
	strlcpy(buffer, "reserved for DRDOS/secured (FAT32, LBA)", buffer_size);
	break;
    case 0xcd:
	strlcpy(buffer, "CTOS Memdump?", buffer_size);
	break;
    case 0xce:
	strlcpy(buffer, "reserved for DRDOS/secured (FAT16, LBA)", buffer_size);
	break;
    case 0xcf:
	strlcpy(buffer, "DR-DOS 7.04+ secured EXT DOS (LBA)", buffer_size);
	break;
    case 0xd0:
	strlcpy(buffer, "REAL/32 secure big partition", buffer_size);
	break;
    case 0xd1:
	strlcpy(buffer, "Old Multiuser DOS secured FAT12", buffer_size);
	break;
    case 0xd4:
	strlcpy(buffer, "Old Multiuser DOS secured FAT16 <32M", buffer_size);
	break;
    case 0xd5:
	strlcpy(buffer, "Old Multiuser DOS secured extended partition",
		buffer_size);
	break;
    case 0xd6:
	strlcpy(buffer, "Old Multiuser DOS secured FAT16 >=32M", buffer_size);
	break;
    case 0xd8:
	strlcpy(buffer, "CP/M-86", buffer_size);
	break;
    case 0xda:
	strlcpy(buffer, "Non-FS Data", buffer_size);
	break;
    case 0xdb:
	strlcpy(buffer,
		"Digital Research CP/M, Concurrent CP/M, Concurrent DOS",
		buffer_size);
	//case 0xdb: strlcpy(buffer, "CTOS (Convergent Technologies OS -Unisys)", buffer_size); break;
	//case 0xdb: strlcpy(buffer, "KDG Telemetry SCPU boot", buffer_size); break;
	break;
    case 0xdd:
	strlcpy(buffer, "Hidden CTOS Memdump?", buffer_size);
	break;
    case 0xde:
	strlcpy(buffer, "Dell PowerEdge Server utilities (FAT fs)",
		buffer_size);
	break;
    case 0xdf:
	strlcpy(buffer, "DG/UX virtual disk manager partition", buffer_size);
	break;
	//case 0xdf: strlcpy(buffer, "BootIt EMBRM", buffer_size); break;
    case 0xe0:
	strlcpy(buffer,
		"Reserved by STMicroelectronics for a filesystem called ST AVFS.",
		buffer_size);
	break;
    case 0xe1:
	strlcpy(buffer, "DOS access or SpeedStor 12-bit FAT extended partition",
		buffer_size);
	break;
    case 0xe3:
	strlcpy(buffer, "DOS R/O or SpeedStor", buffer_size);
	break;
    case 0xe4:
	strlcpy(buffer, "SpeedStor 16-bit FAT extended partition < 1024 cyl.",
		buffer_size);
	break;
    case 0xe5:
	strlcpy(buffer,
		"Tandy DOS with logical sectored FAT (According to Powerquest.)",
		buffer_size);
	//case 0xe5: strlcpy(buffer, "Reserved", buffer_size); break;
	break;
    case 0xe6:
	strlcpy(buffer, "Storage Dimensions SpeedStor", buffer_size);
	break;
    case 0xe8:
	strlcpy(buffer, "LUKS", buffer_size);
	break;
    case 0xeb:
	strlcpy(buffer, "BeOS", buffer_size);
	break;
    case 0xec:
	strlcpy(buffer, "SkyOS SkyFS", buffer_size);
	break;
    case 0xed:
	strlcpy(buffer, "Reserved for Matthias Paul's Sprytix", buffer_size);
	break;
    case 0xee:
	strlcpy(buffer,
		"GPT",
		buffer_size);
	break;
    case 0xef:
	strlcpy(buffer, "EFI file system",
		buffer_size);
	break;
    case 0xf0:
	strlcpy(buffer, "Linux/PA-RISC boot loader", buffer_size);
	break;
    case 0xf1:
	strlcpy(buffer, "SpeedStor", buffer_size);
	break;
    case 0xf2:
	strlcpy(buffer,
		"DOS 3.3+ secondary partition (Powerquest writes: Unisys DOS with logical sectored FAT.)",
		buffer_size);
	break;
    case 0xf3:
	strlcpy(buffer,
		"Reserved (Powerquest writes: Storage Dimensions SpeedStor.)",
		buffer_size);
	break;
    case 0xf4:
	strlcpy(buffer, "SpeedStor large partition", buffer_size);
	//case 0xf4: strlcpy(buffer, "Prologue single-volume partition", buffer_size); break;
	break;
    case 0xf5:
	strlcpy(buffer, "Prologue multi-volume partition", buffer_size);
	break;
    case 0xf6:
	strlcpy(buffer,
		"Reserved (Powerquest writes: Storage Dimensions SpeedStor. )",
		buffer_size);
	break;
    case 0xf7:
	strlcpy(buffer, "DDRdrive Solid State File System", buffer_size);
	break;
    case 0xf9:
	strlcpy(buffer, "pCache", buffer_size);
	break;
    case 0xfa:
	strlcpy(buffer, "Bochs", buffer_size);
	break;
    case 0xfb:
	strlcpy(buffer, "VMware File System partition", buffer_size);
	break;
    case 0xfc:
	strlcpy(buffer, "VMware Swap partition", buffer_size);
	break;
    case 0xfd:
	strlcpy(buffer,
		"Linux raid partition with autodetect using persistent superblock (Powerquest writes: Reserved for FreeDOS. )",
		buffer_size);
	break;
    case 0xfe:
	strlcpy(buffer, "LANstep", buffer_size); break;
	//strlcpy(buffer, "SpeedStor > 1024 cyl.", buffer_size);
	//case 0xfe: strlcpy(buffer, "IBM PS/2 IML (Initial Microcode Load) partition, located at the end of the disk.", buffer_size); break;
	//case 0xfe: strlcpy(buffer, "Windows NT Disk Administrator hidden partition", buffer_size); break;
	//case 0xfe: strlcpy(buffer, "Linux Logical Volume Manager partition (old)", buffer_size); break;
	break;
    case 0xff:
	strlcpy(buffer, "Xenix Bad Block Table ", buffer_size);
	break;
    default:
	strlcpy(buffer, "Unknown", buffer_size);
	break;
    }
}
