/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_axi_uart_lite_dev.h"

extern AlAxiUartLite_HwConfigStruct AlAxiUartLite_HwConfig[AL_AXI_UART_LITE_NUM_INSTANCE];

/**
 * This function searches through the list of hardware configurations to find the
 * configuration that matches the provided device ID.
 *
 * @param DevId The ID of the UART Lite device.
 *
 * @return AlAxiUartLite_HwConfigStruct* Pointer to the hardware configuration structure.
 */
AlAxiUartLite_HwConfigStruct *AlAxiUartLite_Dev_LookupConfig(AL_U32 DevId)
{
    AL_U32 Index;
    AlAxiUartLite_HwConfigStruct *ConfigPtr = AL_NULL;
    for (Index = 0; Index < AL_AXI_UART_LITE_NUM_INSTANCE; Index++)
    {
        if (AlAxiUartLite_HwConfig[Index].DeviceId == DevId)
        {
            ConfigPtr = &AlAxiUartLite_HwConfig[Index];
            break;
        }
    }
    return ConfigPtr;
}

/**
 * This function initializes the UART device with specified configurations.
 *
 * @param Uart Pointer to the UART device structure to initialize.
 * @param DevId The device ID of the UART.
 *
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUartLite_Dev_Init(Al_AxiUartLite_DevStruct *Uart, AL_U32 DevId)
{
    AlAxiUartLite_HwConfigStruct *UartHwConfig = AL_NULL;
    AL_U32 CfgReg = 0;
    AL_U32 BandRateCfg = 0;

    UartHwConfig = AlAxiUartLite_Dev_LookupConfig(DevId);
    Uart->HwConfig.BaseAddress = UartHwConfig->BaseAddress;
    Uart->HwConfig.IntrId = UartHwConfig->IntrId;
    Uart->HwConfig.BaudRate = UartHwConfig->BaudRate;
    Uart->HwConfig.DataWidth = UartHwConfig->DataWidth;
    Uart->HwConfig.ParityEn = UartHwConfig->ParityEn;
    Uart->HwConfig.ParityOdd = UartHwConfig->ParityOdd;
    Uart->HwConfig.ParityEven = UartHwConfig->ParityEven;

    switch (Uart->HwConfig.BaudRate)
    {
    case 9600:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_9600;
        break;
    case 110:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_110;
        break;
    case 300:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_300;
        break;
    case 1200:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_1200;
        break;
    case 2400:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_2400;
        break;
    case 4800:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_4800;
        break;
    case 19200:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_19200;
        break;
    case 38400:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_38400;
        break;
    case 57600:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_57600;
        break;
    case 115200:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_115200;
        break;
    case 128000:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_128000;
        break;
    case 230400:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_230400;
        break;
    case 460800:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_460800;
        break;
    case 921600:
        BandRateCfg = AL_AXIUARTLITE_BANDRATE_921600;
        break;
    default:
        return AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM;
    }

    CfgReg = (BIT(AL_AXI_UART_LITE_CR_TXFIFO_RST_SHIFT) |
              BIT(AL_AXI_UART_LITE_CR_RXFIFO_RST_SHIFT) |
              (BandRateCfg << AL_AXI_UART_LITE_CR_BAUDRATE_SHIFT));
    AlAxiUartLite_SetCfgReg(Uart->HwConfig.BaseAddress, CfgReg);

    Uart->State |= AL_AXI_UART_LITE_STATE_READY;

    return AL_OK;
}

/**
 * This function sends data over the UART device using polling method.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the data buffer to send.
 * @param Size The size of the data to send.
 *
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUartLite_Dev_SendDataPolling(Al_AxiUartLite_DevStruct *Uart, AL_U8 *Data, AL_U32 Size)
{
    AL_U32 HandledCnt = 0;

    while (HandledCnt < Size) {
        if (!(AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress) & BIT(AL_AXI_UART_LITE_TX_FIFO_FULL))) {
            AlAxiUartLite_SendData(Uart->HwConfig.BaseAddress, Data[HandledCnt]);
            HandledCnt ++;
        }
    }

    return AL_OK;
}

/**
 * This function receives data over the UART device using polling method.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the buffer to store received data.
 * @param Size The size of the buffer/data to receive.
 *
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUartLite_Dev_RecvDataPolling(Al_AxiUartLite_DevStruct *Uart, AL_U8 *Data, AL_U32 Size)
{
    AL_U32 HandledCnt = 0;

    while (HandledCnt < Size) {
        if (AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress) & BIT(AL_AXI_UART_LITE_RX_FIFO_HAS_DATA)) {
            Data[HandledCnt] = AlAxiUartLite_RecvData(Uart->HwConfig.BaseAddress);
            HandledCnt ++;
        }
    }

    return AL_OK;
}

/**
 * This function sends data over the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the buffer to store send data.
 * @param Size The size of the buffer/data to send.
 *
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUartLite_Dev_SendData(Al_AxiUartLite_DevStruct *Uart, AL_U8 *Data, AL_U32 Size)
{
    Uart->SendBuffer.BufferPtr      = Data;
    Uart->SendBuffer.RequestedCnt   = Size;
    Uart->SendBuffer.HandledCnt     = 0;
    AL_U32 HandledCnt = 0;
    AL_U32 CfgReg = 0, BaudRate = 0;

    while (HandledCnt < 1) {
        if (!(AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress) & BIT(AL_AXI_UART_LITE_TX_FIFO_FULL))) {
            AlAxiUartLite_SendData(Uart->HwConfig.BaseAddress, Data[HandledCnt]);
            HandledCnt ++;
            Uart->SendBuffer.HandledCnt ++;
        }
    }

    BaudRate = (AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress) & 0xF00) >> AL_AXI_UART_LITE_SR_BAUDRATE_SHIFT;
    CfgReg = BaudRate << AL_AXI_UART_LITE_CR_BAUDRATE_SHIFT |
             BIT(AL_AXI_UART_LITE_CR_ENABLE_INT_SHIFT);
    AlAxiUartLite_SetCfgReg(Uart->HwConfig.BaseAddress, CfgReg);

    return AL_OK;
}

/**
 * This function recv data over the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Data Pointer to the buffer to store received data.
 * @param Size The size of the buffer/data to receive.
 *
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUartLite_Dev_RecvData(Al_AxiUartLite_DevStruct *Uart, AL_U8 *Data, AL_U32 Size)
{
    AL_U32 CfgReg = 0, BaudRate = 0;
    Uart->RecvBuffer.BufferPtr      = Data;
    Uart->RecvBuffer.RequestedCnt   = Size;
    Uart->RecvBuffer.HandledCnt     = 0;

    BaudRate = (AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress) & 0xF00) >> AL_AXI_UART_LITE_SR_BAUDRATE_SHIFT;
    CfgReg = BaudRate << AL_AXI_UART_LITE_CR_BAUDRATE_SHIFT |
             BIT(AL_AXI_UART_LITE_CR_ENABLE_INT_SHIFT);
    AlAxiUartLite_SetCfgReg(Uart->HwConfig.BaseAddress, CfgReg);

    return AL_OK;
}

/**
 * This function clears the UART device receive buffer.
 *
 * @param Uart Pointer to the UART device structure.
 *
 * @return AL_OK if successful, error code otherwise.
 */
