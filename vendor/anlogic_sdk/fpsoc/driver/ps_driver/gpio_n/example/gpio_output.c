#include <stdio.h>
#include "al_gpio_hal.h"

#define GPIO_PIN_NUM 5
#define GPIO_TOGGLE_COUNT 500

AL_S32 main()
{
    printf("gpio output test... \r\n");

    AL_GPIO_HalStruct *GpioHandle;
    AL_S32 Ret;

    Ret = AlGpio_Hal_Init(&GpioHandle, 0, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGpio_Hal_Init error\r\n");
        return Ret;
    }

    AlGpio_Hal_SetDirection(GpioHandle, AL_GPIO_OUTPUT, GPIO_PIN_NUM);
    AlGpio_Hal_WritePin(GpioHandle, GPIO_PIN_NUM, 0);

    for (AL_U32 i = 0; i < GPIO_TOGGLE_COUNT; i++)
    {
        AlGpio_Hal_TogglePin(GpioHandle, GPIO_PIN_NUM);
        AlSys_MDelay(50);
    }

    return Ret;
}