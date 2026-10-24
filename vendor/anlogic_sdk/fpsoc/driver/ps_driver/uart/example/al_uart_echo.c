/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_uart_blocked.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   uart echo example
 * @example al_uart_echo.c
 */

#include "al_uart_hal.h"

static AL_UART_HalStruct AlUartHandle[AL_UART_NUM_INSTANCE];
#define AL_UART_DEVID 1

static AL_UART_InitStruct UART_InitStruct = {
        .BaudRate           = 115200,
        .Parity             = AL_UART_NO_PARITY,
        .WordLength         = AL_UART_CHAR_8BITS,
        .StopBits           = AL_UART_STOP_1BIT,
        .HwFlowCtl          = AL_FALSE,
        .CharTimeoutEnable  = AL_TRUE
    };

static AL_VOID AlUart_Dev_RecvDataHandler(AL_UART_DevStruct *Uart, AL_BOOL CharTimeoutIntr)
{
    while ((AlUart_ll_IsRxDataReady(Uart->BaseAddr) == AL_TRUE)) {
        Uart->RecvBuffer.BufferPtr[Uart->RecvBuffer.HandledCnt] = (AL_U8)AlUart_ll_RecvByte(Uart->BaseAddr);
        Uart->RecvBuffer.HandledCnt ++;
        if (Uart->RecvBuffer.HandledCnt >= Uart->RecvBuffer.RequestedCnt) {
            Uart->RecvBuffer.HandledCnt = 0;
        }

        AlUart_ll_EnableThreIntr(Uart->BaseAddr, AL_TRUE);
        AlUart_ll_SetTxIntr(Uart->BaseAddr, AL_FUNC_ENABLE);
    }
}

static AL_VOID AlUart_Dev_SendDataHandler(AL_UART_DevStruct *Uart)
{
    if (Uart->SendBuffer.HandledCnt == Uart->RecvBuffer.HandledCnt) {
        AlUart_Dev_StopSend(Uart);
    } else {
        while (!(AlUart_Dev_IsTxFifoFull(Uart)) &&
            (Uart->SendBuffer.HandledCnt != Uart->RecvBuffer.HandledCnt)) {
            AlUart_ll_SendByte(Uart->BaseAddr, Uart->RecvBuffer.BufferPtr[Uart->SendBuffer.HandledCnt]);
            Uart->SendBuffer.HandledCnt ++;
            if (Uart->SendBuffer.HandledCnt >= Uart->RecvBuffer.RequestedCnt) {
                Uart->SendBuffer.HandledCnt = 0;
            }
        }
    }
}

#define AL_UART_INTR_MODEM_STATUS(Status)           (Status == AL_UART_MODEM_STATUS)
#define AL_UART_NO_INTER_PEDING(Status)             (Status == AL_UART_NO_INTERRUPT_PENDING)
#define AL_UART_INTR_THRE_EMPTY(Status)             (Status == AL_UART_THR_EMPTY)
#define AL_UART_INTR_RECV_AVAIL(Status)             (Status == AL_UART_RECEIVED_DATA_AVAILABLE)
#define AL_UART_INTR_RECV_LINE_STATUS(Status)       (Status == AL_UART_RECEIVER_LINE_STATUS)
#define AL_UART_INTR_BUSY_DETECT(Status)            (Status == AL_UART_BUSY_DETECT)
#define AL_UART_INTR_CHAR_RECEV_TIMEOUT(Status)     (Status == AL_UART_CHARACTER_TIMEOUT)

AL_VOID AlUart_Dev_IntrEchoHandler(AL_VOID *Instance)
{
    AL_UART_DevStruct *Uart = (AL_UART_DevStruct *)Instance;
    AL_UART_IntrEnum IntrStatus = AlUart_ll_GetIntrStatus(Uart->BaseAddr);

    if (AL_UART_INTR_RECV_AVAIL(IntrStatus) || AL_UART_INTR_CHAR_RECEV_TIMEOUT(IntrStatus)) {
        AlUart_Dev_RecvDataHandler(Uart, AL_UART_INTR_CHAR_RECEV_TIMEOUT(IntrStatus));
    } else if (AL_UART_INTR_THRE_EMPTY(IntrStatus)) {
        AlUart_Dev_SendDataHandler(Uart);
    }
}


AL_S32 AlUart_Hal_InitEcho(AL_UART_HalStruct **Handle, AL_U32 DevId,
                       AL_UART_InitStruct *InitConfig, AL_Uart_EventCallBack Callback)
{
    AL_S32 Ret = AL_OK;
    AL_UART_HwConfigStruct *HwConfig = NULL;

    AL_ASSERT((Handle != AL_NULL), AL_UART_ERR_ILLEGAL_PARAM);

    HwConfig = AlUart_Dev_LookupConfig(DevId);
    if (HwConfig != AL_NULL) {
        *Handle = &AlUartHandle[DevId];
    } else {
        return AL_UART_ERR_ILLEGAL_PARAM;
    }

    Ret = AlUart_Dev_Init(&(*Handle)->Dev, DevId, InitConfig);
    if (Ret != AL_OK) {
        return Ret;
    }

    (AL_VOID)AlIntr_RegHandler((*Handle)->Dev.IntrNum, AL_NULL, AlUart_Dev_IntrEchoHandler, &(*Handle)->Dev);


    return Ret;
}


#define BUF_SIZE (2*1024)

static AL_S32 AlUart_Test_Echo(AL_VOID)
{
    AL_UART_HalStruct *UartHandle;

    AL_U8 *Data = (AL_U8 *)malloc(BUF_SIZE);
    memset(Data, 0, (sizeof(AL_U8) * BUF_SIZE));

    AL_S32 Ret = AlUart_Hal_InitEcho(&UartHandle, AL_UART_DEVID, &UART_InitStruct, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Uart Hal Init error:0x%x\r\n", Ret);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AL_LOG(AL_LOG_LEVEL_INFO, "Send less than %d Bytes data and will show back\r\n", BUF_SIZE);

    AlUart_Hal_RecvData(UartHandle, Data, BUF_SIZE);

    while (1) {

    }
}

AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "Uart blocked test\r\n");

    Ret = AlUart_Test_Echo();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Uart blocked test failed\r\n");
        return Ret;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");
    AL_LOG(AL_LOG_LEVEL_INFO, "Uart blocked test success\r\n");
    return Ret;
}