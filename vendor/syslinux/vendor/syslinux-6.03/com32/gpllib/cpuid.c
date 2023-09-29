/*
 * Portions of this file taken from the Linux kernel,
 * Copyright 1991-2009 Linus Torvalds and contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
*/

#include <stdio.h>
#include <string.h>
#include "cpuid.h"

const char *cpu_flags_names[] = {
    CPU_FLAGS(STRUCT_MEMBER_NAMES)
};

size_t cpu_flags_offset[] = {
    CPU_FLAGS(STRUCTURE_MEMBER_OFFSETS)
};

size_t cpu_flags_count = sizeof cpu_flags_names / sizeof *cpu_flags_names;

struct cpu_dev *cpu_devs[X86_VENDOR_NUM] = { };

bool get_cpu_flag_value_from_name(s_cpu *cpu, const char * flag_name) {
    size_t i;
    bool cpu_flag_present=false, *flag_value = &cpu_flag_present;

    for (i = 0; i < cpu_flags_count; i++) {
	if (strcmp(cpu_flags_names[i],flag_name) == 0) {
        	flag_value = (bool *)((char *)&cpu->flags + cpu_flags_offset[i]);
	}
    }
    return *flag_value;
}


/*
* CPUID functions returning a single datum
*/

/* Probe for the CPUID instruction */
static int have_cpuid_p(void)
{
    return cpu_has_eflag(X86_EFLAGS_ID);
}

static struct cpu_dev amd_cpu_dev = {
    .c_vendor = "AMD",
    .c_ident = {"AuthenticAMD"}
};

static struct cpu_dev intel_cpu_dev = {
    .c_vendor = "Intel",
    .c_ident = {"GenuineIntel"}
};

static struct cpu_dev cyrix_cpu_dev = {
    .c_vendor = "Cyrix",
    .c_ident = {"CyrixInstead"}
};

static struct cpu_dev umc_cpu_dev = {
    .c_vendor = "UMC",
    .c_ident = {"UMC UMC UMC"}

};

static struct cpu_dev nexgen_cpu_dev = {
    .c_vendor = "Nexgen",
    .c_ident = {"NexGenDriven"}
};

static struct cpu_dev centaur_cpu_dev = {
    .c_vendor = "Centaur",
    .c_ident = {"CentaurHauls"}
};

static struct cpu_dev rise_cpu_dev = {
    .c_vendor = "Rise",
    .c_ident = {"RiseRiseRise"}
};

static struct cpu_dev transmeta_cpu_dev = {
    .c_vendor = "Transmeta",
    .c_ident = {"GenuineTMx86", "TransmetaCPU"}
};

static struct cpu_dev nsc_cpu_dev = {
    .c_vendor = "National Semiconductor",
    .c_ident = {"Geode by NSC"}
};

static struct cpu_dev unknown_cpu_dev = {
    .c_vendor = "Unknown Vendor",
    .c_ident = {"Unknown CPU"}
};

/*
 * Read NSC/Cyrix DEVID registers (DIR) to get more detailed info. about the CPU
 */
void do_cyrix_devid(unsigned char *dir0, unsigned char *dir1)
{
	unsigned char ccr2, ccr3;

	/* we test for DEVID by checking whether CCR3 is writable */
	ccr3 = getCx86(CX86_CCR3);
	setCx86(CX86_CCR3, ccr3 ^ 0x80);
	getCx86(0xc0);   /* dummy to change bus */

	if (getCx86(CX86_CCR3) == ccr3) {       /* no DEVID regs. */
		ccr2 = getCx86(CX86_CCR2);
		setCx86(CX86_CCR2, ccr2 ^ 0x04);
		getCx86(0xc0);  /* dummy */

		if (getCx86(CX86_CCR2) == ccr2) /* old Cx486SLC/DLC */
			*dir0 = 0xfd;
		else {                          /* Cx486S A step */
			setCx86(CX86_CCR2, ccr2);
			*dir0 = 0xfe;
		}
	} else {
		setCx86(CX86_CCR3, ccr3);  /* restore CCR3 */

		/* read DIR0 and DIR1 CPU registers */
		*dir0 = getCx86(CX86_DIR0);
		*dir1 = getCx86(CX86_DIR1);
	}
}

