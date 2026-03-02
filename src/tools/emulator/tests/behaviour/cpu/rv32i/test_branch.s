// {
//     "name": "Branch instructions: BEQ, BNE, BLT",
//     "march": "rv32imc",
//     "ram_size": 0,
//     "initial_regs": {},
//     "expected_regs": {
//         "x1": 1,
//         "x2": 1,
//         "x3": 1
//     },
//     "expected_debug": ""
// }
.section .text
.globl _start
_start:
    addi x10, x0, 5
    addi x11, x0, 5
    addi x12, x0, 10

    # Test BEQ: x10 == x11 should branch
    beq  x10, x11, beq_ok
    addi x1, x0, 0
    j    test_bne
beq_ok:
    addi x1, x0, 1

test_bne:
    # Test BNE: x10 != x12 should branch
    bne  x10, x12, bne_ok
    addi x2, x0, 0
    j    test_blt
bne_ok:
    addi x2, x0, 1

test_blt:
    # Test BLT: x10 < x12 should branch
    blt  x10, x12, blt_ok
    addi x3, x0, 0
    j    done
blt_ok:
    addi x3, x0, 1

done:
    ebreak
