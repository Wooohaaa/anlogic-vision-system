/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_uart_16550_dev.h"
/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/

/************************** Variable Definitions *****************************/
extern AlAxiUart16550_HwConfigStruct AlAxiUart16550_HwConfig[AL_AXI_UART_16550_NUM_INSTANCE];
/********************************************************/

/**
 * This function looks up the hardware configuration for a given UART device ID.
 *
 * @param DevId The device ID for which to lookup the configuration.
 * @return A pointer to the hardware configuration structure if found, NULL otherwise.
 */
AlAxiUart16550_HwConfigStruct *AlAxiUart16550_Dev_LookupConfig(AL_U32 DevId)
{
    AL_U32 Index;
    AlAxiUart16550_HwConfigStruct *ConfigPtr = AL_NULL;
    for (Index = 0; Index < AL_AXI_UART_16550_NUM_INSTANCE; Index++)
    {
        if (AlAxiUart16550_HwConfig[Index].DeviceId == DevId)
        {
            ConfigPtr = &AlAxiUart16550_HwConfig[Index];
            break;
        }
    }
    return ConfigPtr;
}

/**
 * This function checks if the UART device's transmit operation is busy.
 *
 * @param Uart Pointer to the UART device structure.
 * @return True if the transmit operation is busy, false otherwise.
 */
AL_BOOL AlAxiUart16550_Dev_IsTxBusy(AlAxiUart16550_DevStruct *Uart)
{
    return (AL_BOOL)(Uart->State & AL_AXI_UART_16550_STATE_TX_BUSY);
}

/**
 * This function checks if the UART device's receive operation is busy.
 *
 * @param Uart Pointer to the UART device structure.
 * @return True if the receive operation is busy, false otherwise.
 */
AL_BOOL AlAxiUart16550_Dev_IsRxBusy(AlAxiUart16550_DevStruct *Uart)
{
    return (AL_BOOL)(Uart->State & AL_AXI_UART_16550_STATE_RX_BUSY);
}

/**
 * This function sets the UART device's transmit operation as busy.
 *
 * @param Uart Pointer to the UART device structure.
 */
AL_VOID AlAxiUart16550_Dev_SetTxBusy(AlAxiUart16550_DevStruct *Uart)
{
    Uart->State |= AL_AXI_UART_16550_STATE_TX_BUSY;
    if (Uart->EventCallBack) {
        AlAxiUart16550_EventStruct UartEvent = {
            .Events        = AL_AXI_UART_16550_EVENT_READY_TO_SEND
        };
        Uart->EventCallBack(UartEvent, Uart->EventCallBackRef);
    }
}

/**
 * This function sets the UART device's receive operation as busy.
 *
 * @param Uart Pointer to the UART device structure.
 */
AL_VOID AlAxiUart16550_Dev_SetRxBusy(AlAxiUart16550_DevStruct *Uart)
{
    Uart->State |= AL_AXI_UART_16550_STATE_RX_BUSY;
        if (Uart->EventCallBack) {
        AlAxiUart16550_EventStruct UartEvent = {
            .Events        = AL_AXI_UART_16550_EVENT_READY_TO_RECEIVE
        };
        Uart->EventCallBack(UartEvent, Uart->EventCallBackRef);
    }
}

/**
 * This function clears the UART device's transmit operation from being busy.
 *
 * @param Uart Pointer to the UART device structure.
 */
AL_VOID AlAxiUart16550_Dev_ClrTxBusy(AlAxiUart16550_DevStruct *Uart)
{
    Uart->State &= (~AL_AXI_UART_16550_STATE_TX_BUSY);
}

/**
 * This function clears the UART device's receive operation from being busy.
 *
 * @param Uart Pointer to the UART device structure.
 */
AL_VOID AlAxiUart16550_Dev_ClrRxBusy(AlAxiUart16550_DevStruct *Uart)
{
    Uart->State &= (~AL_AXI_UART_16550_STATE_RX_BUSY);
}

/**
 * This function sets the baud rate for the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 * @param BaudRate The baud rate to set.
 * @param InputClockHz The input clock frequency in Hz.
 */
