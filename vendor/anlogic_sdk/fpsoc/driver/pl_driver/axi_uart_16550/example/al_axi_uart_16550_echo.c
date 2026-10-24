/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_axi_uart_16550_echo.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2025-12-15
 * @brief   AXI UART 16550 echo example demonstrating interrupt-driven receive and transmit operations
 * @example al_axi_uart_16550_echo.c
 */

#include "al_axi_uart_16550_hal.h"
#include <string.h>
#include <stdlib.h>

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_AXI_UART_16550_TEST_DEVID    0
#define BUF_SIZE                       (2 * 1024)

/**************************** Type Definitions *******************************/

/************************** Variable Definitions *****************************/
static AlAxiUart16550_HalStruct AlAxiUart16550Handle[AL_AXI_UART_16550_NUM_INSTANCE];

static AlAxiUart16550_InitStruct InitStruct = {
        .BaudRate           = 115200,
        .Parity             = AlAxiUart16550_NO_PARITY,
        .WordLength         = AlAxiUart16550_CHAR_8BITS,
        .StopBits           = AlAxiUart16550_STOP_1BIT,
        .CharTimeoutEnable  = AL_TRUE
};

/**
 * This function handles the reception of data from the AXI UART 16550 device specified by the Uart parameter.
 * It continuously reads data from the UART's RX FIFO and stores it in a ring buffer until the FIFO is empty.
 * Each time data is received, it enables the transmit interrupt to trigger transmission of the received data.
 * The buffer pointer wraps around when it reaches the end of the buffer. The function ensures that the transmitter
 * is not already busy before enabling the transmit interrupt to avoid redundant interrupt triggering.
 *
 * @param Uart Pointer to the AXI UART 16550 device structure.
 * @param CharTimeoutIntr Boolean flag indicating if a character timeout interrupt has occurred.
 */
static AL_VOID AlAxiUart16550_Dev_RecvDataHandler(AlAxiUart16550_DevStruct *Uart, AL_BOOL CharTimeoutIntr)
{
    while ((AlAxiUart16550_ll_IsRxDataReady(Uart->HwConfig.BaseAddress) == AL_TRUE)) {
        // Store the received byte into the receive buffer
        Uart->RecvBuffer.BufferPtr[Uart->RecvBuffer.HandledCnt] = (AL_U8)AlAxiUart16550_ll_RecvByte(Uart->HwConfig.BaseAddress);
        Uart->RecvBuffer.HandledCnt ++;
        // Wrap around the index if it exceeds the buffer size
        if (Uart->RecvBuffer.HandledCnt >= Uart->RecvBuffer.RequestedCnt) {
            Uart->RecvBuffer.HandledCnt = 0;
        }

        // Enable transmit interrupt
        if(!AlAxiUart16550_Dev_IsTxBusy(Uart)) {
            AlAxiUart16550_Dev_SetTxBusy(Uart);
            AlAxiUart16550_ll_SetTxIntr(Uart->HwConfig.BaseAddress, AL_FUNC_ENABLE);
        }
    }
}

/**
 * This function handles the transmission of data through the AXI UART 16550 device specified by the Uart parameter.
 * It calculates the number of bytes available in the ring buffer, taking into account wrap-around scenarios,
 * and then transmits up to the FIFO depth or the available bytes, whichever is smaller. The function updates
 * the send pointer correctly with wrap-around handling. If the buffer is empty, it stops the transmission process.
 *
 * @param Uart Pointer to the AXI UART 16550 device structure.
 */
static AL_VOID AlAxiUart16550_Dev_SendDataHandler(AlAxiUart16550_DevStruct *Uart)
{
    AL_U32 FifoDepth  = Uart->HwConfig.FifoDepth;
    AL_U32 buffer_size = Uart->RecvBuffer.RequestedCnt;  // Total size of the buffer

    // Case 1: The buffer is empty, nothing to send
    if (Uart->SendBuffer.HandledCnt == Uart->RecvBuffer.HandledCnt) {
        AlAxiUart16550_Dev_StopSend(Uart);
        return;
    }

    // Case 2: Calculate the correct number of remaining bytes (handling wrap-around)
    AL_U32 data_available = 0;

    if (Uart->RecvBuffer.HandledCnt > Uart->SendBuffer.HandledCnt) {
        // Sub-case A: Write pointer is behind the read pointer, no wrap-around occurred
        // Remaining bytes = Write pointer - Read pointer
        data_available = Uart->RecvBuffer.HandledCnt - Uart->SendBuffer.HandledCnt;
    } else {
        // Sub-case B: Write pointer is in front of the read pointer, wrap-around occurred
        // Remaining bytes = (Buffer end - Read pointer) + Write pointer
        data_available = (buffer_size - Uart->SendBuffer.HandledCnt) + Uart->RecvBuffer.HandledCnt;
    }

    // Number of bytes to send this time = min(Remaining bytes, FIFO depth)
    AL_U32 SendCount = (data_available < FifoDepth) ? data_available : FifoDepth;

    // Send data
    for (AL_U32 i = 0; i < SendCount; i++) {
        AlAxiUart16550_ll_SendByte(Uart->HwConfig.BaseAddress,
                                  Uart->RecvBuffer.BufferPtr[Uart->SendBuffer.HandledCnt]);
        // Update the send pointer (read pointer), correctly handling wrap-around
        Uart->SendBuffer.HandledCnt = (Uart->SendBuffer.HandledCnt + 1) % buffer_size;
    }
}

