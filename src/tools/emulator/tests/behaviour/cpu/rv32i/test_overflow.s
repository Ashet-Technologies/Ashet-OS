// {
//     "name": "Arithmetic overflow: ADD/SUB near INT32 boundaries",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": "0x7FFFFFFF",
//         "x2": "0x80000000",
//         "x3": "0x80000000",
//         "x4": "0x7FFFFFFF",
//         "x5": "0xFFFFFFFE",
//         "x6": 0
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    # Load INT32_MAX = 0x7FFFFFFF
    lui  x1, 0x80000        # x1 = 0x80000000
    addi x1, x1, -1         # x1 = 0x7FFFFFFF (INT32_MAX)

    # Test 1: INT32_MAX + 1 wraps to INT32_MIN (0x80000000)
    addi x2, x1, 1          # x2 = 0x80000000

    # Load INT32_MIN = 0x80000000
    lui  x3, 0x80000        # x3 = 0x80000000 (INT32_MIN)

    # Test 2: INT32_MIN - 1 wraps to INT32_MAX (0x7FFFFFFF)
    addi x4, x3, -1         # x4 = 0x7FFFFFFF

    # Test 3: INT32_MAX + INT32_MAX = 0xFFFFFFFE
    add  x5, x1, x1         # x5 = 0xFFFFFFFE

    # Test 4: INT32_MIN - INT32_MIN = 0
    sub  x6, x3, x3         # x6 = 0

    ebreak
