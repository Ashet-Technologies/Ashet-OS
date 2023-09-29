/*
 *  kempld_wdt.h - Kontron PLD watchdog driver definitions
 *
 *  Copyright (c) 2010 Kontron Embedded Modules GmbH
 *  Author: Michael Brunner <michael.brunner@kontron.com>
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

#ifndef _KEMPLD_WDT_H_
#define _KEMPLD_WDT_H_
#include <stdint.h>

#define KEMPLD_IOPORT 0x0a80
#define KEMPLD_IODATA (KEMPLD_IOPORT+1)

#define KEMPLD_MUTEX_KEY	0x80

/* watchdog register definitions */
#define KEMPLD_WDT_KICK                 0x16
#define KEMPLD_WDT_REV                  0x16
#define         KEMPLD_WDT_REV_GET(x)                   (x & 0xf)
#define KEMPLD_WDT_CFG                  0x17
#define         KEMPLD_WDT_CFG_STAGE_TIMEOUT_OCCURED(x) (1<<x)
#define         KEMPLD_WDT_CFG_ENABLE_LOCK              0x8
#define         KEMPLD_WDT_CFG_ENABLE                   0x10
#define         KEMPLD_WDT_CFG_AUTO_RELOAD              0x40
#define         KEMPLD_WDT_CFG_GLOBAL_LOCK              0x80
#define KEMPLD_WDT_STAGE_CFG(x)         (0x18+x)
#define         KEMPLD_WDT_STAGE_CFG_ACTION_MASK        0x7
#define         KEMPLD_WDT_STAGE_CFG_GET_ACTION(x)      (x & 0x7)
#define         KEMPLD_WDT_STAGE_CFG_ASSERT             0x8
#define         KEMPLD_WDT_STAGE_CFG_PRESCALER_MASK     0x30
#define         KEMPLD_WDT_STAGE_CFG_GET_PRESCALER(x)   ((x & 0x30)>>4)
#define         KEMPLD_WDT_STAGE_CFG_SET_PRESCALER(x)   ((x & 0x30)<<4)
#define KEMPLD_WDT_STAGE_TIMEOUT(x)     (0x1b+x*4)
#define KEMPLD_WDT_MAX_STAGES           3

#define KEMPLD_WDT_ACTION_NONE          0x0
#define KEMPLD_WDT_ACTION_RESET         0x1
#define KEMPLD_WDT_ACTION_NMI           0x2
#define KEMPLD_WDT_ACTION_SMI           0x3
#define KEMPLD_WDT_ACTION_SCI           0x4
#define KEMPLD_WDT_ACTION_DELAY         0x5

#define KEMPLD_WDT_PRESCALER_21BIT      0x0
#define KEMPLD_WDT_PRESCALER_17BIT      0x1
#define KEMPLD_WDT_PRESCALER_12BIT      0x2

const int kempld_prescaler_bits[] = { 21, 17, 12 };

struct kempld_watchdog_stage {
        int     num;
        uint32_t     timeout_mask;
};

/**
 * struct kempld_device_data - Internal representation of the PLD device
 * @io_base:            Pointer to the IO memory
 * @io_index:           Pointer to the IO index register
 * @io_data:            Pointer to the IO data register
 * @pld_clock:          PLD clock frequency
 * @lock:               PLD spin-lock
 * @lock_flags:         PLD spin-lock flags
 * @have_mutex:         Bool value that indicates if mutex is aquired
 * @last_index:         Last written index value
 * @rscr:               Kernel resource structure
 * @dev:                Pointer to kernel device structure
 * @info:               KEMPLD info structure
 */
struct kempld_device_data {
        uint16_t 	        io_base;
        uint16_t		io_index;
        uint16_t		io_data;
        uint32_t		 pld_clock;
/*        spinlock_t              lock;
        unsigned long           lock_flags; */
        int                     have_mutex;
        uint8_t			last_index;
/*        struct resource         rscr;
        struct device           *dev;
        struct kempld_info      info;*/
};

struct watchdog_info {
	uint32_t options;          /* Options the card/driver supports */
	uint32_t firmware_version; /* Firmware version of the card */
	uint8_t  identity[32];     /* Identity of the board */
};

struct kempld_watchdog_data {
        unsigned int                    revision;
        int                             timeout;
        int                             pretimeout;
        unsigned long                   is_open;
        unsigned long                   expect_close;
        int                             stages;
        struct kempld_watchdog_stage    *timeout_stage;
        struct kempld_watchdog_stage    *pretimeout_stage;
        struct kempld_device_data       *pld;
        struct kempld_watchdog_stage    *stage[KEMPLD_WDT_MAX_STAGES];
	struct watchdog_info		ident;
};

#endif /* _KEMPLD_WDT_H_ */
#define KEMPLD_PRESCALER(x)     (0xffffffff>>(32-kempld_prescaler_bits[x]))