#define AL_AXI_UART_16550_INTR_MODEM_STATUS(Status)           (Status == AlAxiUart16550_MODEM_STATUS)
#define AL_AXI_UART_16550_NO_INTER_PEDING(Status)             (Status == AlAxiUart16550_NO_INTERRUPT_PENDING)
#define AL_AXI_UART_16550_INTR_THRE_EMPTY(Status)             (Status == AlAxiUart16550_THR_EMPTY)
#define AL_AXI_UART_16550_INTR_RECV_AVAIL(Status)             (Status == AlAxiUart16550_RECEIVED_DATA_AVAILABLE)
#define AL_AXI_UART_16550_INTR_RECV_LINE_STATUS(Status)       (Status == AlAxiUart16550_RECEIVER_LINE_STATUS)
#define AL_AXI_UART_16550_INTR_CHAR_RECEV_TIMEOUT(Status)     (Status == AlAxiUart16550_CHARACTER_TIMEOUT)

/**
 * This function is the interrupt service routine for AXI UART 16550 echo operations. It checks the interrupt
 * status of the UART device and calls the appropriate handler function. It handles three types of
 * interrupts: received data available, character timeout, and THRE (Transmit Holding Register Empty).
 * The function is registered as the interrupt handler for the AXI UART 16550 device.
 *
 * @param Instance Pointer to the AXI UART 16550 device instance passed as a void pointer.
 */
AL_VOID AlAxiUart16550_Dev_IntrEchoHandler(AL_VOID *Instance)
{
    AlAxiUart16550_DevStruct *Uart = (AlAxiUart16550_DevStruct *)Instance;
    AlAxiUart16550_IntrEnum IntrStatus = AlAxiUart16550_ll_GetIntrStatus(Uart->HwConfig.BaseAddress);

    if (AL_AXI_UART_16550_INTR_RECV_AVAIL(IntrStatus) || AL_AXI_UART_16550_INTR_CHAR_RECEV_TIMEOUT(IntrStatus)) {
        AlAxiUart16550_Dev_RecvDataHandler(Uart, AL_AXI_UART_16550_INTR_CHAR_RECEV_TIMEOUT(IntrStatus));
    } else if (AL_AXI_UART_16550_INTR_THRE_EMPTY(IntrStatus)) {
        AlAxiUart16550_Dev_SendDataHandler(Uart);
    }
}

/**
 * This function initializes the AXI UART 16550 device for echo operation. It configures the UART hardware
 * according to the provided initialization structure, registers the interrupt handler, and sets up
 * the device for interrupt-driven receive and transmit operations. The function returns a handle
 * to the initialized AXI UART 16550 device.
 *
 * @param Handle Pointer to the pointer where the AXI UART 16550 handle will be stored.
 * @param DevId The device ID of the AXI UART 16550 to initialize.
 * @param InitConfig Pointer to the AXI UART 16550 initialization structure containing configuration parameters.
 * @param Callback Optional callback function for AXI UART 16550 events. Set to AL_NULL if not used.
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiUart16550_Hal_InitEcho(AlAxiUart16550_HalStruct **Handle, AL_U32 DevId,
                       AlAxiUart16550_InitStruct *InitConfig, AlAxiUart16550_EventCallBack Callback)
{
    AL_S32 Ret = AL_OK;
    AlAxiUart16550_HwConfigStruct *HwConfig = NULL;

    AL_ASSERT((Handle != AL_NULL), AL_AXI_UART_16550_ERR_ILLEGAL_PARAM);

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

    (AL_VOID)AlIntr_RegHandler((*Handle)->Dev.HwConfig.IntrId, AL_NULL, AlAxiUart16550_Dev_IntrEchoHandler, &(*Handle)->Dev);


    return Ret;
}

/**
 * This function tests the AXI UART 16550 echo functionality. It initializes the AXI UART 16550 device for echo operation,
 * allocates a buffer for data reception, and starts receiving data. The function runs indefinitely,
 * echoing back any data received. The test demonstrates interrupt-driven AXI UART 16550 communication with
 * echo capability.
 *
 * @return Returns AL_OK on success, or an error code on failure.
 */
static AL_S32 AlUart_Test_Echo(AL_VOID)
{
    AL_S32 Ret = AL_OK;
    AlAxiUart16550_HalStruct *UartHandle;

    AL_U8 *Data = (AL_U8 *)malloc(BUF_SIZE);
    memset(Data, 0, (sizeof(AL_U8) * BUF_SIZE));

    Ret = AlAxiUart16550_Hal_InitEcho(&UartHandle, AL_AXI_UART_16550_TEST_DEVID, &InitStruct, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 Init error:0x%x\r\n", Ret);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AL_LOG(AL_LOG_LEVEL_INFO, "Send less than %d Bytes data and will show back\r\n", BUF_SIZE);

    Ret = AlAxiUart16550_Hal_RecvData(UartHandle, Data, BUF_SIZE);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 recv error:0x%x\r\n", Ret);
        return Ret;
    }

    while (1);
}

/**
 * The main entry point for the AXI UART 16550 echo test application. It initializes the system,
 * runs the AXI UART 16550 echo test, and reports the result. The test demonstrates basic AXI UART 16550
 * interrupt-driven echo functionality with a ring buffer implementation.
 *
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "AXI UART 16550 echo test\r\n");

    Soc_PsPlInit();

    Ret = AlUart_Test_Echo();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 test failed\r\n");
        return Ret;
    }

    return Ret;
}