void init_cpu_devs(void)
{
    cpu_devs[X86_VENDOR_INTEL] = &intel_cpu_dev;
    cpu_devs[X86_VENDOR_CYRIX] = &cyrix_cpu_dev;
    cpu_devs[X86_VENDOR_AMD] = &amd_cpu_dev;
    cpu_devs[X86_VENDOR_UMC] = &umc_cpu_dev;
    cpu_devs[X86_VENDOR_NEXGEN] = &nexgen_cpu_dev;
    cpu_devs[X86_VENDOR_CENTAUR] = &centaur_cpu_dev;
    cpu_devs[X86_VENDOR_RISE] = &rise_cpu_dev;
    cpu_devs[X86_VENDOR_TRANSMETA] = &transmeta_cpu_dev;
    cpu_devs[X86_VENDOR_NSC] = &nsc_cpu_dev;
    cpu_devs[X86_VENDOR_UNKNOWN] = &unknown_cpu_dev;
}

void get_cpu_vendor(struct cpuinfo_x86 *c)
{
    char *v = c->x86_vendor_id;
    int i;
    init_cpu_devs();
    for (i = 0; i < X86_VENDOR_NUM-1; i++) {
	if (cpu_devs[i]) {
	    if (!strcmp(v, cpu_devs[i]->c_ident[0]) ||
		(cpu_devs[i]->c_ident[1] &&
		 !strcmp(v, cpu_devs[i]->c_ident[1]))) {
		c->x86_vendor = i;
		return;
	    }
	}
    }

    c->x86_vendor = X86_VENDOR_UNKNOWN;
}

int get_model_name(struct cpuinfo_x86 *c)
{
    unsigned int *v;
    char *p, *q;

    if (cpuid_eax(0x80000000) < 0x80000004)
	return 0;

    v = (unsigned int *)c->x86_model_id;
    cpuid(0x80000002, &v[0], &v[1], &v[2], &v[3]);
    cpuid(0x80000003, &v[4], &v[5], &v[6], &v[7]);
    cpuid(0x80000004, &v[8], &v[9], &v[10], &v[11]);
    c->x86_model_id[48] = 0;

    /* Intel chips right-justify this string for some dumb reason;
       undo that brain damage */
    p = q = &c->x86_model_id[0];
    while (*p == ' ')
	p++;
    if (p != q) {
	while (*p)
	    *q++ = *p++;
	while (q <= &c->x86_model_id[48])
	    *q++ = '\0';	/* Zero-pad the rest */
    }

    return 1;
}

void detect_cache(uint32_t xlvl, struct cpuinfo_x86 *c)
{
    uint32_t eax, ebx, ecx, edx, l2size;
    /* Detecting L1 cache */
    if (xlvl >= 0x80000005) {
	cpuid(0x80000005, &eax, &ebx, &ecx, &edx);
	c->x86_l1_data_cache_size = ecx >> 24;
	c->x86_l1_instruction_cache_size = edx >> 24;
    }

    /* Detecting L2 cache */
    c->x86_l2_cache_size = 0;

    if (xlvl < 0x80000006)	/* Some chips just has a large L1. */
	return;

    cpuid(0x80000006, &eax, &ebx, &ecx, &edx);
    l2size = ecx >> 16;

    /* Vendor based fixes */
    switch (c->x86_vendor) {
    case X86_VENDOR_INTEL:
	/*
	 * Intel PIII Tualatin. This comes in two flavours.
	 * One has 256kb of cache, the other 512. We have no way
	 * to determine which, so we use a boottime override
	 * for the 512kb model, and assume 256 otherwise.
	 */
	if ((c->x86 == 6) && (c->x86_model == 11) && (l2size == 0))
	    l2size = 256;
	break;
    case X86_VENDOR_AMD:
	/* AMD errata T13 (order #21922) */
	if ((c->x86 == 6)) {
	    if (c->x86_model == 3 && c->x86_mask == 0)	/* Duron Rev A0 */
		l2size = 64;
	    if (c->x86_model == 4 && (c->x86_mask == 0 || c->x86_mask == 1))	/* Tbird rev A1/A2 */
		l2size = 256;
	}
	break;
    }
    c->x86_l2_cache_size = l2size;
}

