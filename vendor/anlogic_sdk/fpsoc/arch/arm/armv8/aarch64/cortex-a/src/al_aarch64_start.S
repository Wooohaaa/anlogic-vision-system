/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_aarch64_macro.h"
#include "al_aarch64_sysreg.h"

.align 3

.extern clear_bss
.extern AlGic_Init
.extern AlSys_StartTimer

.globl _start
.globl vectors
.globl _sp
.globl SystemCoreClock

.section .text

.set vector_base, vectors

/* Initial State: MMU Disabled, i/dCache Disabled */
_start:

    /* disable intr */
    msr daifset, 0xF
    isb
    /* enable exception */
    msr daifclr, 0x4
    isb
    /* disable mmu */
	bl disable_mmu
    /* init register */
    mov x0, #0
	mov x1, #0
	mov x2, #0
	mov x3, #0
	mov x4, #0
	mov x5, #0
	mov x6, #0
	mov x7, #0
	mov x8, #0
	mov x9, #0
	mov x10, #0
	mov x11, #0
	mov x12, #0
	mov x13, #0
	mov x14, #0
	mov x15, #0
	mov x16, #0
	mov x17, #0
	mov x18, #0
	mov x19, #0
	mov x20, #0
	mov x21, #0
	mov x22, #0
	mov x23, #0
	mov x24, #0
	mov x25, #0
	mov x26, #0
	mov x27, #0
	mov x28, #0
	mov x29, #0
	mov x30, #0
	movi v0.2d, #0
	movi v1.2d, #0
	movi v2.2d, #0
	movi v3.2d, #0
	movi v4.2d, #0
	movi v5.2d, #0
	movi v6.2d, #0
	movi v7.2d, #0
	movi v8.2d, #0
	movi v9.2d, #0
	movi v10.2d, #0
	movi v11.2d, #0
	movi v12.2d, #0
	movi v13.2d, #0
	movi v14.2d, #0
	movi v15.2d, #0
	movi v16.2d, #0
	movi v17.2d, #0
	movi v18.2d, #0
	movi v19.2d, #0
	movi v20.2d, #0
	movi v21.2d, #0
	movi v22.2d, #0
	movi v23.2d, #0
	movi v24.2d, #0
	movi v25.2d, #0
	movi v26.2d, #0
	movi v27.2d, #0
	movi v28.2d, #0
	movi v29.2d, #0
	movi v30.2d, #0
	movi v31.2d, #0
    b setup_vector

/* set up vector table */
setup_vector:
    /* Gets the current exception level, and jumps to the corresponding label to execute
     * x0 = CurrentEL，
     * 0xc --> el3_entry
     * 0x8 --> el2_entry
     * 0x4 --> el1_entry
    **/
    switch_el x0, el3_entry, el2_entry, el1_entry

    b .

/* execute el3 */
el3_entry:

    /* Set vector table base address */
    adrp x0, vector_base
    add  x0, x0, :lo12:vector_base
    msr vbar_el3, x0

    /* Enable FP/SIMD */
    msr cptr_el3, xzr

    /* SMP EN */
    mrs x0, S3_1_c15_c2_1
	orr x0, x0, #0x40
	msr S3_1_c15_c2_1, x0
	isb

    /* enable hardware coherency between cores */
    mov x0, #(0x01 << 6)
    msr actlr_el3, x0    //Enable L2ACTLR write access from EL2
    msr actlr_el2, x0    //Enable L2ACTLR write access from Non-secure EL1

    /* set icc_sre_el3 */
    mov x0, #(0x1 << 0)         //SRE, Enable system register
    orr x0, x0, #(0x1 << 1)     //DFB, Disable FIQ bypass
    orr x0, x0, #(0x1 << 2)     //DIB, Disable IRQ bypass
    orr x0, x0, #(0x1 << 3)     //Enable, Enable lower EL access SRE_EL1 and SRE_EL2
    msr S3_6_c12_c12_5, x0
    isb

    /* set icc_igrpen1_el3 */
    mov x0, #(0x1 << 0)         //Enable group 1 interrupts for Non-secure state
    orr x0, x0, #(0x1 << 1)     //Enable group 1 interrupts for Secure state
    msr S3_6_c12_c12_7, x0

    /* set icc_igrpen0_el1 */
    mov x0, #(0x1 << 0)         //Enable group 0 interrupts
    msr S3_0_c12_c12_6, x0

    mrs    x0, scr_el3
    orr    x0, x0, #(0x1 << 1)      /* Enable IRQ */
    orr    x0, x0, #(0x1 << 2)      /* Enable FIQ */
    orr    x0, x0, #(0x1 << 3)      /* Enable EA */
    bic    x0, x0, #0x1             /* clear scr_el3.NS */
    msr    scr_el3, x0

    /* Set counter frequency */
    ldr    x0, =SystemCoreClock
    ldr    x0, [x0]
    msr    cntfrq_el0, x0
    mrs    x1, cntfrq_el0

