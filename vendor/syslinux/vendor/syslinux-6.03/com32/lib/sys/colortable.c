#include <colortbl.h>

static struct color_table default_color_table[] = {
    {"default", "0", 0xffffffff, 0x00000000, SHADOW_NORMAL}
};

struct color_table *console_color_table = default_color_table;
int console_color_table_size =
    (sizeof default_color_table / sizeof(struct color_table));
