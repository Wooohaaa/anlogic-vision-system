/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_uart_nonblocked.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   uart poll nonblock example
 * @example al_uart_poll_nonblock.c
 */

/***************************** Include Files *********************************/
#include <string.h>
#include <stdlib.h>
#include "al_uart_hal.h"

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/
#define BUF_SIZE 16
#define AL_UART_TIME_OUT_MS 10000
#define AL_UART_DEVID 1

/************************** Variable Definitions *****************************/

/***************** Macros (Inline Functions) Definitions *********************/

/**************************** Type Definitions *******************************/

/************************** Variable Definitions *****************************/
static AL_UART_InitStruct UART_InitStruct = {
        .BaudRate           = 115200,
        .WordLength         = AL_UART_CHAR_8BITS,
        .StopBits           = AL_UART_STOP_1BIT,
        .Parity             = AL_UART_NO_PARITY,
        .HwFlowCtl          = AL_FALSE,
        .CharTimeoutEnable  = AL_TRUE
    };


/************************** Function Prototypes ******************************/
static AL_S32 AlUart_Test_RecvAndSendPollNonBlock(AL_VOID);

/************************** Function Definitions ******************************/
/**
 * This function initializes the UART nonblocked test, executes the test by calling AlUart_Test_RecvAndSendPollNonBlock,
 * and logs the result. If the test fails, it logs an error message and returns the error code. Otherwise,
 * it logs a success message and returns AL_OK.
 *
 * @return AL_OK on success, or an error code on failure.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "Uart recv and send polling nonblocked test\r\n");

    Ret = AlUart_Test_RecvAndSendPollNonBlock();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Uart recv and send polling nonblocked test failed\r\n");
        return Ret;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");
    AL_LOG(AL_LOG_LEVEL_INFO, "Uart recv and send polling nonblocked test success\r\n");
    return Ret;
}

/**
 * This function initializes the UART hardware with predefined configurations, then enters a loop where it
 * waits to receive data. Once data is received, it sends the data back. The function tests the UART's ability
 * to receive and send data in a blocking manner, using a timeout mechanism. If any operation fails, it logs
 * an error message and returns the error code.
 *
 * @return AL_OK on success, or an error code on failure.
 */
static AL_S32 AlUart_Test_RecvAndSendPollNonBlock(AL_VOID)
{
    AL_UART_HalStruct *UartHandle;
    AL_U32 RecvActualSize;
    AL_U32 SendActualSize;
    AL_U32 Timeout = 3000;

    AL_U8 *Data = (AL_U8 *)malloc(BUF_SIZE);

    memset(Data, 0, (sizeof(AL_U8) * BUF_SIZE));

    AL_S32 Ret = AlUart_Hal_Init(&UartHandle, AL_UART_DEVID, &UART_InitStruct,  (AL_Uart_EventCallBack)AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Uart Hal Init error:0x%x\r\n", Ret);
        free(Data);
        return Ret;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Send more than %d Bytes data and will show back\r\n", BUF_SIZE);
    AL_LOG(AL_LOG_LEVEL_INFO, "If the number of data is less than %d, it will be displayed after %d ms\r\n", BUF_SIZE, Timeout);

    while (1) {
        AlUart_Hal_RecvDataPollingNonBlock(UartHandle, Data, BUF_SIZE, &RecvActualSize, Timeout);

        AlUart_Hal_SendDataPollingNonBlock(UartHandle, Data, RecvActualSize, &SendActualSize, Timeout);
    }

    free(Data);

    return Ret;
}
