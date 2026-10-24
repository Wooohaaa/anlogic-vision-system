/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_canfd_hal.h"

/************************** Variable Definitions *****************************/
static AlAxiCanFd_HalStruct AlAxiCanFdHandle[AL_AXI_CANFD_NUM_INSTANCE] = { 0 };

/************************** Function Prototypes ******************************/
extern AL_VOID AlAxiCanFd_Dev_IntrHandler(AL_VOID *Instance);
extern AL_U32 AlAxiCanFd_Dev_RegisterEventCallBack(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_EventCallBack CallBack, AL_VOID *CallBackRef);


static AL_VOID AlCanFd_DefEventCallBack(AlAxiCanFd_EventStruct *Event, void *CallBackRef)
{
    AlAxiCanFd_HalStruct *Handle = (AlAxiCanFd_HalStruct *)CallBackRef;
    switch (Event->EventId)
    {
        case AXI_CANFD_EVENT_TXOK:
            AlOsal_Mb_Send(&Handle->TxEventQueue, Event);
            break;
        case AXI_CANFD_EVENT_RXOK:
            AlOsal_Mb_Send(&Handle->RxEventQueue, Event);
            break;
        case AXI_CANFD_EVENT_ARBLST:
        case AXI_CANFD_EVENT_PEE:
        case AXI_CANFD_EVENT_BSFRD:
        case AXI_CANFD_EVENT_TSCNT_OFLW:
        case AXI_CANFD_EVENT_RXFOFLW:
        case AXI_CANFD_EVENT_ERROR:
        case AXI_CANFD_EVENT_BSOFF:
        case AXI_CANFD_EVENT_SLP:
        case AXI_CANFD_EVENT_WKUP:
        case AXI_CANFD_EVENT_RXFWMFLL:
        case AXI_CANFD_EVENT_TXRRS:
        case AXI_CANFD_EVENT_TXCRS:
        case AXI_CANFD_EVENT_RXRBF_RXFOFLW_1:
        case AXI_CANFD_EVENT_RXBOFLW_RXFWMFLL_1:
        case AXI_CANFD_EVENT_RXMNF:
        case AXI_CANFD_EVENT_TXEOFLW:
        case AXI_CANFD_EVENT_TXEWMFLL:
            break;
        default:
            break;
    }
}

static AL_U32 AlAxiCanFd_Hal_WaitSendDoneOrTimeout(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_EventStruct *Event, AL_U32 Timeout)
{
    AL_U32 Status;
    AL_U32 TxBufIdx;

    if (Handle->Dev.IsTxIntrEn) {
        Status = AlOsal_Mb_Receive(&(Handle->TxEventQueue), Event, Timeout);
        if (Status != AL_OK) {
            return AL_AXICANFD_ERR_TIMEOUT;
        }
    } else {
        Status = AL_WAIT_COND_UNTIL_TIMEOUT(
                AL_OK == AlAxiCanFd_Dev_GetFreeTxBuf(&Handle->Dev, &TxBufIdx), Timeout);
        if (Status != AL_TRUE) {
            return AL_AXICANFD_ERR_TIMEOUT;
        }
    }

    return AL_OK;
}

static AL_U32 AlAxiCanFd_Hal_WaitRecvDoneOrTimeout(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_EventStruct *Event, AL_U32 Timeout)
{
    AL_U32 Status;
    AL_U32 FifoNo;
    AL_U32 RxBufIdx;

    if (Handle->Dev.IsRxIntrEn) {
        Status = AlOsal_Mb_Receive(&(Handle->RxEventQueue), Event, Timeout);
        if (Status != AL_OK) {
            return AL_AXICANFD_ERR_TIMEOUT;
        }
    } else {
        Status = AL_WAIT_COND_UNTIL_TIMEOUT(
                AL_OK == AlAxiCanFd_Dev_GetFullRxBufIdx(&Handle->Dev, &FifoNo, &RxBufIdx), Timeout);
        if (Status != AL_TRUE) {
            return AL_AXICANFD_ERR_TIMEOUT;
        }
    }

    return AL_OK;
}

