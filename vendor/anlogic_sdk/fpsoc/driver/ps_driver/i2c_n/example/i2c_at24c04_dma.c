#include <stdio.h>
#include "al_i2c_hal.h"
#include "al_misc_ll.h"

#define EEPROM_ADDRESS         (0x50)
#define I2C_PAGE_SIZE          (16)
#define EEP_FIRST_PAGE         (0x00)
#define BUFFER_SIZE            (16)

#define CACHELINE_SIZE (32)
#define TEST_BUFFER_SIZE  (6U)

#define I2C_TX_DATA_ADDR  (I2C0_BASE_ADDR + I2C_TXDATA_ADDR)
#define I2C_RX_DATA_ADDR  (I2C0_BASE_ADDR + I2C_RXDATA_ADDR)

__attribute__((aligned(CACHELINE_SIZE))) AL_U8 I2cTxBuffer[TEST_BUFFER_SIZE];
__attribute__((aligned(CACHELINE_SIZE))) AL_U8 I2cRxBuffer[TEST_BUFFER_SIZE];

AL_U8 I2cTxBuffer[TEST_BUFFER_SIZE] = {0x00, 0x55, 0xaa, 0x5a, 0xa5, 0x77};

static AL_I2C_InitStruct I2CInitConfigs = {
    .WorkMode = AL_I2C_CPU_MODE,
    .RoleMode = AL_I2C_MASTER_MODE,
    .ClkSpeed = AL_I2C_STANDARD_MODE,
    .SclDuty  = AL_I2C_SCL_DUTY_50,
    .SclPull  = AL_TRUE,
    .SdaPull  = AL_TRUE,
};

static AL_DMA_ChanCfgStruct I2cTxChanCfg = {
    .ChanType                  = AL_DMA_CHAN_I2C_TX,
    .DstAddr                   = I2C_TX_DATA_ADDR,
    .SrcAddr                   = I2cTxBuffer,
    .Msize                     = TEST_BUFFER_SIZE,
    .PaChanCfg.TransPer        = AL_DMA_CHAN_I2C_TX,
    .PaChanCfg.TransMode       = AL_DMA_SINGLE_MODE,
    .PaChanCfg.DstAddrType     = AL_DMA_ADDR_FIXED,
    .PaChanCfg.SrcAddrType     = AL_DMA_ADDR_INCREASE,
    .PaChanCfg.TransWidth      = AL_DMA_CHAN_WIDTH_8_BIT,
    .ChanIntrCfg.IntrChanFull  = AL_TRUE,
    .ChanIntrCfg.IntrChanHalf  = AL_TRUE,
    .ChanIntrCfg.IntrChanError = AL_TRUE,
};

static AL_DMA_ChanCfgStruct I2cRxChanCfg = {
    .ChanType                  = AL_DMA_CHAN_I2C_RX,
    .DstAddr                   = I2cRxBuffer,
    .SrcAddr                   = I2C_RX_DATA_ADDR,
    .Msize                     = TEST_BUFFER_SIZE,
    .PaChanCfg.TransPer        = AL_DMA_PER_I2C_RX,
    .PaChanCfg.TransMode       = AL_DMA_SINGLE_MODE,
    .PaChanCfg.DstAddrType     = AL_DMA_ADDR_INCREASE,
    .PaChanCfg.SrcAddrType     = AL_DMA_ADDR_FIXED,
    .PaChanCfg.TransWidth      = AL_DMA_CHAN_WIDTH_8_BIT,
    .ChanIntrCfg.IntrChanFull  = AL_TRUE,
    .ChanIntrCfg.IntrChanHalf  = AL_TRUE,
    .ChanIntrCfg.IntrChanError = AL_TRUE,
};

AL_S32 main()
{
#ifdef ENABLE_DCACHE
    ccm_cache_flush();
    AlCache_DisableDCache();
    ISB();
#endif
    printf("I2c dma write and read at24c04 test...\r\n");

    AL_I2C_HalStruct *I2cHandle;
    AL_DMA_HalStruct *DmaHandle;
    AL_S32 Ret;
    AL_U8 PageAddr = 0x00;

    AlMisc_ll_SetClkEn(AL_MISC_I2C, 1);
    AlMisc_ll_SetReset(AL_MISC_I2C, 0);
    AlMisc_ll_SetReset(AL_MISC_I2C, 1);

    AlMisc_ll_SetClkEn(AL_MISC_UDMA, 1);
    AlMisc_ll_SetReset(AL_MISC_UDMA, 0);
    AlMisc_ll_SetReset(AL_MISC_UDMA, 1);

    Ret = AlI2c_Hal_Init(&I2cHandle, 0, &I2CInitConfigs, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, " error\r\n");
        return Ret;
    }

    AlDma_Hal_Init(&DmaHandle, 0, AL_NULL);

    AL_U16 DeviceAddress = EEPROM_ADDRESS;

    AlI2c_Hal_MasterSendDataDma(DmaHandle, &I2cTxChanCfg, I2cHandle, DeviceAddress, TEST_BUFFER_SIZE, AL_I2C_START, AL_I2C_STOP);

    AlSys_MDelay(100);

    Ret = AlI2c_Hal_MasterSendDataPolling(I2cHandle, DeviceAddress, &PageAddr, 1, AL_I2C_START, AL_I2C_NOSTOP);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlI2c_Hal_MasterSendDataPolling error\r\n");
        return Ret;
    }

    AlI2c_Hal_MasterRecvDataDma(DmaHandle, &I2cRxChanCfg, I2cHandle, DeviceAddress, TEST_BUFFER_SIZE, AL_I2C_RESTART, AL_I2C_STOP);

    for (int i = 0; i < TEST_BUFFER_SIZE; i++)
    {
        printf("I2cRxBuffer is %x\r\n", I2cRxBuffer[i]);
    }


    return AL_OK;

}