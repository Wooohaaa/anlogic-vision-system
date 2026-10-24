#include <stdio.h>
#include "al_core.h"
#include "al_softcore_systimer.h"
//#include "al_softcore_systimer.h"
#include "al_usart_hal.h"


#define TEST_BUFFER_SIZE 120

static AL_USART_InitStruct UsartInitConfigs = {
    .BaudRate              = 115200,
    .WordLength            = AL_USART_CHAR_8_BITS,
    .StopBits              = AL_USART_STOP_1_BIT,
    .Parity                = AL_USART_NO_PARITY,
    .TxCtl                 = AL_TRUE,
    .RxCtl                 = AL_TRUE,
    .HwFlowCtl.Cts         = AL_FALSE,
    .HwFlowCtl.Rts         = AL_FALSE,
    .TxFifoWaterMark       = 0x8,
    .RxFifoWaterMark       = 0x8,
    .HwFlowCtl             = AL_FALSE,
    .RxIdleTimeout         = 0xffff,
    .RxWmTimeout           = 0xffff,
    .SeparateEn            = AL_TRUE,
    .DmaEn                 = AL_FALSE,
    .RxDmaEn               = AL_FALSE,
};
volatile AL_USART_HalStruct *UsartHandle = AL_NULL;
void main(void) {

    AL_USART_DevStruct UsartHandleStruct;
    AL_USART_DevStruct *UsartHandle = &UsartHandleStruct;

    // Initialize SysTimer
    SysTimer_enable();
    SysTimer_SetLoadValue(1000000); // Set timer load value (example: 1 million cycles)
    SysTimer_SetCompareValue(500000); // Set compare value (example: half the timer cycle)

    SysTimer_Start();

    AL_U8 Data[TEST_BUFFER_SIZE] = {0};
    strcpy((char*)Data, "Hello this is a test of mtimer: \r\n");

    AL_S32 Ret = AlUsart_Dev_Init(UsartHandle, 0, &UsartInitConfigs);
    if (Ret != AL_OK) {
        // Initialization error handling
        return;
    }

    Ret = AlUsart_Dev_SendDataPolling(UsartHandle, Data, strlen((char*)Data));
    if (Ret != AL_OK) {
        // Handle send error
        return;
    }

    // Wait until timer reaches compare value (polling method)
    while (SysTimer_GetLoadValue() > SysTimer_GetCompareValue());

    // Stop the timer
    SysTimer_Stop();

    // Send another message indicating timer event
    strcpy((char*)Data, "SysTimer reached compare value!\r\n");
    Ret = AlUsart_Dev_SendDataPolling(UsartHandle, Data, strlen((char*)Data));
    if (Ret != AL_OK) {
        // Handle send error
        return;
    }

    SysTimer_disable();
}