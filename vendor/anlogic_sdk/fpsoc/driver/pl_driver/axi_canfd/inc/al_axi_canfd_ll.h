/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/

#ifndef __AL_AXI_CANFD_LL_H__
#define __AL_AXI_CANFD_LL_H__

#include "al_type.h"
#include "al_reg_io.h"
#include "al_axi_canfd_hw.h"

static inline AL_U32 AlAxiCanFd_ll_ReadReg(AL_U64 BaseAddr, AL_U32 Offset)
{
    return AL_PL_REG32_READ(BaseAddr + Offset);
}

static inline void AlAxiCanFd_ll_WriteReg(AL_U64 BaseAddr, AL_U32 Offset, AL_U32 Value)
{
    AL_REG32_WRITE(BaseAddr + Offset, Value);
}

static inline void AlAxiCanFd_ll_SwRst(AL_U64 BaseAddr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_SW_RST_OFFSET, AXI_CANFD_SW_RST_SRST_SHIFT, 1);
}

static inline void AlAxiCanFd_ll_SetEnable(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_SW_RST_OFFSET, AXI_CANFD_SW_RST_CEN_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetSleep(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_SLEEP_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetLoopback(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_LBACK_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetSnoop(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_SNOOP_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetBRSD(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_BRSD_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetDAR(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_DAR_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetDPEE(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_DPEE_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetSBR(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_SBR_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetFDEN(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_SBR_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetABR(AL_U64 BaseAddr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_ABR_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetITO(AL_U64 BaseAddr, AL_U32 ITO)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_MODE_SEL_OFFSET, AXI_CANFD_MODE_SEL_ITO_SHIFT, AXI_CANFD_MODE_SEL_ITO_SIZE, ITO);
}

static inline void AlAxiCanFd_ll_SetArbitrationPrescaler(AL_U64 BaseAddr, AL_U32 BRP)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_BRP_OFFSET, AXI_CANFD_BRP_BRP_SHIFT, AXI_CANFD_BRP_BRP_SIZE, BRP);
}

static inline void AlAxiCanFd_ll_SetArbitrationTiming(AL_U64 BaseAddr, AL_U32 TS1, AL_U32 TS2, AL_U32 SJW)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_APBT_OFFSET, AXI_CANFD_APBT_TS1_SHIFT, AXI_CANFD_APBT_TS1_SIZE, TS1);
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_APBT_OFFSET, AXI_CANFD_APBT_TS2_SHIFT, AXI_CANFD_APBT_TS2_SIZE, TS2);
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_APBT_OFFSET, AXI_CANFD_APBT_SJW_SHIFT, AXI_CANFD_APBT_SJW_SIZE, SJW);
}

static inline AL_U32 AlAxiCanFd_ll_GetTxErrorCount(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AXI_CANFD_ERR_CNT_OFFSET, AXI_CANFD_ERR_CNT_TEC_SHIFT, AXI_CANFD_ERR_CNT_TEC_SIZE);
}

static inline AL_U32 AlAxiCanFd_ll_GetRxErrorCount(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AXI_CANFD_ERR_CNT_OFFSET, AXI_CANFD_ERR_CNT_REC_SHIFT, AXI_CANFD_ERR_CNT_REC_SIZE);
}

static inline AL_U32 AlAxiCanFd_ll_GetErrorStatus(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_CANFD_ERR_STS_OFFSET);
}

static inline AL_VOID AlAxiCanFd_ll_ClearErrorStatus(AL_U64 BaseAddr, AL_U32 ErrSta)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_ERR_STS_OFFSET, 0, 32, ErrSta);
}

static inline AL_U32 AlAxiCanFd_ll_GetStatus(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_CANFD_STS_OFFSET);
}

static inline AL_U32 AlAxiCanFd_ll_GetIntrStatus(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_CANFD_INT_STS_OFFSET);
}