void detect_cyrix(struct cpuinfo_x86 *c) {
	unsigned char dir0, dir0_msn, dir0_lsn, dir1 = 0;
        char *buf = c->x86_model_id;
	char Cx86_cb[] = "?.5x Core/Bus Clock";
	const char cyrix_model_mult1[] = "12??43";
	const char cyrix_model_mult2[] = "12233445";
        const char *p = NULL;

	do_cyrix_devid(&dir0, &dir1);
	dir0_msn = dir0 >> 4; /* identifies CPU "family"   */
	dir0_lsn = dir0 & 0xf;                /* model or clock multiplier */
	c->x86_model = (dir1 >> 4) + 1;
        c->x86_mask = dir1 & 0xf;
	switch (dir0_msn) {
		unsigned char tmp;

	        case 0: /* Cx486SLC/DLC/SRx/DRx */
                	 p = Cx486_name[dir0_lsn & 7];
			 break;
	
		case 1: /* Cx486S/DX/DX2/DX4 */
	                 p = (dir0_lsn & 8) ? Cx486D_name[dir0_lsn & 5] : Cx486S_name[dir0_lsn & 3];
			 break;

	         case 2: /* 5x86 */
	                 Cx86_cb[2] = cyrix_model_mult1[dir0_lsn & 5];
			 p = Cx86_cb+2;
			 break;

		case 3: /* 6x86/6x86L */
			   Cx86_cb[1] = ' ';
			   Cx86_cb[2] = cyrix_model_mult1[dir0_lsn & 5];
			   if (dir1 > 0x21) { /* 686L */
				   Cx86_cb[0] = 'L';
				   p = Cx86_cb;
				   (c->x86_model)++;
			   } else             /* 686 */
				   p = Cx86_cb+1;
			   
			   c->coma_bug = 1;
			   break;
		case 4:
	                   c->x86_l1_data_cache_size = 16; /* Yep 16K integrated cache thats it */
			   if (c->cpuid_level != 2) { /* Media GX */
				   Cx86_cb[2] = (dir0_lsn & 1) ? '3' : '4';
				   p = Cx86_cb+2;
			   }
			   break;
		
		case 5: /* 6x86MX/M II */
			   if (dir1 > 7) {
				   dir0_msn++;  /* M II */
			   } else {
	                           c->coma_bug = 1;      /* 6x86MX, it has the bug. */
			   }

			   tmp = (!(dir0_lsn & 7) || dir0_lsn & 1) ? 2 : 0;
			   Cx86_cb[tmp] = cyrix_model_mult2[dir0_lsn & 7];
			   p = Cx86_cb+tmp;
			   if (((dir1 & 0x0f) > 4) || ((dir1 & 0xf0) == 0x20))
				   (c->x86_model)++;
			   break;
		
		case 0xf:  /* Cyrix 486 without DEVID registers */
			   switch (dir0_lsn) {
				   case 0xd:  /* either a 486SLC or DLC w/o DEVID */
					   dir0_msn = 0; 
					   p = Cx486_name[(c->hard_math) ? 1 : 0];
					   break;
				   
				   case 0xe:  /* a 486S A step */
					   dir0_msn = 0;
					   p = Cx486S_name[0];
					   break;
			   }
			   break;
			   
		default:
			   dir0_msn = 7;
			   break;
	}

	/* If the processor is unknown, we keep the model name we got
	 * from the generic call */
	if (dir0_msn < 7) {	
		strcpy(buf, Cx86_model[dir0_msn & 7]);
		if (p) strcat(buf, p);
	}
}

