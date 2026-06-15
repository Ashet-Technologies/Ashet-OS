// {
//     "name": "Debug output: write bytes to serial",
//     "march": "rv32imc",
//     "ram_size": 4,
//     "initial_regs": {},
//     "expected_regs": {},
//     "expected_debug": [72, 105, 10]
// }
.section .text
.globl _start
_start:
    lui  x1, 0x40041        # x1 = 0x40041000 (debug TX base)
    addi x2, x0, 0x48       # 'H'
    sb   x2, 0(x1)
    addi x2, x0, 0x69       # 'i'
    sb   x2, 0(x1)
    addi x2, x0, 0x0A       # '\n'
    sb   x2, 0(x1)
    ebreak
