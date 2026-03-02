// {
//     "name": "M-extension: multiply and divide",
//     "march": "rv32imc",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x3": 200,
//         "x4": 2,
//         "x5": 0,
//         "x6": 5,
//         "x7": 4294967295
//     },
//     "expected_debug": ""
// }
# Test M-extension multiply/divide instructions.
# Assemble and convert to raw binary with:
#   riscv64-unknown-elf-gcc -march=rv32imc -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_mul.elf test_mul.s
#   riscv64-unknown-elf-objcopy -O binary test_mul.elf test_mul.bin
#
# Expected results at EBREAK:
#   x3 = 200  (MUL 10*20)
#   x4 = 2    (DIVU 20/10)
#   x5 = 0    (REMU 20%10)
#   x6 = 5    (DIVU 50/10)
#   x7 = 0xFFFFFFFF (DIV by zero)
.section .text
.globl _start
_start:
    addi x1, x0, 10
    addi x2, x0, 20
    mul  x3, x1, x2       # x3 = 200
    divu x4, x2, x1       # x4 = 2
    remu x5, x2, x1       # x5 = 0
    addi x8, x0, 50
    divu x6, x8, x1       # x6 = 5
    divu x7, x1, x0       # x7 = 0xFFFFFFFF (div by zero)
    ebreak
