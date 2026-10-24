/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_canfd_dev.h"
#include "al_axi_canfd_ll.h"

/***************** Macros (Inline Functions) Definitions *********************/
#define DLC_MAX_VAL 0xFU
#define SWAP_ENDIAN_32(x) ((((x) & 0xFF) << 24) | (((x) & 0xFF00) << 8) | (((x) & 0xFF0000) >> 8) | (((x) & 0xFF000000) >> 24))

/************************** Variable Definitions *****************************/
extern AlAxiCanFd_HwConfigStruct AlAxiCanFd_HwConfig[AL_AXI_CANFD_NUM_INSTANCE];
static const AL_U8 DlcToLen[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 16, 20, 24, 32, 48, 64};

AlAxiCanFd_HwConfigStruct *AlAxiCanFd_Dev_LookupConfig(AL_U32 DevId)
{
    AL_U32 Index = 0;
    AlAxiCanFd_HwConfigStruct *HwConfig = AL_NULL;

    for (Index = 0; Index < AL_AXI_CANFD_NUM_INSTANCE; Index++) {
        if (AlAxiCanFd_HwConfig[Index].DeviceId == DevId) {
            HwConfig = &AlAxiCanFd_HwConfig[Index];
            break;
        }
    }

    return HwConfig;
}

AL_U32 AlAxiCanFd_Dev_RegisterEventCallBack(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_EventCallBack CallBack, AL_VOID *CallBackRef)
{
    if (Dev == AL_NULL || CallBack == AL_NULL) {
        return AL_ERROR;
    }

    Dev->EventCallBack = CallBack;
    Dev->EventCallBackRef = CallBackRef;

    return AL_OK;
}

AL_VOID AlAxiCanFd_Dev_RecvHandler(AL_VOID *Instance, AL_U32 IntrSta)
{
    AlAxiCanFd_DevStruct *Dev = (AlAxiCanFd_DevStruct *)Instance;

    AlAxiCanFd_EventStruct Event = {
        .EventId    = AXI_CANFD_EVENT_RXOK,
        .EventData  = 0,
    };

    if (Dev->EventCallBack) {
        Dev->EventCallBack(&Event, Dev->EventCallBackRef);
    }
}

AL_VOID AlAxiCanFd_Dev_SendHandler(AL_VOID *Instance, AL_U32 IntrSta)
{
    AlAxiCanFd_DevStruct *Dev = (AlAxiCanFd_DevStruct *)Instance;

    AlAxiCanFd_EventStruct Event = {
        .EventId    = AXI_CANFD_EVENT_TXOK,
        .EventData  = 0,
    };

    if (Dev->EventCallBack) {
        Dev->EventCallBack(&Event, Dev->EventCallBackRef);
    }
}

AL_VOID AlAxiCanFd_Dev_EventHandler(AL_VOID *Instance, AL_U32 IntrSta)
{
    AlAxiCanFd_DevStruct *Dev = (AlAxiCanFd_DevStruct *)Instance;
    AlAxiCanFd_EventStruct Event = {
        .EventId    = AXI_CANFD_EVENT_ARBLST,
        .EventData  = 0,
    };

    if (Dev->EventCallBack) {
        Dev->EventCallBack(&Event, Dev->EventCallBackRef);
    }
}

AL_VOID AlAxiCanFd_Dev_ErrorHandler(AL_VOID *Instance, AL_U32 IntrSta)
{
    AL_U32 ErrSta;
    AlAxiCanFd_DevStruct *Dev = (AlAxiCanFd_DevStruct *)Instance;
    AL_U64 BaseAddr = Dev->HwConfig.BaseAddress;

    ErrSta = AlAxiCanFd_ll_GetErrorStatus(BaseAddr);
    AlAxiCanFd_ll_ClearErrorStatus(BaseAddr, ErrSta);

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_CRCER_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: CRC error.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_FMER_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: Form error.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_STER_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: Stuff error.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_BERR_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: Bit error.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_ACKER_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: Ack error.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_F_CRCER_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: CRC Error in CAN FD Data Phase.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_F_FMER_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: Form Error in CAN FD Data Phase.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_F_STER_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: Stuff Error in CAN FD Data Phase.");
    }

    if (ErrSta & BIT(AXI_CANFD_ERR_STS_F_BERR_SHIFT)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AxiCanFd: Bit Error in CAN FD Data Phase.");
    }

    AlAxiCanFd_EventStruct Event = {
        .EventId    = AXI_CANFD_EVENT_ERROR,
        .EventData  = 0,
    };

    if (Dev->EventCallBack) {
        Dev->EventCallBack(&Event, Dev->EventCallBackRef);
    }
}