#ifdef SMP

	mrs  x0, MPIDR_EL1
	and  x0, x0, #0xFF
    mov  x19, x0
    cmp  x19, #0
    bne  secondary

primary:
    /* set up stack point for each core */
    /* primary core */
    ldr x0, =_sp
    mov sp, x0
    b   setup_memory

secondary:
    /* secondary cores */
    ldr x0, =_sp_cpu1
    mov sp, x0
    b   main_entry

#else
    /* set up stack point */
    ldr x28, =_sp
    mov sp, x28
#endif

setup_memory:

    /*
     * Load code/rodata section from lma to vma if text lma != vma
     */
    ldr    x0, =_text_lma
    ldr    x1, =_text_start
    cmp    x0, x1
    beq    2f
    ldr    x2, =_etext
    cmp    x1, x2
    bge    2f

1:
    /* Load code/rodata section */
    ldr    x3, [x0]
    str    x3, [x1]
    add    x0, x0, #8
    add    x1, x1, #8
    cmp    x1, x2
    blt    1b

    /*
     * Load data section from lma to vma if data lma != vma
     */
2:
    /* Load data section */
    ldr    x0, =_data_lma
    ldr    x1, =_data_start
    cmp    x0, x1   /*cmp _data_lma & _data_start(vma)*/
    beq    4f       /*omit data copy if lam = vma*/
    ldr    x2, =_edata
    cmp    x1, x2   /*cmp _data_start(vma) & _edata(end of valid data vma) */
    bge    4f

3:
    /* Load data section */
    ldr    x3, [x0]
    str    x3, [x1]
    add    x0, x0, #8
    add    x1, x1, #8
    cmp    x1, x2
    blt    3b

4:
    /*
     * Load rt code/rodata section from lma to vma if text lma != vma
     */
    ldr    x0, =_text_rt_lma
    ldr    x1, =_text_rt_start
    cmp    x0, x1
    beq    2f
    ldr    x2, =_text_rt_end
    cmp    x1, x2
    bge    2f

1:
    ldr    x3, [x0]
    str    x3, [x1]
    add    x0, x0, #8
    add    x1, x1, #8
    cmp    x1, x2
    blt    1b

    /*
     * Load rt data section from lma to vma if data lma != vma
     */
2:
    /* Load data section */
    ldr    x0, =_data_rt_lma
    ldr    x1, =_data_rt_start
    cmp    x0, x1
    beq    4f
    ldr    x2, =_data_rt_end
    cmp    x1, x2
    bge    4f

3:
    /* Load data section */
    ldr    x3, [x0]
    str    x3, [x1]
    add    x0, x0, #8
    add    x1, x1, #8
    cmp    x1, x2
    blt    3b

4:

#ifdef SUPPORT_NONSECURE
    bl clear_bss
    bl AlGic_Init
    bl AlSys_StartTimer
