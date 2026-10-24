/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_aarch64_core.h"
#include "al_aarch64_sysreg.h"
#include "al_type.h"
#include "al_utils_def.h"

#define AL_CALL_STACK_DEPTH 32

#ifdef USE_RTOS
#ifdef RTOS_RTTHREAD
extern AL_UINTPTR _heap_start;
extern AL_UINTPTR stack_top;
#endif
#ifdef RTOS_FREERTOS
extern AL_UINTPTR _bss_start;
extern AL_UINTPTR _bss_end;
#endif
#else
extern AL_UINTPTR stack_start;
extern AL_UINTPTR stack_top;
#endif

extern void AlMpu_DecodeErrRegion(void);

static const char * const EsrInfo[] = {
    [EC_UNKNOWN] = "Unknown reason.",
    [EC_WFE_WFI] = "Trapped WF* instruction execution.",
    [EC_AARCH32_CP15_MRC_MCR] = "Trapped MCR or MRC access with (coproc==0b1111).",
    [EC_AARCH32_CP15_MRRC_MCRR] = "Trapped MCRR or MRRC access with (coproc==0b1111).",
    [EC_AARCH32_CP14_MRC_MCR] = "Trapped MCR or MRC access with (coproc==0b1110).",
    [EC_AARCH32_CP14_LDC_STC] = "Trapped LDC or STC access.",
    [EC_FP_SIMD] = "Access to SME, SVE, Advanced SIMD or floating-point functionality trapped.",
    [EC_ILLEGAL] = "Illegal Execution state.",
    [EC_AARCH64_SVC] = "SVC instruction execution in AArch64 state.",
    [EC_AARCH64_HVC] = "HVC instruction execution in AArch64 state.",
    [EC_AARCH64_SMC] = "SMC instruction execution in AArch64 state.",
    [EC_AARCH64_SYS] = "Trapped MSR, MRS or System instruction execution in AArch64 state.",
    [EC_IABORT_LOWER_EL] = "Instruction Abort from a lower Exception level.",
    [EC_IABORT_CUR_EL] = "Instruction Abort from current Exception level.",
    [EC_PC_ALIGN] = "PC alignment fault exception.",
    [EC_DABORT_LOWER_EL] = "Data Abort from a lower Exception level.",
    [EC_DABORT_CUR_EL] = "Data Abort from current Exception level.",
    [EC_SP_ALIGN] = "SP alignment fault exception.",
    [EC_AARCH64_FP] = "Trapped floating-point exception taken from AArch64 state.",
    [EC_SERROR] = "SError interrupt",
    [EC_BRK] = "BRK instruction execution in AArch64 state."
};

static AL_VOID ErrReasonFromEsr(AL_UINTPTR Esr)
{
    AL_UINTPTR Ec = (Esr & (ESR_EC_MASK << ESR_EC_SHIFT)) >> ESR_EC_SHIFT;
    /* TODO: decode Iss field */
    // AL_UINTPTR Iss = Esr & ESR_ISS_MASK;
    AL_LOG(AL_LOG_LEVEL_ERROR, "ESR: 0x%016lx - %s\r\n", Esr, EsrInfo[Ec]);

#if MPU_PROTECT_MODE != 0
    AlMpu_DecodeErrRegion();
#endif
}