AL_VOID AlAxiUart16550_Dev_SetBaudRate(AlAxiUart16550_DevStruct *Uart, AL_U32 BaudRate, AL_U32 InputClockHz)
{
    AL_FLOAT DivisorFloat = (AL_FLOAT)InputClockHz / (16.0f * BaudRate);

    AL_U32 Divisor = (AL_U32)(DivisorFloat + 0.5f);

    Divisor = (Divisor < 1) ? 1 : Divisor;
    Divisor = (Divisor > 0xFFFF) ? 0xFFFF : Divisor;

    AL_U8 DllInt = Divisor & 0xFF;
    AL_U8 DlhInt = (Divisor >> 8) & 0xFF;

    AlAxiUart16550_ll_SetBaudRate(Uart->HwConfig.BaseAddress, DllInt, DlhInt);
}

/**
 * This function initializes the UART device with specified configurations.
 *
 * @param Uart Pointer to the UART device structure to initialize.
 * @param DevId The device ID of the UART.
 * @param InitConfig Pointer to the initialization configuration structure.
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUart16550_Dev_Init(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_HwConfigStruct *HwConfig, AlAxiUart16550_InitStruct *InitConfig)
{
    Uart->HwConfig   = *HwConfig;
    Uart->InitConfig = *InitConfig;

    AlAxiUart16550_ll_DisableAllIntr(Uart->HwConfig.BaseAddress);
    AlAxiUart16550_ll_ResetRxFifo(Uart->HwConfig.BaseAddress);
    AlAxiUart16550_ll_ResetTxFifo(Uart->HwConfig.BaseAddress);

    AlAxiUart16550_Dev_SetBaudRate(Uart, InitConfig->BaudRate, HwConfig->InputClockHz);

    AlAxiUart16550_ll_SetParity(Uart->HwConfig.BaseAddress, Uart->InitConfig.Parity);
    AlAxiUart16550_ll_SetDataWidth(Uart->HwConfig.BaseAddress, Uart->InitConfig.WordLength);
    AlAxiUart16550_ll_SetStopBitsLength(Uart->HwConfig.BaseAddress, Uart->InitConfig.StopBits);

    AlAxiUart16550_ll_EnableFifo(Uart->HwConfig.BaseAddress, AL_FUNC_ENABLE);

    AlAxiUart16550_ll_SetRxFifoThre(Uart->HwConfig.BaseAddress, AlAxiUart16550_RxFIFO_CHAR_62);

    Uart->State |= AL_AXI_UART_16550_STATE_READY;

    return AL_OK;
}

/**
 * This function enables or disables UART interrupts for receive or transmit operations. It is called internally by
 * the UART driver to control the interrupt enable state based on the current operation, such as starting or stopping
 * receive or transmit operations.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Transfer Specifies the type of operation (UART_RX or UART_TX) for which to set or clear interrupts.
 * @param State Specifies whether to enable or disable interrupts for the specified operation.
 */
static AL_VOID AlAxiUart16550_Dev_SetIntr(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_TransferEnum Transfer,  AL_FUNCTION State)
{
    AL_BOOL IsRxBusy = AlAxiUart16550_Dev_IsRxBusy(Uart);
    AL_BOOL IsTxBusy = AlAxiUart16550_Dev_IsTxBusy(Uart);

    AlOsal_EnterDevCtritical(Uart->HwConfig.IntrId, (IsRxBusy && IsTxBusy));

    (Transfer == AL_AXI_UART_16550_TX) ? AlAxiUart16550_ll_SetTxIntr(Uart->HwConfig.BaseAddress, State) :
                                         AlAxiUart16550_ll_SetRxIntr(Uart->HwConfig.BaseAddress, State);

    AlOsal_ExitDevCtritical(Uart->HwConfig.IntrId, IsRxBusy && IsTxBusy);
}

/**
 * This function stops the ongoing data transmission on the specified UART device.
 * It disables the UART TX interrupt and clears the TX busy status flag to indicate
 * that the UART is no longer transmitting data.
 *
 * @param Uart Pointer to the UART device structure.
 */
AL_VOID AlAxiUart16550_Dev_StopSend(AlAxiUart16550_DevStruct *Uart)
{
    AlAxiUart16550_Dev_SetIntr(Uart, AL_AXI_UART_16550_TX, AL_FUNC_DISABLE);
    AlAxiUart16550_Dev_ClrTxBusy(Uart);
}

