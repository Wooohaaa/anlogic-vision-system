#include <stdio.h>
#include "al_usart_hal.h"
#include "al_core.h"
#include "al_softcore_systimer.h"

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

AL_USART_DevStruct UsartHandleStruct;
AL_USART_DevStruct *UsartdevHandle = &UsartHandleStruct;
int main(void) {

    AL_U8 Data[TEST_BUFFER_SIZE] = {0};
    strcpy((char*)Data, "Hello this is a test of interruption of mtimer: \r\n");

    AL_S32 Ret = AlUsart_Hal_Init(&UsartdevHandle, 0, &UsartInitConfigs, AL_NULL);
    AlIntr_SetLocalInterrupt(1); //set mstatus.MIe to enable global interruption
    Ret = AlUsart_Dev_SendDataPolling(UsartdevHandle, Data, strlen((char*)Data));
    // Initialize SysTimer
    SysTimer_SetCompareValue(500000); // Set compare value (example: half the timer cycle)
    SysTimer_SetCMPIRQ();
    SysTimer_enable();
    SysTimer_Start();

    while(1) {
        // Main loop
        // Typically empty, waiting for interrupts
    }

    return 0;
}