static inline void AlAxiCanFd_ll_SetIntrEnable(AL_U64 BaseAddr, AL_U32 Intr, AL_BOOL IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_INT_EN_OFFSET, Intr, IsEnable);
}

static inline AL_U32 AlAxiCanFd_ll_GetIntrEnables(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_CANFD_INT_EN_OFFSET);
}

static inline void AlAxiCanFd_ll_DisableAllIntr(AL_U64 BaseAddr)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_INT_EN_OFFSET, 0, 32, 0);
}

static inline void AlAxiCanFd_ll_ClearIntrStatus(AL_U64 BaseAddr, AL_U32 Intr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_INT_CLR_OFFSET, Intr, 1U);
}

static inline void AlAxiCanFd_ll_ClearAllIntrStatus(AL_U64 BaseAddr)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_INT_CLR_OFFSET, 0, 32, 0xFFFFFFFF);
}

static inline void AlAxiCanFd_ll_ClearTimestamp(AL_U64 BaseAddr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_TS_OFFSET, AXI_CANFD_TS_CTS_SHIFT, 1U);
}

static inline AL_U32 AlAxiCanFd_ll_GetTimestamp(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AXI_CANFD_TS_OFFSET, AXI_CANFD_TS_TS_CNT_SHIFT, AXI_CANFD_TS_TS_CNT_SIZE);
}

static inline void AlAxiCanFd_ll_SetDataPrescaler(AL_U64 BaseAddr, AL_U32 Value)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_DPBRP_OFFSET, AXI_CANFD_DPBRP_DP_BRP_SHIFT, AXI_CANFD_DPBRP_DP_BRP_SIZE, Value);
}

static inline void AlAxiCanFd_ll_SetTxDlyCompOffset(AL_U64 BaseAddr, AL_U32 Value)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_DPBRP_OFFSET, AXI_CANFD_DPBRP_TDCOFF_SHIFT, AXI_CANFD_DPBRP_TDCOFF_SIZE, Value);
}

static inline void AlAxiCanFd_ll_SetTxDlyCompEnable(AL_U64 BaseAddr, AL_U32 IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_DPBRP_OFFSET, AXI_CANFD_DPBRP_TDC_SHIFT, IsEnable);
}

static inline void AlAxiCanFd_ll_SetDataTiming(AL_U64 BaseAddr, AL_U32 TS1, AL_U32 TS2, AL_U32 SJW)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_DPBT_OFFSET, AXI_CANFD_DPBT_DP_TS1_SHIFT, AXI_CANFD_DPBT_DP_TS1_SIZE, TS1);
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_DPBT_OFFSET, AXI_CANFD_DPBT_DP_TS2_SHIFT, AXI_CANFD_DPBT_DP_TS2_SIZE, TS2);
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_DPBT_OFFSET, AXI_CANFD_DPBT_DP_SJW_SHIFT, AXI_CANFD_DPBT_DP_SJW_SIZE, SJW);
}

static inline void AlAxiCanFd_ll_SetTxBufRdyReq(AL_U64 BaseAddr, AL_U32 Index)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_TBRR_OFFSET, AXI_CANFD_TBRR_RR_SHIFT + Index, 1U);
}

static inline AL_U32 AlAxiCanFd_ll_GetTxBufRdyReq(AL_U64 BaseAddr, AL_U32 Index)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AXI_CANFD_TBRR_OFFSET, AXI_CANFD_TBRR_RR_SHIFT + Index);
}

static inline void AlAxiCanFd_ll_SetTxBufRdyReqClearedIntrEn(AL_U64 BaseAddr, AL_U32 Index, AL_U32 IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_INT_EN_TBRR_OFFSET, AXI_CANFD_INT_EN_TBRR_RR_SHIFT + Index, IsEnable);
}

static inline void AlAxiCanFd_ll_SetTxBufCancelReq(AL_U64 BaseAddr, AL_U32 Index)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_TBCR_OFFSET, AXI_CANFD_TBCR_CR_SHIFT + Index, 1U);
}