/**
 * This function stops the ongoing data reception on the specified UART device.
 * It disables the UART RX interrupt and clears the RX busy status flag to indicate
 * that the UART is no longer receiving data.
 *
 * @param Uart Pointer to the UART device structure.
 */
AL_VOID AlAxiUart16550_Dev_StopReceive(AlAxiUart16550_DevStruct *Uart)
{
    AlAxiUart16550_Dev_SetIntr(Uart, AL_AXI_UART_16550_RX, AL_FUNC_DISABLE);
    AlAxiUart16550_Dev_ClrRxBusy(Uart);
}

/**
 * This function sends a single byte over the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Char The character to send.
 */
AL_VOID AlAxiUart16550_Dev_SendByte(AlAxiUart16550_DevStruct *Uart, AL_U8 Char)
{
    AlAxiUart16550_ll_DisableAllIntr(Uart->HwConfig.BaseAddress);
    while (!AlAxiUart16550_ll_IsEmptyTxFifo(Uart->HwConfig.BaseAddress));
    AlAxiUart16550_ll_SendByte(Uart->HwConfig.BaseAddress, Char);
}

/**
 * This function sends data over the UART device using polling method.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the data buffer to send.
 * @param Size The size of the data to send.
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUart16550_Dev_SendDataPolling(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 Size)
{
    AL_U32 HandledCnt = 0;
    AL_U32 RemainByte = Size;
    AL_U32 FifoDepth  = Uart->HwConfig.FifoDepth;
    AL_U32 SendCount  = 0;

    if (AlAxiUart16550_Dev_IsTxBusy(Uart)){
        return AL_AXI_UART_16550_ERR_BUSY;
    }

    AlAxiUart16550_Dev_SetTxBusy(Uart);

    while (HandledCnt < Size) {
        if ((AlAxiUart16550_ll_IsEmptyTxFifo(Uart->HwConfig.BaseAddress))) {
            SendCount = RemainByte < FifoDepth ? RemainByte : FifoDepth;
            for (AL_U32 i = 0; i < SendCount; i++) {
                AlAxiUart16550_ll_SendByte(Uart->HwConfig.BaseAddress, Data[HandledCnt]);
                HandledCnt ++;
            }
            RemainByte = Size - HandledCnt;
        }
    }

    /* Waiting for transmitter Shift Register and the FIFO both empty. */
    // while (!(AlAxiUart16550_ll_IsEmptyTsrAndTxFifo(Uart->HwConfig.BaseAddress)));

    AlAxiUart16550_Dev_ClrTxBusy(Uart);

    return AL_OK;
}

