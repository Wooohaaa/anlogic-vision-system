/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/
#include "al_axi_iic_hw.h"


/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/
#define AXI_IIC0_CLK                   (75 * MHz)
#define AXI_IIC1_CLK                   (75 * MHz)

#define AXI_IIC0_DEVICE_ID 0
#define AXI_IIC1_DEVICE_ID 1

#define AXI_I2C0_BASE_ADDR 0x80030000
#define AXI_I2C1_BASE_ADDR 0x1f1030000

#define AXI_IIC0_IRQn 117
#define AXI_IIC1_IRQn 125

/************************** Variable Prototypes ******************************/
AlAxiIic_HwConfigStruct AlAxiIic_HwConfig[] =
{
#if (AL_AXI_IIC_NUM_INSTANCE > 0)
    {
        .DeviceId       = AXI_IIC0_DEVICE_ID,
        .BaseAddress    = AXI_I2C0_BASE_ADDR,
        .IntrId         = AXI_IIC0_IRQn,
        .InputClk       = AXI_IIC0_CLK,
    },

    {
        .DeviceId       = AXI_IIC1_DEVICE_ID,
        .BaseAddress    = AXI_I2C1_BASE_ADDR,
        .IntrId         = AXI_IIC1_IRQn,
        .InputClk       = AXI_IIC1_CLK,
    },
#endif
};
