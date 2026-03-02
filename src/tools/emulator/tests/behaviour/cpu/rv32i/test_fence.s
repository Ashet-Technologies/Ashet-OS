// {
//     "name": "FENCE: executes as NOP without side effects",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 1,
//         "x2": 2
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    addi x1, x0, 1
    fence                   # should do nothing
    addi x2, x0, 2         # should execute normally after fence
    ebreak