void generic_identify(struct cpuinfo_x86 *c)
{
    uint32_t tfms, xlvl;
    uint32_t eax, ebx, ecx, edx;

    /* Get vendor name */
    cpuid(0x00000000,
	  (uint32_t *) & c->cpuid_level,
	  (uint32_t *) & c->x86_vendor_id[0],
	  (uint32_t *) & c->x86_vendor_id[8],
	  (uint32_t *) & c->x86_vendor_id[4]);

    get_cpu_vendor(c);

    /* Intel-defined flags: level 0x00000001 */
    if (c->cpuid_level >= 0x00000001) {
	uint32_t capability, excap;
	cpuid(0x00000001, &tfms, &ebx, &excap, &capability);
	c->x86_capability[0] = capability;
	c->x86_capability[4] = excap;
	c->x86 = (tfms >> 8) & 15;
	c->x86_model = (tfms >> 4) & 15;
	if (c->x86 == 0xf)
	    c->x86 += (tfms >> 20) & 0xff;
	if (c->x86 >= 0x6)
	    c->x86_model += ((tfms >> 16) & 0xF) << 4;
	c->x86_mask = tfms & 15;
	if (cpu_has(c, X86_FEATURE_CLFLSH))
	    c->x86_clflush_size = ((ebx >> 8) & 0xff) * 8;
    } else {
	/* Have CPUID level 0 only - unheard of */
	c->x86 = 4;
    }

    /* AMD-defined flags: level 0x80000001 */
    xlvl = cpuid_eax(0x80000000);
    if ((xlvl & 0xffff0000) == 0x80000000) {
	if (xlvl >= 0x80000001) {
	    c->x86_capability[1] = cpuid_edx(0x80000001);
	    c->x86_capability[6] = cpuid_ecx(0x80000001);
	}
	if (xlvl >= 0x80000004)
	    get_model_name(c);	/* Default name */
    }

    /* Specific detection code */
    switch (c->x86_vendor) {
	    case X86_VENDOR_CYRIX:
	    case X86_VENDOR_NSC: detect_cyrix(c); break;
	    default: break;
    }

    /* Detecting the number of cores */
    switch (c->x86_vendor) {
    case X86_VENDOR_AMD:
	if (xlvl >= 0x80000008) {
	    c->x86_num_cores = (cpuid_ecx(0x80000008) & 0xff) + 1;
	    if (c->x86_num_cores & (c->x86_num_cores - 1))
		c->x86_num_cores = 1;
	}
	break;
    case X86_VENDOR_INTEL:
	if (c->cpuid_level >= 0x00000004) {
	    cpuid(0x4, &eax, &ebx, &ecx, &edx);
	    c->x86_num_cores = ((eax & 0xfc000000) >> 26) + 1;
	}
	break;
    default:
	c->x86_num_cores = 1;
	break;
    }

    detect_cache(xlvl, c);
}

/*
 * Checksum an MP configuration block.
 */

static int mpf_checksum(unsigned char *mp, int len)
{
    int sum = 0;

    while (len--)
	sum += *mp++;

    return sum & 0xFF;
}

static int smp_scan_config(unsigned long base, unsigned long length)
{
    unsigned long *bp = (unsigned long *)base;
    struct intel_mp_floating *mpf;

//        printf("Scan SMP from %p for %ld bytes.\n", bp,length);
    if (sizeof(*mpf) != 16) {
	printf("Error: MPF size\n");
	return 0;
    }

    while (length > 0) {
	mpf = (struct intel_mp_floating *)bp;
	if ((*bp == SMP_MAGIC_IDENT) &&
	    (mpf->mpf_length == 1) &&
	    !mpf_checksum((unsigned char *)bp, 16) &&
	    ((mpf->mpf_specification == 1)
	     || (mpf->mpf_specification == 4))) {
	    return 1;
	}
	bp += 4;
	length -= 16;
    }
    return 0;
}

int find_smp_config(void)
{
//        unsigned int address;

    /*
     * FIXME: Linux assumes you have 640K of base ram..
     * this continues the error...
     *
     * 1) Scan the bottom 1K for a signature
     * 2) Scan the top 1K of base RAM
     * 3) Scan the 64K of bios
     */
    if (smp_scan_config(0x0, 0x400) ||
	smp_scan_config(639 * 0x400, 0x400) ||
	smp_scan_config(0xF0000, 0x10000))
	return 1;
    /*
     * If it is an SMP machine we should know now, unless the
     * configuration is in an EISA/MCA bus machine with an
     * extended bios data area.
     *
     * there is a real-mode segmented pointer pointing to the
     * 4K EBDA area at 0x40E, calculate and scan it here.
     *
     * NOTE! There are Linux loaders that will corrupt the EBDA
     * area, and as such this kind of SMP config may be less
     * trustworthy, simply because the SMP table may have been
     * stomped on during early boot. These loaders are buggy and
     * should be fixed.
     *
     * MP1.4 SPEC states to only scan first 1K of 4K EBDA.
     */

//        address = get_bios_ebda();
//        if (address)
//                smp_scan_config(address, 0x400);
    return 0;
}

