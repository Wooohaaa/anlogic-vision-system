#include <stdio.h>
#include "al_usart_hal.h"

#define TEST_BUFFER_SIZE 16

static AL_USART_InitStruct UsartInitConfigs = {
    .BaudRate              = 115200,
    .WordLength            = AL_USART_CHAR_8_BITS,
    .StopBits              = AL_USART_STOP_1_BIT,
    .Parity                = AL_USART_NO_PARITY,
    .TxCtl                 = AL_TRUE,
    .RxCtl                 = AL_TRUE,
    .HwFlowCtl = {
        .Cts         = AL_FALSE,
        .Rts         = AL_FALSE,
    },
    .TxFifoWaterMark       = 0x8,
    .RxFifoWaterMark       = 0x8,
    .RxIdleTimeout         = 0xffff,
    .RxWmTimeout           = 0xffff,
    .SeparateEn            = AL_TRUE,
    .DmaEn                 = AL_FALSE,
    .RxDmaEn               = AL_FALSE,
};

AL_S32 main()
{

    printf("Usart polling test ...\r\n");
    printf("Send more than %d Bytes data and will show back\r\n", TEST_BUFFER_SIZE);

    AL_USART_HalStruct *UsartHandle;
    AL_U8 Data[TEST_BUFFER_SIZE] = {0};

    AL_S32 Ret = AlUsart_Hal_Init(&UsartHandle, 0, &UsartInitConfigs, AL_NULL);
    if (Ret != AL_OK) {
        printf("AlUsart_Hal_Init error\r\n");
        return Ret;
    }

    Ret = AlUsart_Hal_RecvDataPolling(UsartHandle, Data, TEST_BUFFER_SIZE);
    if (Ret != AL_OK) {
        printf("AlUsart_Hal_RecvDataPolling Error\r\n");
        return Ret;
    }

    Ret = AlUsart_Hal_SendDataPolling(UsartHandle, Data, TEST_BUFFER_SIZE);
    if (Ret != AL_OK) {
        printf("AlUsart_Hal_SendDataPolling Error\r\n");
        return Ret;
    }

    printf("\r\n");
    printf("Usart polling test success\r\n");

    return 0;
}