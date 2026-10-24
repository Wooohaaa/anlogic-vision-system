/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_gpio_hw.h"

/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/

#define AXI_GPIO0_DEVICE_ID         0
#define AXI_GPIO1_DEVICE_ID         1
#define AXI_GPIO0_IRQn              114
#define AXI_GPIO1_IRQn              115
#define AXI_GPIO0_BASE_ADDR        0x80000000
#define AXI_GPIO1_BASE_ADDR        0x80100000

/************************** Variable Prototypes ******************************/
AlAxiGpio_HwConfigStruct AlAxiGpio_HwConfig[] =
{
#if (AL_AXI_GPIO_NUM_INSTANCE > 0)
    {
        .DeviceId           = AXI_GPIO0_DEVICE_ID,
        .BaseAddress        = AXI_GPIO0_BASE_ADDR,
        .IntrId             = AXI_GPIO0_IRQn,
    },
    {
        .DeviceId           = AXI_GPIO1_DEVICE_ID,
        .BaseAddress        = AXI_GPIO1_BASE_ADDR,
        .IntrId             = AXI_GPIO1_IRQn,
    }
#endif
};