static inline void AlAxiCanFd_ll_SetTxBufCancelReqIntrEn(AL_U64 BaseAddr, AL_U32 Index, AL_U32 IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_INT_EN_TBCSC_OFFSET, AXI_CANFD_INT_EN_TBCSC_ECRS_SHIFT + Index, IsEnable);
}

static inline AL_U32 AlAxiCanFd_ll_GetRxFifoStatus(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_CANFD_RXF_STS_OFFSET);
}

static inline AL_U32 AlAxiCanFd_ll_GetTxEventFifoLevel(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AXI_CANFD_TXE_FIFO_STS_OFFSET,
        AXI_CANFD_TXE_FIFO_STS_TXE_FL_SHIFT, AXI_CANFD_TXE_FIFO_STS_TXE_FL_SIZE);
}

static inline AL_U32 AlAxiCanFd_ll_GetTxEventReadIndex(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AXI_CANFD_TXE_FIFO_STS_OFFSET,
        AXI_CANFD_TXE_FIFO_STS_TXE_RI_SHIFT, AXI_CANFD_TXE_FIFO_STS_TXE_RI_SIZE);
}

static inline AL_VOID AlAxiCanFd_ll_TxEventIncrIdx(AL_U64 BaseAddr)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_TXE_FIFO_STS_OFFSET,
        AXI_CANFD_TXE_FIFO_STS_TXE_IRI_SHIFT, 1);
}

static inline AL_VOID AlAxiCanFd_ll_SetAcptFilterEn(AL_U64 BaseAddr, AL_U32 Index, AL_U32 IsEnable)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_AF_OFFSET,
        AXI_CANFD_AF_UAF0_SHIFT + Index, IsEnable == 0 ? 0 : 1);
}

static inline AL_U32 AlAxiCanFd_ll_GetAcptFilterEn(AL_U64 BaseAddr, AL_U32 Index)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AXI_CANFD_AF_OFFSET, AXI_CANFD_AF_UAF0_SHIFT + Index);
}

static inline AL_VOID AlAxiCanFd_ll_SetAfMaskReg(AL_U64 BaseAddr, AL_U32 Index, AL_U32 MaskReg)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_AFMR_OFFSET(Index),
        0, 32, MaskReg);
}

static inline AL_VOID AlAxiCanFd_ll_SetAfIdReg(AL_U64 BaseAddr, AL_U32 Index, AL_U32 IdReg)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_AFID_OFFSET(Index),
        0, 32, IdReg);
}

static inline AL_VOID AlAxiCanFd_ll_SetMailboxEn(AL_U64 BaseAddr, AL_U32 Index, AL_U32 IsEnable)
{
    AL_U32 Offset = (Index / 16) * 4U;
    AL_U32 Shift = Index % 16;

    AL_PL_REG32_SET_BIT(BaseAddr + AXI_CANFD_RXBC_STS0_OFFSET + Offset,
        AXI_CANFD_RXBC_STS0_HCB_SHIFT + Shift, IsEnable == 0 ? 0 : 1);
}

static inline AL_U32 AlAxiCanFd_ll_GetMailboxEn(AL_U64 BaseAddr, AL_U32 Index)
{
    AL_U32 Offset = (Index / 16) * 4U;
    AL_U32 Shift = Index % 16;

    return AL_PL_REG32_GET_BIT(BaseAddr + AXI_CANFD_RXBC_STS0_OFFSET + Offset,
        AXI_CANFD_RXBC_STS0_HCB_SHIFT + Shift);
}

static inline AL_VOID AlAxiCanFd_ll_SetMailboxMaskReg(AL_U64 BaseAddr, AL_U32 Index, AL_U32 MaskReg)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_CANFD_MAILBOX_MASK_OFFSET(Index),
        0, 32, MaskReg);
}

#endif /* __AL_AXI_CANFD_LL_H__ */