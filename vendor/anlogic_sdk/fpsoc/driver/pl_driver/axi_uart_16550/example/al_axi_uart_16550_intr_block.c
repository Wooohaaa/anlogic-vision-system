/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_axi_uart_16550_intr_block.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2025-12-15
 * @brief   AXI UART 16550 interrupt blocking mode test
 * @example al_axi_uart_16550_intr_block.c
 */

/***************************** Include Files *********************************/
#include "al_axi_uart_16550_hal.h"
#include <string.h>
#include <stdlib.h>

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_AXI_UART_16550_TEST_DEVID    0
#define BUF_SIZE                        16

/************************** Variable Definitions *****************************/
static AlAxiUart16550_InitStruct InitStruct = {
        .BaudRate           = 115200,
        .Parity             = AlAxiUart16550_NO_PARITY,
        .WordLength         = AlAxiUart16550_CHAR_8BITS,
        .StopBits           = AlAxiUart16550_STOP_1BIT,
        .CharTimeoutEnable  = AL_TRUE
    };

/************************** Function Prototypes ******************************/
static AL_S32 AlAxiUart16550_Test_RecvAndSendIntrBlock(AL_VOID);


/**
 * The main entry point for the AXI UART 16550 interrupt blocking mode test application.
 * It initializes the system, runs the AXI UART 16550 interrupt blocking test, and reports
 * the result. The test demonstrates polled data reception and transmission with timeout
 * mechanism, continuously receiving data and echoing it back in a blocking mode.
 *
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "AXI UART 16550 recv and send interrupt blocked test\r\n");

    Soc_PsPlInit();

    Ret = AlAxiUart16550_Test_RecvAndSendIntrBlock();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 recv and send interrupt blocked test failed\r\n");
        return Ret;
    }

    return Ret;
}

/**
 * This function tests the AXI UART 16550 interrupt blocking mode functionality. It initializes
 * the AXI UART 16550 device, allocates a buffer for data reception, and enters an infinite loop
 * that continuously receives data and echoes it back. The test uses blocking mode for both
 * receive and send operations with timeout mechanism. The test demonstrates polled UART
 * communication with timeout handling and continuous echo operation.
 *
 * @return Returns AL_OK on success, or an error code on failure.
 */
static AL_S32 AlAxiUart16550_Test_RecvAndSendIntrBlock(AL_VOID)
{
    AlAxiUart16550_HalStruct *UartHandle;
    AL_U32 ReceiveSize;

    AL_U8 *Data = (AL_U8 *)malloc(BUF_SIZE);
    memset(Data, 0, (sizeof(AL_U8) * BUF_SIZE));

    AL_S32 Ret = AlAxiUart16550_Hal_Init(&UartHandle, AL_AXI_UART_16550_TEST_DEVID, &InitStruct, AL_NULL);
    if (Ret != AL_OK){
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 Init error:0x%x\r\n", Ret);
        free(Data);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AL_LOG(AL_LOG_LEVEL_INFO, "Send more than %d Bytes data and will show back\r\n", BUF_SIZE);
    while (1) {
        Ret = AlAxiUart16550_Hal_RecvDataBlock(UartHandle, Data, BUF_SIZE, &ReceiveSize, AL_WAITFOREVER);
        if (ReceiveSize > 0) {
            Ret = AlAxiUart16550_Hal_SendDataBlock(UartHandle, Data, ReceiveSize, AL_WAITFOREVER);
            if (Ret != AL_OK) {
                AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 send data error\r\n");
                break;
            }
        }
    }

    free(Data);

    return Ret;
}