/**
 * This function receives data over the UART device using polling method.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the buffer to store received data.
 * @param Size The size of the buffer/data to receive.
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUart16550_Dev_RecvDataPolling(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 Size)
{
    AL_U32 HandledCnt = 0;

    if (AlAxiUart16550_Dev_IsRxBusy(Uart)){
        return AL_AXI_UART_16550_ERR_BUSY;
    }

    AlAxiUart16550_Dev_SetRxBusy(Uart);

    while (HandledCnt < Size) {
        if (AlAxiUart16550_ll_IsRxDataReady(Uart->HwConfig.BaseAddress)) {
            Data[HandledCnt] = AlAxiUart16550_ll_RecvByte(Uart->HwConfig.BaseAddress);
            HandledCnt ++;
        }
    }

    AlAxiUart16550_Dev_ClrRxBusy(Uart);

    return AL_OK;
}

/**
 * This function sends data over the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 * @param SendData Pointer to the data buffer to send.
 * @param SendSize The size of the data to send.
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUart16550_Dev_SendData(AlAxiUart16550_DevStruct *Uart, AL_U8 *SendData, AL_U32 SendSize)
{
    AL_ASSERT((Uart != AL_NULL && SendData != AL_NULL && SendSize != 0), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);
    AL_ASSERT(((Uart->State & AL_AXI_UART_16550_STATE_READY) == AL_AXI_UART_16550_STATE_READY), AL_AXI_UART_16550_ERR_NOT_READY);
    AL_ASSERT((!AlAxiUart16550_Dev_IsTxBusy(Uart)), AL_AXI_UART_16550_ERR_BUSY);

    AlAxiUart16550_Dev_SetTxBusy(Uart);

    Uart->SendBuffer.BufferPtr      = SendData;
    Uart->SendBuffer.RequestedCnt   = SendSize;
    Uart->SendBuffer.HandledCnt     = 0;

    AlAxiUart16550_Dev_SetIntr(Uart, AL_AXI_UART_16550_TX, AL_FUNC_ENABLE);

    return AL_OK;
}

/**
 * This function receives data from the UART device specified by the Uart parameter and stores it in the buffer
 * pointed to by ReceiveBuf. The function will receive up to ReceiveSize bytes. The actual number of bytes received
 * is determined by the availability of data in the UART's RX FIFO and the ReceiveSize parameter. If the number of
 * bytes received is less than ReceiveSize, the function will enable UART RX interrupt to handle the remaining data.
 *
 * @param Uart Pointer to the UART device structure.
 * @param ReceiveBuf Pointer to the buffer where received data will be stored.
 * @param ReceiveSize Number of bytes to receive.
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Dev_RecvData(AlAxiUart16550_DevStruct *Uart, AL_U8 *ReceiveBuf, AL_U32 ReceiveSize)
{
    AL_U32 ReceivedCount = 0;

    AL_ASSERT((Uart != AL_NULL && ReceiveBuf != AL_NULL && ReceiveSize != 0), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);
    AL_ASSERT(((Uart->State & AL_AXI_UART_16550_STATE_READY) == AL_AXI_UART_16550_STATE_READY), AL_AXI_UART_16550_ERR_NOT_READY);
    AL_ASSERT((!AlAxiUart16550_Dev_IsRxBusy(Uart)), AL_AXI_UART_16550_ERR_BUSY);

    AlAxiUart16550_Dev_SetRxBusy(Uart);

    /* Enable Rx Line Interrupt */
    AlAxiUart16550_ll_EnableRecvLineIntr(Uart->HwConfig.BaseAddress, AL_TRUE);

    /*
     * Loop until there is no more data in RX Fifo or the specified
     * number of bytes has been received
     */
    while ((ReceivedCount < ReceiveSize) && (AlAxiUart16550_ll_IsRxDataReady(Uart->HwConfig.BaseAddress))) {
        ReceiveBuf[ReceivedCount] = (AL_U8)AlAxiUart16550_ll_RecvByte(Uart->HwConfig.BaseAddress);
        ReceivedCount ++;
    }

    /* Setup the buffer parameters */
    if (ReceivedCount < ReceiveSize) {
        Uart->RecvBuffer.RequestedCnt   = ReceiveSize;
        Uart->RecvBuffer.HandledCnt     = ReceivedCount;
        Uart->RecvBuffer.BufferPtr      = ReceiveBuf;

        AlAxiUart16550_Dev_SetIntr(Uart, AL_AXI_UART_16550_RX, AL_FUNC_ENABLE);
    } else {
        if (Uart->EventCallBack) {
            AlAxiUart16550_EventStruct UartEvent = {
                .Events        = AL_AXI_UART_16550_EVENT_RECEIVE_DONE,
                .EventData    = Uart->RecvBuffer.HandledCnt
            };
            Uart->EventCallBack(UartEvent, Uart->EventCallBackRef);
        }
        AlAxiUart16550_Dev_ClrRxBusy(Uart);
    }

    return AL_OK;
}

/**
 * This function sends data to the UART device specified by the Uart parameter using a polling non-blocking method.
 * It attempts to send up to RequestSize bytes from the buffer pointed to by Data within the specified Timeout period.
 * The function continuously checks if the UART TX FIFO is empty and writes a byte when possible until either all data
 * is sent or the timeout expires. The actual number of bytes sent is stored in the variable pointed to by ActualSize.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the buffer containing data to be sent.
 * @param RequestSize Number of bytes to send.
 * @param ActualSize Pointer to a variable where the actual number of bytes sent will be stored.
 * @param Timeout Timeout period in milliseconds.
 * @return Returns AL_OK on success.
 */
