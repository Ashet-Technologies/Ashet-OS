// {
//     "name": "Negative immediates: ADDI/SLTI with sign-extended values",
//     "march": "rv32i",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": "0xFFFFFFFF",
//         "x2": "0xFFFFF800",
//         "x3": 5,
//         "x4": 1,
//         "x5": 0,
//         "x6": 1,
//         "x7": 0
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    # ADDI with negative immediates
    addi x1, x0, -1         # x1 = 0xFFFFFFFF (-1)
    addi x2, x0, -2048      # x2 = 0xFFFFF800 (-2048, min 12-bit signed)
    addi x3, x1, 6          # x3 = -1 + 6 = 5

    # SLTI: signed comparison with negative immediate
    addi x10, x0, -5        # x10 = -5

    slti x4, x10, -4        # -5 < -4? yes -> x4 = 1
    slti x5, x10, -6        # -5 < -6? no  -> x5 = 0

    # SLTIU: unsigned comparison, but immediate is still sign-extended
    # -1 sign-extends to 0xFFFFFFFF, so 5 < 0xFFFFFFFF is true
    addi x11, x0, 5
    sltiu x6, x11, -1       # 5 < 0xFFFFFFFF? yes (unsigned) -> x6 = 1
    # 0 is never < 0
    sltiu x7, x0, 0         # 0 < 0? no -> x7 = 0

    ebreak
