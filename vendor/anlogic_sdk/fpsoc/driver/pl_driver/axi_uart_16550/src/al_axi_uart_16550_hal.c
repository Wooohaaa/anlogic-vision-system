/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_uart_16550_hal.h"
#include "al_log.h"

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/

/************************** Variable Definitions *****************************/
static AlAxiUart16550_HalStruct AlAxiUart16550Handle[AL_AXI_UART_16550_NUM_INSTANCE];
/********************************************************/

static AlAxiUart16550_InitStruct Allog_Uart16550Init = {
        .BaudRate           = 115200,
        .Parity             = AlAxiUart16550_NO_PARITY,
        .WordLength         = AlAxiUart16550_CHAR_8BITS,
        .StopBits           = AlAxiUart16550_STOP_1BIT,
        .CharTimeoutEnable  = AL_TRUE
};

AlLog_Ops Allog_Uart16550 =
{
    .DevId            = (LOG_DEV - AL_LOG_UART16550),
    .InitConfig       = &Allog_Uart16550Init,
    .AlLog_Init       = (AL_S32  (*)(AL_VOID**, AL_U32, AL_VOID*, AL_VOID*))AlAxiUart16550_Hal_Init,
    .AlLog_Write      = (AL_S32  (*)(AL_VOID*, const void *, AL_U32))AL_NULL,
    .AlLog_WriteByte  = (AL_VOID (*)(AL_VOID*, AL_U8))AlAxiUart16550_Dev_SendByte,
    .AlLog_Read       = (AL_S32  (*)(AL_VOID*, AL_U8 *, AL_U32))AlAxiUart16550_Dev_RecvDataPolling,
    .AlLog_DeInit     = AL_NULL
};


/**
 * This function is called back when a UART event occurs and handles the event by sending it to the
 * appropriate message queue based on the type of event.
 *
 * @param UartEvent The UART event structure containing details about the event.
 * @param CallbackRef A void pointer to the UART handle structure.
 * @return void
 */
static AL_VOID AlAxiUart16550_Hal_DefEventHandler(AlAxiUart16550_EventStruct UartEvent, AL_VOID *CallbackRef)
{
    AlAxiUart16550_HalStruct *Handle = (AlAxiUart16550_HalStruct *)CallbackRef;

    switch (UartEvent.Events)
    {
    case AL_AXI_UART_16550_EVENT_SEND_DONE:
        AlOsal_Mb_Send(&Handle->TxEventQueue, &UartEvent);
        break;

    case AL_AXI_UART_16550_EVENT_RECEIVE_DONE:
    case AL_AXI_UART_16550_EVENT_CHAR_TIMEOUT:
    case AL_AXI_UART_16550_EVENT_OVER_RUN_ERR:
        AlOsal_Mb_Send(&Handle->RxEventQueue, &UartEvent);
        break;

    case AL_AXI_UART_16550_EVENT_MODEM_STATUS_INTR:
        AL_LOG(AL_LOG_LEVEL_INFO, "Uart experienced a modem status interrupt. \r\n");
        break;

    case AL_AXI_UART_16550_EVENT_READY_TO_RECEIVE:
        break;

    case AL_AXI_UART_16550_EVENT_READY_TO_SEND:
       break;

    default:
        break;
    }

    if (UartEvent.Events & (AL_AXI_UART_16550_EVENT_PARITY_ERR | AL_AXI_UART_16550_EVENT_FRAMING_ERR | AL_AXI_UART_16550_EVENT_BREAK_INTR)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Uart receive error 0x%x .\r\n", AL_AXI_UART_16550_EVENTS_TO_ERRS(UartEvent.Events));
        AlOsal_Mb_Send(&Handle->RxEventQueue, &UartEvent);
    }
}