AL_S32 AlAxiUart16550_Dev_SendDataPollingNonBlock(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 RequestSize,
                                       AL_U32 *ActualSize, AL_U32 Timeout)
{
    AL_U32 HandledCnt = 0;
    volatile AL_U64 Start = AlSys_GetTimerTickCount();
    volatile AL_U64 Freq  = AlSys_GetTimerFreq();
    volatile AL_U32 DelayMs = Timeout;
    volatile AL_U64 Endtick =  (Start + Freq * DelayMs / 1000);
    volatile AL_U64 CurTick =  AlSys_GetTimerTickCount();

    while ((HandledCnt < RequestSize) && (Endtick >= CurTick)) {
        if (AlAxiUart16550_ll_IsEmptyTxFifo(Uart->HwConfig.BaseAddress)) {
            AlAxiUart16550_ll_SendByte(Uart->HwConfig.BaseAddress, Data[HandledCnt]);
            HandledCnt ++;
        }
        CurTick = AlSys_GetTimerTickCount();
    }

    *ActualSize = HandledCnt;

    return AL_OK;
}

/**
 * This function receives data from the UART device specified by the Uart parameter using a polling non-blocking method.
 * It attempts to receive up to RequestSize bytes and stores them in the buffer pointed to by Data within the specified
 * Timeout period. The function continuously checks if data is available in the UART RX FIFO and reads a byte when ready,
 * until either the requested number of bytes is received or the timeout expires. The actual number of bytes received
 * is stored in the variable pointed to by ReceiveSize.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the buffer where received data will be stored.
 * @param RequestSize Number of bytes to receive.
 * @param ReceiveSize Pointer to a variable where the actual number of bytes received will be stored.
 * @param Timeout Timeout period in milliseconds.
 * @return Returns AL_OK on success.
 */
AL_S32 AlAxiUart16550_Dev_RecvDataPollingNonBlock(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 RequestSize,
                                       AL_U32 *ReceiveSize, AL_U32 Timeout)
{
    AL_U32 HandledCnt = 0;
    volatile AL_U64 Start = AlSys_GetTimerTickCount();
    volatile AL_U64 Freq  = AlSys_GetTimerFreq();
    volatile AL_U32 DelayMs = Timeout;
    volatile AL_U64 Endtick =  (Start + Freq * DelayMs / 1000);
    volatile AL_U64 CurTick =  AlSys_GetTimerTickCount();

    while ((HandledCnt < RequestSize) && (Endtick >= CurTick)) {
        if ((AlAxiUart16550_ll_IsRxDataReady(Uart->HwConfig.BaseAddress))) {
            Data[HandledCnt] = AlAxiUart16550_ll_RecvByte(Uart->HwConfig.BaseAddress);
            HandledCnt ++;
        }
        CurTick = AlSys_GetTimerTickCount();
    }

    *ReceiveSize = HandledCnt;

    return AL_OK;
}

/**
 * This function is called internally by the UART driver to handle receive errors such as overrun, parity, framing,
 * and break conditions. It is typically called from an interrupt service routine when a receive line status
 * interrupt occurs. The function reads any remaining data from the RX FIFO and updates the event structure with
 * the appropriate error flags.
 *
 * @param Uart Pointer to the UART device structure.
 * @param IntrStatus The interrupt status indicating the type of receive error.
 */
static AL_VOID AlAxiUart16550_Dev_RecvErrorHandler(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_IntrEnum IntrStatus)
{
    AlAxiUart16550_EventStruct UartEvent = {
        .Events     = 0,
        .EventData  = 0,
    };

    AL_U32 ErrorStatus = AlAxiUart16550_ll_GetLineState(Uart->HwConfig.BaseAddress);

    if(ErrorStatus & (AL_AXI_UART_16550_OVERRUN_ERR)) {
        while ((AlAxiUart16550_ll_IsRxDataReady(Uart->HwConfig.BaseAddress) == AL_TRUE) &&
            (Uart->RecvBuffer.HandledCnt < Uart->RecvBuffer.RequestedCnt)) {
                Uart->RecvBuffer.BufferPtr[Uart->RecvBuffer.HandledCnt] = (AL_U8)AlAxiUart16550_ll_RecvByte(Uart->HwConfig.BaseAddress);
                Uart->RecvBuffer.HandledCnt ++;
        }
        UartEvent.Events |= AL_AXI_UART_16550_EVENT_OVER_RUN_ERR;
    }

    if (ErrorStatus & (AL_AXI_UART_16550_PARITY_ERR)) {
        UartEvent.Events |= AL_AXI_UART_16550_EVENT_PARITY_ERR;
    }
    if (ErrorStatus & (AL_AXI_UART_16550_FRAMING_ERR)) {
        UartEvent.Events |= AL_AXI_UART_16550_EVENT_FRAMING_ERR;
    }
    if (ErrorStatus & (AL_AXI_UART_16550_BREAK_ERR)) {
        UartEvent.Events |= AL_AXI_UART_16550_EVENT_BREAK_INTR;
    }

    /* Disable Rx Line Interrupt */
    AlAxiUart16550_ll_EnableRecvLineIntr(Uart->HwConfig.BaseAddress, AL_FALSE);

    AlAxiUart16550_Dev_StopReceive(Uart);

    UartEvent.EventData = Uart->RecvBuffer.HandledCnt;
    if (Uart->EventCallBack) {
        (*Uart->EventCallBack)(UartEvent, Uart->EventCallBackRef);
    }
}

