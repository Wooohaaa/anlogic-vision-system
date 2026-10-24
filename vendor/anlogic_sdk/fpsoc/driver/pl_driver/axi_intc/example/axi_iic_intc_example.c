/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_axi_intc_hal.h"
#include "al_axi_iic_hal.h"

#include <string.h>

#define AL_AXI_INTC_DEV_ID      0
#define BUFFER_SIZE             16

#define TRANSFER_METHOD               1  // 1 = BLOCK, 0 = POLLING
#define TEST_ITERATIONS               10

#define EEPROM_DEVICE_ADDRESS         0x50
#define EEPROM_READ_WRITE_LENGTH      0x0a
#define EEPROM_READ_WRITE_START_ADDR  0x0000

AlAxiIic_HalStruct *IicHandle;

AlAxiIic_InitStruct IicInitConfig =
{
    .IIC_Mode           =   AL_AXI_IIC_MASTER           ,
    .IIC_AddressMode    =   AL_AXI_IIC_7BIT             ,
    .SpeedMode          =   AL_AXI_IIC_STANDARD_MODE    ,
    .SetupTime          =   300,
    .HoldTime           =   300,
};

AL_U8 RecvBuf[EEPROM_READ_WRITE_LENGTH] = {0x0};
AL_U8 SendBuf[EEPROM_READ_WRITE_LENGTH] = {
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa
};


AL_S32 CompareBuffers(AL_U8 *recv, AL_U8 *send, int length);
AL_S32 Eeprom_SendData(AlAxiIic_HalStruct *Handle, AL_U16 StartAddr, AL_U8 *SendBuff, AL_U32 SendSize);
AL_S32 Eeprom_RecvData(AlAxiIic_HalStruct *Handle, AL_U16 StartAddr, AL_U8 *RecvBuff, AL_U32 RecvSize);
AL_S32 Eeprom_Test();

AL_S32 Eeprom_SendData(AlAxiIic_HalStruct *Handle, AL_U16 StartAddr, AL_U8 *SendBuff, AL_U32 SendSize)
{
    AL_U32 Ret = AL_OK;
    AL_U8 TempBuf[EEPROM_READ_WRITE_LENGTH + 2];

    TempBuf[0] = (StartAddr >> 8) & 0xFF;
    TempBuf[1] = StartAddr & 0xFF;
    memcpy(&TempBuf[2], SendBuff, SendSize);

    Ret = AlAxiIic_Hal_MasterSendDataBlock(Handle, EEPROM_DEVICE_ADDRESS, TempBuf, SendSize + 2, AL_AXI_IIC_STOP, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Send Data failed %d\r\n", Ret);
        return Ret;
    }
    AlSys_MDelay(10);

    return Ret;
}

/**
 * This function reads data from the EEPROM using the specified IIC handle.
 *
 * @param Handle Pointer to the IIC HAL structure.
 * @param RecvBuff Pointer to the buffer to store received data.
 * @param StartReadAddr The start address to read from.
 * @param RecvSize The size of the data to receive.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 Eeprom_RecvData(AlAxiIic_HalStruct *Handle, AL_U16 StartAddr, AL_U8 *RecvBuff, AL_U32 RecvSize)
{
    AL_U32 Ret = AL_OK;
    AL_U8 AddrBuf[2];

    AddrBuf[0] = (StartAddr >> 8) & 0xFF;
    AddrBuf[1] = StartAddr & 0xFF;

    Ret = AlAxiIic_Hal_MasterSendDataBlock(Handle, EEPROM_DEVICE_ADDRESS, AddrBuf, 2, AL_AXI_IIC_NSTOP, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Send Address failed %d\r\n", Ret);
        return Ret;
    }
    AlSys_MDelay(1);
    Ret = AlAxiIic_Hal_MasterRecvDataBlock(Handle, EEPROM_DEVICE_ADDRESS, RecvBuff, RecvSize, AL_AXI_IIC_STOP, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Recv Data failed %d\r\n", Ret);
        return Ret;
    }

    return Ret;
}

/**
 * This function compares two buffers and returns whether they are equal.
 *
 * @param recv Pointer to the received buffer.
 * @param send Pointer to the sent buffer.
 * @param length The length of the buffers to compare.
 *
 * @return AL_S32 Returns AL_OK if the buffers are equal, or an error code if they are not.
 */
AL_S32 CompareBuffers(AL_U8 *recv, AL_U8 *send, int length)
{
    AL_U32 Ret = AL_OK;

    for (int i = 0; i < length; i++) {
        if (recv[i] != send[i]) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Mismatch at index %d: ReadBuf=0x%02x, WriteBuf=0x%02x\r\n", i, recv[i], send[i]);
            return AL_ERROR;
        }
    }

    return Ret;
}

AL_S32 Eeprom_Test()
{
    AL_U32 Ret = AL_OK;

    for (int i = 0; i < TEST_ITERATIONS; i++) {
        AL_LOG(AL_LOG_LEVEL_INFO, "=== AXI IIC EEPROM Test: Round %d ===\r\n", i + 1);
        memset(RecvBuf, 0, EEPROM_READ_WRITE_LENGTH);

        /* 1. write eeprom */
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Write Data start\r\n");
        Ret = Eeprom_SendData(IicHandle, EEPROM_READ_WRITE_START_ADDR, SendBuf, EEPROM_READ_WRITE_LENGTH);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Write Data failed %d\r\n", Ret);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Write Data done\r\n");

        /* 2. read eeprom */
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Read Data start\r\n");
        Ret = Eeprom_RecvData(IicHandle, EEPROM_READ_WRITE_START_ADDR, RecvBuf, EEPROM_READ_WRITE_LENGTH);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Read Data failed %d\r\n", Ret);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Read Data done\r\n");

        /* 3. check eeprom data*/
        Ret = CompareBuffers(RecvBuf, SendBuf, EEPROM_READ_WRITE_LENGTH);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "AXI IIC EEPROM Test: Round %d Failed\r\n", i + 1);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "AXI IIC EEPROM Test: Round %d Success\r\n", i + 1);
    }

    return Ret;
}

int main()
{
    AL_S32 Ret;

    Soc_PsPlInit();

    Ret = AlAxiIic_Hal_Init(&IicHandle, 0, &IicInitConfig, (AlAxiIic_EventCallBack)AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "AlAxiIic_Hal_Init failed %d", Ret);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    Eeprom_Test();

    return 0;
}