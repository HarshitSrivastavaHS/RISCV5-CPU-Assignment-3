.eqv MMIO_BASE 0xFFFF0000
.eqv LED_OFF 0x60
.eqv DIP_OFF 0x64
.eqv SEVENSEG_OFF 0x80

.text
.globl main
main:
    li s0, MMIO_BASE
    sw zero, LED_OFF(s0)
    sw zero, SEVENSEG_OFF(s0)
    la s5, cases
    sw zero, 384(s5)
    sw zero, 388(s5)
    mv s1, s5
    li s2, 16
    li s3, 1
run_case:
    lw t0, 0(s1)
    lw t1, 4(s1)
    lw t2, 8(s1)
    li t3, 1
    beq t0, t3, do_mul
    li t3, 2
    beq t0, t3, do_div
    divu t4, t1, t2
    j check_result
do_mul:
    mul t4, t1, t2
    j check_result
do_div:
    div t4, t1, t2
check_result:
    sw t4, 16(s1)
    lw t5, 12(s1)
    xor t6, t4, t5
    sltiu t6, t6, 1
    sw t6, 20(s1)
    and s3, s3, t6
    addi s1, s1, 24
    addi s2, s2, -1
    bne s2, zero, run_case
    sw s3, 384(s5)
    li t0, 1
    sw t0, 388(s5)
display:
    lw s4, DIP_OFF(s0)
    andi t0, s4, 15
    slli t1, t0, 4
    slli t2, t0, 3
    add t1, t1, t2
    add s1, s5, t1
    srli t2, s4, 4
    andi t2, t2, 3
    slli t2, t2, 2
    bne t2, zero, load_view
    li t2, 16
load_view:
    add t2, s1, t2
    lw t3, 0(t2)
    sw t3, SEVENSEG_OFF(s0)
    lw t1, 0(s1)
    slli t1, t1, 4
    or t1, t1, t0
    lw t2, 20(s1)
    slli t2, t2, 6
    or t1, t1, t2
    slli t2, s3, 7
    or t1, t1, t2
    sw t1, LED_OFF(s0)
    j display

.data
.align 2
cases:
    .word 1, 7, 3, 21, 0, 0
    .word 1, -7, 3, -21, 0, 0
    .word 1, -7, -3, 21, 0, 0
    .word 1, 0, 123, 0, 0, 0
    .word 1, 0x80000000, -1, 0x80000000, 0, 0
    .word 1, 546540564, 456546541, 0x88F78E84, 0, 0
    .word 2, 7, 3, 2, 0, 0
    .word 2, -7, 3, -2, 0, 0
    .word 2, 7, -3, -2, 0, 0
    .word 2, -7, -3, 2, 0, 0
    .word 2, 0, 3, 0, 0, 0
    .word 2, 0x80000000, -1, 0x80000000, 0, 0
    .word 3, 7, 3, 2, 0, 0
    .word 3, 0xFFFFFFFF, 3, 0x55555555, 0, 0
    .word 3, 0x80000000, 2, 0x40000000, 0, 0
    .word 3, 5, 7, 0, 0, 0
suite_pass:
    .word 0
suite_done:
    .word 0
