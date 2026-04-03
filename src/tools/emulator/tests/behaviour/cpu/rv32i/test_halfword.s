// {
//     "name": "Half-word store and load",
//     "march": "rv32i",
//     "ram_size": 1024,
//     "initial_regs": {},
//     "expected_regs": {
//         "x3": "0xFFFFFFFF",
//         "x4": "0x0000FFFF"
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    lui  x1, 0x80000       # x1 = 0x80000000 (RAM base)
    addi x2, x0, -1        # x2 = 0xFFFFFFFF
    sh   x2, 0(x1)         # store 0xFFFF to RAM
    lh   x3, 0(x1)         # x3 = sign_extend(0xFFFF) = 0xFFFFFFFF
    lhu  x4, 0(x1)         # x4 = 0x0000FFFF
    ebreak
