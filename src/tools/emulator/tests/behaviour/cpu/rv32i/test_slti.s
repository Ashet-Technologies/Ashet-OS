// {
//     "name": "SLTI and SLTIU",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": -5,
//         "x2": 1,
//         "x3": 0
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    addi  x1, x0, -5       # x1 = -5
    slti  x2, x1, 0        # x2 = 1 (-5 < 0 signed)
    sltiu x3, x1, 0        # x3 = 0 (0xFFFFFFFB > 0 unsigned)
    ebreak