static AL_VOID AlAxiUartLite_Dev_RecvDataHandler(Al_AxiUartLite_DevStruct *Uart)
{
    while ((AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress) & BIT(AL_AXI_UART_LITE_RX_FIFO_HAS_DATA)) &&
           (Uart->RecvBuffer.HandledCnt < Uart->RecvBuffer.RequestedCnt)) {
        Uart->RecvBuffer.BufferPtr[Uart->RecvBuffer.HandledCnt] = AlAxiUartLite_RecvData(Uart->HwConfig.BaseAddress);
        Uart->RecvBuffer.HandledCnt ++;
    }

    if (Uart->RecvBuffer.HandledCnt == Uart->RecvBuffer.RequestedCnt) {
        if (Uart->EventCallBack) {
            Al_AxiUartLite_EventStruct UartEvent = {
                .Events        = AL_AXI_UART_LITE_EVENT_RECEIVE_DONE,
                .EventData     = Uart->RecvBuffer.HandledCnt
            };
            (*Uart->EventCallBack)(UartEvent, Uart->EventCallBackRef);
        }
    }
}

/**
 * This function sends data over the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 *
 * @return AL_OK if successful, error code otherwise.
 */
static AL_VOID AlAxiUartLite_Dev_SendDataHandler(Al_AxiUartLite_DevStruct *Uart)
{

    while ((!(AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress) & BIT(AL_AXI_UART_LITE_TX_FIFO_FULL))) &&
        (Uart->SendBuffer.HandledCnt < Uart->SendBuffer.RequestedCnt)) {
        AlAxiUartLite_SendData(Uart->HwConfig.BaseAddress, Uart->SendBuffer.BufferPtr[Uart->SendBuffer.HandledCnt]);
        Uart->SendBuffer.HandledCnt ++;
    }

    if (Uart->SendBuffer.HandledCnt == Uart->SendBuffer.RequestedCnt) {
        if (Uart->EventCallBack) {
            Al_AxiUartLite_EventStruct UartEvent = {
                .Events        = AL_AXI_UART_LITE_EVENT_SEND_DONE,
                .EventData     = Uart->SendBuffer.HandledCnt
            };
            (*Uart->EventCallBack)(UartEvent, Uart->EventCallBackRef);
        }
    }
}


