/*
 * ansi.h
 */

#ifndef COM32_LIB_SYS_ANSI_H
#define COM32_LIB_SYS_ANSI_H

#include <inttypes.h>
#include <stdbool.h>
#include "vesa/video.h"

#define ANSI_MAX_PARMS	16

enum ansi_state {
    st_init,
    st_esc,
    st_csi,
    st_tbl,
    st_tblc,
};

struct curxy {
    uint8_t x, y;
} __attribute__ ((packed));

struct term_state {
    enum ansi_state state;
    int nparms;			/* Number of parameters seen */
    int parms[ANSI_MAX_PARMS];
    bool pvt;			/* Private code? */
    struct curxy xy;
    struct curxy saved_xy;
    attr_t cindex;		/* SOH color index */
    uint8_t fg;
    uint8_t bg;
    uint8_t intensity;
    bool vtgraphics;		/* VT graphics on/off */
    bool underline;
    bool blink;
    bool reverse;
    bool autocr;
    bool autowrap;
    bool cursor;
};

struct ansi_ops {
    void (*erase) (const struct term_state * st, int x0, int y0, int x1,
		   int y1);
    void (*write_char) (int x, int y, uint8_t ch, const struct term_state * st);
    void (*showcursor) (const struct term_state * st);
    void (*scroll_up) (const struct term_state * st);
    void (*set_cursor) (int x, int y, bool visible);
    void (*beep) (void);
};

struct term_info {
    int rows, cols;		/* Screen size */
    int disabled;
    struct term_state *ts;
    const struct ansi_ops *op;
};

void __ansi_init(const struct term_info *ti);
void __ansi_putchar(const struct term_info *ti, uint8_t ch);
void __ansicon_beep(void);

#endif /* COM32_LIB_SYS_ANSI_H */
