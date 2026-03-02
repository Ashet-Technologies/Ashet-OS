// {
//     "name": "LUI and AUIPC",
//     "march": "rv32imc",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": "0x12345000",
//         "x2": "0x12345678",
//         "x3": "0x0000100C"
//     },
//     "expected_debug": ""
// }
# Expected results at EBREAK:
#   x1 = 0x12345000 (LUI)
#   x2 = 0x12345678 (LUI + ADDI)
#   x3 = 0x0000100C (AUIPC at PC=0x0C with imm=0x1000)
.section .text
.globl _start
_start:
    lui    x1, 0x12345       # x1 = 0x12345000
    lui    x2, 0x12345
    addi   x2, x2, 0x678    # x2 = 0x12345678
    auipc  x3, 1            # x3 = PC + 0x1000; PC here = 0x08, so x3 = 0x1008
    ebreak