#ifdef USE_RTOS
#ifdef RTOS_RTTHREAD
AL_UINTPTR *AlBackTrace_DumpRegs(AL_UINTPTR *Sp)
{
    AL_UINTPTR *StackPointer = Sp;
    AL_UINTPTR *Fp;
    AL_UINTPTR Esr, Fpcr, Fpsr;

    __asm__ __volatile__("mov %0, x1":"=r"(Esr)::"x1");
    ErrReasonFromEsr(Esr);

    AL_LOG(AL_LOG_LEVEL_ERROR, "FAR: 0x%016lx\r\n", get_far());
    AL_LOG(AL_LOG_LEVEL_ERROR, "ELR: 0x%016lx\r\n", *(StackPointer++));
    AL_LOG(AL_LOG_LEVEL_ERROR, "SPSR: 0x%016lx\r\n", *(StackPointer++));

    AL_LOG(AL_LOG_LEVEL_ERROR, "x30: 0x%016lx, xzr: 0x%016lx\r\n",
           *(StackPointer), *(StackPointer + 1));
    StackPointer += 2;
    Fpcr = *(StackPointer++);
    Fpsr = *(StackPointer++);
    Fp = StackPointer + 1;
    for (AL_U32 i = 0; i < 29; i+=2) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "x%-2d: 0x%016lx, x%-2d: 0x%016lx\r\n",
               28 - i, *(StackPointer + i), 29 - i, *(StackPointer + i + 1));
    }
    StackPointer += 30;
    AL_LOG(AL_LOG_LEVEL_ERROR, "FPCR: 0x%016lx\r\n", Fpcr);
    AL_LOG(AL_LOG_LEVEL_ERROR, "FPSR: 0x%016lx\r\n", Fpsr);
    for (AL_U32 i = 0; i < 15; i++) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Q%-2d: 0x%016lx%016lx\r\n",
                15 - i, *(StackPointer + (i << 1)), *(StackPointer + (i << 1) + 1));
    }

    return Fp;
}
#endif
#ifdef RTOS_FREERTOS
AL_UINTPTR *AlBackTrace_DumpRegs(AL_UINTPTR *Sp)
{
    AL_UINTPTR *StackPointer = Sp;
    AL_UINTPTR CriticalNestingConst;
    AL_UINTPTR PortTaskHasFPUContextConst;
    AL_UINTPTR Esr, x0, CurTcbConst;

    __asm__ __volatile__("mov %0, x1":"=r"(Esr)::"x1");
    PortTaskHasFPUContextConst = *(StackPointer++);
    CriticalNestingConst = *(StackPointer++);
    AL_LOG(AL_LOG_LEVEL_ERROR, "PortTaskHasFPUContextConst: %ld\r\n", PortTaskHasFPUContextConst);
    AL_LOG(AL_LOG_LEVEL_ERROR, "CriticalNestingConst: %ld\r\n", CriticalNestingConst);

    if (PortTaskHasFPUContextConst) {
        for (AL_U32 i = 0; i < 31; i+=2) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Q%-2d: 0x%016lx%016lx\r\n",
                   31 - i, *(StackPointer + (i << 1)), *(StackPointer + (i << 1) + 1));
            AL_LOG(AL_LOG_LEVEL_ERROR, "Q%-2d: 0x%016lx%016lx\r\n",
                   30 - i, *(StackPointer + (i << 1) + 2), *(StackPointer + (i << 1) + 3));
        }
        StackPointer += 64;
        AL_LOG(AL_LOG_LEVEL_ERROR, "FPCR: 0x%016lx\r\n", *(StackPointer++));
        AL_LOG(AL_LOG_LEVEL_ERROR, "FPSR: 0x%016lx\r\n", *(StackPointer++));
    }
    AL_LOG(AL_LOG_LEVEL_ERROR, "ELR: 0x%016lx\r\n", *(StackPointer++));
    ErrReasonFromEsr(Esr);
    AL_LOG(AL_LOG_LEVEL_ERROR, "FAR: 0x%016lx\r\n", get_far());
    AL_LOG(AL_LOG_LEVEL_ERROR, "SPSR: 0x%016lx\r\n", *(StackPointer++));
    for (AL_U32 i = 0; i < 31; i+=2) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "x%-2d: 0x%016lx, x%-2d: 0x%016lx\r\n",
               30 - i, *(StackPointer + i), 31 - i, *(StackPointer + i + 1));
    }
    StackPointer += 3;

    return StackPointer;
}
#endif
#else
AL_UINTPTR *AlBackTrace_DumpRegs(AL_UINTPTR *Sp)
{
    AL_UINTPTR *StackPointer = Sp;
    AL_UINTPTR Esr, x0;
    AL_LOG(AL_LOG_LEVEL_ERROR, "FAR: 0x%016lx\r\n", get_far());
    AL_LOG(AL_LOG_LEVEL_ERROR, "SPSR: 0x%016lx\r\n", *(StackPointer++));
    Esr = *(StackPointer++);
    ErrReasonFromEsr(Esr);
    AL_LOG(AL_LOG_LEVEL_ERROR, "ELR: 0x%016lx\r\n", *(StackPointer++));
    x0 = *(StackPointer++);
    AL_LOG(AL_LOG_LEVEL_ERROR, "FPCR: 0x%016lx\r\n", *(StackPointer++));
    AL_LOG(AL_LOG_LEVEL_ERROR, "FPSR: 0x%016lx\r\n", *(StackPointer++));
    for (AL_U32 i = 0; i < 32; i++) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Q%-2d: 0x%016lx%016lx\r\n",
                                   i, *(StackPointer + (i << 1)), *(StackPointer + (i << 1) + 1));
    }
    StackPointer += 64;
    AL_LOG(AL_LOG_LEVEL_ERROR, "x0: 0x%016lx\r\n", x0);
    for (AL_U32 i = 1; i < 30; i+=2) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "x%-2d: 0x%016lx, x%-2d: 0x%016lx\r\n",
                                   i, *(StackPointer + i - 1), (i + 1), *(StackPointer + i));
    }
    StackPointer += 30;

    StackPointer -= 2;

    return StackPointer;
}
#endif