void set_cpu_flags(struct cpuinfo_x86 *c, s_cpu * cpu)
{
    cpu->flags.fpu = cpu_has(c, X86_FEATURE_FPU);
    cpu->flags.vme = cpu_has(c, X86_FEATURE_VME);
    cpu->flags.de = cpu_has(c, X86_FEATURE_DE);
    cpu->flags.pse = cpu_has(c, X86_FEATURE_PSE);
    cpu->flags.tsc = cpu_has(c, X86_FEATURE_TSC);
    cpu->flags.msr = cpu_has(c, X86_FEATURE_MSR);
    cpu->flags.pae = cpu_has(c, X86_FEATURE_PAE);
    cpu->flags.mce = cpu_has(c, X86_FEATURE_MCE);
    cpu->flags.cx8 = cpu_has(c, X86_FEATURE_CX8);
    cpu->flags.apic = cpu_has(c, X86_FEATURE_APIC);
    cpu->flags.sep = cpu_has(c, X86_FEATURE_SEP);
    cpu->flags.mtrr = cpu_has(c, X86_FEATURE_MTRR);
    cpu->flags.pge = cpu_has(c, X86_FEATURE_PGE);
    cpu->flags.mca = cpu_has(c, X86_FEATURE_MCA);
    cpu->flags.cmov = cpu_has(c, X86_FEATURE_CMOV);
    cpu->flags.pat = cpu_has(c, X86_FEATURE_PAT);
    cpu->flags.pse_36 = cpu_has(c, X86_FEATURE_PSE36);
    cpu->flags.psn = cpu_has(c, X86_FEATURE_PN);
    cpu->flags.clflsh = cpu_has(c, X86_FEATURE_CLFLSH);
    cpu->flags.dts = cpu_has(c, X86_FEATURE_DTES);
    cpu->flags.acpi = cpu_has(c, X86_FEATURE_ACPI);
    cpu->flags.pbe = cpu_has(c, X86_FEATURE_PBE);
    cpu->flags.mmx = cpu_has(c, X86_FEATURE_MMX);
    cpu->flags.fxsr = cpu_has(c, X86_FEATURE_FXSR);
    cpu->flags.sse = cpu_has(c, X86_FEATURE_XMM);
    cpu->flags.sse2 = cpu_has(c, X86_FEATURE_XMM2);
    cpu->flags.ss = cpu_has(c, X86_FEATURE_SELFSNOOP);
    cpu->flags.htt = cpu_has(c, X86_FEATURE_HT);
    cpu->flags.acc = cpu_has(c, X86_FEATURE_ACC);
    cpu->flags.syscall = cpu_has(c, X86_FEATURE_SYSCALL);
    cpu->flags.mp = cpu_has(c, X86_FEATURE_MP);
    cpu->flags.nx = cpu_has(c, X86_FEATURE_NX);
    cpu->flags.mmxext = cpu_has(c, X86_FEATURE_MMXEXT);
    cpu->flags.fxsr_opt = cpu_has(c, X86_FEATURE_FXSR_OPT);
    cpu->flags.gbpages = cpu_has(c, X86_FEATURE_GBPAGES);
    cpu->flags.rdtscp = cpu_has(c, X86_FEATURE_RDTSCP);
    cpu->flags.lm = cpu_has(c, X86_FEATURE_LM);
    cpu->flags.nowext = cpu_has(c, X86_FEATURE_3DNOWEXT);
    cpu->flags.now = cpu_has(c, X86_FEATURE_3DNOW);
    cpu->flags.smp = find_smp_config();
    cpu->flags.pni = cpu_has(c, X86_FEATURE_XMM3);
    cpu->flags.pclmulqd = cpu_has(c, X86_FEATURE_PCLMULQDQ);
    cpu->flags.dtes64 = cpu_has(c, X86_FEATURE_DTES64);
    cpu->flags.vmx = cpu_has(c, X86_FEATURE_VMX);
    cpu->flags.smx = cpu_has(c, X86_FEATURE_SMX);
    cpu->flags.est = cpu_has(c, X86_FEATURE_EST);
    cpu->flags.tm2 = cpu_has(c, X86_FEATURE_TM2);
    cpu->flags.sse3 = cpu_has(c, X86_FEATURE_SSE3);
    cpu->flags.cid = cpu_has(c, X86_FEATURE_CID);
    cpu->flags.fma = cpu_has(c, X86_FEATURE_FMA);
    cpu->flags.cx16 = cpu_has(c, X86_FEATURE_CX16);
    cpu->flags.xtpr = cpu_has(c, X86_FEATURE_XTPR);
    cpu->flags.pdcm = cpu_has(c, X86_FEATURE_PDCM);
    cpu->flags.dca = cpu_has(c, X86_FEATURE_DCA);
    cpu->flags.xmm4_1 = cpu_has(c, X86_FEATURE_XMM4_1);
    cpu->flags.xmm4_2 = cpu_has(c, X86_FEATURE_XMM4_2);
    cpu->flags.x2apic = cpu_has(c, X86_FEATURE_X2APIC);
    cpu->flags.movbe = cpu_has(c, X86_FEATURE_MOVBE);
    cpu->flags.popcnt = cpu_has(c, X86_FEATURE_POPCNT);
    cpu->flags.aes = cpu_has(c, X86_FEATURE_AES);
    cpu->flags.xsave = cpu_has(c, X86_FEATURE_XSAVE);
    cpu->flags.osxsave = cpu_has(c, X86_FEATURE_OSXSAVE);
    cpu->flags.avx = cpu_has(c, X86_FEATURE_AVX);
    cpu->flags.hypervisor = cpu_has(c, X86_FEATURE_HYPERVISOR);
    cpu->flags.ace2 = cpu_has(c, X86_FEATURE_ACE2);
    cpu->flags.ace2_en = cpu_has(c, X86_FEATURE_ACE2_EN);
    cpu->flags.phe = cpu_has(c, X86_FEATURE_PHE);
    cpu->flags.phe_en = cpu_has(c, X86_FEATURE_PHE_EN);
    cpu->flags.pmm = cpu_has(c, X86_FEATURE_PMM);
    cpu->flags.pmm_en = cpu_has(c, X86_FEATURE_PMM_EN);
    cpu->flags.extapic = cpu_has(c, X86_FEATURE_EXTAPIC);
    cpu->flags.cr8_legacy = cpu_has(c, X86_FEATURE_CR8_LEGACY);
    cpu->flags.abm = cpu_has(c, X86_FEATURE_ABM);
    cpu->flags.sse4a = cpu_has(c, X86_FEATURE_SSE4A);
    cpu->flags.misalignsse = cpu_has(c, X86_FEATURE_MISALIGNSSE);
    cpu->flags.nowprefetch = cpu_has(c, X86_FEATURE_3DNOWPREFETCH);
    cpu->flags.osvw = cpu_has(c, X86_FEATURE_OSVW);
    cpu->flags.ibs = cpu_has(c, X86_FEATURE_IBS);
    cpu->flags.sse5 = cpu_has(c, X86_FEATURE_SSE5);
    cpu->flags.skinit = cpu_has(c, X86_FEATURE_SKINIT);
    cpu->flags.wdt = cpu_has(c, X86_FEATURE_WDT);
    cpu->flags.ida = cpu_has(c, X86_FEATURE_IDA);
    cpu->flags.arat = cpu_has(c, X86_FEATURE_ARAT);
    cpu->flags.tpr_shadow = cpu_has(c, X86_FEATURE_TPR_SHADOW);
    cpu->flags.vnmi = cpu_has(c, X86_FEATURE_VNMI);
    cpu->flags.flexpriority = cpu_has(c, X86_FEATURE_FLEXPRIORITY);
    cpu->flags.ept = cpu_has(c, X86_FEATURE_EPT);
    cpu->flags.vpid = cpu_has(c, X86_FEATURE_VPID);
    cpu->flags.svm = cpu_has(c, X86_FEATURE_SVM);
}

