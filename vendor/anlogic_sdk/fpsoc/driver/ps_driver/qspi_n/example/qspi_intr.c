#include <stdio.h>
#include "al_misc_ll.h"
#include "al_qspi_hal.h"

#define TEST_BUFFER_SIZE         8

AL_U8 TxBuffer[TEST_BUFFER_SIZE];
AL_U8 RxBuffer[TEST_BUFFER_SIZE];

AL_U8 TxBuffer[TEST_BUFFER_SIZE] =
{
    0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88
};

static AL_QSPI_InitStruct QspiInitConfigs = {
    .SckDiv              = 16,
    .DevMode             = AL_QSPI_MASTER,
    .ProtocolMode        = AL_QSPI_PROTOCOL_MODE_SINGLE,
    .FrameLen            = AL_QSPI_FRAMELEN_8BIT,
    .CSMode              = AL_QSPI_CS_MODE_AUTO,
    .CPOL                = AL_QSPI_CLK_LOW_LEVLE,
    .CPHA                = AL_QSPI_CLK_EDGE1,
    .Endian              = AL_QSPI_ENDIAN_MSB,
    .DmaModeEn           = 0,
    .TxDmaEn             = 0,
    .RxDmaEn             = 0,
    .TxDmaContinousEn    = 0,
    .RxDmaContinousEn    = 0,
};


AL_U32 main()
{
    printf("qspi interrupt test ...\r\n");

    AL_QSPI_HalStruct *QspiHandle;
    AL_DMA_HalStruct *DmaHandle;
    AL_S32 Ret = 0;

    AlMisc_ll_SetClkEn(AL_MISC_QSPI1, 1);
    AlMisc_ll_SetReset(AL_MISC_QSPI1, 0);
    AlMisc_ll_SetReset(AL_MISC_QSPI1, 1);


    Ret = AlQspi_Hal_Init(&QspiHandle, 1, &QspiInitConfigs, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, " error\r\n");
        return Ret;
    }

    AlIntr_SetLocalInterrupt(1);

    AlQspi_Hal_RecvData(QspiHandle, RxBuffer, TEST_BUFFER_SIZE);
    AlQspi_Hal_SendData(QspiHandle, TxBuffer, TEST_BUFFER_SIZE);

    return 0;
}