/*
 * Copyright (c) 2019-Present Nuclei Limited. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2020/03/26     Huaqi        First Nuclei RISC-V porting implementation
 */

#include "al_rv_sysregs.h"
#include "riscv_bits.h"

#ifndef __riscv_32e
#define RT_SAVED_REGNUM         30
#else
#define RT_SAVED_REGNUM         14
#endif

#ifdef __riscv_flen

#define portFPU_CONTEXT_WORDS   32
#define portFPU_CONTEXT_SIZE (portFPU_CONTEXT_WORDS * FPREGBYTES)

.macro portasmSAVE_FPU_REGISTERS
    addi    sp, sp, -portFPU_CONTEXT_SIZE
    FPSTORE   f0, 0 * FPREGBYTES(sp)
    FPSTORE   f1, 1 * FPREGBYTES(sp)
    FPSTORE   f2, 2 * FPREGBYTES(sp)
    FPSTORE   f3, 3 * FPREGBYTES(sp)
    FPSTORE   f4, 4 * FPREGBYTES(sp)
    FPSTORE   f5, 5 * FPREGBYTES(sp)
    FPSTORE   f6, 6 * FPREGBYTES(sp)
    FPSTORE   f7, 7 * FPREGBYTES(sp)
    FPSTORE   f8, 8 * FPREGBYTES(sp)
    FPSTORE   f9, 9 * FPREGBYTES(sp)
    FPSTORE   f10, 10 * FPREGBYTES(sp)
    FPSTORE   f11, 11 * FPREGBYTES(sp)
    FPSTORE   f12, 12 * FPREGBYTES(sp)
    FPSTORE   f13, 13 * FPREGBYTES(sp)
    FPSTORE   f14, 14 * FPREGBYTES(sp)
    FPSTORE   f15, 15 * FPREGBYTES(sp)
    FPSTORE   f16, 16 * FPREGBYTES(sp)
    FPSTORE   f17, 17 * FPREGBYTES(sp)
    FPSTORE   f18, 18 * FPREGBYTES(sp)
    FPSTORE   f19, 19 * FPREGBYTES(sp)
    FPSTORE   f20, 20 * FPREGBYTES(sp)
    FPSTORE   f21, 21 * FPREGBYTES(sp)
    FPSTORE   f22, 22 * FPREGBYTES(sp)
    FPSTORE   f23, 23 * FPREGBYTES(sp)
    FPSTORE   f24, 24 * FPREGBYTES(sp)
    FPSTORE   f25, 25 * FPREGBYTES(sp)
    FPSTORE   f26, 26 * FPREGBYTES(sp)
    FPSTORE   f27, 27 * FPREGBYTES(sp)
    FPSTORE   f28, 28 * FPREGBYTES(sp)
    FPSTORE   f29, 29 * FPREGBYTES(sp)
    FPSTORE   f30, 30 * FPREGBYTES(sp)
    FPSTORE   f31, 31 * FPREGBYTES(sp)
    .endm

.macro portasmRESTORE_FPU_REGISTERS
    FPLOAD   f0, 0 * FPREGBYTES(sp)
    FPLOAD   f1, 1 * FPREGBYTES(sp)
    FPLOAD   f2, 2 * FPREGBYTES(sp)
    FPLOAD   f3, 3 * FPREGBYTES(sp)
    FPLOAD   f4, 4 * FPREGBYTES(sp)
    FPLOAD   f5, 5 * FPREGBYTES(sp)
    FPLOAD   f6, 6 * FPREGBYTES(sp)
    FPLOAD   f7, 7 * FPREGBYTES(sp)
    FPLOAD   f8, 8 * FPREGBYTES(sp)
    FPLOAD   f9, 9 * FPREGBYTES(sp)
    FPLOAD   f10, 10 * FPREGBYTES(sp)
    FPLOAD   f11, 11 * FPREGBYTES(sp)
    FPLOAD   f12, 12 * FPREGBYTES(sp)
    FPLOAD   f13, 13 * FPREGBYTES(sp)
    FPLOAD   f14, 14 * FPREGBYTES(sp)
    FPLOAD   f15, 15 * FPREGBYTES(sp)
    FPLOAD   f16, 16 * FPREGBYTES(sp)
    FPLOAD   f17, 17 * FPREGBYTES(sp)
    FPLOAD   f18, 18 * FPREGBYTES(sp)
    FPLOAD   f19, 19 * FPREGBYTES(sp)
    FPLOAD   f20, 20 * FPREGBYTES(sp)
    FPLOAD   f21, 21 * FPREGBYTES(sp)
    FPLOAD   f22, 22 * FPREGBYTES(sp)
    FPLOAD   f23, 23 * FPREGBYTES(sp)
    FPLOAD   f24, 24 * FPREGBYTES(sp)
    FPLOAD   f25, 25 * FPREGBYTES(sp)
    FPLOAD   f26, 26 * FPREGBYTES(sp)
    FPLOAD   f27, 27 * FPREGBYTES(sp)
    FPLOAD   f28, 28 * FPREGBYTES(sp)
    FPLOAD   f29, 29 * FPREGBYTES(sp)
    FPLOAD   f30, 30 * FPREGBYTES(sp)
    FPLOAD   f31, 31 * FPREGBYTES(sp)

    addi    sp, sp, 32 * FPREGBYTES
    .endm
