/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_core.h"
#include "al_gicv3_private.h"
#include "al_gicv3_dist.h"
#include "al_gicv3_rdist.h"

extern AL_U32 AlGic_CorePos(void);

#define GICV3_SPECIAL_START     (1020)
#define GICV3_SPECIAL_END       (1023)
#define GICV3_SPECIAL_NUM       (GICV3_SPECIAL_END - GICV3_SPECIAL_START +1)

AL_INTR_HandlerStruct irq_handler_list[SOC_INT_MAX + GICV3_SPECIAL_NUM];

/**
 * @desc  : irq handle implement
 * @flow  : read irq number -> deal with this irq event ->     write eoi
 */
AL_VOID do_irq_handle(AL_VOID)
{
    AL_U32 IntrId;
    AL_INTR_HandlerStruct Handler;

    IntrId = AlGicv3_AckIntrSel1();

    /* enable irq for preemption if not use rtos */
#ifndef USE_RTOS
    enable_irq();
#endif

    if (IntrId < SOC_INT_MAX) {
        Handler = irq_handler_list[IntrId];
    } else {
        Handler = irq_handler_list[IntrId - GICV3_SPECIAL_START + SOC_INT_MAX];
    }

    if (Handler.Func == NULL) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "can not found your irq handle at number: %d\r\n", IntrId);
    } else {
        Handler.Func(Handler.Param);
    }

    /******************************************
      disable irq before write eoi, because after write eoi, the running irq priority return to 0xFF;
      any interrupt will enter the irq handle function
    *****************************************/
    disable_irq();

    AlGicv3_EndOfIntrSel1(IntrId);
}

/**
 * @desc  : irq handle implement; this is weak function because we need to read ICC_IAR0_EL1 if group0 case
 * @flow  : read irq number -> deal with this irq event ->     write eoi
 */
AL_VOID do_fiq_handle(AL_VOID)
{
    AL_U32 IntrId;
    AL_INTR_HandlerStruct Handler;

    IntrId = AlGicv3_AckIntrSel1();

    /* enable fiq for preemption if not use rtos */
#ifndef USE_RTOS
    enable_fiq();
#endif

    if (IntrId < SOC_INT_MAX) {
        Handler = irq_handler_list[IntrId];
    } else {
        Handler = irq_handler_list[IntrId - GICV3_SPECIAL_START + SOC_INT_MAX];
    }

    if (Handler.Func == NULL) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "core[%d]: can not found your fiq handle at number: %d\n",
                                    AlGic_CorePos(), IntrId);
    } else {
        Handler.Func(Handler.Param);
    }

    /******************************************
      disable fiq before write eoi, because after write eoi, the running irq priority return to 0xFF;
      any interrupt will enter the fiq handle function
    *****************************************/
    disable_fiq();

    AlGicv3_EndOfIntrSel1(IntrId);
}

static AL_VOID AlIntr_RequestIntr(AL_U32 IntrId, AL_U32 CoreId, AL_VOID *Handler, AL_VOID *Param)
{
    AL_INTR_HandlerStruct *HandleArray;

    HandleArray = irq_handler_list;

    if (IntrId < SOC_INT_MAX) {
        HandleArray[IntrId].Func    = Handler;
        HandleArray[IntrId].Param   = Param;
        AlGicv3_EnableInterrupt(IntrId, CoreId);
    } else {
        HandleArray[IntrId - GICV3_SPECIAL_START + SOC_INT_MAX].Func = Handler;
        HandleArray[IntrId - GICV3_SPECIAL_START + SOC_INT_MAX].Param = Param;
    }
}

__attribute__((weak)) AL_S32 AlIntr_Hal_RegHandler(AL_U32 IntrId, AL_INTR_AttrStrct *IntrAttr, AL_INTR_Func Func, AL_VOID *Param)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "IntrId(%d) out of range\r\n", IntrId);
    return AL_ERR_ILLEGAL_PARAM;
}

AL_S32 AlIntr_RegHandlerToCore(AL_U32 IntrId, AL_U32 CoreId, AL_INTR_AttrStrct *IntrAttr, AL_INTR_Func Func, AL_VOID *Param)
{
    AL_U32 CpuId = CoreId;
    AL_INTR_AttrStrct *Attr;
    AL_S32 Ret = AL_OK;
    AL_DEFAULT_ATTR(DefAttr);

    Attr = (IntrAttr != AL_NULL) ? IntrAttr : &DefAttr;

    /* > SOC_INT_MAX && (not in the range of special range) */
    if ((IntrId >= SOC_INT_MAX) && (IntrId < GICV3_SPECIAL_START || IntrId > GICV3_SPECIAL_END)) {
        return AlIntr_Hal_RegHandler(IntrId, IntrAttr, Func, Param);
    }

    Ret = AlGicv3_SetInterruptTriggerMode(IntrId, CpuId, Attr->TrigMode);
    AlGicv3_SetInterruptPriority(IntrId, CpuId, Attr->Priority);

    if (IS_SPI(IntrId)) {
#ifdef SUPPORT_NONSECURE
        AlGicv3_SetInterruptType(IntrId, CpuId, INTR_GROUP1NS);
#else
        AlGicv3_SetInterruptType(IntrId, CpuId, INTR_GROUP1S);
#endif
        AlGicv3_SetSpiRouting(IntrId, GICV3_IRM_PE, CpuId);
    }

    AlIntr_RequestIntr(IntrId, CpuId, Func, Param);

    return Ret;
}

