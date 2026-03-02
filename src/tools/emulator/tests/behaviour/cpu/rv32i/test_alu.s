// {
//     "name": "ALU: register-register operations",
//     "march": "rv32imc",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 10,
//         "x2": 20,
//         "x3": 30,
//         "x4": -10,
//         "x5": 0,
//         "x6": 30,
//         "x7": 20
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    addi x1, x0, 10
    addi x2, x0, 20
    add  x3, x1, x2      # x3 = 30
    sub  x4, x1, x2      # x4 = -10
    and  x5, x1, x2      # x5 = 10 & 20 = 0
    or   x6, x1, x2      # x6 = 10 | 20 = 30
    addi x8, x0, 30
    xor  x7, x1, x8      # x7 = 10 ^ 30 = 20
    ebreak