AL_U32 AlAxiCanFd_Hal_Init(AlAxiCanFd_HalStruct **Handle, AL_U32 DevId,
    AlAxiCanFd_InitConfigStruct *InitConfig, AlAxiCanFd_EventCallBack CallBack)
{
    AL_U32 Status;
    AlAxiCanFd_HwConfigStruct *HwConfig = AL_NULL;

    HwConfig = AlAxiCanFd_Dev_LookupConfig(DevId);
    if (HwConfig == AL_NULL) {
        return AL_ERROR;
    } else {
        *Handle = &AlAxiCanFdHandle[DevId];
    }

    Status = AlAxiCanFd_Dev_Init(&(*Handle)->Dev, HwConfig, InitConfig);
    if (Status != AL_OK) {
        return AL_ERROR;
    }

    if (CallBack == AL_NULL) {
        AlAxiCanFd_Dev_RegisterEventCallBack(&(*Handle)->Dev, AlCanFd_DefEventCallBack, (AL_VOID *)*Handle);
    } else {
        AlAxiCanFd_Dev_RegisterEventCallBack(&(*Handle)->Dev, CallBack, (AL_VOID *)*Handle);
    }

    (AL_VOID)AlIntr_RegHandler(HwConfig->IntrId, AL_NULL, AlAxiCanFd_Dev_IntrHandler, &(*Handle)->Dev);

    Status = AlOsal_Lock_Init(&(*Handle)->AxiCanFdLock, "AxiCanFdLock");
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlOsal_Mb_Init(&(*Handle)->TxEventQueue, "TxEventQueue");
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlOsal_Mb_Init(&(*Handle)->RxEventQueue, "RxEventQueue");
    if (Status != AL_OK) {
        return Status;
    }

    return AL_OK;
}