AL_S32 AlIntr_RegHandler(AL_U32 IntrId, AL_INTR_AttrStrct *IntrAttr, AL_INTR_Func Func, AL_VOID *Param)
{
    return AlIntr_RegHandlerToCore(IntrId, AlGic_CorePos(), IntrAttr, Func, Param);
}

AL_S32 AlIntr_SetInterrupt(AL_U32 IntrId, AL_FUNCTION State)
{
    AL_S32 Ret = AL_OK;

    switch (State) {
    case AL_FUNC_DISABLE:
        AlGicv3_DisableInterrupt(IntrId, AlGic_CorePos());
        Ret = AL_OK;
        break;

    case AL_FUNC_ENABLE:
        AlGicv3_EnableInterrupt(IntrId, AlGic_CorePos());
        Ret = AL_OK;
        break;

    default:
        Ret = AL_INTR_ERR_ILLEGAL_PARAM;
        break;
    }

    return Ret;
}

AL_S32 AlIntr_SetLocalInterrupt(AL_FUNCTION State)
{
    AL_S32 Ret = AL_OK;

    switch (State) {
    case AL_FUNC_DISABLE:
        disable_all_intr();
        Ret = AL_OK;
        break;

    case AL_FUNC_ENABLE:
        enable_all_intr();
        break;

    default:
        Ret = AL_INTR_ERR_ILLEGAL_PARAM;
        break;
    }

    return Ret;
}

AL_VOID AlIntr_RestoreLocalInterruptMask(AL_S32 Mask)
{
    set_intr_mask(Mask);
}

AL_S32 AlIntr_SaveLocalInterruptMask(AL_VOID)
{
#if defined(__aarch64__)
    AL_U32 ExceptionState ;
    AL_U32 EXCEPTION_ALL = (DAIF_IRQ_BIT | DAIF_FIQ_BIT) << 6;
    ExceptionState = get_intr_mask();
    ExceptionState = ExceptionState & EXCEPTION_ALL;
    if (ExceptionState != EXCEPTION_ALL) {
        (AL_U32)AlIntr_SetLocalInterrupt(AL_FUNC_DISABLE);
        return ExceptionState;
    }
    return ExceptionState;
#endif
}

AL_VOID AlIntr_ClearAllPending(AL_VOID)
{
    AL_U32 ClearVal = 0xFFFFFFFF;
    AL_U32 NumSpi = AlGicv3_GetSpiLimit(Gicv3DrvData->GicdBase);

    for (AL_U32 Id = MIN_SPI_ID; Id < NumSpi; Id += (1U << ICENABLER_SHIFT)) {
        Gicd_WriteIcenabler(Gicv3DrvData->GicdBase, Id, ClearVal);
        Gicd_WriteIcpendr(Gicv3DrvData->GicdBase, Id, ClearVal);
        Gicd_WriteIcactiver(Gicv3DrvData->GicdBase, Id, ClearVal);
    }
extern AL_U32 AlGic_CorePos(void);
    Gicr_WriteIcpendr0(Gicv3DrvData->RdistBaseAddrs[AlGic_CorePos()], ClearVal);
}


AL_S32 AlIntr_SetPreemptionBitsCount(AL_U32 Bits)
{
    GICV3_SYSREG_WRITE(icc_bpr1_el1, Bits);

    return AL_OK;
}

AL_VOID AlIntr_SetPriorityMask(AL_U32 Mask)
{
    GICV3_SYSREG_WRITE(icc_pmr_el1, Mask);
}

AL_U32 AlIntr_GetPriorityMask(AL_VOID)
{
    return (GICV3_SYSREG_READ(icc_pmr_el1) & 0xFF);
}

AL_VOID AlIntr_GenSoftIntr(AL_U32 IntrNum, AL_U64 CpuId)
{
    AlGicv3_RaiseSgi(IntrNum, AL_GICV3_SAME, CpuId);
}

AL_VOID AlIntr_GenNonSecSoftIntr(AL_U32 IntrNum, AL_U64 CpuId)
{
    AlGicv3_RaiseSgi(IntrNum, AL_GICV3_G1NS, CpuId);
}
