/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/

#ifndef __AL_AXI_CANFD_HAL_H__
#define __AL_AXI_CANFD_HAL_H__

#include "al_axi_canfd_dev.h"
#include "al_osal.h"

#define AXI_CANFD_CREATE_TXMSG(ID, SRR_RTR_RRS, IDE, RTR_RRS, DLC, EDL_FDF, BRS, EFC, MM, TxBuf) \
(AlAxiCanFd_TxMsgStruct){ \
    .IdRegVal = ((IDE) == 0 ? (((ID) & 0x7FFU) << AXI_CANFD_TB_ID_ID_SHIFT) : ((((ID) >> 18) & 0x7FFU) << AXI_CANFD_TB_ID_ID_SHIFT)) | \
                (((SRR_RTR_RRS) & 0x1U) << AXI_CANFD_TB_ID_SRR_RTR_RRS_SHIFT) | \
                (((IDE) & 0x1U) << AXI_CANFD_TB_ID_IDE_SHIFT) | \
                ((IDE) == 0 ? 0 : (((ID) & 0x3FFFFU) << AXI_CANFD_TB_ID_EXT_ID_SHIFT)) | \
                (((RTR_RRS) & 0x1U) << AXI_CANFD_TB_ID_RTR_RRS_SHIFT), \
    .DlcRegVal = (((DLC) & 0xFU) << AXI_CANFD_TB_DLC_DLC_SHIFT) | \
                 (((EDL_FDF) & 0x1U) << AXI_CANFD_TB_DLC_EDL_FDF_SHIFT) | \
                 (((BRS) & 0x1U) << AXI_CANFD_TB_DLC_BRS_SHIFT) | \
                 (((EFC) & 0x1U) << AXI_CANFD_TB_DLC_EFC_SHIFT) | \
                 (((MM) & 0xFFU) << AXI_CANFD_TB_DLC_MM_SHIFT), \
    .Data = (AL_U8 *)(TxBuf), \
}

#define AXI_CANFD_CREATE_FILTER(ID, SRR, IDE, EXT_ID, RTR) \
    (((ID) << 21) | ((SRR) << 20) | ((IDE) << 19) | ((EXT_ID) << 1) | ((RTR) << 0))

#define AXI_CANFD_CREATE_TIMING(ARBI_DIV, ARBI_TS1, ARBI_TS2, ARBI_SJW, \
    DATA_DIV, DATA_TS1, DATA_TS2, DATA_SJW, IS_TDC_EN, TDC_OFFSET) \
(AlAxiCanFd_Timing){ \
    .ArbiPrescaler = ((ARBI_DIV) - 1), \
    .ArbiTS1 = ((ARBI_TS1) - 1), \
    .ArbiTS2 = ((ARBI_TS2) - 1), \
    .ArbiSJW = ((ARBI_SJW) - 1), \
 \
    .DataPrescaler = ((DATA_DIV) - 1), \
    .DataTS1 = ((DATA_TS1) - 1), \
    .DataTS2 = ((DATA_TS2) - 1), \
    .DataSJW = ((DATA_SJW) - 1), \
 \
    .IsTdcEn = (IS_TDC_EN), \
    .TdcOffset = (TDC_OFFSET), \
}

#define AXI_CANFD_DLC_TO_LEN(DLC) \
    ({AlAxiCanFd_Dev_DlcToLength(DLC);})

typedef struct {
    AlAxiCanFd_DevStruct Dev;

    AL_Lock AxiCanFdLock;
    AL_MailBox TxEventQueue;
    AL_MailBox RxEventQueue;
} AlAxiCanFd_HalStruct;

AL_U32 AlAxiCanFd_Hal_Init(AlAxiCanFd_HalStruct **Handle, AL_U32 DevId,
    AlAxiCanFd_InitConfigStruct *InitConfig,
    AlAxiCanFd_EventCallBack CallBack);
AL_U32 AlAxiCanFd_Hal_SetIntrFlag(AlAxiCanFd_HalStruct *Handle, AL_U32 IsTxIntrEn, AL_U32 IsRxIntrEn);
AL_U32 AlAxiCanFd_Hal_SendFrame(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_TxMsgStruct *TxMsg,
    AL_U32 Timeout);
AL_U32 AlAxiCanFd_Hal_RecvFrame(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_RxMsgStruct *RxMsg,
    AL_U32 Timeout);
AL_U32 AlAxiCanFd_Hal_RecvTxEvent(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_TxEventStruct *TxEvent,
    AL_U32 Timeout);
AL_U32 AlAxiCanFd_Hal_SetRxFilter(AlAxiCanFd_HalStruct *Handle, AL_U32 Index,
    AlAxiCanFd_RxFilter *RxFilter, AL_U32 Timeout);
AL_U32 AlAxiCanFd_Hal_IoCtl(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_IoCtlCmdEnum Cmd,
    AL_VOID *Data, AL_U32 Timeout);

#endif /* __AL_AXI_CANFD_HAL_H__ */