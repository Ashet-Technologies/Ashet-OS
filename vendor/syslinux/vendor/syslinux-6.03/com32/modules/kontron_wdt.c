/*
 *  kempld_wdt.c - Kontron PLD watchdog driver
 *
 *  Copyright (c) 2010 Kontron Embedded Modules GmbH
 *  Author: Michael Brunner <michael.brunner@kontron.com>
 *  Author: Erwan Velu <erwan.velu@zodiacaerospace.com>
 *
 *  Note: From the PLD watchdog point of view timeout and pretimeout are
 *        defined differently than in the kernel.
 *        First the pretimeout stage runs out before the timeout stage gets
 *        active. This has to be kept in mind.
 *
 *  Kernel/API:                     P-----| pretimeout
 *                |-----------------------T timeout
 *  Watchdog:     |-----------------P       pretimeout_stage
 *                                  |-----T timeout_stage
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License 2 as published
 *  by the Free Software Foundation.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; see the file COPYING.  If not, write to
 *  the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <string.h>
#include <sys/io.h>
#include <unistd.h>
#include <syslinux/boot.h>
#include <stdio.h>
#include <stdlib.h>
#include <console.h>
#include "kontron_wdt.h"

struct kempld_device_data  pld;
struct kempld_watchdog_data wdt;
uint8_t status;
char default_label[255];

/* Default Timeout is 60sec */
#define TIMEOUT 60
#define PRETIMEOUT 0

#define do_div(n,base) ({ \
		int __res; \
		__res = ((unsigned long) n) % (unsigned) base; \
		n = ((unsigned long) n) / (unsigned) base; \
		__res; })


/* Basic Wrappers to get code as less changed as possible */
void iowrite8(uint8_t val, uint16_t addr) { outb(val,addr); }
void iowrite16(uint16_t val, uint16_t addr) { outw(val,addr); }
void iowrite32(uint32_t val, uint16_t addr) { outl(val,addr);}
uint8_t ioread8(uint16_t addr)   { return inb(addr);}
uint16_t ioread16(uint16_t addr) { return inw(addr);}
uint32_t ioread32(uint32_t addr) { return inl(addr);}


/**
 * kempld_set_index -  change the current register index of the PLD
 * @pld:   kempld_device_data structure describing the PLD
 * @index: register index on the chip
 *
 * This function changes the register index of the PLD.
 */
void kempld_set_index(struct kempld_device_data *pld, uint8_t index)
{
        if (pld->last_index != index) {
                iowrite8(index, pld->io_index);
                pld->last_index = index;
        }
}


uint8_t kempld_read8(struct kempld_device_data *pld, uint8_t index) {
        kempld_set_index(pld, index);
        return ioread8(pld->io_data);
}


void kempld_write8(struct kempld_device_data *pld, uint8_t index, uint8_t data) {
        kempld_set_index(pld, index);
        iowrite8(data, pld->io_data);
}


uint16_t kempld_read16(struct kempld_device_data *pld, uint8_t index)
{
        return kempld_read8(pld, index) | kempld_read8(pld, index+1) << 8;
}


void kempld_write16(struct kempld_device_data *pld, uint8_t index, uint16_t data)
{
        kempld_write8(pld, index, (uint8_t)data);
        kempld_write8(pld, index+1, (uint8_t)(data>>8));
}

uint32_t kempld_read32(struct kempld_device_data *pld, uint8_t index)
{
        return kempld_read16(pld, index) | kempld_read16(pld, index+2) << 16;
}

void kempld_write32(struct kempld_device_data *pld, uint8_t index, uint32_t data)
{
        kempld_write16(pld, index, (uint16_t)data);
        kempld_write16(pld, index+2, (uint16_t)(data>>16));
}

static void kempld_release_mutex(struct kempld_device_data *pld)
{
        iowrite8(pld->last_index | KEMPLD_MUTEX_KEY, pld->io_index);
}

void init_structure(void) {
	/* set default values for the case we start the watchdog or change
	 * the configuration */
	memset(&wdt,0,sizeof(wdt));
	memset(&pld,0,sizeof(pld));
	memset(&default_label,0,sizeof(default_label));
        wdt.timeout = TIMEOUT;
        wdt.pretimeout = PRETIMEOUT;
        wdt.pld = &pld;

	pld.io_base=KEMPLD_IOPORT;
	pld.io_index=KEMPLD_IOPORT;
	pld.io_data=KEMPLD_IODATA;
	pld.pld_clock=33333333;
}

static int kempld_probe(void) {
   /* Check for empty IO space */
	int ret=0;
	uint8_t  index_reg = ioread8(pld.io_index);
        if ((index_reg == 0xff) && (ioread8(pld.io_data) == 0xff)) {
                ret = 1;
                goto err_empty_io;
        }
	printf("Kempld structure found at 0x%X (data @ 0x%X)\n",pld.io_base,pld.io_data);
	return 0;

err_empty_io:
	printf("No IO Found !\n");
	return ret;
}