AL_VOID AlAxiCanFd_Dev_IntrHandler(AL_VOID *Instance)
{
    AL_U64 BaseAddr;
    AL_U32 IntrStatus;
    AL_U32 IntrEnables;
    AlAxiCanFd_DevStruct *Dev = (AlAxiCanFd_DevStruct *)Instance;

    BaseAddr = Dev->HwConfig.BaseAddress;
    IntrEnables = AlAxiCanFd_ll_GetIntrEnables(BaseAddr);
    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_INT_EN_OFFSET, 0);
    IntrStatus = IntrEnables & AlAxiCanFd_ll_GetIntrStatus(BaseAddr);

    if (IntrStatus &
        (BIT(AXI_CANFD_INT_STS_ARBLST_SHIFT) |
         BIT(AXI_CANFD_INT_STS_PEE_SHIFT) |
         BIT(AXI_CANFD_INT_STS_BSFRD_SHIFT) |
         BIT(AXI_CANFD_INT_STS_TSCNT_OFLW_SHIFT) |
         BIT(AXI_CANFD_INT_STS_RXFOFLW_SHIFT) |
         BIT(AXI_CANFD_INT_STS_BSOFF_SHIFT) |
         BIT(AXI_CANFD_INT_STS_SLP_SHIFT) |
         BIT(AXI_CANFD_INT_STS_WKUP_SHIFT) |
         BIT(AXI_CANFD_INT_STS_TXRRS_SHIFT) |
         BIT(AXI_CANFD_INT_STS_TXCRS_SHIFT) |
         BIT(AXI_CANFD_INT_STS_RXRBF_RXFOFLW_1_SHIFT) |
         BIT(AXI_CANFD_INT_STS_RXBOFLW_RXFWMFLL_1_SHIFT) |
         BIT(AXI_CANFD_INT_STS_RXMNF_SHIFT) |
         BIT(AXI_CANFD_INT_STS_TXEOFLW_SHIFT))) {
        AlAxiCanFd_Dev_EventHandler(Instance, IntrStatus);
    }

    if (IntrStatus & BIT(AXI_CANFD_INT_STS_ERROR_SHIFT)) {
        Dev->StaRcd.Err_Cnt++;
        AlAxiCanFd_Dev_ErrorHandler(Instance, IntrStatus);
    }

    if (IntrStatus &
        (BIT(AXI_CANFD_INT_STS_TXOK_SHIFT) |
         BIT(AXI_CANFD_INT_STS_TXEWMFLL_SHIFT))) {
        Dev->StaRcd.Tx_Cnt++;
        AlAxiCanFd_Dev_SendHandler(Instance, IntrStatus);
    }

    if (IntrStatus &
        (BIT(AXI_CANFD_INT_STS_RXOK_SHIFT) |
         BIT(AXI_CANFD_INT_STS_RXFWMFLL_SHIFT) |
         BIT(AXI_CANFD_INT_STS_RXRBF_RXFOFLW_1_SHIFT) |
         BIT(AXI_CANFD_INT_STS_RXBOFLW_RXFWMFLL_1_SHIFT))) {
        Dev->StaRcd.Rx_Cnt++;
        AlAxiCanFd_Dev_RecvHandler(Instance, IntrStatus);
    }

    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_INT_CLR_OFFSET, IntrStatus);
    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_INT_EN_OFFSET, IntrEnables);
}

