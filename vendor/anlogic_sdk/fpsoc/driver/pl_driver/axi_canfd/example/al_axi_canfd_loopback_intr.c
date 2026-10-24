/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include <stdlib.h>
#include "al_axi_canfd_hal.h"

/***************** Macros (Inline Functions) Definitions *********************/
#define TEST_ARBI_BAUDRATE   1000000
#define TEST_ARBI_SJW        1
#define TEST_ARBI_TS1        5
#define TEST_ARBI_TS2        2
#define TEST_ARBI_BIT_WIDTH  (TEST_ARBI_TS1 + TEST_ARBI_TS2 + TEST_ARBI_SJW)
#define TEST_DATA_BAUDRATE   8000000
#define TEST_DATA_SJW        1
#define TEST_DATA_TS1        2
#define TEST_DATA_TS2        2
#define TEST_DATA_BIT_WIDTH  (TEST_DATA_TS1 + TEST_DATA_TS2 + TEST_DATA_SJW)

#define TEST_FRAME_NUM       100
#define TIMEOUT_VAL          10000


#define RECV_IDE_BIT_SHIFT   19

typedef struct {
    AlAxiCanFd_HalStruct *Handle;
    AlAxiCanFd_RxMsgStruct *RxMsg;
    AL_U32 RxMsgIdx;
} CallbackRefType;

/* Only for example test */
typedef struct {
    AL_U32 IdVal;
    int IdType;
} TestCanFdId;


volatile static AL_U32 ReceiveDone = 0;
AlAxiCanFd_RxMsgStruct RxMsg[TEST_FRAME_NUM] = { 0 };
AlAxiCanFd_TxMsgStruct TxMsg;
static AL_U32 RxMsgIdx = 0;


static AL_VOID CallbackForExample(AlAxiCanFd_EventStruct *Event, void *CallBackRef)
{
    AlAxiCanFd_HalStruct *Handle = (AlAxiCanFd_HalStruct *)CallBackRef;
    switch (Event->EventId)
    {
        case AXI_CANFD_EVENT_TXOK:
            /**
             * Add code for transmit here.
            */
            AlOsal_Mb_Send(&Handle->TxEventQueue, Event);
            break;
        case AXI_CANFD_EVENT_RXOK:
            /**
             * Add code for receive here.
            */
            AlAxiCanFd_Hal_RecvFrame(Handle, &RxMsg[RxMsgIdx], 0);
            RxMsgIdx++;
            if (RxMsgIdx == TEST_FRAME_NUM) {
                ReceiveDone = 1;
            }
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

AL_VOID GenerateRandomId(TestCanFdId *CanId) {
    CanId->IdType = rand() % 2;

    if (CanId->IdType == 0) {
        CanId->IdVal = rand() % (0x7FF + 1);
    } else {
        unsigned int part1 = rand();
        unsigned int part2 = rand();
        unsigned int part3 = rand();
        CanId->IdVal = (part1 << 18) | (part2 << 3) | (part3 & 0x07);
        CanId->IdVal &= 0x1FFFFFFF;
    }
}

AL_U32 main(void)
{
    AL_U32 DevId = 0;
    AL_U32 Status = 0;
    AL_U32 Index;
    AL_U32 ByteIndex;
    AL_U32 ArbiDiv;
    AL_U32 DataDiv;
    AlAxiCanFd_HalStruct *Handle;
    AL_U32 TxData[] = { 0x12345678, 0x9ABCDEF0 };
    TestCanFdId RandId[TEST_FRAME_NUM];
    AlAxiCanFd_Timing Timing;
    CallbackRefType CallbackRef = {Handle, RxMsg, 0};

    AL_LOG(AL_LOG_LEVEL_INFO, "Start al-axi-canfd loopback intr example.\r\n");

    Soc_PsPlInit();

    for (Index = 0; Index < TEST_FRAME_NUM; Index++) {
        GenerateRandomId(&RandId[Index]);
    }

    Status = AlAxiCanFd_Hal_Init(&Handle, DevId, AL_NULL, CallbackForExample);
    if (Status != AL_OK) {
        return AL_ERROR;
    }
    AlAxiCanFd_Hal_SetIntrFlag(Handle, 1, 1);
    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    Status = AlAxiCanFd_Hal_SetRxFilter(Handle, 0, &(AlAxiCanFd_RxFilter){
        .IsEnable = 1,
        .IdReg = AXI_CANFD_CREATE_FILTER(0x000, 0, 0, 0, 0),
        .MaskReg = AXI_CANFD_CREATE_FILTER(0x000, 0, 0, 0, 0),
    }, TIMEOUT_VAL);

    ArbiDiv = Handle->Dev.HwConfig.InputClk / TEST_ARBI_BAUDRATE / TEST_ARBI_BIT_WIDTH;
    DataDiv = Handle->Dev.HwConfig.InputClk / TEST_DATA_BAUDRATE / TEST_DATA_BIT_WIDTH;
    Timing = AXI_CANFD_CREATE_TIMING(ArbiDiv, TEST_ARBI_TS1, TEST_ARBI_TS2, TEST_ARBI_SJW,
        DataDiv, TEST_DATA_TS1, TEST_DATA_TS2, TEST_DATA_SJW, 1, 1);
    AlAxiCanFd_Hal_IoCtl(Handle, AXI_CANFD_IOCTL_SET_TIMING, &Timing, TIMEOUT_VAL);

    /* Set loopback mode */
    AlAxiCanFd_Hal_IoCtl(Handle, AXI_CANFD_IOCTL_SET_MODE, &(int){AXI_CANFD_MODE_LOOPBACK}, TIMEOUT_VAL);

    for (Index = 0; Index < TEST_FRAME_NUM; Index++) {
        TxMsg = AXI_CANFD_CREATE_TXMSG(RandId[Index].IdVal, 0, RandId[Index].IdType, 0, 7, 1, 1, 0, 0, TxData);
        Status = AlAxiCanFd_Hal_SendFrame(Handle, &TxMsg, TIMEOUT_VAL);
        if (Status != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Send frame failed: 0x%x.\r\n", Status);
            return Status;
        }
    }

    while (ReceiveDone == 0);

    for (Index = 0; Index < TEST_FRAME_NUM; Index++) {
        AL_U32 TmpId = RxMsg[Index].IdRegVal.Ide ? ((RxMsg[Index].IdRegVal.Id << 18) | RxMsg[Index].IdRegVal.ExtId) :
                        RxMsg[Index].IdRegVal.Id;
        if (RxMsg[Index].IdRegVal.Val & (1 << RECV_IDE_BIT_SHIFT)) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Rx %d: id=0x%08x\r\n", Index, TmpId);
        } else {
            AL_LOG(AL_LOG_LEVEL_INFO, "Rx %d: id=0x%03x\r\n", Index, TmpId);
        }

        for (ByteIndex = 0; ByteIndex < AXI_CANFD_DLC_TO_LEN(7); ByteIndex++) {
            if (RxMsg[Index].Data[ByteIndex] != TxMsg.Data[ByteIndex]) {
                AL_LOG(AL_LOG_LEVEL_ERROR, "Data error\r\n");
                return Status;
            }
        }
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Test success.\r\n");

    return 0;
}