AL_U32 AlAxiCanFd_Hal_SetIntrFlag(AlAxiCanFd_HalStruct *Handle, AL_U32 IsTxIntrEn, AL_U32 IsRxIntrEn)
{
    if (Handle == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    return AlAxiCanFd_Dev_SetIntrOrPollingMode(&Handle->Dev, IsTxIntrEn, IsRxIntrEn);
}

AL_U32 AlAxiCanFd_Hal_SendFrame(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_TxMsgStruct *TxMsg, AL_U32 Timeout)
{
    AL_U32 Status = AL_OK;
    AL_U32 TxBufIdx = 0xFFFFFFFFU;
    AlAxiCanFd_EventStruct CanFdEvent = { 0 };

    if (Handle == AL_NULL || TxMsg == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    Status = AlOsal_Lock_Take(&Handle->AxiCanFdLock, Timeout);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlAxiCanFd_Dev_GetFreeTxBuf(&Handle->Dev, &TxBufIdx);
    if (Status == AL_AXICANFD_ERR_BUSY) {
        Status = AlAxiCanFd_Hal_WaitSendDoneOrTimeout(Handle, &CanFdEvent, Timeout);
        if (Status != AL_OK) {
            (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);
            return Status;
        }

        Status = AlAxiCanFd_Dev_GetFreeTxBuf(&Handle->Dev, &TxBufIdx);
        if (Status == AL_AXICANFD_ERR_BUSY) {
            Status = AlAxiCanFd_Hal_WaitSendDoneOrTimeout(Handle, &CanFdEvent, Timeout);
            if (Status != AL_OK) {
                (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);
                return Status;
            }

            Status = AlAxiCanFd_Dev_GetFreeTxBuf(&Handle->Dev, &TxBufIdx);
        }
    }

    if (Status != AL_OK) {
        (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);
        return Status;
    }

    Status = AlAxiCanFd_Dev_SendFrame(&Handle->Dev, TxMsg, TxBufIdx);

    (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);

    return Status;
}

AL_U32 AlAxiCanFd_Hal_RecvFrame(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_RxMsgStruct *RxMsg, AL_U32 Timeout)
{
    AL_U32 Status = AL_OK;
    AL_U32 FifoNo = 0xFFFFFFFFU;
    AL_U32 RxIndex = 0xFFFFFFFFU;
    AlAxiCanFd_EventStruct CanFdEvent = { 0 };

    if (Handle == AL_NULL || RxMsg == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    Status = AlOsal_Lock_Take(&Handle->AxiCanFdLock, Timeout);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlAxiCanFd_Dev_GetFullRxBufIdx(&Handle->Dev, &FifoNo, &RxIndex);
    if (Status == AL_AXICANFD_NO_DATA) {
        Status = AlAxiCanFd_Hal_WaitRecvDoneOrTimeout(Handle, &CanFdEvent, Timeout);
        if (Status != AL_OK) {
            (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);
            return Status;
        }

        Status = AlAxiCanFd_Dev_GetFullRxBufIdx(&Handle->Dev, &FifoNo, &RxIndex);
        if (Status == AL_AXICANFD_NO_DATA) {
            Status = AlAxiCanFd_Hal_WaitRecvDoneOrTimeout(Handle, &CanFdEvent, Timeout);
            if (Status != AL_OK) {
                (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);
                return Status;
            }
        }

        Status = AlAxiCanFd_Dev_GetFullRxBufIdx(&Handle->Dev, &FifoNo, &RxIndex);
    }

    if (Status != AL_OK) {
        (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);
        return Status;
    }

    Status = AlAxiCanFd_Dev_RecvFrame(&Handle->Dev, RxMsg, FifoNo, RxIndex);

    (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);

    return Status;
}

AL_U32 AlAxiCanFd_Hal_RecvTxEvent(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_TxEventStruct *TxEvent, AL_U32 Timeout)
{
    AL_U32 Status;
    AlAxiCanFd_EventStruct CanFdEvent = { 0 };

    if (Handle == AL_NULL || TxEvent == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    Status = AlOsal_Lock_Take(&Handle->AxiCanFdLock, Timeout);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlAxiCanFd_Dev_RecvTxEvent(&Handle->Dev, TxEvent);
    if (Status != AL_OK) {
        (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);
        return Status;
    }

    Status = AlAxiCanFd_Hal_WaitRecvDoneOrTimeout(Handle, &CanFdEvent, Timeout); /* maybe need a new mailbox */
    if (Status != AL_OK) {
        Status = AL_ERROR;
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);

    return Status;
}

AL_U32 AlAxiCanFd_Hal_SetRxFilter(AlAxiCanFd_HalStruct *Handle, AL_U32 Index, AlAxiCanFd_RxFilter *RxFilter, AL_U32 Timeout)
{
    AL_U32 Status;

    if (Handle == AL_NULL || RxFilter == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    Status = AlOsal_Lock_Take(&Handle->AxiCanFdLock, Timeout);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlAxiCanFd_Dev_SetRxFilter(&Handle->Dev, Index, RxFilter);

    (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);

    return Status;
}

AL_U32 AlAxiCanFd_Hal_IoCtl(AlAxiCanFd_HalStruct *Handle, AlAxiCanFd_IoCtlCmdEnum Cmd, AL_VOID *Data, AL_U32 Timeout)
{
    AL_U32 Status;

    if (Handle == AL_NULL) {
        return AL_ERROR;
    }

    Status = AlOsal_Lock_Take(&Handle->AxiCanFdLock, Timeout);
    if (Status != AL_OK) {
        return Status;
    }

    switch (Cmd)
    {
        case AXI_CANFD_IOCTL_SET_TIMING:
            Status = AlAxiCanFd_Dev_SetMode(&Handle->Dev, AXI_CANFD_MODE_CONFIG);
            if (Status != AL_OK) {
                break;
            }

            Status = AlAxiCanFd_Dev_SetTiming(&Handle->Dev, (AlAxiCanFd_Timing *)(Data));
            if (Status != AL_OK) {
                break;
            }

            Status = AlAxiCanFd_Dev_SetMode(&Handle->Dev, AXI_CANFD_MODE_NORMAL);
            if (Status != AL_OK) {
                break;
            }

            Status = AL_OK;

        case AXI_CANFD_IOCTL_SET_MODE:
            Status = AlAxiCanFd_Dev_SetMode(&Handle->Dev, *(AlAxiCanFd_ModeEnum *)Data);
            break;

        case AXI_CANFD_IOCTL_GET_TIMING:
            Status = AlAxiCanFd_Dev_GetTiming(&Handle->Dev, (AlAxiCanFd_Timing *)(Data));
            break;

        case AXI_CANFD_IOCTL_GET_MODE:
            Status = AlAxiCanFd_Dev_GetMode(&Handle->Dev, (AlAxiCanFd_ModeEnum *)Data);
            break;
        default:
            Status = AL_ERROR;
            break;
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->AxiCanFdLock);

    return Status;
}