/**
 * This function handles the receive error interrupt.
 *
 * @param Uart Pointer to the UART device structure.
 * @param UartStatus The status of the UART device.
 *
 * @return AL_OK if successful, error code otherwise.
 */
static AL_VOID AlAxiUartLite_Dev_RecvErrorHandler(Al_AxiUartLite_DevStruct *Uart, AL_U32 UartStatus)
{
    Al_AxiUartLite_EventStruct UartEvent = {
        .Events     = 0,
        .EventData  = 0,
    };

    UartEvent.EventData = Uart->RecvBuffer.HandledCnt;
    if (Uart->EventCallBack) {
        (*Uart->EventCallBack)(UartEvent, Uart->EventCallBackRef);
    }
}

/**
 *
 * This function is the main interrupt handler for the UART device. It checks the interrupt status and calls the
 * appropriate handler function for the specific interrupt condition. This includes handling receive data available,
 * transmit holding register empty, receive line status, bus busy detect, no interrupt pending, and modem status
 * interrupts.
 *
 * @param Instance Pointer to the UART device structure.
 *
 * @return None.
 */
AL_VOID AlAxiUartLite_Dev_IntrHandler(AL_VOID *Instance)
{
    Al_AxiUartLite_DevStruct *Uart = (Al_AxiUartLite_DevStruct *)Instance;
    AL_U32 UartStatus = AlAxiUartLite_GetStatus(Uart->HwConfig.BaseAddress);

    if (UartStatus & BIT(AL_AXI_UART_LITE_INT_EN)) {
        if ((UartStatus & BIT(AL_AXI_UART_LITE_RX_FIFO_HAS_DATA)) || (UartStatus & BIT(AL_AXI_UART_LITE_RX_FIFO_FULL))) {
            AlAxiUartLite_Dev_RecvDataHandler(Uart);
        }
        if (((UartStatus & BIT(AL_AXI_UART_LITE_TX_FIFO_EMPTY)) != 0)
            && (Uart->SendBuffer.RequestedCnt > 0)) {
            AlAxiUartLite_Dev_SendDataHandler(Uart);
        }
        if ((UartStatus & BIT(AL_AXI_UART_LITE_OVERRUN_ERR)) || (UartStatus & BIT(AL_AXI_UART_LITE_FRAME_ERR)) || (UartStatus & BIT(AL_AXI_UART_LITE_PARITY_ERR))) {
            AlAxiUartLite_Dev_RecvErrorHandler(Uart, UartStatus);
        }
    }
}

/**
 * This function registers the event callback function for the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 * @param Callback The event callback function.
 * @param CallbackRef A reference to the callback function.
 *
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUartLite_Dev_RegisterEventCallBack(Al_AxiUartLite_DevStruct *Uart, Al_AxiUartLite_EventCallBack Callback, AL_VOID *CallbackRef)
{
    AL_ASSERT((Uart != AL_NULL && Callback != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Uart->EventCallBack        = Callback;
    Uart->EventCallBackRef     = CallbackRef;

    return AL_OK;
}

/**
 * This function unregisters the event callback function for the UART device.
 *
 * @param Uart Pointer to the UART device structure.
 *
 * @return AL_OK if successful, error code otherwise.
 */
AL_S32 AlAxiUartLite_Dev_UnRegisterEventCallBack(Al_AxiUartLite_DevStruct *Uart)
{
    AL_ASSERT((Uart != AL_NULL), AL_AXI_UART_LITE_ERR_ILLEGAL_PARAM);

    Uart->EventCallBack = (Al_AxiUartLite_EventCallBack)AL_NULL;

    return AL_OK;
}