#endif

/* switch to el1 */
#ifdef SWITCH_TO_EL1_EL0_FROM_EL3
    switch_el3_to_el1_el0
#endif

    b   main_entry

.align 3

/* el2 */
el2_entry:
    adrp x0, vector_base
    add  x0, x0, :lo12:vector_base
    msr vbar_el2, x0

    /* Enable FP/SIMD */
    mov x0, #0x33ff
    msr cptr_el2, x0

    /* set up stack point */
    ldr x28, =_sp
    mov sp, x28

    b   main_entry

.align 3

/* el1 */
el1_entry:
    /* Set up stack point */
    ldr x28, =_sp
    mov sp, x28

    adrp x0, vector_base
    add  x0, x0, :lo12:vector_base

    msr vbar_el1, x0

    /* Enable FP/SIMD */
    mov x0, #3 << 20
    /* Enable SVE */
    orr x0, x0, #3 << 16
    msr cpacr_el1, x0

    /* Enable cpu interface */
    mrs x0, icc_sre_el1
	orr x0, x0, #0x1
	msr icc_sre_el1, x0

main_entry:
    bl enable_icache

/*Enable MMU & Dcache*/
#ifdef ENABLE_MMU
    bl enable_mmu
#endif


#ifdef SMP
	/* Get CPU Id */
	mrs  x0, MPIDR_EL1
	and  x0, x0, #0xFF
    mov  x19, x0
    cmp  x19, #0
    bne  common_startup_flow

#endif

#ifndef SUPPORT_NONSECURE
    bl clear_bss
#endif

common_startup_flow:

    bl AlChip_Init

    bl board_init

    /* Call entry function when using RT-Thread */
    bl entry

    bl components_init

	bl __libc_init_array

    bl main

	bl __libc_fini_array

hang:
    /* hang */
    b .

.global board_init
.weak board_init
board_init:
    ret

.weak entry
entry:
    ret

_psci_dcache_level:
    lsl	x12, x0, #1
    msr	csselr_el1, x12		/* select cache level */
    isb				/* sync change of cssidr_el1 */
    mrs	x6, ccsidr_el1		/* read the new cssidr_el1 */
    and	x2, x6, #7		/* x2 <- log2(cache line size)-4 */
    add	x2, x2, #4		/* x2 <- log2(cache line size) */
    mov	x3, #0x3ff
    and	x3, x3, x6, lsr #3	/* x3 <- max number of #ways */
    clz	w5, w3			/* bit position of #ways */
    mov	x4, #0x7fff
    and	x4, x4, x6, lsr #13	/* x4 <- max number of #sets */
    /* x12 <- cache level << 1 */
    /* x2 <- line length offset */
    /* x3 <- number of cache ways - 1 */
    /* x4 <- number of cache sets - 1 */
    /* x5 <- bit position of #ways */

loop_set:
    mov	x6, x3			/* x6 <- working copy of #ways */
loop_way:
    lsl	x7, x6, x5
    orr	x9, x12, x7		/* map way and level to cisw value */
    lsl	x7, x4, x2
    orr	x9, x9, x7		/* map set number to cisw value */
    tbz	w1, #0, 1f
    dc	isw, x9
    b	2f
1:  dc	cisw, x9		/* clean & invalidate by set/way */
2:  subs    x6, x6, #1		/* decrement the way */
    b.ge    loop_way
    subs    x4, x4, #1		/* decrement the set */
    b.ge    loop_set

    ret

.global psci_cpu_pwrdown
psci_cpu_pwrdown:
    msr daifset, #0xf
    mrs x0, sctlr_el3
    movn x1, #(1 << 2)
    and x1, x0, x1
    msr sctlr_el3, x1
    mov x0, xzr
    mov x1, xzr
    bl  _psci_dcache_level
    isb
    dsb sy
0:  wfe
    b    0b
