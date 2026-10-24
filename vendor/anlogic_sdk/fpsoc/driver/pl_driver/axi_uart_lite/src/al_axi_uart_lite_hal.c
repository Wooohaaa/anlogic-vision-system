/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_uart_lite_hal.h"
#include "al_log.h"

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/

/************************** Variable Definitions *****************************/

static Al_AxiUartLite_HalStruct AlAxiUartLiteHandle[AL_AXI_UART_LITE_NUM_INSTANCE];


AlLog_Ops Allog_UartLite =
{
    .InitConfig   =  AL_NULL,
    .DevId        = (LOG_DEV - AL_LOG_UARTLITE0),
    .AlLog_Init   = (AL_S32 (*)(AL_VOID **, AL_U32, AL_VOID*, AL_VOID*))AlAxiUartLite_Hal_LogInit,
    .AlLog_Write  = (AL_S32 (*)(AL_VOID*, const void*, AL_U32))AlAxiUartLite_Dev_SendDataPolling,
    .AlLog_Read   = (AL_S32 (*)(AL_VOID*, AL_U8 *, AL_U32))AlAxiUartLite_Dev_RecvDataPolling,
    .AlLog_DeInit = AL_NULL
};


/**
 * This function is called when a UART event occurs. It updates the status and logs the event.
 *
 * @param UartEvent The UART event structure.
 * @param CallbackRef Pointer to the callback reference.
 *
 * @return None.
 */
static AL_VOID AlAxiUartLite_Hal_DefEventHandler(Al_AxiUartLite_EventStruct UartEvent, AL_VOID *CallbackRef)
{
    Al_AxiUartLite_HalStruct *Handle = (Al_AxiUartLite_HalStruct *)CallbackRef;
    switch (UartEvent.Events)
    {
    case AL_AXI_UART_LITE_EVENT_SEND_DONE:
        AlOsal_Mb_Send(&Handle->TxEventQueue, &UartEvent);
        break;

    case AL_AXI_UART_LITE_EVENT_RECEIVE_DONE:
        AlOsal_Mb_Send(&Handle->RxEventQueue, &UartEvent);
        break;

    default:
        break;
    }
}

