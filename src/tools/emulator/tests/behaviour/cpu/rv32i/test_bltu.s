// {
//     "name": "BLTU: unsigned comparison branch",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x3": 1
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    addi x1, x0, -1       # x1 = 0xFFFFFFFF
    addi x2, x0, 1        # x2 = 1
    bltu x2, x1, skip     # 1 < 0xFFFFFFFF → taken
    addi x3, x0, 0        # not reached
    j done
skip:
    addi x3, x0, 1
done:
    ebreak
