/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_axi_uart_16550_poll_nonblock.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   AXI UART 16550 polling non-blocking mode test demonstrating timed data reception
 *          and transmission with timeout mechanism
 * @example al_axi_uart_16550_poll_nonblock.c
 */

/***************************** Include Files *********************************/
#include <string.h>
#include <stdlib.h>
#include "al_axi_uart_16550_hal.h"

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_AXI_UART_16550_TEST_DEVID    0
#define BUF_SIZE                        16

/**************************** Type Definitions *******************************/

/************************** Variable Definitions *****************************/
static AlAxiUart16550_InitStruct InitStruct = {
        .BaudRate           = 115200,
        .Parity             = AlAxiUart16550_NO_PARITY,
        .WordLength         = AlAxiUart16550_CHAR_8BITS,
        .StopBits           = AlAxiUart16550_STOP_1BIT,
        .CharTimeoutEnable  = AL_TRUE
    };

/************************** Function Prototypes ******************************/
static AL_S32 AlAxiUart16550_Test_RecvAndSendPollNonBlock(AL_VOID);


/**
 * The main entry point for the AXI UART 16550 polling non-blocking mode test application.
 * It initializes the system, runs the AXI UART 16550 polling non-blocking test, and reports
 * the result. The test demonstrates timed data reception and transmission with timeout
 * mechanism, allowing partial data transfer within specified timeout periods.
 *
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "AXI UART 16550 recv and send polling nonblocked test\r\n");

    Soc_PsPlInit();

    Ret = AlAxiUart16550_Test_RecvAndSendPollNonBlock();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 recv and send polling nonblocked test failed\r\n");
        return Ret;
    }

    return Ret;
}

/**
 * This function tests the AXI UART 16550 polling non-blocking mode functionality. It initializes
 * the AXI UART 16550 device, allocates a buffer for data reception, and enters an infinite loop
 * that continuously receives and transmits data with timeout control. The test uses non-blocking
 * polling mode for both receive and send operations, allowing partial data transfer within the
 * specified timeout period. The test demonstrates timed UART communication with timeout handling
 * and continuous echo operation.
 *
 * @return Returns AL_OK on success, or an error code on failure.
 */
static AL_S32 AlAxiUart16550_Test_RecvAndSendPollNonBlock(AL_VOID)
{
    AlAxiUart16550_HalStruct *UartHandle;
    AL_U32 RecvActualSize;
    AL_U32 SendActualSize;
    AL_U32 Timeout = 3000;
    AL_S32 Ret = AL_OK;

    AL_U8 *Data = (AL_U8 *)malloc(BUF_SIZE);
    memset(Data, 0, (sizeof(AL_U8) * BUF_SIZE));

    Ret = AlAxiUart16550_Hal_Init(&UartHandle, AL_AXI_UART_16550_TEST_DEVID, &InitStruct, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 Init error:0x%x\r\n", Ret);
        free(Data);
        return Ret;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Send more than %d Bytes data and will show back\r\n", BUF_SIZE);
    AL_LOG(AL_LOG_LEVEL_INFO, "If the number of data is less than %d, it will be displayed after %d ms\r\n", BUF_SIZE, Timeout);

    while (1) {
        Ret = AlAxiUart16550_Hal_RecvDataPollingNonBlock(UartHandle, Data, BUF_SIZE, &RecvActualSize, Timeout);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 receive data error\r\n");
            break;
        }

        Ret = AlAxiUart16550_Hal_SendDataPollingNonBlock(UartHandle, Data, RecvActualSize, &SendActualSize, Timeout);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 receive data error\r\n");
            break;
        }
    }

    free(Data);

    return Ret;
}
