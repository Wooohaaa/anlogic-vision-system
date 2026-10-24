/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/

#ifndef __AL_AXI_CANFD_DEV_H__
#define __AL_AXI_CANFD_DEV_H__

#include "al_type.h"
#include "al_axi_canfd_hw.h"


#define AL_AXICANFD_ERR_ILLEGAL_PARAM    AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, AL_ERR_ILLEGAL_PARAM)
#define AL_AXICANFD_ERR_BUSY             AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, AL_ERR_BUSY)
#define AL_AXICANFD_ERR_TIMEOUT          AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, AL_ERR_TIMEOUT)
#define AL_AXICANFD_ERR_NOT_SUPPORT      AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_SUPPORT)
#define AL_AXICANFD_ERR_NOT_READY        AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_READY)
#define AL_AXICANFD_ERR_NOT_READY        AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_READY)
#define AL_AXICANFD_NO_DATA              AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, AL_ERR_MAX + 1)
#define AL_AXICANFD_EVENTS_TO_ERRS(Event) (AL_DEF_ERR(AL_AXICANFD, AL_LOG_LEVEL_ERROR, (Event << AL_ERR_MAX)))

#define AL_AXI_CANFD_SEQUENTIAL 0
#define AL_AXI_CANFD_MAILBOX    1

typedef enum
{
    AXI_CANFD_MODE_CONFIG      = BIT(0),
    AXI_CANFD_MODE_LOOPBACK    = BIT(1),
    AXI_CANFD_MODE_SLEEP       = BIT(2),
    AXI_CANFD_MODE_NORMAL      = BIT(3),
    AXI_CANFD_MODE_SNOOP       = BIT(4),
} AlAxiCanFd_ModeEnum;

typedef enum
{
    AXI_CANFD_IOCTL_SET_TIMING = 0,
    AXI_CANFD_IOCTL_SET_MODE,

    AXI_CANFD_IOCTL_GET_TIMING,
    AXI_CANFD_IOCTL_GET_MODE,
} AlAxiCanFd_IoCtlCmdEnum;


typedef enum
{
    AXI_CANFD_EVENT_ARBLST                     = BIT(0),
    AXI_CANFD_EVENT_TXOK                       = BIT(1),
    AXI_CANFD_EVENT_PEE                        = BIT(2),
    AXI_CANFD_EVENT_BSFRD                      = BIT(3),
    AXI_CANFD_EVENT_RXOK                       = BIT(4),
    AXI_CANFD_EVENT_TSCNT_OFLW                 = BIT(5),
    AXI_CANFD_EVENT_RXFOFLW                    = BIT(6),
    AXI_CANFD_EVENT_ERROR                      = BIT(8),
    AXI_CANFD_EVENT_BSOFF                      = BIT(9),
    AXI_CANFD_EVENT_SLP                        = BIT(10),
    AXI_CANFD_EVENT_WKUP                       = BIT(11),
    AXI_CANFD_EVENT_RXFWMFLL                   = BIT(12),
    AXI_CANFD_EVENT_TXRRS                      = BIT(13),
    AXI_CANFD_EVENT_TXCRS                      = BIT(14),
    AXI_CANFD_EVENT_RXRBF_RXFOFLW_1            = BIT(15),
    AXI_CANFD_EVENT_RXBOFLW_RXFWMFLL_1         = BIT(16),
    AXI_CANFD_EVENT_RXMNF                      = BIT(17),
    AXI_CANFD_EVENT_TXEOFLW                    = BIT(30),
    AXI_CANFD_EVENT_TXEWMFLL                   = BIT(31),
} AlAxiCanFd_EventIdEnum;

typedef enum
{
    AL_AXI_CANFD_STATE_NOT_INIT              = 0,
    AL_AXI_CANFD_STATE_READY                 = BIT(0),
    AL_AXI_CANFD_STATE_SEND_BUSY             = BIT(1),
    AL_AXI_CANFD_STATE_RECV_BUSY             = BIT(2),
    AL_AXI_CANFD_STATE_RECV_TX_EVENT_BUSY    = BIT(3),
    AL_AXI_CANFD_STATE_ERROR                 = BIT(4),
} AlAxiCanFd_StateEnum;

/**************************** Type Definitions *******************************/
/**
 * @brief  Define the message structure for the mailbox used by axi-qspi
 */
typedef struct
{
    AlAxiCanFd_EventIdEnum       EventId;
    AL_U32                       EventData;
} AlAxiCanFd_EventStruct;

/**
 * @brief  Define the callback handle type for events
 */
typedef AL_VOID (*AlAxiCanFd_EventCallBack)(AlAxiCanFd_EventStruct *CanFdEvent, AL_VOID *CallbackRef);


typedef struct
{
    AL_U32 IdRegVal;
    AL_U32 DlcRegVal;
    AL_U8 *Data;
}AlAxiCanFd_TxMsgStruct;