/**
 * This function sets up the hardware configuration for the UART, initializes locks and message queues for TX
 * and RX, and registers the event callback function.
 *
 * @param Handle A pointer to a pointer of the UART handle structure to be initialized.
 * @param DevId The device ID of the UART to be initialized.
 * @param InitConfig A pointer to the UART initialization structure.
 * @param Callback The event callback function to be registered.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_Init(AlAxiUart16550_HalStruct **Handle, AL_U32 DevId, AlAxiUart16550_InitStruct *InitConfig, AlAxiUart16550_EventCallBack Callback)
{
    AL_S32 Ret = AL_OK;
    AlAxiUart16550_HwConfigStruct *HwConfig = NULL;

    Soc_PsPlInit();

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

#if defined(__riscv)
    AL_INTR_AttrStrct AxiUart16550Attr = {
        .TrigMode   =  POSTIVE_EDGE_TRIGGER,
        .Priority   =  0,
        .VectorMode =  NON_VECTOR_INTERRUPT,
    };
#else
    AL_INTR_AttrStrct AxiUart16550Attr = {
        .TrigMode   = POSTIVE_EDGE_TRIGGER,
        .Priority   = 137,
    };
#endif

    HwConfig = AlAxiUart16550_Dev_LookupConfig(DevId);
    if (HwConfig != AL_NULL) {
        *Handle = &AlAxiUart16550Handle[DevId];
    } else {
        return AL_AXI_UART_16550_ERR_ILLEGAL_PARAM;
    }

    Ret = AlAxiUart16550_Dev_Init(&(*Handle)->Dev, HwConfig, InitConfig);
    if (Ret != AL_OK) {
        return Ret;
    }

    if(Callback == AL_NULL) {
        Ret = AlAxiUart16550_Dev_RegisterEventCallBack(&(*Handle)->Dev, AlAxiUart16550_Hal_DefEventHandler, (AL_VOID *)*Handle);
    } else {
        Ret = AlAxiUart16550_Dev_RegisterEventCallBack(&(*Handle)->Dev, Callback, (AL_VOID *)*Handle);
    }
    if (Ret != AL_OK) {
        return Ret;
    }

    (AL_VOID)AlIntr_RegHandler((*Handle)->Dev.HwConfig.IntrId, &AxiUart16550Attr, AlAxiUart16550_Dev_IntrHandler, &(*Handle)->Dev);

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
 * This function sends data by polling  * the UART device until all data is sent or an error occurs.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the data buffer to be sent.
 * @param Size The size of the data buffer to be sent.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_SendDataPolling(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->TxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_SendDataPolling(&Handle->Dev, Data, Size);

    (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);

    return Ret;
}

/**
 * This function receives data by polling the UART device until the specified amount of data is received or an error occurs.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the buffer where received data will be stored.
 * @param Size The size of the data buffer to be received.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_RecvDataPolling(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_RecvDataPolling(&Handle->Dev, Data, Size);

    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    return Ret;
}

/**
 * This function sends data using a polling non-blocking method within a specified timeout period.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the buffer containing the data to be sent.
 * @param RequestSize The size of the data buffer to be sent.
 * @param ActualSize A pointer to a variable where the actual size of sent data will be stored.
 * @param Timeout The timeout period in milliseconds.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_SendDataPollingNonBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 RequestSize,
                                       AL_U32 *ActualSize, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_SendDataPollingNonBlock(&Handle->Dev, Data, RequestSize, ActualSize, Timeout);

    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    return Ret;
}

/**
 * This function receives data using a polling non-blocking method within a specified timeout period.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the buffer where received data will be stored.
 * @param RequestSize The size of the data buffer to be received.
 * @param ReceiveSize A pointer to a variable where the actual size of received data will be stored.
 * @param Timeout The timeout period in milliseconds.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_RecvDataPollingNonBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 RequestSize,
                                       AL_U32 *ReceiveSize, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_RecvDataPollingNonBlock(&Handle->Dev, Data, RequestSize, ReceiveSize, Timeout);

    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    return Ret;
}

/**
 * This function sends data and waits for a send complete event or an error event within a specified timeout period.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the data buffer to be sent.
 * @param Size The size of the data buffer to be sent.
 * @param Timeout The timeout period in milliseconds.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_SendDataBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    AlAxiUart16550_EventStruct AlAxiUart16550_Event = {0};

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->TxLock, Timeout);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_SendData(&Handle->Dev, Data, Size);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);
        return Ret;
    }

    Ret = AlOsal_Mb_Receive(&Handle->TxEventQueue, &AlAxiUart16550_Event, Timeout);
    if (Ret != AL_OK) {
        AlAxiUart16550_Dev_StopSend(&Handle->Dev);
        (AL_VOID)AlOsal_Mb_Receive(&Handle->TxEventQueue, &AlAxiUart16550_Event, AL_WAITING_NO);
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);

    if (Ret == AL_OK && (AlAxiUart16550_Event.Events == AL_AXI_UART_16550_EVENT_SEND_DONE))
        return AL_OK;
    else
        return (Ret != AL_OK) ? Ret : AL_AXI_UART_16550_EVENTS_TO_ERRS(AlAxiUart16550_Event.Events);
}

/**
 * This function receives data and waits for a receive complete event or an error event within a specified timeout period.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the buffer where received data will be stored.
 * @param RequestSize The size of the data buffer to be received.
 * @param ReceiveSize A pointer to a variable where the actual size of received data will be stored.
 * @param Timeout The timeout period in milliseconds.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_RecvDataBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 RequestSize, AL_U32 *ReceiveSize, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    AlAxiUart16550_EventStruct AlAxiUart16550_Event = {0};

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_RecvData(&Handle->Dev, Data, RequestSize);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);
        return Ret;
    }

    Ret = AlOsal_Mb_Receive(&Handle->RxEventQueue, &AlAxiUart16550_Event, Timeout);
    if (Ret != AL_OK) {
        AlAxiUart16550_Dev_StopReceive(&Handle->Dev);
        (AL_VOID)AlOsal_Mb_Receive(&Handle->RxEventQueue, &AlAxiUart16550_Event, AL_WAITING_NO);
    }

    *ReceiveSize =  AlAxiUart16550_Event.EventData;

    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    if (Ret == AL_OK && (AlAxiUart16550_Event.Events == AL_AXI_UART_16550_EVENT_RECEIVE_DONE))
        return AL_OK;
    else
        return (Ret != AL_OK) ? Ret : AL_AXI_UART_16550_EVENTS_TO_ERRS(AlAxiUart16550_Event.Events);
}

/**
 * This function sends data using the UART device.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the data buffer to be sent.
 * @param Size The size of the data buffer to be sent.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_SendData(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->TxLock, 0);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_SendData(&Handle->Dev, Data, Size);

    (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);

    return Ret;
}

/**
 * This function receives data using the UART device.
 *
 * @param Handle A pointer to the UART handle structure.
 * @param Data A pointer to the buffer where received data will be stored.
 * @param Size The size of the data buffer to be received.
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_RecvData(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, 0);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiUart16550_Dev_RecvData(&Handle->Dev, Data, Size);

    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    return Ret;
}

/**
 * This function performs an IOCTL command on the UART device.
 *
 * @param Handle Pointer to the UART handle structure.
 * @param Cmd The IOCTL command to be performed.
 * @param IoctlParam Pointer to the IOCTL parameter union.
 * @return AL_S32 Returns AL_OK on success, error code otherwise.
 */
AL_S32 AlAxiUart16550_Hal_IoCtl(AlAxiUart16550_HalStruct *Handle, AlAxiUart16550_IoCtlCmdEnum Cmd, AlAxiUart16550_IoctlParamUnion *IoctlParam)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Ret = AlOsal_Lock_Take(&Handle->RxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        goto ERR_1;
    }

    Ret = AlOsal_Lock_Take(&Handle->TxLock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        goto ERR_0;
    }

    Ret = AlAxiUart16550_Dev_IoCtl(&Handle->Dev, Cmd, IoctlParam);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Uart Ioctl cmd error:%d\r\n", Ret);
    }

ERR_0:
    (AL_VOID)AlOsal_Lock_Release(&Handle->TxLock);

ERR_1:
    (AL_VOID)AlOsal_Lock_Release(&Handle->RxLock);

    return Ret;
}
