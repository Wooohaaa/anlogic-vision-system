/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_axi_uart_16550_ioctl_baud_test.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2025-12-30
 * @brief   AXI UART 16550 IOCTL baud rate test application demonstrating baud rate configuration
 *          and validation through polling mode communication tests
 * @example al_axi_uart_16550_ioctl_baud_test.c
 */

#include "al_axi_uart_16550_hal.h"
#include <string.h>
#include <stdlib.h>

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_AXI_UART_16550_TEST_DEVID    0
#define TEST_BUF_SIZE                   16

/************************** Variable Definitions *****************************/
static AlAxiUart16550_InitStruct InitStruct = {
    .BaudRate           = 115200,
    .Parity             = AlAxiUart16550_NO_PARITY,
    .WordLength         = AlAxiUart16550_CHAR_8BITS,
    .StopBits           = AlAxiUart16550_STOP_1BIT,
    .CharTimeoutEnable  = AL_TRUE
};

#define BUF_SIZE                        16

/**
 * This function performs a basic polling mode receive and send test for the AXI UART 16550 device.
 * It allocates a buffer, receives data from the UART, and immediately sends the same data back
 * to demonstrate successful communication at the currently configured baud rate. The test uses
 * blocking polling mode for both receive and send operations.
 *
 * @param UartHandle Pointer to the initialized AXI UART 16550 device handle.
 * @return Returns AL_OK on success, or an error code on failure.
 */
static AL_S32 AlAxiUart16550_Test_RecvAndSendPollBlock(AlAxiUart16550_HalStruct *UartHandle)
{
    AL_U8 *Data = (AL_U8 *)malloc(BUF_SIZE);
    memset(Data, 0, (sizeof(AL_U8) * BUF_SIZE));

    AL_S32 Ret;
    AL_LOG(AL_LOG_LEVEL_INFO, "  >>> Send %d Bytes data and will show back\r\n", BUF_SIZE);

    Ret = AlAxiUart16550_Hal_RecvDataPolling(UartHandle, Data, BUF_SIZE);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 receive data error\r\n");
        free(Data);
        return Ret;
    }

    Ret = AlAxiUart16550_Hal_SendDataPolling(UartHandle, Data, BUF_SIZE);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 send data error\r\n");
        free(Data);
        return Ret;
    }

    free(Data);
    return Ret;
}

/**
 * This function comprehensively tests the baud rate configuration functionality of the AXI UART 16550 device.
 * It iterates through multiple standard baud rates (9600, 19200, 38400, 57600, 115200, 230400), configures
 * each rate using IOCTL commands, verifies the configuration by reading back the baud rate, and performs
 * a communication test at each configured rate. The test demonstrates the proper functioning of both
 * AL_AXI_UART_16550_IOCTL_SET_BAUD_RATE and AL_AXI_UART_16550_IOCTL_GET_BAUD_RATE IOCTL commands.
 *
 * @param UartHandle Pointer to the initialized AXI UART 16550 device handle.
 * @return Returns AL_OK if all baud rate tests pass successfully, or an error code on failure.
 */
static AL_S32 Test_BaudRate_Configuration(AlAxiUart16550_HalStruct *UartHandle)
{
    AlAxiUart16550_IoctlParamUnion IoctlParam;
    AL_U32 TestBaudRates[] = {9600, 19200, 38400, 57600, 115200, 230400};
    AL_U32 BaudRateCount = sizeof(TestBaudRates) / sizeof(TestBaudRates[0]);
    AL_S32 Ret = AL_OK;
    AL_U32 i;

    AL_LOG(AL_LOG_LEVEL_INFO, "Starting Baud Rate Configuration Test...\r\n");

    for (i = 0; i < BaudRateCount; i++) {
        AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");
        AL_LOG(AL_LOG_LEVEL_INFO, "--- Test Step %d/%d ---\r\n", i+1, BaudRateCount);

        /* Set new baud rate using IOCTL command */
        IoctlParam.BaudRate = TestBaudRates[i];
        Ret = AlAxiUart16550_Hal_IoCtl(UartHandle, AL_AXI_UART_16550_IOCTL_SET_BAUD_RATE, &IoctlParam);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "  Set baud rate to %d FAILED: 0x%x\r\n", TestBaudRates[i], Ret);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "  Baud rate set to %d.\r\n", TestBaudRates[i]);

        /* Verify baud rate configuration by reading back the current setting */
        Ret = AlAxiUart16550_Hal_IoCtl(UartHandle, AL_AXI_UART_16550_IOCTL_GET_BAUD_RATE, &IoctlParam);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "  Get baud rate FAILED: 0x%x\r\n", Ret);
            return Ret;
        }

        AL_LOG(AL_LOG_LEVEL_INFO, "  Baud rate verification (get=%d).\r\n", IoctlParam.BaudRate);

        /* Prompt user to adjust serial tool baud rate for communication test */
        AL_LOG(AL_LOG_LEVEL_INFO, "  >>> Please change your serial tool baud rate to %d now.\r\n", TestBaudRates[i]);

        /* Perform communication test at the newly configured baud rate */
        Ret = AlAxiUart16550_Test_RecvAndSendPollBlock(UartHandle);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "  Echo test at %d baud FAILED: 0x%x\r\n", TestBaudRates[i], Ret);
            return Ret;
        }

        AL_LOG(AL_LOG_LEVEL_INFO, "  Baud rate %d test PASSED.\r\n", TestBaudRates[i]);
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Baud rate configuration test completed successfully.\r\n");
    return AL_OK;
}

/**
 * The main entry point for the AXI UART 16550 IOCTL baud rate test application.
 * It initializes the system hardware and the AXI UART 16550 device, then executes
 * the comprehensive baud rate configuration test. The application validates the
 * IOCTL interface for baud rate control and demonstrates proper UART communication
 * at multiple standard baud rates through polling mode tests.
 *
 * @return Returns AL_OK if all tests pass successfully, or an error code on failure.
 */
AL_S32 main(AL_VOID)
{
    AlAxiUart16550_HalStruct *UartHandle;
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "=== AXI UART 16550 Baud Rate IOCTL Test Start ===\r\n");
    AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");

    /* Initialize system hardware */
    Soc_PsPlInit();

    /* Initialize AXI UART 16550 device with default parameters */
    Ret = AlAxiUart16550_Hal_Init(&UartHandle, AL_AXI_UART_16550_TEST_DEVID, &InitStruct, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AXI UART 16550 Init error:0x%x\r\n", Ret);
        return Ret;
    }

    /* Execute comprehensive baud rate configuration test */
    Ret = Test_BaudRate_Configuration(UartHandle);
    if (Ret == AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "\r\n");
        AL_LOG(AL_LOG_LEVEL_INFO, "=== All tests PASSED! ===\r\n");
    } else {
        AL_LOG(AL_LOG_LEVEL_ERROR, "=== Test FAILED: 0x%x ===\r\n", Ret);
    }

    return Ret;
}