AL_VOID AlBackTrace_DumpStack(AL_UINTPTR *CurFp)
{
#ifdef USE_RTOS
#ifdef RTOS_RTTHREAD
    AL_UINTPTR *EndofStack = (AL_UINTPTR *)(&_heap_start);
    AL_UINTPTR *StartofStack = (AL_UINTPTR *)(&stack_top);
    AL_UINTPTR *Lr = CurFp - 5;
#endif
#ifdef RTOS_FREERTOS
    AL_UINTPTR *EndofStack = (AL_UINTPTR *)(&_bss_start);
    AL_UINTPTR *StartofStack = (AL_UINTPTR *)(&_bss_end);
    AL_UINTPTR *Lr = CurFp - 3;
#endif
#else
    AL_UINTPTR *EndofStack = (AL_UINTPTR *)(&stack_start);
    AL_UINTPTR *StartofStack = (AL_UINTPTR *)(&stack_top);
    AL_UINTPTR *Lr = CurFp + 1;
#endif
    AL_UINTPTR *Fp, *Pc;
    AL_UINTPTR CallDepth[AL_CALL_STACK_DEPTH];
    AL_U32 CurDepth = 0;

    Fp = CurFp;
    Pc = (AL_UINTPTR *)((*Lr) - 4);

    do {
        al_printf("%d: FP: 0x%016lx PC: 0x%016lx\r\n", CurDepth, (AL_UINTPTR)Fp, (AL_UINTPTR)Pc);

        if (CurDepth < AL_CALL_STACK_DEPTH) {
            CallDepth[CurDepth++] = (AL_UINTPTR)Pc;
        }

        Fp = (AL_UINTPTR *)*Fp;
        if ((Fp > StartofStack) || (Fp < EndofStack)) {
            break;
        }
        Lr = Fp + 1;
        Pc = (AL_UINTPTR *)((*Lr) - 4);
    } while(1);

    al_printf("Show more call stack info by run: addr2line -e <elfname> -afpiC ");
    for (AL_U32 i = 0; i < CurDepth; i++) {
        al_printf("%08lx ", CallDepth[i]);
    }
    al_printf("\r\n");
}

AL_VOID AlBackTrace_Fault(AL_UINTPTR *Sp)
{
    AL_UINTPTR *CurFp;

    CurFp = AlBackTrace_DumpRegs(Sp);

    AlBackTrace_DumpStack(CurFp);

}