static int kempld_wdt_probe_stages(struct kempld_watchdog_data *wdt)
{
        struct kempld_device_data *pld = wdt->pld;
        int i, ret;
        uint32_t timeout;
        uint32_t timeout_mask;
        struct kempld_watchdog_stage *stage;

        wdt->stages = 0;
        wdt->timeout_stage = NULL;
        wdt->pretimeout_stage = NULL;

        for (i = 0; i < KEMPLD_WDT_MAX_STAGES; i++) {

		timeout = kempld_read32(pld, KEMPLD_WDT_STAGE_TIMEOUT(i));
                kempld_write32(pld, KEMPLD_WDT_STAGE_TIMEOUT(i), 0x00000000);
                timeout_mask = kempld_read32(pld, KEMPLD_WDT_STAGE_TIMEOUT(i));
                kempld_write32(pld, KEMPLD_WDT_STAGE_TIMEOUT(i), timeout);

                if (timeout_mask != 0xffffffff) {
                        stage = malloc(sizeof(struct kempld_watchdog_stage));
                        if (stage == NULL) {
                                ret = -1;
                                goto err_alloc_stages;
                        }
                        stage->num = i;
                        stage->timeout_mask = ~timeout_mask;
                        wdt->stage[i] = stage;
                        wdt->stages++;

                        /* assign available stages to timeout and pretimeout */
                        if (wdt->stages == 1)
                                wdt->timeout_stage = stage;
                        else if (wdt->stages == 2) {
                                wdt->pretimeout_stage = wdt->timeout_stage;
                                wdt->timeout_stage = stage;
                        }
                } else {
                        wdt->stage[i] = NULL;
                }
        }

        return 0;
err_alloc_stages:
	kempld_release_mutex(pld);
	printf("Cannot allocate stages\n");
	return ret;
}

static int kempld_wdt_keepalive(struct kempld_watchdog_data *wdt)
{
        struct kempld_device_data *pld = wdt->pld;

	kempld_write8(pld, KEMPLD_WDT_KICK, 'K');

        return 0;
}

static int kempld_wdt_setstageaction(struct kempld_watchdog_data *wdt,
                                 struct kempld_watchdog_stage *stage,
                                 int action)
{
        struct kempld_device_data *pld = wdt->pld;
        uint8_t stage_cfg;

        if (stage == NULL)
                return -1;

        stage_cfg = kempld_read8(pld, KEMPLD_WDT_STAGE_CFG(stage->num));
        stage_cfg &= ~KEMPLD_WDT_STAGE_CFG_ACTION_MASK;
        stage_cfg |= (action & KEMPLD_WDT_STAGE_CFG_ACTION_MASK);
        if (action == KEMPLD_WDT_ACTION_RESET)
                stage_cfg |= KEMPLD_WDT_STAGE_CFG_ASSERT;
        else
                stage_cfg &= ~KEMPLD_WDT_STAGE_CFG_ASSERT;

        kempld_write8(pld, KEMPLD_WDT_STAGE_CFG(stage->num), stage_cfg);
        stage_cfg = kempld_read8(pld, KEMPLD_WDT_STAGE_CFG(stage->num));

        return 0;
}

static int kempld_wdt_setstagetimeout(struct kempld_watchdog_data *wdt,
                                 struct kempld_watchdog_stage *stage,
                                 int timeout)
{
        struct kempld_device_data *pld = wdt->pld;
        uint8_t stage_cfg;
        uint8_t prescaler;
        uint64_t stage_timeout64;
        uint32_t stage_timeout;

        if (stage == NULL)
                return -1;

        prescaler = KEMPLD_WDT_PRESCALER_21BIT;

        stage_timeout64 = ((uint64_t)timeout*pld->pld_clock);
        do_div(stage_timeout64, KEMPLD_PRESCALER(prescaler));
        stage_timeout = stage_timeout64 & stage->timeout_mask;

        if (stage_timeout64 != (uint64_t)stage_timeout)
                return -1;

        stage_cfg = kempld_read8(pld, KEMPLD_WDT_STAGE_CFG(stage->num));
        stage_cfg &= ~KEMPLD_WDT_STAGE_CFG_PRESCALER_MASK;
        stage_cfg |= KEMPLD_WDT_STAGE_CFG_SET_PRESCALER(prescaler);
        kempld_write8(pld, KEMPLD_WDT_STAGE_CFG(stage->num), stage_cfg);
        kempld_write32(pld, KEMPLD_WDT_STAGE_TIMEOUT(stage->num),
                       stage_timeout);

        return 0;
}


