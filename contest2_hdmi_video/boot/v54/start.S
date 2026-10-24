/* PH1P35 QSPI XIP -> original v39 TCM application. No stack, peripherals or PWM.
 * Flash layout follows the SDK's ILM/DLM boot region at offset 0x00e00000.
 * Invalid headers/CRC fail closed. The original application remains unchanged.
 */
.section .text.boot,"ax",@progbits
.globl _boot_start
_boot_start:
    csrw mie, zero
    csrci mstatus, 8
    li t0, 2
    csrw 0x7ca, t0 /* CSR_MCACHE_CTL: SDK startup disables caches with value 2 */
    li t0, 0x20e10000
    lw t1, 0(t0)
    li t2, 0x41525543
    bne t1, t2, boot_fail
    lw a2, 4(t0)
    beqz a2, boot_fail
    li t2, 0xc000
    bgtu a2, t2, boot_fail
    andi t2, a2, 3
    bnez t2, boot_fail
    lw t1, 8(t0)
    li t2, 0x08000000
    bne t1, t2, boot_fail
    lw a0, 12(t0)
    li t2, 0x08000100
    bne a0, t2, boot_fail
    lw a1, 16(t0)
    addi t0, t0, 32
    add a3, t1, a2
copy_word:
    lw t2, 0(t0)
    sw t2, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    bltu t1, a3, copy_word
    li t0, 0x08000000
    li t1, -1
    li t5, 0xedb88320
crc_byte:
    lbu t2, 0(t0)
    xor t1, t1, t2
    li t3, 8
crc_bit:
    andi t4, t1, 1
    srli t1, t1, 1
    beqz t4, crc_no_xor
    xor t1, t1, t5
crc_no_xor:
    addi t3, t3, -1
    bnez t3, crc_bit
    addi t0, t0, 1
    bltu t0, a3, crc_byte
    not t1, t1
    bne t1, a1, boot_fail
    fence rw,rw
    fence.i
    jr a0
boot_fail:
    wfi
    j boot_fail
