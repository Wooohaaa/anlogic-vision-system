/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @brief This example demonstrates how to use the spi-nor driver with user params.
 * @example al_spi_nor_user_params_example.c
 */

#include <stdlib.h>
#include "al_spi_nor.h"

#define TEST_ADDR 0x00
#define TEST_SIZE 0x1000

#ifndef CONTROLLER_TYPE_FOR_EXAMPLE
#define CONTROLLER_TYPE_FOR_EXAMPLE    (AL_CONTROLLER_PS_QSPI)
#endif

const AlSpiNorInfo UserFlashInfoList[] =
{
    {"GD25LB256E", {0xC8, 0x67, 0x19}, 64 * 1024, 512, 256, 0x20, 0x30,
        AL_SPI_NOR_FLAG_DUAL | AL_SPI_NOR_FLAG_QUAD | AL_SPI_NOR_FLAG_QE_MODE0 | AL_SPI_NOR_FLAG_WRAP_MODE2},
    {"MT25QU128ABA", {0x20, 0xBB, 0x18}, 64 * 1024, 256, 256, 0x00, 0x10,
        AL_SPI_NOR_FLAG_DUAL | AL_SPI_NOR_FLAG_QUAD | AL_SPI_NOR_FLAG_QE_MODE0 | AL_SPI_NOR_FLAG_WRAP_MODE3},
    {"MX25L25645G", {0xC2, 0x20, 0x19}, 64 * 1024, 512, 256, 0x5A, 0xFF,
        AL_SPI_NOR_FLAG_DUAL | AL_SPI_NOR_FLAG_QUAD | AL_SPI_NOR_FLAG_QE_MODE2 | AL_SPI_NOR_FLAG_WRAP_MODE4},
};
const AL_U32 UserFlashInfoListSize = sizeof(UserFlashInfoList) / sizeof(UserFlashInfoList[0]);

/**
 * @return AL_S32 Process execution status
 * @retval AL_OK All operations completed successfully
 * @retval 0 Error occurred during any operation phase
 *
 * @details Execution sequence:
 * 1. Hardware configuration setup
 * 2. Controller initialization with custom parameters
 * 3. Pre-write sector erase and verification
 * 4. Test pattern programming and validation
 * 5. Data integrity cross-check
 *
 * @note Critical configuration parameters:
 * - TEST_SIZE: Defined data buffer size
 * - TEST_ADDR: Target flash memory address
 * - CONTROLLER_TYPE_FOR_EXAMPLE: Hardware-specific controller ID
 * - UserFlashInfoList: Custom flash configuration table
 */
AL_S32 main(AL_VOID)
{
    AL_U32 ControllerType = CONTROLLER_TYPE_FOR_EXAMPLE;
    AL_U32 DevId = 0;
    AL_S32 Status;
    AL_U32 Index = 0;
    AlSpiNor SpiNor = {
        .UserParams = {
            .IsForceStandardMode = AL_TRUE,
            .UserFlashInfoList = UserFlashInfoList,
            .UserFlashInfoListSize = UserFlashInfoListSize,
        },
    };

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