#endif

#define RT_CONTEXT_SIZE         (RT_SAVED_REGNUM * REGBYTES)

    .extern rt_interrupt_from_thread
    .extern rt_interrupt_to_thread


.section    .text


/*
 * void rt_hw_context_switch_to(rt_ubase_t to);
 * a0 --> to_thread
 */
    .globl rt_hw_context_switch_to

/* Start the first task.  This also clears the bit that indicates the FPU is
	in use in case the FPU was used before the scheduler was started - which
	would otherwise result in the unnecessary leaving of space in the stack
	for lazy saving of FPU registers. */
.align 3
rt_hw_context_switch_to:
    /* Setup Interrupt Stack using
       The stack that was used by main()
       before the scheduler is started is
       no longer required after the scheduler is started.
       Interrupt stack pointer is stored in CSR_MSCRATCH */
    la t0, _sp
    csrw CSR_MSCRATCH, t0
    LOAD sp, 0x0(a0)                /* Read sp from first TCB member(a0) */

    /* Pop PC from stack and set MEPC */
    LOAD t0,  0  * REGBYTES(sp)
    csrw CSR_MEPC, t0
    /* Pop mstatus from stack and set it */
    LOAD t0,  (RT_SAVED_REGNUM - 1)  * REGBYTES(sp)
    csrw CSR_MSTATUS, t0
    /* Interrupt still disable here */
    /* Restore Registers from Stack */
    LOAD x1,  1  * REGBYTES(sp)    /* RA */
    LOAD x5,  2  * REGBYTES(sp)
    LOAD x6,  3  * REGBYTES(sp)
    LOAD x7,  4  * REGBYTES(sp)
    LOAD x8,  5  * REGBYTES(sp)
    LOAD x9,  6  * REGBYTES(sp)
    LOAD x10, 7  * REGBYTES(sp)
    LOAD x11, 8  * REGBYTES(sp)
    LOAD x12, 9  * REGBYTES(sp)
    LOAD x13, 10 * REGBYTES(sp)
    LOAD x14, 11 * REGBYTES(sp)
    LOAD x15, 12 * REGBYTES(sp)
#ifndef __riscv_32e
    LOAD x16, 13 * REGBYTES(sp)
    LOAD x17, 14 * REGBYTES(sp)
    LOAD x18, 15 * REGBYTES(sp)
    LOAD x19, 16 * REGBYTES(sp)
    LOAD x20, 17 * REGBYTES(sp)
    LOAD x21, 18 * REGBYTES(sp)
    LOAD x22, 19 * REGBYTES(sp)
    LOAD x23, 20 * REGBYTES(sp)
    LOAD x24, 21 * REGBYTES(sp)
    LOAD x25, 22 * REGBYTES(sp)
    LOAD x26, 23 * REGBYTES(sp)
    LOAD x27, 24 * REGBYTES(sp)
    LOAD x28, 25 * REGBYTES(sp)
    LOAD x29, 26 * REGBYTES(sp)
    LOAD x30, 27 * REGBYTES(sp)
    LOAD x31, 28 * REGBYTES(sp)
#endif

    addi sp, sp, RT_CONTEXT_SIZE

#ifdef __riscv_flen
    /* Restore Fpu registers when fpu is enabled */
    portasmRESTORE_FPU_REGISTERS
#endif

    mret

.align 2
.global eclic_msip_handler
eclic_msip_handler:

#ifdef __riscv_flen
    /* Save Fpu registers when fpu is enabled */
    portasmSAVE_FPU_REGISTERS
