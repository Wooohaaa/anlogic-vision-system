/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    axi_gpio_output_led.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2024-09-08
 * @brief   control LED example
 * @example axi_gpio_output_led.c
 */

#include "al_axi_gpio_hal.h"

#define GPIO0_DEVICE_ID 0
#define USE_PIN

/**
 * This function initializes the AXI GPIO device and toggles the LED connected to the GPIO pins.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 main()
{
    AL_U32 Pin_Val = 0;
    AL_U32 Val = 0xffffffff;
    AL_S32 ret = AL_OK;

    Soc_PsPlInit();

    AL_LOG(AL_LOG_LEVEL_INFO, "Axi gpio output test!");

    /* Instantiate a axi gpio and init it */
    AlAxiGpio_Hal_Struct *Gpio0;

    ret = AlAxiGpio_Hal_Init(&Gpio0, GPIO0_DEVICE_ID, AL_NULL);
    if (ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Axi gpio0 init failed!");
        return ret;
    }

    while (1) {
        ret = AlOsal_Lock_Take(&Gpio0->Lock, AL_WAITFOREVER);
        if (ret != AL_OK) {
            return ret;
        }

    #ifdef USE_PIN
        /* Set Direction */
        AlAxiGpio_Hal_SetPinDirection(Gpio0, AL_AXI_GPIO_CHANNEL1, 15, AL_AXI_GPIO_OUT);
        AlAxiGpio_Hal_SetPinDirection(Gpio0, AL_AXI_GPIO_CHANNEL2, 14, AL_AXI_GPIO_OUT);

        /* Toggle led */
        Pin_Val = ~Pin_Val;
        AlAxiGpio_Hal_WritePin(Gpio0, AL_AXI_GPIO_CHANNEL1, 15, Pin_Val);
        AlAxiGpio_Hal_WritePin(Gpio0, AL_AXI_GPIO_CHANNEL2, 14, Pin_Val);
    #else
        /* Set gpio0 channel1 and channel2 as output */
        AlAxiGpio_Hal_SetChannelDirection(Gpio0, AL_AXI_GPIO_CHANNEL1, AL_AXI_GPIO_CHANNEL_OUT);

        /* Toggle led */
        Val = ~Val;
        AlAxiGpio_Hal_WriteChannel(Gpio0, AL_AXI_GPIO_CHANNEL1, Val);
        AlAxiGpio_Hal_WriteChannel(Gpio0, AL_AXI_GPIO_CHANNEL2, Val);
    #endif

        (AL_VOID)AlOsal_Lock_Release(&Gpio0->Lock);

        AlSys_MDelay(500);
    }

    return 0;
}
