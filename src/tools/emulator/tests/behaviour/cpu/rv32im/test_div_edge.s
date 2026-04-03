// {
//     "name": "M-extension: signed division edge cases",
//     "march": "rv32im",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x3": 2147483648,
//         "x4": 0,
//         "x5": 2147483648
//     },
//     "expected_debug": ""
// }
# Test M-extension division/remainder edge cases.
# Assemble with:
#   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -Ttext=0x0 -o test_div_edge.elf test_div_edge.s
#   riscv64-unknown-elf-objcopy -O binary test_div_edge.elf test_div_edge.bin
#
# Expected:
#   x3 = 0x80000000 (INT32_MIN / -1 = INT32_MIN, overflow)
#   x4 = 0          (INT32_MIN % -1 = 0, overflow)
#   x5 = 0x80000000 (INT32_MIN % 0 = dividend)
.section .text
.globl _start
_start:
    lui  x1, 0x80000       # x1 = 0x80000000 = INT32_MIN
    addi x2, x0, -1        # x2 = -1
    div  x3, x1, x2        # overflow: returns INT32_MIN
    rem  x4, x1, x2        # overflow: returns 0
    rem  x5, x1, x0        # div by zero: returns dividend
    ebreak