#endif

    addi sp, sp, -RT_CONTEXT_SIZE
    STORE x1,  1  * REGBYTES(sp)    /* RA */
    STORE x5,  2  * REGBYTES(sp)
    STORE x6,  3  * REGBYTES(sp)
    STORE x7,  4  * REGBYTES(sp)
    STORE x8,  5  * REGBYTES(sp)
    STORE x9,  6  * REGBYTES(sp)
    STORE x10, 7  * REGBYTES(sp)
    STORE x11, 8  * REGBYTES(sp)
    STORE x12, 9  * REGBYTES(sp)
    STORE x13, 10 * REGBYTES(sp)
    STORE x14, 11 * REGBYTES(sp)
    STORE x15, 12 * REGBYTES(sp)
#ifndef __riscv_32e
    STORE x16, 13 * REGBYTES(sp)
    STORE x17, 14 * REGBYTES(sp)
    STORE x18, 15 * REGBYTES(sp)
    STORE x19, 16 * REGBYTES(sp)
    STORE x20, 17 * REGBYTES(sp)
    STORE x21, 18 * REGBYTES(sp)
    STORE x22, 19 * REGBYTES(sp)
    STORE x23, 20 * REGBYTES(sp)
    STORE x24, 21 * REGBYTES(sp)
    STORE x25, 22 * REGBYTES(sp)
    STORE x26, 23 * REGBYTES(sp)
    STORE x27, 24 * REGBYTES(sp)
    STORE x28, 25 * REGBYTES(sp)
    STORE x29, 26 * REGBYTES(sp)
    STORE x30, 27 * REGBYTES(sp)
    STORE x31, 28 * REGBYTES(sp)
#endif
    /* Push mstatus to stack */
    csrr t0, CSR_MSTATUS
    STORE t0,  (RT_SAVED_REGNUM - 1)  * REGBYTES(sp)

    /* Push additional registers */

    csrr t0, CSR_MEPC
    STORE t0, 0(sp)

    /* Store sp to task stack */
    LOAD t0, rt_interrupt_from_thread
    STORE sp, 0(t0)


    jal rt_hw_taskswitch

    /* Switch task context */
    LOAD t0, rt_interrupt_to_thread
    LOAD sp, 0x0(t0)

    /* Pop PC from stack and set MEPC */
    LOAD t0,  0  * REGBYTES(sp)
    csrw CSR_MEPC, t0

    /* Pop additional registers */

    /* Pop mstatus from stack and set it */
    LOAD t0,  (RT_SAVED_REGNUM - 1)  * REGBYTES(sp)
    csrw CSR_MSTATUS, t0
    /* Interrupt still disable here */
    /* Restore Registers from Stack */
    LOAD x1,  1  * REGBYTES(sp)    /* RA */
    LOAD x5,  2  * REGBYTES(sp)
    LOAD x6,  3  * REGBYTES(sp)
    LOAD x7,  4  * REGBYTES(sp)
    LOAD x8,  5  * REGBYTES(sp)
    LOAD x9,  6  * REGBYTES(sp)
    LOAD x10, 7  * REGBYTES(sp)
    LOAD x11, 8  * REGBYTES(sp)
    LOAD x12, 9  * REGBYTES(sp)
    LOAD x13, 10 * REGBYTES(sp)
    LOAD x14, 11 * REGBYTES(sp)
    LOAD x15, 12 * REGBYTES(sp)
#ifndef __riscv_32e
    LOAD x16, 13 * REGBYTES(sp)
    LOAD x17, 14 * REGBYTES(sp)
    LOAD x18, 15 * REGBYTES(sp)
    LOAD x19, 16 * REGBYTES(sp)
    LOAD x20, 17 * REGBYTES(sp)
    LOAD x21, 18 * REGBYTES(sp)
    LOAD x22, 19 * REGBYTES(sp)
    LOAD x23, 20 * REGBYTES(sp)
    LOAD x24, 21 * REGBYTES(sp)
    LOAD x25, 22 * REGBYTES(sp)
    LOAD x26, 23 * REGBYTES(sp)
    LOAD x27, 24 * REGBYTES(sp)
    LOAD x28, 25 * REGBYTES(sp)
    LOAD x29, 26 * REGBYTES(sp)
    LOAD x30, 27 * REGBYTES(sp)
    LOAD x31, 28 * REGBYTES(sp)
#endif

    addi sp, sp, RT_CONTEXT_SIZE

#ifdef __riscv_flen
    /* Restore Fpu registers when fpu is enabled */
    portasmRESTORE_FPU_REGISTERS
#endif

    mret
