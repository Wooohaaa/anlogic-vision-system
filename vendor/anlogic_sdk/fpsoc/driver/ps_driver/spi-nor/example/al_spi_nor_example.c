/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @brief This example demonstrates how to use the spi-nor driver.
 * @example al_spi_nor_example.c
 */

#include <stdlib.h>
#include "al_spi_nor.h"

#define TEST_ADDR 0x00
#define TEST_SIZE 0x1000

#ifndef CONTROLLER_TYPE_FOR_EXAMPLE
#define CONTROLLER_TYPE_FOR_EXAMPLE    (AL_CONTROLLER_PS_QSPI)
#endif


/**
 * @brief Main function for SPI NOR Flash operation example
 *
 * @return AL_S32
 * @retval AL_OK if all operations succeed
 * @retval 0 if any operation fails
 *
 * @details Execution flow:
 * 1. Generate random test pattern
 * 2. Initialize SPI NOR controller
 * 3. Erase target sector
 * 4. Verify erase operation
 * 5. Program test data
 * 6. Verify programmed data
 *
 * @note The following macros must be defined:
 * - TEST_SIZE: Data buffer size
 * - TEST_ADDR: Target flash address
 * - CONTROLLER_TYPE_FOR_EXAMPLE: Controller identifier
 */
AL_S32 main(AL_VOID)
{
    AlSpiNor SpiNor = { 0 };
    AL_U32 ControllerType = CONTROLLER_TYPE_FOR_EXAMPLE;
    AL_U32 DevId = 0;
    AL_S32 Status;
    AL_U32 Index = 0;

    AL_U8 SendData[TEST_SIZE] = { 0 };
    AL_U8 RecvData[TEST_SIZE] = { 0 };

    AL_LOG(AL_LOG_LEVEL_INFO, "Start spi-nor example\r\n");

    for (Index = 0; Index < TEST_SIZE; Index++) {
        SendData[Index] = rand() % 256;
    }

    Status = AlSpiNor_Init(&SpiNor, ControllerType, DevId);
    if (Status != AL_OK) {
        goto EXAMPLE_FAIL;
    }

    Status = AlSpiNor_Erase(&SpiNor, TEST_ADDR, SpiNor.EraseSize);
    if (Status != AL_OK) {
        goto EXAMPLE_FAIL;
    }

    Status = AlSpiNor_Read(&SpiNor, TEST_ADDR, TEST_SIZE, RecvData);
    if (Status != AL_OK) {
        goto EXAMPLE_FAIL;
    }

    for (Index = 0; Index < TEST_SIZE; Index++) {
        if (RecvData[Index] != 0xFF) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Data error after sector erase\r\n");
            goto EXAMPLE_FAIL;
        }
    }

    Status = AlSpiNor_Write(&SpiNor, TEST_ADDR, TEST_SIZE, SendData);
    if (Status != AL_OK) {
        goto EXAMPLE_FAIL;
    }

    Status = AlSpiNor_Read(&SpiNor, TEST_ADDR, TEST_SIZE, RecvData);
    if (Status != AL_OK) {
        goto EXAMPLE_FAIL;
    }

    for (Index = 0; Index < TEST_SIZE; Index++) {
        if (RecvData[Index] != SendData[Index]) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Data error after write date at Index %d\r\n", Index);
            goto EXAMPLE_FAIL;
        }
    }

    AL_LOG(AL_LOG_LEVEL_ERROR, "Spi-nor example success\r\n");
    return AL_OK;

EXAMPLE_FAIL:
    AL_LOG(AL_LOG_LEVEL_ERROR, "Spi-nor example failed\r\n");

    return 0;
}