typedef struct
{
    union
    {
        struct {
            AL_U32 RtrRrs : 1;
            AL_U32 ExtId : 18;
            AL_U32 Ide : 1;
            AL_U32 SrrRtrRrs : 1;
            AL_U32 Id : 11;
        };
        AL_U32 Val;
    } IdRegVal;

    union
    {
        struct {
            AL_U32 Timestamp : 16;
            AL_U32 FilterIdx : 5;
            AL_U32 Rsvd : 4;
            AL_U32 Esi : 1;
            AL_U32 Brs : 1;
            AL_U32 EdlFdf : 1;
            AL_U32 Dlc : 4;
        };
        AL_U32 Val;
    } DlcRegVal;

    AL_U8 Data[64];
}AlAxiCanFd_RxMsgStruct;

typedef struct
{
    AL_U32 IsEnable;    /* for fifo mode, it's the enable of filter
                            for mailbox mode, it's the enable of mailbox buffer*/
    AL_U32 MaskReg;
    AL_U32 IdReg;
} AlAxiCanFd_RxFilter;

typedef struct
{
    AL_U32 IdRegVal;
    AL_U32 DlcRegVal;
}AlAxiCanFd_TxEventStruct;

typedef struct
{
    AL_U8 IsDisBitRateSwitch;
    AL_U8 IsDisAutoRetransmission;
    AL_U8 IsDisProtocolExceptionEvent;
    AL_U8 IsAutoBusRecovery;
    AL_U8 InternalTimingOpt;
} AlAxiCanFd_InitConfigStruct;

typedef struct
{
    AL_U32 ArbLst_Cnt;
    AL_U32 Tx_Cnt;
    AL_U32 Rx_Cnt;
    AL_U32 Err_Cnt;
} AlAxiCanFd_StatusRecord;

typedef struct
{
    AL_U32 ArbiPrescaler;
    AL_U32 ArbiTS1;
    AL_U32 ArbiTS2;
    AL_U32 ArbiSJW;

    AL_U32 DataPrescaler;
    AL_U32 DataTS1;
    AL_U32 DataTS2;
    AL_U32 DataSJW;

    AL_U32 IsTdcEn;
    AL_U32 TdcOffset;
} AlAxiCanFd_Timing;

typedef struct
{
    AlAxiCanFd_HwConfigStruct HwConfig;
    AlAxiCanFd_InitConfigStruct InitConfig;

    AL_U32 IsTxIntrEn;
    AL_U32 IsRxIntrEn;

    AlAxiCanFd_Timing Timing;

    AlAxiCanFd_ModeEnum CurMode;

    AlAxiCanFd_EventCallBack EventCallBack;
    AL_VOID *EventCallBackRef;

    volatile AlAxiCanFd_StateEnum State;
    AlAxiCanFd_StatusRecord StaRcd;
} AlAxiCanFd_DevStruct;

AlAxiCanFd_HwConfigStruct *AlAxiCanFd_Dev_LookupConfig(AL_U32 DevId);
AL_U32 AlAxiCanFd_Dev_Init(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_HwConfigStruct *HwConfig,
    AlAxiCanFd_InitConfigStruct *InitConfig);
AL_U32 AlAxiCanFd_Dev_SetIntrOrPollingMode(AlAxiCanFd_DevStruct *Dev, AL_U32 IsTxIntrEn, AL_U32 IsRxIntrEn);
AL_U32 AlAxiCanFd_Dev_SendFrame(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_TxMsgStruct *TxMsg, AL_U32 Index);
AL_U32 AlAxiCanFd_Dev_RecvFrame(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_RxMsgStruct *RxMsg, AL_U32 FifoNo, AL_U32 RxIndex);
AL_U32 AlAxiCanFd_Dev_RecvTxEvent(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_TxEventStruct *TxEvent);
AL_U32 AlAxiCanFd_Dev_GetMode(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_ModeEnum *Mode);
AL_U32 AlAxiCanFd_Dev_SetMode(AlAxiCanFd_DevStruct *Dev, const AlAxiCanFd_ModeEnum Mode);
AL_U32 AlAxiCanFd_Dev_SetTiming(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_Timing *Timing);
AL_U32 AlAxiCanFd_Dev_GetTiming(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_Timing *Timing);
AL_U32 AlAxiCanFd_Dev_SetRxFilter(AlAxiCanFd_DevStruct *Dev, AL_U32 Index, AlAxiCanFd_RxFilter *RxFilter);
AL_U32 AlAxiCanFd_Dev_GetFreeTxBuf(AlAxiCanFd_DevStruct *Dev, AL_U32 *TxBufIndex);
AL_U32 AlAxiCanFd_Dev_GetFullRxBufIdx(AlAxiCanFd_DevStruct *Dev, AL_U32 *FifoNo, AL_U32 *RxIndex);
AL_U32 AlAxiCanFd_Dev_DlcToLength(AL_U32 Dlc);

#endif /* __AL_AXI_CANFD_DEV_H__ */