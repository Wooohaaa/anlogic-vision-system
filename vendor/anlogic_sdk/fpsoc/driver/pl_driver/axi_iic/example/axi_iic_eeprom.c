/**
 * Axi Iic Eeprom Test.
*/

/**
 * @file    axi_iic_eeprom.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2024-09-08
 * @brief   axi iic eeprom example
 * @example axi_iic_eeprom.c
 */

#include "al_axi_iic_hal.h"
#include <string.h>

#define TRANSFER_METHOD               1  // 1 = BLOCK, 0 = POLLING
#define TEST_ITERATIONS               100

#define EEPROM_DEVICE_ADDRESS         0x50
#define EEPROM_READ_WRITE_LENGTH      0x0a
#define EEPROM_READ_WRITE_START_ADDR  0x00

AlAxiIic_InitStruct InitConfig =
{
    .IIC_Mode           =   AL_AXI_IIC_MASTER           ,
    .IIC_AddressMode    =   AL_AXI_IIC_7BIT             ,
    .SpeedMode          =   AL_AXI_IIC_STANDARD_MODE    ,
    .SetupTime          =   300,
    .HoldTime           =   300,
};

AL_U8 ReadBuf[EEPROM_READ_WRITE_LENGTH] = {0x0};
AL_U8 WriteBuf[EEPROM_READ_WRITE_LENGTH + 1] = {
    EEPROM_READ_WRITE_START_ADDR,    /* Start Write Address */
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa
};

AL_S32 CompareBuffers(AL_U8 *recv, AL_U8 *send, int length);
AL_S32 Eeprom_WriteData(AlAxiIic_HalStruct *Handle, AL_U8 *SendBuff, AL_U32 SendSize);
AL_S32 Eeprom_ReadData(AlAxiIic_HalStruct *Handle, AL_U8 *RecvBuff, AL_U8 StartReadAddr, AL_U32 RecvSize);

/**
 * This function initializes the IIC HAL, writes data to the EEPROM, reads data from the EEPROM,
 * and compares the written and read data to verify the correctness.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 main()
{
    AL_U32 Ret = AL_OK;
    AlAxiIic_HalStruct *Handle;

    Soc_PsPlInit();

    Ret = AlAxiIic_Hal_Init(&Handle, 0, &InitConfig,(AlAxiIic_EventCallBack)AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "AlAxiIic_Hal_Init failed %d", Ret);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    for (int i = 0; i < TEST_ITERATIONS; i++) {
        AL_LOG(AL_LOG_LEVEL_INFO, "=== AXI IIC EEPROM Test: Round %d ===", i + 1);
        memset(ReadBuf, 0, EEPROM_READ_WRITE_LENGTH);

        /* 1. write eeprom */
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Write Data start");
        Ret = Eeprom_WriteData(Handle, WriteBuf, EEPROM_READ_WRITE_LENGTH + 1);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Write Data failed %d", Ret);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Write Data done");

        /* 2. read eeprom */
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Read Data start");
        Ret = Eeprom_ReadData(Handle, ReadBuf, EEPROM_READ_WRITE_START_ADDR, EEPROM_READ_WRITE_LENGTH);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Read Data failed %d", Ret);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Eeprom Read Data done");

        /* 3. check eeprom data*/
        Ret = CompareBuffers(ReadBuf, WriteBuf + 1, EEPROM_READ_WRITE_LENGTH);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "AXI IIC EEPROM Test: Round %d Failed", i + 1);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "AXI IIC EEPROM Test: Round %d Success", i + 1);
    }

    return Ret;
}

/**
 * This function writes data to the EEPROM using the specified IIC handle.
 *
 * @param Handle Pointer to the IIC HAL structure.
 * @param SendBuff Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 Eeprom_WriteData(AlAxiIic_HalStruct *Handle, AL_U8 *SendBuff, AL_U32 SendSize)
{
    AL_U32 Ret = AL_OK;

#if TRANSFER_METHOD == 0
    Ret = AlAxiIic_Hal_MasterSendDataPolling(Handle, EEPROM_DEVICE_ADDRESS, SendBuff, SendSize, AL_AXI_IIC_STOP);
#else
    Ret = AlAxiIic_Hal_MasterSendDataBlock(Handle, EEPROM_DEVICE_ADDRESS, SendBuff, SendSize, AL_AXI_IIC_STOP, AL_WAITFOREVER);
#endif
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Send Data failed %d", Ret);
        return Ret;
    }
    AlSys_MDelay(10);	/* Wait Writing Finish */

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
AL_S32 Eeprom_ReadData(AlAxiIic_HalStruct *Handle, AL_U8 *RecvBuff, AL_U8 StartReadAddr, AL_U32 RecvSize)
{
    AL_U32 Ret = AL_OK;

#if TRANSFER_METHOD == 0
    Ret = AlAxiIic_Hal_MasterSendDataPolling(Handle, EEPROM_DEVICE_ADDRESS, &StartReadAddr, 1, AL_AXI_IIC_NSTOP);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Send Data failed %d", Ret);
        return Ret;
    }
    AlSys_MDelay(1);
    Ret = AlAxiIic_Hal_MasterRecvDataPolling(Handle, EEPROM_DEVICE_ADDRESS, RecvBuff, RecvSize, AL_AXI_IIC_STOP);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Recv Data failed %d", Ret);
        return Ret;
    }
#else
    Ret = AlAxiIic_Hal_MasterSendDataBlock(Handle, EEPROM_DEVICE_ADDRESS, &StartReadAddr, 1, AL_AXI_IIC_NSTOP, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Send Data failed %d", Ret);
        return Ret;
    }
    AlSys_MDelay(1);
    Ret = AlAxiIic_Hal_MasterRecvDataBlock(Handle, EEPROM_DEVICE_ADDRESS, RecvBuff, RecvSize, AL_AXI_IIC_STOP, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Master Recv Data failed %d", Ret);
        return Ret;
    }
#endif

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
