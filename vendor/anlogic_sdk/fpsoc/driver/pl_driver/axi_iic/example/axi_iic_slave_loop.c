/**
 * AXI IIC Slave Loop Test.
*/

/**
 * @file    axi_iic_slave_loop.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2024-09-08
 * @brief   axi iic slave loop example
 * @example axi_iic_slave_loop.c
 */

#include "al_axi_iic_hal.h"
#include <string.h>

#define TRANSFER_METHOD               1  // 1 = BLOCK, 0 = POLLING
#define IIC_LOOP_SLAVE_ADDR           0x52
#define TRANSFER_LENGTH               0x0a

AL_U8 TransferBuf[TRANSFER_LENGTH] = {0};

AlAxiIic_InitStruct InitConfig =
{
    .IIC_Mode           = AL_AXI_IIC_SLAVE      ,
    .IIC_AddressMode    = AL_AXI_IIC_7BIT       ,
    .SlaveAddr          = IIC_LOOP_SLAVE_ADDR   ,
    .SpeedMode          = AL_AXI_IIC_STANDARD_MODE    ,
    .SetupTime          = 300,
    .HoldTime           = 300,
};

/**
 * This function initializes the IIC HAL, receives data from the master, and sends data back to the master
 * in a loop to test the slave functionality.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 main()
{
    AL_U32 Ret = AL_OK;
    AL_U32 test_round = 0;
    AlAxiIic_HalStruct *Handle;

    Soc_PsPlInit();

    Ret = AlAxiIic_Hal_Init(&Handle, 0, &InitConfig, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "AlAxiIic_Hal_Init failed %d", Ret);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    while (1)
    {
        AL_LOG(AL_LOG_LEVEL_INFO, "=== AXI IIC Test: Round %d ===", ++test_round);
        memset(TransferBuf, 0, TRANSFER_LENGTH);

#if TRANSFER_METHOD == 0
        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Recv Data Polling Operation start");
        Ret = AlAxiIic_Hal_SlaveRecvDataPolling(Handle, TransferBuf, TRANSFER_LENGTH);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Slave Recv Data Polling failed %d", Ret);
            return Ret;
        }

        for (int i = 0; i < TRANSFER_LENGTH; i++) {
            AL_LOG(AL_LOG_LEVEL_INFO, "TransferBuf[%d]: 0x%02x\r\n", i, TransferBuf[i]);
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Recv Data Polling Operation success");

        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Send Data Polling Operation start");
        Ret = AlAxiIic_Hal_SlaveSendDataPolling(Handle, TransferBuf, TRANSFER_LENGTH);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Slave Send Data Polling failed %d", Ret);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Send Data Polling Operation success");
#else
        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Recv Data Block Operation start");
        Ret = AlAxiIic_Hal_SlaveRecvDataBlock(Handle, TransferBuf, TRANSFER_LENGTH, AL_WAITFOREVER);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Slave Recv Data Block failed %d\r\n", Ret);
            return Ret;
        }

        for (int i = 0; i < TRANSFER_LENGTH; i++) {
            AL_LOG(AL_LOG_LEVEL_INFO, "TransferBuf[%d]: 0x%02x\r\n", i, TransferBuf[i]);
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Recv Data Block Operation success");

        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Send Data Block Operation start");
        Ret = AlAxiIic_Hal_SlaveSendDataBlock(Handle, TransferBuf, TRANSFER_LENGTH, AL_WAITFOREVER);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Slave Send Data Block failed %d", Ret);
            return Ret;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Slave Send Data Block Operation success");
#endif
    }

    return Ret;
}
