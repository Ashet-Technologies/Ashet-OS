// {
//     "name": "ADDI: load immediate into register",
//     "march": "rv32imc",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 42
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    addi x1, x0, 42
    ebreak
