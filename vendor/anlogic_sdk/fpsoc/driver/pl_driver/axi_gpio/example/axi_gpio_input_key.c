/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    axi_gpio_input_key.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2024-09-08
 * @brief   control axi gpio interrupt example
 * @example axi_gpio_input_key.c
 */

#include "al_axi_gpio_hal.h"

#define GPIO0_DEVICE_ID 0

/**
 * This function is called when a GPIO event occurs. It logs the interrupt status for the corresponding channel.
 *
 * @param Event The GPIO event structure.
 * @param CallbackRef Pointer to the callback reference.
 *
 * @return None.
 */
static void Callback(AlAxiGpio_EventStruct Event, AL_VOID *CallbackRef)
{
    (AL_VOID)CallbackRef;

    BUG_ON(!(Event.Channel & (BIT(AL_AXI_GPIO_CHANNEL1) | BIT(AL_AXI_GPIO_CHANNEL2))));

    if (Event.Channel & BIT(AL_AXI_GPIO_CHANNEL1)) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Channel 1 interrupt occurred, IntrStatus = 0x%x", Event.EventData);
    }

    if (Event.Channel & BIT(AL_AXI_GPIO_CHANNEL2)) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Channel 2 interrupt occurred, IntrStatus = 0x%x", Event.EventData);
    }
}

/**
 * This function initializes the AXI GPIO device, sets the direction of the GPIO channels and pins as input,
 * and enables interrupts for the GPIO channels.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 main()
{
    AL_S32 ret = AL_OK;

    Soc_PsPlInit();

    AL_LOG(AL_LOG_LEVEL_INFO, "Axi gpio input key interrupt test!");

    /* Instantiate a axi gpio and init it */
    AlAxiGpio_Hal_Struct *Gpio0;

    ret = AlAxiGpio_Hal_Init(&Gpio0, GPIO0_DEVICE_ID, Callback);
    if (ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Axi gpio0 init failed!");
        return ret;
    }

    /* Set Direction as IN. */
    AlAxiGpio_Hal_SetChannelDirection(Gpio0, AL_AXI_GPIO_CHANNEL2, AL_AXI_GPIO_CHANNEL_IN);
    AlAxiGpio_Hal_SetPinDirection(Gpio0, AL_AXI_GPIO_CHANNEL1, 1, AL_AXI_GPIO_IN);
    AlAxiGpio_Hal_SetPinDirection(Gpio0, AL_AXI_GPIO_CHANNEL2, 1, AL_AXI_GPIO_IN);

    AL_LOG(AL_LOG_LEVEL_INFO, "Read Bit in = 0x%x", AlAxiGpio_Hal_ReadPin(Gpio0, AL_AXI_GPIO_CHANNEL1, 1));
    AL_LOG(AL_LOG_LEVEL_INFO, "Read Channel in = 0x%x", AlAxiGpio_Hal_ReadChannel(Gpio0, AL_AXI_GPIO_CHANNEL2));

    /* Enable axi gpio channel1 interrupt */
    AL_INTR_AttrStrct AttrGpio = {
        .TrigMode = POSTIVE_EDGE_TRIGGER,
        .Priority = 0x20
    };

    ret = AlAxiGpio_Hal_IntInit(Gpio0, AL_AXI_GPIO_CHANNEL1, &AttrGpio);
    ret = AlAxiGpio_Hal_IntInit(Gpio0, AL_AXI_GPIO_CHANNEL2, &AttrGpio);
    if(ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_INFO, "Axi gpio0 channel 1 interrupt init failed, ret = 0x%x\r\n!", ret);
        return ret;
    }

    AlSys_MDelay(5000);

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    while (1)
    {

    }

    return 0;
}
