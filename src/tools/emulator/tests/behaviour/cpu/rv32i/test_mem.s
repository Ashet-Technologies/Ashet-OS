// {
//     "name": "Load/store with RAM",
//     "march": "rv32imc",
//     "ram_size": 1024,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": "0x80000000",
//         "x2": "0xDEADBEEF",
//         "x3": "0xDEADBEEF",
//         "x4": "0xFFFFFFEF",
//         "x5": "0x000000EF",
//         "x6": "0x000000BE",
//         "x7": "0x000000AD",
//         "x8": "0x000000DE"
//     },
//     "expected_debug": ""
// }
# Expected results at EBREAK:
#   x3 = 0xDEADBEEF (SW/LW round-trip)
#   x4 = 0xFFFFFFEF (LB sign-extends 0xEF)
#   x5 = 0x000000EF (LBU zero-extends 0xEF)
.section .text
.globl _start
_start:
    lui  x1, 0x80000         # x1 = 0x80000000 (RAM base)
    li   x2, 0xDEADBEEF      # x2 = 0xDEADBEEF (assembler handles lui+addi)
    sw   x2, 0(x1)           # store to RAM
    lw   x3, 0(x1)           # x3 should be 0xDEADBEEF
    lb   x4, 0(x1)           # x4 = sign_extend(0xEF) = 0xFFFFFFEF
    lbu  x5, 0(x1)           # x5 = 0x000000EF
    lbu  x6, 1(x1)           # x5 = 0x000000BE
    lbu  x7, 2(x1)           # x5 = 0x000000AD
    lbu  x8, 3(x1)           # x5 = 0x000000DE
    ebreak