/**
 * This function is called internally by the UART driver to handle data transmission. It is typically called from an
 * interrupt service routine when the UART's TX FIFO is ready to accept more data. The function sends data from the
 * transmit buffer to the TX FIFO until the buffer is empty or the TX FIFO is full.
 *
 * @param Uart Pointer to the UART device structure.
 */
static AL_VOID AlAxiUart16550_Dev_SendDataHandler(AlAxiUart16550_DevStruct *Uart)
{
    AL_U32 FifoDepth  = Uart->HwConfig.FifoDepth;

    if (Uart->SendBuffer.HandledCnt == Uart->SendBuffer.RequestedCnt) {

        AlAxiUart16550_Dev_StopSend(Uart);

        if (Uart->EventCallBack) {
            AlAxiUart16550_EventStruct UartEvent = {
                .Events        = AL_AXI_UART_16550_EVENT_SEND_DONE,
                .EventData     = Uart->SendBuffer.HandledCnt
            };
            (*Uart->EventCallBack)(UartEvent, Uart->EventCallBackRef);
        }
    } else {
        AL_U32 RemainByte = Uart->SendBuffer.RequestedCnt - Uart->SendBuffer.HandledCnt;
        AL_U32 SendCount  = RemainByte < FifoDepth ? RemainByte : FifoDepth;
        for (AL_U32 i = 0; i < SendCount; i++) {
            AlAxiUart16550_ll_SendByte(Uart->HwConfig.BaseAddress, Uart->SendBuffer.BufferPtr[Uart->SendBuffer.HandledCnt]);
            Uart->SendBuffer.HandledCnt ++;
        }
    }
}

/**
 * This function is called internally by the UART driver to handle received data. It is typically called from an
 * interrupt service routine when data is available in the UART's RX FIFO. The function reads data from the RX FIFO
 * into the receive buffer until the buffer is full or there is no more data available. If a character timeout
 * interrupt occurs and character timeout is enabled, the function will also handle this condition.
 *
 * @param Uart Pointer to the UART device structure.
 * @param CharTimeoutIntr Indicates whether a character timeout interrupt occurred.
 */
static AL_VOID AlAxiUart16550_Dev_RecvDataHandler(AlAxiUart16550_DevStruct *Uart, AL_BOOL CharTimeoutIntr)
{
    AlAxiUart16550_EventStruct UartEvent = {
        .EventData = 0,
        .Events    = 0,
    };

    while ((AlAxiUart16550_ll_IsRxDataReady(Uart->HwConfig.BaseAddress) == AL_TRUE) &&
           (Uart->RecvBuffer.HandledCnt < Uart->RecvBuffer.RequestedCnt)) {
        Uart->RecvBuffer.BufferPtr[Uart->RecvBuffer.HandledCnt] = (AL_U8)AlAxiUart16550_ll_RecvByte(Uart->HwConfig.BaseAddress);
        Uart->RecvBuffer.HandledCnt ++;
    }

    if ((Uart->RecvBuffer.HandledCnt == Uart->RecvBuffer.RequestedCnt) || (CharTimeoutIntr && Uart->InitConfig.CharTimeoutEnable)) {
        UartEvent.Events = ((Uart->RecvBuffer.HandledCnt == Uart->RecvBuffer.RequestedCnt) ?
                             AL_AXI_UART_16550_EVENT_RECEIVE_DONE : AL_AXI_UART_16550_EVENT_CHAR_TIMEOUT);
        UartEvent.EventData = Uart->RecvBuffer.HandledCnt;

        /* Disable Rx Line Interrupt */
        AlAxiUart16550_ll_EnableRecvLineIntr(Uart->HwConfig.BaseAddress, AL_FALSE);

        AlAxiUart16550_Dev_StopReceive(Uart);

        if (Uart->EventCallBack) {
            Uart->EventCallBack(UartEvent, Uart->EventCallBackRef);
        }
    }
}