/**
 * This function initializes the UART Lite HAL with the specified device ID and event callback.
 *
 * @param Handle Pointer to the handle structure.
 * @param DevId The ID of the UART device.
 * @param Callback Pointer to the event callback function.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUartLite_Hal_Init(Al_AxiUartLite_HalStruct **Handle, AL_U32 DevId, Al_AxiUartLite_EventCallBack Callback)
{
    AL_S32 Ret = AL_OK;
    AlAxiUartLite_HwConfigStruct *HwConfig = NULL;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

#if defined(__riscv)
    AL_INTR_AttrStrct AxiUartLiteAttr = {
        .TrigMode   =  POSTIVE_EDGE_TRIGGER,
        .Priority   =  0,
        .VectorMode =  NON_VECTOR_INTERRUPT,
    };
#else
    AL_INTR_AttrStrct AxiUartLiteAttr = {
        .TrigMode   = POSTIVE_EDGE_TRIGGER,
        .Priority   = 137,
    };
#endif

    HwConfig = AlAxiUartLite_Dev_LookupConfig(DevId);
    if (HwConfig != AL_NULL) {
        *Handle = &AlAxiUartLiteHandle[DevId];
    } else {
        return AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM;
    }

    Ret = AlAxiUartLite_Dev_Init(&(*Handle)->Dev, DevId);
    if (Ret != AL_OK) {
        return Ret;
    }

    if(Callback == AL_NULL) {
        Ret = AlAxiUartLite_Dev_RegisterEventCallBack(&(*Handle)->Dev, AlAxiUartLite_Hal_DefEventHandler, (AL_VOID *)*Handle);
    } else {
        Ret = AlAxiUartLite_Dev_RegisterEventCallBack(&(*Handle)->Dev, Callback, (AL_VOID *)*Handle);
    }
    if (Ret != AL_OK) {
        return Ret;
    }

    (AL_VOID)AlIntr_RegHandler((*Handle)->Dev.HwConfig.IntrId, &AxiUartLiteAttr, AlAxiUartLite_Dev_IntrHandler, &(*Handle)->Dev);

    Ret = AlOsal_Lock_Init(&(*Handle)->TxLock, "Uart-TxLock");
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlOsal_Lock_Init(&(*Handle)->RxLock, "Uart-RxLock");
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlOsal_Mb_Init(&(*Handle)->TxEventQueue, "UART_TXDONE");
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlOsal_Mb_Init(&(*Handle)->RxEventQueue, "UART_RXDONE");
    if (Ret != AL_OK) {
        return Ret;
    }

    return Ret;
}

/**
 * This function sends data by polling the UART device until all data is sent or an error occurs.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the data buffer to be sent.
 * @param Size The size of the data buffer.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUartLite_Hal_SendDataPolling(Al_AxiUartLite_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Ret = AlAxiUartLite_Dev_SendDataPolling(&Handle->Dev, Data, Size);

    return Ret;
}

/**
 * This function receives data from the UART Lite device using a polling method.
 * It checks the validity of the handle and then calls the device-specific
 * receive function.
 *
 * @param Handle Pointer to the UART Lite handle structure.
 * @param Data Pointer to the buffer where received data will be stored.
 * @param Size Number of bytes to receive.
 *
 * @return AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUartLite_Hal_RecvDataPolling(Al_AxiUartLite_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Ret = AlAxiUartLite_Dev_RecvDataPolling(&Handle->Dev, Data, Size);

    return Ret;
}

/**
 * This function sends data using UART Lite in blocking mode.
 *
 * @param Handle Pointer to the UART Lite HAL structure.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 * @param Timeout The timeout value for the transfer.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUartLite_Hal_SendDataBlock(Al_AxiUartLite_HalStruct *Handle, AL_U8 *Data, AL_U32 Size, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    Al_AxiUartLite_EventStruct UartEvent = {0};
    AL_U32 CfgReg = 0, BaudRate = 0;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->TxLock, Timeout);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUartLite_Dev_SendData(&Handle->Dev, Data, Size);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);
        return Ret;
    }
    Ret = AlOsal_Mb_Receive(&Handle->TxEventQueue, &UartEvent, Timeout);
    if (Ret != AL_OK) {
        BaudRate = (AlAxiUartLite_GetStatus(Handle->Dev.HwConfig.BaseAddress) & 0xF00) >> AL_AXI_UART_LITE_SR_BAUDRATE_SHIFT;
        CfgReg = BaudRate << AL_AXI_UART_LITE_CR_BAUDRATE_SHIFT;
        AlAxiUartLite_SetCfgReg(Handle->Dev.HwConfig.BaseAddress, CfgReg);
        (AL_VOID)AlOsal_Mb_Receive(&Handle->TxEventQueue, &UartEvent, AL_WAITING_NO);
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);

    if (Ret == AL_OK && (UartEvent.Events == AL_AXI_UART_LITE_EVENT_SEND_DONE))
        return AL_OK;
    else
        return (Ret != AL_OK) ? Ret : AL_AXI_UART_LITE_EVENTS_TO_ERRS(UartEvent.Events);

    return Ret;
}

/**
 * This function receives data using UART Lite in blocking mode.
 *
 * @param Handle Pointer to the UART Lite HAL structure.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 * @param Timeout The timeout value for the transfer.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUartLite_Hal_RecvDataBlock(Al_AxiUartLite_HalStruct *Handle, AL_U8 *Data, AL_U32 RequestSize, AL_U32 *ReceiveSize, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    Al_AxiUartLite_EventStruct UartEvent = {0};
    AL_U32 CfgReg = 0, BaudRate = 0;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUartLite_Dev_RecvData(&Handle->Dev, Data, RequestSize);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);
        return Ret;
    }

    Ret = AlOsal_Mb_Receive(&Handle->RxEventQueue, &UartEvent, Timeout);
    if (Ret != AL_OK) {
        BaudRate = (AlAxiUartLite_GetStatus(Handle->Dev.HwConfig.BaseAddress) & 0xF00) >> AL_AXI_UART_LITE_SR_BAUDRATE_SHIFT;
        CfgReg = BaudRate << AL_AXI_UART_LITE_CR_BAUDRATE_SHIFT;
        AlAxiUartLite_SetCfgReg(Handle->Dev.HwConfig.BaseAddress, CfgReg);
        (AL_VOID)AlOsal_Mb_Receive(&Handle->RxEventQueue, &UartEvent, AL_WAITING_NO);
    }

    *ReceiveSize =  UartEvent.EventData;

    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    if (Ret == AL_OK && (UartEvent.Events == AL_AXI_UART_LITE_EVENT_RECEIVE_DONE))
        return AL_OK;
    else
        return (Ret != AL_OK) ? Ret : AL_AXI_UART_LITE_EVENTS_TO_ERRS(UartEvent.Events);
}

/**
 * This function sends data using the UART device.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the data buffer to be sent.
 * @param Size The size of the data buffer to be sent.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUartLite_Hal_SendData(Al_AxiUartLite_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->TxLock, 0);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUartLite_Dev_SendData(&Handle->Dev, Data, Size);

    (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);

    return Ret;
}

/**
 * This function receives data using the UART device.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the buffer where received data will be stored.
 * @param Size The size of the data buffer to be received.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUartLite_Hal_RecvData(Al_AxiUartLite_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, 0);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUartLite_Dev_RecvData(&Handle->Dev, Data, Size);

    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    return Ret;
}
