/* ----------------------------------------------------------------------- *
 *
 *   Pportions of this file taken from the dmidecode project
 *
 *   Copyright (C) 2000-2002 Alan Cox <alan@redhat.com>
 *   Copyright (C) 2002-2008 Jean Delvare <khali@linux-fr.org>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the Free Software
 *   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 *
 *   For the avoidance of doubt the "preferred form" of this code is one which
 *   is in an open unpatent encumbered format. Where cryptographic key signing
 *   forms part of the process of creating an executable the information
 *   including keys needed to generate an equivalently functional executable
 *   are deemed to be part of the source code.
*/

#include <dmi/dmi.h>
#include <stdio.h>

const char *dmi_processor_type(uint8_t code)
{
    /* 3.3.5.1 */
    static const char *type[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"Central Processor",
	"Math Processor",
	"DSP Processor",
	"Video Processor"	/* 0x06 */
    };

    if (code >= 0x01 && code <= 0x06)
	return type[code - 0x01];
    return out_of_spec;
}

const char *dmi_processor_family(uint8_t code, char *manufacturer)
{
    /* 3.3.5.2 */
    /* TODO : Need to implement code/value (see dmidecode) insteed of array to address large index */
    static const char *family[256] = {
	NULL,			/* 0x00 */
	"Other",
	"Unknown",
	"8086",
	"80286",
	"80386",
	"80486",
	"8087",
	"80287",
	"80387",
	"80487",
	"Pentium",
	"Pentium Pro",
	"Pentium II",
	"Pentium MMX",
	"Celeron",
	"Pentium II Xeon",
	"Pentium III",
	"M1",
	"M2",
	"Celeron M",		/* 0x14 */
	"Pentium 4 HT",
	NULL,
	NULL,			/* 0x17 */
	"Duron",
	"K5",
	"K6",
	"K6-2",
	"K6-3",
	"Athlon",
	"AMD2900",
	"K6-2+",
	"Power PC",
	"Power PC 601",
	"Power PC 603",
	"Power PC 603+",
	"Power PC 604",
	"Power PC 620",
	"Power PC x704",
	"Power PC 750",
	"Core 2 Duo",		/* 0x28 */
	"Core 2 Duo Mobile",
	"Core Solo Mobile",
	"Atom",
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x2F */
	"Alpha",
	"Alpha 21064",
	"Alpha 21066",
	"Alpha 21164",
	"Alpha 21164PC",
	"Alpha 21164a",
	"Alpha 21264",
	"Alpha 21364",
	NULL,			/* 0x38 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x3F */
	"MIPS",
	"MIPS R4000",
	"MIPS R4200",
	"MIPS R4400",
	"MIPS R4600",
	"MIPS R10000",
	NULL,			/* 0x46 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x4F */
	"SPARC",
	"SuperSPARC",
	"MicroSPARC II",
	"MicroSPARC IIep",
	"UltraSPARC",
	"UltraSPARC II",
	"UltraSPARC IIi",
	"UltraSPARC III",
	"UltraSPARC IIIi",
	NULL,			/* 0x59 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x5F */
	"68040",
	"68xxx",
	"68000",
	"68010",
	"68020",
	"68030",
	NULL,			/* 0x66 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x6F */
	"Hobbit",
	NULL,			/* 0x71 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x77 */
	"Crusoe TM5000",
	"Crusoe TM3000",
	"Efficeon TM8000",
	NULL,			/* 0x7B */
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x7F */
	"Weitek",
	NULL,			/* 0x81 */
	"Itanium",
	"Athlon 64",
	"Opteron",
	"Sempron",
	"Turion 64",		/* 0x86 */
	"Dual-Core Opteron",
	"Atlhon 64 X2",
	"Turion 64 X2",
	"Quad-Core Opteron",
	"Third-Generation Opteron",
	"Phenom FX",
	"Phenom X4",
	"Phenom X2",
	"Athlon X2",		/* 0x8F */
	"PA-RISC",
	"PA-RISC 8500",
	"PA-RISC 8000",
	"PA-RISC 7300LC",
	"PA-RISC 7200",
	"PA-RISC 7100LC",
	"PA-RISC 7100",
	NULL,			/* 0x97 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,			/* 0x9F */
	"V30",
	"Quad-Core Xeon 3200",	/* 0xA1 */
	"Dual-Core Xeon 3000",
	"Quad-Core Xeon 5300",
	"Dual-Core Xeon 5100",
	"Dual-Core Xeon 5000",
	"Dual-Core Xeon LV",
	"Dual-Core Xeon ULV",
	"Dual-Core Xeon 7100",
	"Quad-Core Xeon 5400",
	"Quad-Core Xeon",	/* 0xAA */
	"Dual-Core Xeon 5200",
	"Dual-Core Xeon 7200",
	"Quad-Core Xeon 7300",
	"Quad-Core Xeon 7400",
	"Multi-Core Xeon 7400",			/* 0xAF */
	"Pentium III Xeon",
	"Pentium III Speedstep",
	"Pentium 4",
	"Xeon",
	"AS400",
	"Xeon MP",
	"Athlon XP",
	"Athlon MP",
	"Itanium 2",
	"Pentium M",
	"Celeron D",		/* 0xBA */
	"Pentium D",
	"Pentium EE",
	"Core Solo",		/* 0xBD */
	NULL,
	"Core 2 Duo",
	"Core 2 Solo",
	"Core 2 Extreme",
	"Core 2 Quad",
	"Core 2 Extreme Mobile",
	"Core 2 Duo Mobile",
	"Core 2 Solo Mobile",
	"Core i7",
	"Dual-Core Celeron",		/* 0xC7 */
	"IBM390",
	"G4",
	"G5",
	"ESA/390 G6",		/* 0xCB */
	"z/Architectur",
	NULL,
	NULL,
	NULL,
	NULL,			/*0xD0 */
	NULL,
	"C7-M",
	"C7-D",
	"C7",
	"Eden",
	"Multi-Core Xeon",			/*0xD6 */
	"Dual-Core Xeon 3xxx",
	"Quad-Core Xeon 3xxx",  /*0xD8 */
	NULL,
	"Dual-Core Xeon 5xxx", /*0xDA */
	"Quad-Core Xeon 5xxx",
	NULL,
	"Dual-Core Xeon 7xxx", /*0xDD */
	"Quad-Core Xeon 7xxx",
	"Multi-Core Xeon 7xxx",
	NULL,			/*0xE0 */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	"Embedded Opteron Quad-Core",	/* 0xE6 */
	"Phenom Triple-Core",
	"Turion Ultra Dual-Core Mobile",
	"Turion Dual-Core Mobile",
	"Athlon Dual-Core",
	"Sempron SI",		/*0xEB */
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,			/* 0xF9 */
	"i860",
	"i960",
	NULL,			/* 0xFC */
	NULL,
	NULL,
	NULL,			/* 0xFF */
    };
    /* Special case for ambiguous value 0xBE */
    if (code == 0xBE) {
	/* Best bet based on manufacturer string */
	if (strstr(manufacturer, "Intel") != NULL
	    || strncasecmp(manufacturer, "Intel", 5) == 0)
	    return "Core 2";
	if (strstr(manufacturer, "AMD") != NULL
	    || strncasecmp(manufacturer, "AMD", 3) == 0)
	    return "K7";
	return "Core 2 or K7";
    }

    if (family[code] != NULL) {
	return family[code];
    }
    return out_of_spec;
}