/**
 * This function is called internally by the UART driver when there are no pending interrupts for the UART device.
 * It updates the event structure with the no interrupt pending event and calls the event callback function if
 * registered.
 *
 * @param Uart Pointer to the UART device structure.
 */
static AL_VOID AlAxiUart16550_Dev_NoInterruptPeding(AlAxiUart16550_DevStruct *Uart)
{
    AlAxiUart16550_EventStruct UartEvent = {
        .Events = AL_AXI_UART_16550_EVENT_NO_INTR_PEDING
    };
    if (Uart->EventCallBack) {
        (*Uart->EventCallBack)(UartEvent, Uart->EventCallBackRef);
    }
}

/**
 * This function is called internally by the UART driver to handle modem status interrupts. It updates the event
 * structure with the modem status interrupt event and calls the event callback function if registered.
 *
 * @param Uart Pointer to the UART device structure.
 */
static AL_VOID AlAxiUart16550_Dev_ModemStatusIntr(AlAxiUart16550_DevStruct *Uart)
{
    AlAxiUart16550_EventStruct UartEvent = {
        .Events = AL_AXI_UART_16550_EVENT_MODEM_STATUS_INTR,
    };
    if (Uart->EventCallBack) {
        (*Uart->EventCallBack)(UartEvent, Uart->EventCallBackRef);
    }
}

#define AL_AXI_UART_16550_INTR_MODEM_STATUS(Status)           (Status == AlAxiUart16550_MODEM_STATUS)
#define AL_AXI_UART_16550_NO_INTER_PEDING(Status)             (Status == AlAxiUart16550_NO_INTERRUPT_PENDING)
#define AL_AXI_UART_16550_INTR_THRE_EMPTY(Status)             (Status == AlAxiUart16550_THR_EMPTY)
#define AL_AXI_UART_16550_INTR_RECV_AVAIL(Status)             (Status == AlAxiUart16550_RECEIVED_DATA_AVAILABLE)
#define AL_AXI_UART_16550_INTR_RECV_LINE_STATUS(Status)       (Status == AlAxiUart16550_RECEIVER_LINE_STATUS)
#define AL_AXI_UART_16550_INTR_CHAR_RECEV_TIMEOUT(Status)     (Status == AlAxiUart16550_CHARACTER_TIMEOUT)

/**
 * This function is the main interrupt handler for the UART device. It checks the interrupt status and calls the
 * appropriate handler function for the specific interrupt condition. This includes handling receive data available,
 * transmit holding register empty, receive line status, bus busy detect, no interrupt pending, and modem status
 * interrupts.
 *
 * @param Instance Pointer to the UART device structure.
 */
__attribute__((weak))  AL_VOID AlAxiUart16550_Dev_IntrHandler(AL_VOID *Instance)
{
    AlAxiUart16550_DevStruct *Uart = (AlAxiUart16550_DevStruct *)Instance;
    AlAxiUart16550_IntrEnum IntrStatus = AlAxiUart16550_ll_GetIntrStatus(Uart->HwConfig.BaseAddress);

    if (AL_AXI_UART_16550_INTR_RECV_AVAIL(IntrStatus) || AL_AXI_UART_16550_INTR_CHAR_RECEV_TIMEOUT(IntrStatus)) {
        AlAxiUart16550_Dev_RecvDataHandler(Uart, AL_AXI_UART_16550_INTR_CHAR_RECEV_TIMEOUT(IntrStatus));
    } else if (AL_AXI_UART_16550_INTR_THRE_EMPTY(IntrStatus)) {
        AlAxiUart16550_Dev_SendDataHandler(Uart);
    } else if (AL_AXI_UART_16550_INTR_RECV_LINE_STATUS(IntrStatus)) {
        AlAxiUart16550_Dev_RecvErrorHandler(Uart, IntrStatus);
    } else if (AL_AXI_UART_16550_NO_INTER_PEDING(IntrStatus)) {
        AlAxiUart16550_Dev_NoInterruptPeding(Uart);
    } else if (AL_AXI_UART_16550_INTR_MODEM_STATUS(IntrStatus)) {
        AlAxiUart16550_Dev_ModemStatusIntr(Uart);
    }

}