static int kempld_wdt_settimeout(struct kempld_watchdog_data *wdt)
{
        int stage_timeout;
        int stage_pretimeout;
        int ret;
        if ((wdt->timeout <= 0) ||
            (wdt->pretimeout < 0) ||
            (wdt->pretimeout > wdt->timeout)) {
                ret = -1;
                goto err_check_values;
        }

        if ((wdt->pretimeout == 0) || (wdt->pretimeout_stage == NULL)) {
                if (wdt->pretimeout != 0)
                        printf("No pretimeout stage available, only enabling reset!\n");
                stage_pretimeout = 0;
                stage_timeout =  wdt->timeout;
        } else {
                stage_pretimeout = wdt->timeout - wdt->pretimeout;
                stage_timeout =  wdt->pretimeout;
        }

        if (stage_pretimeout != 0) {
                ret = kempld_wdt_setstageaction(wdt, wdt->pretimeout_stage,
                                                KEMPLD_WDT_ACTION_NMI);
        } else if ((stage_pretimeout == 0)
                   && (wdt->pretimeout_stage != NULL)) {
                ret = kempld_wdt_setstageaction(wdt, wdt->pretimeout_stage,
                                                KEMPLD_WDT_ACTION_NONE);
        } else
                ret = 0;
        if (ret)
                goto err_setstage;

        if (stage_pretimeout != 0) {
                ret = kempld_wdt_setstagetimeout(wdt, wdt->pretimeout_stage,
                                                 stage_pretimeout);
                if (ret)
                        goto err_setstage;
        }

        ret = kempld_wdt_setstageaction(wdt, wdt->timeout_stage,
                                        KEMPLD_WDT_ACTION_RESET);
        if (ret)
                goto err_setstage;

        ret = kempld_wdt_setstagetimeout(wdt, wdt->timeout_stage,
                                         stage_timeout);
        if (ret)
                goto err_setstage;

        return 0;
err_setstage:
err_check_values:
        return ret;
}

static int kempld_wdt_start(struct kempld_watchdog_data *wdt)
{
        struct kempld_device_data *pld = wdt->pld;
        uint8_t status;

        status = kempld_read8(pld, KEMPLD_WDT_CFG);
        status |= KEMPLD_WDT_CFG_ENABLE;
        kempld_write8(pld, KEMPLD_WDT_CFG, status);
        status = kempld_read8(pld, KEMPLD_WDT_CFG);

        /* check if the watchdog was enabled */
        if (!(status & KEMPLD_WDT_CFG_ENABLE))
                return -1;

        return 0;
}

/* A regular configuration file looks like

   LABEL WDT
       COM32 wdt.c32
       APPEND timeout=120 default_label=local
*/
void detect_parameters(const int argc, const char *argv[]) {
	for (int i = 1; i < argc; i++) {
		/* Override the timeout if specified on the cmdline */
		if (!strncmp(argv[i], "timeout=", 8)) {
			wdt.timeout=atoi(argv[i]+8);
		} else
		/* Define which boot entry shall be used */
		if (!strncmp(argv[i], "default_label=", 14)) {
			strlcpy(default_label, argv[i] + 14, sizeof(default_label));
		}
	}
}

int main(int argc, const char *argv[]) {
	int ret=0;
	openconsole(&dev_rawcon_r, &dev_stdcon_w);
	init_structure();
	detect_parameters(argc,argv);
	kempld_probe();

        /* probe how many usable stages we have */
        if (kempld_wdt_probe_stages(&wdt)) {
		printf("Cannot Probe Stages\n");
		return -1;
	}

	/* Useless but who knows */
	wdt.ident.firmware_version = KEMPLD_WDT_REV_GET(kempld_read8(&pld, KEMPLD_WDT_REV));

        status = kempld_read8(&pld, KEMPLD_WDT_CFG);
	/* kick the watchdog if it is already enabled, otherwise start it */
        if (status & KEMPLD_WDT_CFG_ENABLE) {
		/* Maybye the BIOS did setup a first timer
		 * in this case, let's enforce the timeout
		 * to be sure we do have the proper value */
		kempld_wdt_settimeout(&wdt);
                kempld_wdt_keepalive(&wdt);
        } else {
		ret = kempld_wdt_settimeout(&wdt);
                if (ret) {
			printf("Unable to setup timeout !\n");
			goto booting;
		}

		ret = kempld_wdt_start(&wdt);
                if (ret) {
			printf("Unable to start watchdog !\n");
			goto booting;
		}

        }

	printf("Watchog armed ! Rebooting in %d seconds if no feed occurs !\n",wdt.timeout);

booting:
	/* Release Mutex to let Linux's Driver taking control */
        kempld_release_mutex(&pld);

	/* Let's boot the default entry if specified */
	if (strlen(default_label)>0) {
		printf("Executing default label = '%s'\n",default_label);
		syslinux_run_command(default_label);
	} else {
		return ret;
	}
}
