// {
//     "name": "Shifts: boundary amounts 0 and 31",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": "0xDEADBEEF",
//         "x2": "0xDEADBEEF",
//         "x3": "0xDEADBEEF",
//         "x4": "0x80000000",
//         "x5": 1,
//         "x6": "0xFFFFFFFF",
//         "x7": "0x00000001"
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    li   x10, 0xDEADBEEF

    # Shift by 0: value unchanged
    slli x1, x10, 0         # x1 = 0xDEADBEEF
    srli x2, x10, 0         # x2 = 0xDEADBEEF
    srai x3, x10, 0         # x3 = 0xDEADBEEF

    # Shift by 31
    addi x11, x0, 1
    slli x4, x11, 31        # x4 = 0x80000000 (1 << 31)

    srli x5, x4, 31         # x5 = 1 (0x80000000 >> 31 logical)

    srai x6, x4, 31         # x6 = 0xFFFFFFFF (0x80000000 >> 31 arithmetic, sign extends)

    # SRL vs SRA distinction on negative number shifted by large amount
    li   x12, 0x80000000
    srli x7, x12, 31        # x7 = 1 (logical: zero-fill)

    ebreak