/**
 * This function registers a callback function that will be called by the UART driver when specified events occur.
 * The callback function is specified by the Callback parameter, and a reference to user data can be passed with
 * the CallbackRef parameter. This allows the user to register a custom function to handle UART events such as
 * transmission completion, reception completion, and errors.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Callback Pointer to the callback function.
 * @param CallbackRef Pointer to user data that will be passed to the callback function.
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Dev_RegisterEventCallBack(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_EventCallBack Callback, AL_VOID *CallbackRef)
{
    AL_ASSERT((Uart != AL_NULL && Callback != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Uart->EventCallBack        = Callback;
    Uart->EventCallBackRef     = CallbackRef;

    return AL_OK;
}

/**
 * This function unregisters the callback function that was previously registered for handling UART events. After
 * calling this function, the UART driver will no longer call the event callback function when events occur.
 *
 * @param Uart Pointer to the UART device structure.
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Dev_UnRegisterEventCallBack(AlAxiUart16550_DevStruct *Uart)
{
    AL_ASSERT((Uart != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    Uart->EventCallBack = AL_NULL;

    return AL_OK;
}


AL_S32 AlAxiUart16550_Dev_IoCtl(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_IoCtlCmdEnum Cmd, AlAxiUart16550_IoctlParamUnion *IoctlParam)
{
    AL_S32 Ret = AL_OK;

    AL_ASSERT((Uart != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

    if(!AlAxiUart16550_ll_IsEmptyTsrAndTxFifo(Uart->HwConfig.BaseAddress)){
        AL_LOG(AL_LOG_LEVEL_ERROR, "access during a transaction\r\n");
        return AL_AXI_UART_16550_ERR_BUSY;
    }

    switch (Cmd)
    {
    case AL_AXI_UART_16550_IOCTL_SET_BAUD_RATE: {
        AL_U32 BaudRate = IoctlParam->BaudRate;
        AlAxiUart16550_Dev_SetBaudRate(Uart, BaudRate, Uart->HwConfig.InputClockHz);
        break;
    }
    case AL_AXI_UART_16550_IOCTL_GET_BAUD_RATE: {
        AL_U32 BaudRate = AlAxiUart16550_ll_GetBaudRate(Uart->HwConfig.BaseAddress, Uart->HwConfig.InputClockHz);
        IoctlParam->BaudRate = BaudRate;
        break;
    }
    case AL_AXI_UART_16550_IOCTL_SET_DATA_WIDTH: {
        AL_U32 DataWidth = IoctlParam->DataWidth;
        AlAxiUart16550_ll_SetDataWidth(Uart->HwConfig.BaseAddress, DataWidth);
        break;
    }
    case AL_AXI_UART_16550_IOCTL_GET_DATA_WIDTH: {
        AL_U32 DataWidth = AlAxiUart16550_ll_GetDataWidth(Uart->HwConfig.BaseAddress);
        IoctlParam->DataWidth = DataWidth;
        break;
    }
    case AL_AXI_UART_16550_IOCTL_SET_STOP_BITS: {
        AL_U32 StopBits = IoctlParam->StopBits;
        AlAxiUart16550_ll_SetStopBitsLength(Uart->HwConfig.BaseAddress, StopBits);
        break;
    }
    case AL_AXI_UART_16550_IOCTL_GET_STOP_BITS: {
        AL_U32 StopBits = AlAxiUart16550_ll_GetStopBitsLength(Uart->HwConfig.BaseAddress);
        IoctlParam->StopBits = StopBits;
        break;
    }
    case AL_AXI_UART_16550_IOCTL_SET_PARITY: {
        AL_U32 Parity = IoctlParam->Parity;
        AlAxiUart16550_ll_SetParity(Uart->HwConfig.BaseAddress, Parity);
        break;
    }
    case AL_AXI_UART_16550_IOCTL_GET_PARITY: {
        AL_U32 Parity = AlAxiUart16550_ll_GetParity(Uart->HwConfig.BaseAddress);
        IoctlParam->Parity = Parity;
        break;
    }
    default:
        AL_LOG(AL_LOG_LEVEL_ERROR, "AL_UAER_ERR_IOCTL_CMD");
        break;
    }

    return Ret;
}