AL_U32 AlAxiCanFd_Dev_GetMode(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_ModeEnum *Mode)
{
    AL_U32 RegVal;
    AL_U64 BaseAddr = Dev->HwConfig.BaseAddress;

    if (Dev == AL_NULL || Mode == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    RegVal = AlAxiCanFd_ll_GetStatus(BaseAddr) & AXI_CANFD_STS_MODE_MASK;

    switch (RegVal)
    {
        case BIT(AXI_CANFD_STS_CONFIG_SHIFT):
            *Mode = AXI_CANFD_MODE_CONFIG;
            break;
        case BIT(AXI_CANFD_STS_LBACK_SHIFT):
            *Mode = AXI_CANFD_MODE_LOOPBACK;
            break;
        case BIT(AXI_CANFD_STS_SLEEP_SHIFT):
            *Mode = AXI_CANFD_MODE_SLEEP;
            break;
        case BIT(AXI_CANFD_STS_NORMAL_SHIFT):
            *Mode = AXI_CANFD_MODE_NORMAL;
            break;
        case BIT(AXI_CANFD_STS_SNOOP_SHIFT):
            *Mode = AXI_CANFD_MODE_SNOOP;
            break;
        default:
            return AL_ERROR;
    }

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_SetMode(AlAxiCanFd_DevStruct *Dev, const AlAxiCanFd_ModeEnum Mode)
{
    AL_U32 RegVal;
    AL_U32 Status;
    AL_U64 BaseAddr = Dev->HwConfig.BaseAddress;

    if (Dev == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    RegVal = AlAxiCanFd_ll_GetStatus(BaseAddr) & BIT(AXI_CANFD_STS_BBSY_SHIFT);
    if (RegVal) {
        return AL_AXICANFD_ERR_BUSY;
    }

    AlAxiCanFd_ll_SetEnable(BaseAddr, AL_FALSE);
    RegVal = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_MODE_SEL_OFFSET) &
        ~AXI_CANFD_MODE_SEL_MODE_MASK;

    switch (Mode)
    {
        case AXI_CANFD_MODE_CONFIG:
            break;
        case AXI_CANFD_MODE_NORMAL:
            AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_MODE_SEL_OFFSET, RegVal);
            break;
        case AXI_CANFD_MODE_LOOPBACK:
            AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_MODE_SEL_OFFSET,
                RegVal | BIT(AXI_CANFD_MODE_SEL_LBACK_SHIFT));
            break;
        case AXI_CANFD_MODE_SLEEP:
            AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_MODE_SEL_OFFSET,
                RegVal | BIT(AXI_CANFD_MODE_SEL_SLEEP_SHIFT));
            break;
        case AXI_CANFD_MODE_SNOOP:
            AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_MODE_SEL_OFFSET,
                RegVal | BIT(AXI_CANFD_MODE_SEL_SNOOP_SHIFT));
            break;
        default:
            return AL_ERROR;
    }

    if (Mode != AXI_CANFD_MODE_CONFIG) {
        AlAxiCanFd_ll_SetEnable(BaseAddr, AL_TRUE);
    }

    while (Dev->CurMode != Mode) {
        Status = AlAxiCanFd_Dev_GetMode(Dev, &Dev->CurMode);
        if (Status != AL_OK) {
            return Status;
        }
    }

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_Init(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_HwConfigStruct *HwConfig,
    AlAxiCanFd_InitConfigStruct *InitConfig)
{
    AL_U32 Status;
    AL_U32 RxFilterNum;
    AL_U64 BaseAddr = HwConfig->BaseAddress;

    if (Dev == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    Dev->HwConfig = *HwConfig;

    if (InitConfig == AL_NULL) {
        Dev->InitConfig.IsDisBitRateSwitch = 0;
        Dev->InitConfig.IsDisAutoRetransmission = 0;
        Dev->InitConfig.IsDisProtocolExceptionEvent = 0;
        Dev->InitConfig.IsAutoBusRecovery = 0;
        Dev->InitConfig.InternalTimingOpt = 0;
    } else {
        Dev->InitConfig = *InitConfig;
    }

    AlAxiCanFd_ll_SwRst(BaseAddr);
    AlSys_UDelay(5);

    Status = AlAxiCanFd_Dev_SetMode(Dev, AXI_CANFD_MODE_CONFIG);
    if (Status != AL_OK) {
        return Status;
    }

    AlAxiCanFd_ll_SetBRSD(BaseAddr, Dev->InitConfig.IsDisBitRateSwitch);
    AlAxiCanFd_ll_SetDAR(BaseAddr, Dev->InitConfig.IsDisAutoRetransmission);
    AlAxiCanFd_ll_SetDPEE(BaseAddr, Dev->InitConfig.IsDisProtocolExceptionEvent);
    AlAxiCanFd_ll_SetABR(BaseAddr, Dev->InitConfig.IsAutoBusRecovery);
    AlAxiCanFd_ll_SetITO(BaseAddr, Dev->InitConfig.InternalTimingOpt);

    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_INT_EN_OFFSET,
        BIT(AXI_CANFD_INT_EN_ARBLST_SHIFT) |
        BIT(AXI_CANFD_INT_EN_TXOK_SHIFT) |
        BIT(AXI_CANFD_INT_EN_PEE_SHIFT) |
        BIT(AXI_CANFD_INT_EN_BSFRD_SHIFT) |
        BIT(AXI_CANFD_INT_EN_RXOK_SHIFT) |
        BIT(AXI_CANFD_INT_EN_TSCNT_OFLW_SHIFT) |
        BIT(AXI_CANFD_INT_EN_RXFOFLW_SHIFT) |
        BIT(AXI_CANFD_INT_EN_ERROR_SHIFT) |
        BIT(AXI_CANFD_INT_EN_BSOFF_SHIFT) |
        BIT(AXI_CANFD_INT_EN_SLP_SHIFT) |
        BIT(AXI_CANFD_INT_EN_WKUP_SHIFT) |
        // BIT(AXI_CANFD_INT_EN_RXFWMFLL_SHIFT) |
        BIT(AXI_CANFD_INT_EN_TXRRS_SHIFT) |
        BIT(AXI_CANFD_INT_EN_TXCRS_SHIFT) |
        BIT(AXI_CANFD_INT_EN_RXRBF_RXFOFLW_1_SHIFT) |
        BIT(AXI_CANFD_INT_EN_RXBOFLW_RXFWMFLL_1_SHIFT) |
        BIT(AXI_CANFD_INT_EN_RXMNF_SHIFT) |
        BIT(AXI_CANFD_INT_EN_TXEOFLW_SHIFT) |
        BIT(AXI_CANFD_INT_EN_TXEWMFLL_SHIFT));

    RxFilterNum = Dev->HwConfig.RxMode == 0 ? 32 : Dev->HwConfig.RxBufNum;
    for (AL_U32 Index = 0; Index < RxFilterNum; Index++) {
        AlAxiCanFd_Dev_SetRxFilter(Dev, Index,
            &(AlAxiCanFd_RxFilter){
                .MaskReg = 0x00000000,
                .IdReg = 0x00000000,
                .IsEnable = AL_FALSE,
            });
    }

    Dev->IsTxIntrEn = 0;
    Dev->IsRxIntrEn = 0;
    Dev->State = AL_AXI_CANFD_STATE_READY;

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_SetIntrOrPollingMode(AlAxiCanFd_DevStruct *Dev, AL_U32 IsTxIntrEn, AL_U32 IsRxIntrEn)
{
    AL_U64 BaseAddr;

    if (Dev == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    BaseAddr = Dev->HwConfig.BaseAddress;
    if (IsTxIntrEn) {
        AlAxiCanFd_ll_SetIntrEnable(BaseAddr, AXI_CANFD_INT_EN_TXOK_SHIFT, 1);
        Dev->IsTxIntrEn = 1;
    } else {
        AlAxiCanFd_ll_SetIntrEnable(BaseAddr, AXI_CANFD_INT_EN_TXOK_SHIFT, 0);
        Dev->IsTxIntrEn = 0;
    }

    if (IsRxIntrEn) {
        AlAxiCanFd_ll_SetIntrEnable(BaseAddr, AXI_CANFD_INT_EN_RXOK_SHIFT, 1);
        Dev->IsRxIntrEn = 1;
    } else {
        AlAxiCanFd_ll_SetIntrEnable(BaseAddr, AXI_CANFD_INT_EN_RXOK_SHIFT, 0);
        Dev->IsRxIntrEn = 0;
    }

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_SetTiming(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_Timing *Timing)
{
    AL_U64 BaseAddr;

    if (Dev == AL_NULL || Timing == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    BaseAddr = Dev->HwConfig.BaseAddress;

    AlAxiCanFd_ll_SetArbitrationPrescaler(BaseAddr, Timing->ArbiPrescaler);
    AlAxiCanFd_ll_SetArbitrationTiming(BaseAddr, Timing->ArbiTS1, Timing->ArbiTS2, Timing->ArbiSJW);
    AlAxiCanFd_ll_SetDataPrescaler(BaseAddr, Timing->DataPrescaler);
    AlAxiCanFd_ll_SetDataTiming(BaseAddr, Timing->DataTS1, Timing->DataTS2, Timing->DataSJW);
    AlAxiCanFd_ll_SetTxDlyCompEnable(BaseAddr, Timing->IsTdcEn);
    AlAxiCanFd_ll_SetTxDlyCompOffset(BaseAddr, Timing->TdcOffset);

    Dev->Timing = *Timing;
    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_GetTiming(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_Timing *Timing)
{
    if (Dev == AL_NULL || Timing == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    *Timing = Dev->Timing;

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_SetRxFilter(AlAxiCanFd_DevStruct *Dev, AL_U32 Index, AlAxiCanFd_RxFilter *RxFilter)
{
    AL_U64 BaseAddr;
    AL_U32 RegVal;

    if (Dev == AL_NULL || RxFilter == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    BaseAddr = Dev->HwConfig.BaseAddress;

    RegVal = AlAxiCanFd_ll_GetStatus(BaseAddr) & BIT(AXI_CANFD_STS_BBSY_SHIFT);
    if (RegVal) {
        return AL_AXICANFD_ERR_BUSY;
    }

    if (Dev->HwConfig.RxMode == AL_AXI_CANFD_SEQUENTIAL) {
        if (Index >= 32) {
            return AL_AXICANFD_ERR_ILLEGAL_PARAM;
        }
        AlAxiCanFd_ll_SetAcptFilterEn(BaseAddr, Index, 0U);
        AlAxiCanFd_ll_SetAfMaskReg(BaseAddr, Index, RxFilter->MaskReg);
        AlAxiCanFd_ll_SetAfIdReg(BaseAddr, Index, RxFilter->IdReg);
        AlAxiCanFd_ll_SetAcptFilterEn(BaseAddr, Index, RxFilter->IsEnable);
    } else {
        if (Index >= Dev->HwConfig.RxBufNum) {
            return AL_AXICANFD_ERR_ILLEGAL_PARAM;
        }
        AlAxiCanFd_ll_SetMailboxEn(BaseAddr, Index, 0U);
        AlAxiCanFd_ll_SetMailboxMaskReg(BaseAddr, Index, RxFilter->MaskReg);
        AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_RB_ID_OFFSET(0, Index), RxFilter->IdReg);
        AlAxiCanFd_ll_SetMailboxEn(BaseAddr, Index, RxFilter->IsEnable);
    }

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_GetFreeTxBuf(AlAxiCanFd_DevStruct *Dev, AL_U32 *TxBufIndex)
{
    AL_U64 BaseAddr = Dev->HwConfig.BaseAddress;
    AL_U32 Reg = 0;
    AL_U32 Index = 0;

    if (Dev == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    Reg = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_TBRR_OFFSET);
    for (Index = 0; Index < Dev->HwConfig.TxBufNum; Index++) {
        if ((Reg & BIT(Index)) == 0) {
            *TxBufIndex = Index;
            return AL_OK;
        }
    }

    return AL_AXICANFD_ERR_BUSY;
}

AL_U32 AlAxiCanFd_Dev_DlcToLength(AL_U32 Dlc)
{
    if (Dlc > DLC_MAX_VAL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    return DlcToLen[Dlc];
}

AL_U32 AlAxiCanFd_Dev_RecvTxEvent(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_TxEventStruct *TxEvent)
{
    AL_U32 FillLevel;
    AL_U32 ReadIdx;
    AL_U64 BaseAddr = Dev->HwConfig.BaseAddress;

    if (Dev == AL_NULL || TxEvent == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    if (!(Dev->State & AL_AXI_CANFD_STATE_READY)) {
        return AL_AXICANFD_ERR_NOT_READY;
    }

    if (Dev->State & AL_AXI_CANFD_STATE_RECV_TX_EVENT_BUSY) {
        return AL_AXICANFD_ERR_BUSY;
    }


    FillLevel = AlAxiCanFd_ll_GetTxEventFifoLevel(BaseAddr);
    ReadIdx = AlAxiCanFd_ll_GetTxEventReadIndex(BaseAddr);

    if (FillLevel == 0U) {
        return AL_AXICANFD_NO_DATA;
    }

    TxEvent->IdRegVal = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_TXE_FIFO_TB_ID_OFFSET(ReadIdx));
    TxEvent->DlcRegVal = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_TXE_FIFO_TB_DLC_OFFSET(ReadIdx));

    AlAxiCanFd_ll_TxEventIncrIdx(BaseAddr);

    Dev->State &= ~AL_AXI_CANFD_STATE_RECV_TX_EVENT_BUSY;

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_SendFrame(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_TxMsgStruct *TxMsg, AL_U32 BufIdx)
{
    AL_U32 Index;
    AL_U32 RemLen;
    AL_U32 TempData = 0U;
    AL_U32 DataByteLen;
    AL_U32 IsCanFdFrame = AL_FALSE;
    AL_U64 BaseAddr = Dev->HwConfig.BaseAddress;

    if (Dev == AL_NULL || TxMsg == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    if (!(Dev->State & AL_AXI_CANFD_STATE_READY)) {
        return AL_AXICANFD_ERR_NOT_READY;
    }

    if (Dev->State & AL_AXI_CANFD_STATE_SEND_BUSY) {
        return AL_AXICANFD_ERR_BUSY;
    }

    Dev->State |= AL_AXI_CANFD_STATE_SEND_BUSY;

    if (TxMsg->DlcRegVal & (1U << AXI_CANFD_TB_DLC_EDL_FDF_SHIFT)) {
        IsCanFdFrame = AL_TRUE;
    }

    DataByteLen = AlAxiCanFd_Dev_DlcToLength(TxMsg->DlcRegVal >> AXI_CANFD_TB_DLC_DLC_SHIFT);
    if (!IsCanFdFrame && (DataByteLen > 8)) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_TB_ID_OFFSET(BufIdx), TxMsg->IdRegVal);
    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_TB_DLC_OFFSET(BufIdx), TxMsg->DlcRegVal);
    for (Index = 0; Index < (DataByteLen & 0xFFFFFFFCU); Index += 4) {
        AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_TB_DW0_OFFSET(BufIdx) + Index,
            SWAP_ENDIAN_32(*(AL_U32 *)(&(TxMsg->Data[Index]))));
    }
    RemLen = DataByteLen & 0x3U;
    if (RemLen) {
        for (; RemLen; RemLen--, Index++) {
            TempData = (TempData << 8) | (AL_U32)TxMsg->Data[Index];
        }
        TempData <<= (4 - (DataByteLen & 0x3)) * 8;
        AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_TB_DW0_OFFSET(BufIdx) + (Index & ~0x3U),
            TempData);
    }

    AlAxiCanFd_ll_SetTxBufRdyReq(BaseAddr, BufIdx);

    Dev->State &= ~AL_AXI_CANFD_STATE_SEND_BUSY;

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_GetFullRxBufIdx(AlAxiCanFd_DevStruct *Dev, AL_U32 *FifoNo, AL_U32 *RxIndex)
{
    AL_U32 RegVal;
    AL_U32 Csb;
    AL_U32 Status = AL_AXICANFD_NO_DATA;
    AL_U64 BaseAddr;

    if (Dev == AL_NULL || FifoNo == AL_NULL || RxIndex == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    *FifoNo = 0;
    BaseAddr = Dev->HwConfig.BaseAddress;
    if (Dev->HwConfig.RxMode == AL_AXI_CANFD_SEQUENTIAL) {
        RegVal = AlAxiCanFd_ll_GetRxFifoStatus(BaseAddr);

        if (RegVal & AXI_CANFD_RXF_STS_FL_MASK) {
            *RxIndex = RegVal & AXI_CANFD_RXF_STS_RI_MASK;
            Status = AL_OK;
        }

        if (Dev->HwConfig.IsFifo1En) {
            if (RegVal & AXI_CANFD_RXF_STS_FL_1_MASK) {
                *RxIndex = (RegVal & AXI_CANFD_RXF_STS_RI_1_MASK) >> AXI_CANFD_RXF_STS_RI_1_SHIFT;
                *FifoNo = 1;
                Status = AL_OK;
            }
        }
    } else {
        RegVal = AlAxiCanFd_ll_GetIntrStatus(BaseAddr);
        *RxIndex = (RegVal & AXI_CANFD_INT_STS_RXLRM_BI_MASK) >> AXI_CANFD_INT_STS_RXLRM_BI_SHIFT;

        RegVal = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_RXBC_STS0_OFFSET + (*RxIndex / 16) * 4);
        Csb = (RegVal >> ((*RxIndex % 16) + AXI_CANFD_RXBC_STS0_CSB_SHIFT)) & 0x1U;
        if (!Csb) {
            Status = AL_AXICANFD_NO_DATA;
        } else {
            Status = AL_OK;
        }
    }

    return Status;
}

AL_U32 AlAxiCanFd_Dev_RecvFrameSequential(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_RxMsgStruct *RxMsg, AL_U32 FifoNo, AL_U32 RxIndex)
{
    AL_U32 RegVal;
    AL_U32 DataByteLen;
    AL_U32 Index;
    AL_U64 BaseAddr;

    if (Dev == AL_NULL || RxMsg == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    BaseAddr = Dev->HwConfig.BaseAddress;

    RxMsg->IdRegVal.Val = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_RB_ID_OFFSET(FifoNo, RxIndex));
    RxMsg->DlcRegVal.Val = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_RB_DLC_OFFSET(FifoNo, RxIndex));
    DataByteLen = AlAxiCanFd_Dev_DlcToLength(RxMsg->DlcRegVal.Dlc);

    for (Index = 0; Index < DataByteLen; Index += 4U) {
        *(AL_U32 *)(&RxMsg->Data[Index]) =
            SWAP_ENDIAN_32(AlAxiCanFd_ll_ReadReg(BaseAddr,
                AXI_CANFD_RB_DW0_OFFSET(FifoNo, RxIndex) + Index));
    }

    RegVal = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_RXF_STS_OFFSET);
    RegVal |= (1U << (FifoNo == 0 ? AXI_CANFD_RXF_STS_IRI_SHIFT : AXI_CANFD_RXF_STS_IRI_1_SHIFT));
    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_RXF_STS_OFFSET, RegVal);

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_RecvFrameMailbox(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_RxMsgStruct *RxMsg, AL_U32 RxIndex)
{
    AL_U32 RegVal;
    AL_U32 DataByteLen;
    AL_U32 Index;
    AL_U64 BaseAddr;

    if (Dev == AL_NULL || RxMsg == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    BaseAddr = Dev->HwConfig.BaseAddress;

    RxMsg->IdRegVal.Val = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_RB_ID_OFFSET(0, RxIndex));
    RxMsg->DlcRegVal.Val = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_RB_DLC_OFFSET(0, RxIndex));
    DataByteLen = AlAxiCanFd_Dev_DlcToLength(RxMsg->DlcRegVal.Dlc);

    for (Index = 0; Index < DataByteLen; Index += 4U) {
        *(AL_U32 *)(&RxMsg->Data[Index]) =
            SWAP_ENDIAN_32(AlAxiCanFd_ll_ReadReg(BaseAddr,
                AXI_CANFD_RB_DW0_OFFSET(0, RxIndex) + Index));
    }

    RegVal = AlAxiCanFd_ll_ReadReg(BaseAddr, AXI_CANFD_RXBC_STS0_OFFSET + (RxIndex / 16) * 4);
    RegVal = (RegVal & 0xFFFFU) | BIT(((RxIndex % 16) + AXI_CANFD_RXBC_STS0_CSB_SHIFT));
    AlAxiCanFd_ll_WriteReg(BaseAddr, AXI_CANFD_RXBC_STS0_OFFSET + (RxIndex / 16) * 4, RegVal);

    return AL_OK;
}

AL_U32 AlAxiCanFd_Dev_RecvFrame(AlAxiCanFd_DevStruct *Dev, AlAxiCanFd_RxMsgStruct *RxMsg, AL_U32 FifoNo, AL_U32 RxIndex)
{
    AL_U32 Status;

    if (Dev == AL_NULL || RxMsg == AL_NULL) {
        return AL_AXICANFD_ERR_ILLEGAL_PARAM;
    }

    if (!(Dev->State & AL_AXI_CANFD_STATE_READY)) {
        return AL_AXICANFD_ERR_NOT_READY;
    }

    if (Dev->State & AL_AXI_CANFD_STATE_RECV_BUSY) {
        return AL_AXICANFD_ERR_BUSY;
    }

    Dev->State |= AL_AXI_CANFD_STATE_RECV_BUSY;
    if (Dev->HwConfig.RxMode == AL_AXI_CANFD_SEQUENTIAL) {
        Status = AlAxiCanFd_Dev_RecvFrameSequential(Dev, RxMsg, FifoNo, RxIndex);
    } else {
        Status = AlAxiCanFd_Dev_RecvFrameMailbox(Dev, RxMsg, RxIndex);
    }

    Dev->State &= ~AL_AXI_CANFD_STATE_RECV_BUSY;
    return Status;
}