void set_generic_info(struct cpuinfo_x86 *c, s_cpu * cpu)
{
    cpu->family = c->x86;
    cpu->vendor_id = c->x86_vendor;
    cpu->model_id = c->x86_model;
    cpu->stepping = c->x86_mask;
    strlcpy(cpu->vendor, cpu_devs[c->x86_vendor]->c_vendor,
	    sizeof(cpu->vendor));
    strlcpy(cpu->model, c->x86_model_id, sizeof(cpu->model));
    cpu->num_cores = c->x86_num_cores;
    cpu->l1_data_cache_size = c->x86_l1_data_cache_size;
    cpu->l1_instruction_cache_size = c->x86_l1_instruction_cache_size;
    cpu->l2_cache_size = c->x86_l2_cache_size;
}

void detect_cpu(s_cpu * cpu)
{
    struct cpuinfo_x86 c;
    memset(&c,0,sizeof(c));
    c.x86_clflush_size = 32;
    c.x86_vendor = X86_VENDOR_UNKNOWN;
    c.cpuid_level = -1;		/* CPUID not detected */
    c.x86_num_cores = 1;
    memset(&cpu->flags, 0, sizeof(s_cpu_flags));

    if (!have_cpuid_p())
	return;

    generic_identify(&c);
    set_generic_info(&c, cpu);
    set_cpu_flags(&c, cpu);
}
