#include <stdint.h>

extern void dyncall(uint32_t, uint32_t) ;

uint32_t _start() {
    dyncall(10, 20);
    return 0;
}