const char *dmi_processor_status(uint8_t code)
{
    static const char *status[] = {
	"Unknown",		/* 0x00 */
	"Enabled",
	"Disabled By User",
	"Disabled By BIOS",
	"Idle",			/* 0x04 */
	"<OUT OF SPEC>",
	"<OUT OF SPEC>",
	"Other"			/* 0x07 */
    };

    if (code <= 0x04)
	return status[code];
    if (code == 0x07)
	return status[0x05];
    return out_of_spec;
}

const char *dmi_processor_upgrade(uint8_t code)
{
    /* 3.3.5.5 */
    static const char *upgrade[] = {
	"Other",		/* 0x01 */
	"Unknown",
	"Daughter Board",
	"ZIF Socket",
	"Replaceable Piggy Back",
	"None",
	"LIF Socket",
	"Slot 1",
	"Slot 2",
	"370-pin Socket",
	"Slot A",
	"Slot M",
	"Socket 423",
	"Socket A (Socket 462)",
	"Socket 478",
	"Socket 754",
	"Socket 940",
	"Socket 939"		/* 0x12 */
	"Socket mPGA604",
	"Socket LGA771",
	"Socket LGA775",
	"Socket S1",
	"Socket AM2",
	"Socket F (1207)"
	"Socket LGA1366"	/* 0x19 */
    };

    if (code >= 0x01 && code <= 0x19)
	return upgrade[code - 0x01];
    return out_of_spec;
}

void dmi_processor_cache(uint16_t code, const char *level, uint16_t ver,
			 char *cache)
{
    if (code == 0xFFFF) {
	if (ver >= 0x0203)
	    sprintf(cache, "Not Provided");
	else
	    sprintf(cache, "No %s Cache", level);
    } else
	sprintf(cache, "0x%04X", code);
}

/* Intel AP-485 revision 28, table 5 */
const char *cpu_flags_strings[PROCESSOR_FLAGS_ELEMENTS] = {
    "FPU (Floating-point unit on-chip)",	/* 0 */
    "VME (Virtual mode extension)",
    "DE (Debugging extension)",
    "PSE (Page size extension)",
    "TSC (Time stamp counter)",
    "MSR (Model specific registers)",
    "PAE (Physical address extension)",
    "MCE (Machine check exception)",
    "CX8 (CMPXCHG8 instruction supported)",
    "APIC (On-chip APIC hardware supported)",
    NULL,			/* 10 */
    "SEP (Fast system call)",
    "MTRR (Memory type range registers)",
    "PGE (Page global enable)",
    "MCA (Machine check architecture)",
    "CMOV (Conditional move instruction supported)",
    "PAT (Page attribute table)",
    "PSE-36 (36-bit page size extension)",
    "PSN (Processor serial number present and enabled)",
    "CLFSH (CLFLUSH instruction supported)",
    NULL,			/* 20 */
    "DS (Debug store)",
    "ACPI (ACPI supported)",
    "MMX (MMX technology supported)",
    "FXSR (Fast floating-point save and restore)",
    "SSE (Streaming SIMD extensions)",
    "SSE2 (Streaming SIMD extensions 2)",
    "SS (Self-snoop)",
    "HTT (Hyper-threading technology)",
    "TM (Thermal monitor supported)",
    "IA64 (IA64 capabilities)",	/* 30 */
    "PBE (Pending break enabled)"	/* 31 */
};
