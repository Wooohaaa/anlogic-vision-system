#include <stdio.h>
#include <string.h>
#include "al_misc_ll.h"
#include "al_i2c_hal.h"
#include "al_dma_hal.h"

#define TEST_BUFFER_SIZE  (16U)
#define SLAVE_DEVICE_ADDRESS  (0X50)
#define I2C_TX_DATA_ADDR  (I2C0_BASE_ADDR + I2C_TXDATA_ADDR)
#define I2C_RX_DATA_ADDR  (I2C0_BASE_ADDR + I2C_RXDATA_ADDR)
#define CACHELINE_SIZE (32)

__attribute__ ((aligned (CACHELINE_SIZE))) AL_U8 TxBuffer[TEST_BUFFER_SIZE] = {0};
__attribute__ ((aligned (CACHELINE_SIZE))) AL_U8 RxBuffer[TEST_BUFFER_SIZE] = {0};

static AL_I2C_InitStruct I2CInitConfigs = {
    .WorkMode  = AL_I2C_CPU_MODE,
    .RoleMode  = AL_I2C_SLAVE_MODE,
    .ClkSpeed  = AL_I2C_STANDARD_MODE,
    .SclDuty   = AL_I2C_SCL_DUTY_50,
    .SclPull   = AL_TRUE,
    .SdaPull   = AL_TRUE,
    .SlaveAddr = 0x50,
};

static AL_DMA_ChanCfgStruct I2cTxChanCfg = {
    .ChanType                  = AL_DMA_CHAN_I2C_TX,
    .DstAddr                   = I2C_TX_DATA_ADDR,
    .SrcAddr                   = (AL_U32)(uintptr_t)TxBuffer,
    .Msize                     = TEST_BUFFER_SIZE,
    .PaChanCfg.TransPer        = AL_DMA_PER_I2C_TX,
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
    .DstAddr                   = (AL_U32)(uintptr_t)RxBuffer,
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
    AL_I2C_HalStruct *I2cHandle;
    AL_DMA_HalStruct *DmaHandle;
    AL_S32 Ret = 0;

    printf("I2c slave dma test...\r\n");

    AlMisc_ll_SetClkEn(AL_MISC_I2C, 1);
    AlMisc_ll_SetReset(AL_MISC_I2C, 0);
    AlMisc_ll_SetReset(AL_MISC_I2C, 1);

    AlMisc_ll_SetClkEn(AL_MISC_UDMA, 1);
    AlMisc_ll_SetReset(AL_MISC_UDMA, 0);
    AlMisc_ll_SetReset(AL_MISC_UDMA, 1);

    memset(TxBuffer, 0, TEST_BUFFER_SIZE * sizeof(AL_U8));
    memset(RxBuffer, 0, TEST_BUFFER_SIZE * sizeof(AL_U8));

    for (AL_U32 i = 0; i < TEST_BUFFER_SIZE; i++)
    {
        TxBuffer[i] = 'a' + i;
    }

    Ret = AlI2c_Hal_Init(&I2cHandle, 0, &I2CInitConfigs, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, " error\r\n");
        return Ret;
    }

    Ret = AlDma_Hal_Init(&DmaHandle, 0, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, " error\r\n");
        return Ret;
    }

    AlIntr_SetLocalInterrupt(1);

    do {
        Ret = AlI2c_Hal_SlaveRecvDataDma(DmaHandle, &I2cRxChanCfg, I2cHandle, TEST_BUFFER_SIZE);
    } while (Ret != AL_OK);

#ifdef ENABLE_DCACHE
    AlCache_InvalidateDcacheRange(RxBuffer, (RxBuffer + TEST_BUFFER_SIZE * sizeof(AL_U8)));
    ISB();
#endif

    for (int i = 0; i < TEST_BUFFER_SIZE; i++) {
        printf("RxBuffer is %#X\r\n", RxBuffer[i]);
    }

#ifdef ENABLE_DCACHE
    AlCache_FlushDcacheRange(TxBuffer, (TxBuffer + TEST_BUFFER_SIZE * sizeof(AL_U8)));
    ISB();
#endif

    do {
        Ret = AlI2c_Hal_SlaveSendDataDma(DmaHandle, &I2cTxChanCfg, I2cHandle, TEST_BUFFER_SIZE);
    } while (Ret != AL_OK);

    return AL_OK;
}