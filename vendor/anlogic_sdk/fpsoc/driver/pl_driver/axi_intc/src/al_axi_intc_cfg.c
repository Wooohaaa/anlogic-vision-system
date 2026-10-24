/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/********************************* including Files *********************************/
#include "al_hal.h"
#include "al_axi_intc_hw.h"

/********************************* Constant Definitions *****************************/


/********************************* Type definitions *********************************/


/********************************* Macros  & Inline Functions Definitions ***********/


AlAxiIntc_HwConfigStruct AlAxiIntc_HwConfig[] =
{
#if (AL_AXI_INTC_NUM_INSTANCE > 0)
    {
        .DeviceId               = 0,
        .BaseAddress            = 0x80000000,
        .InputSoftIntrNum       = 0,
        .InputHardWareIntrNum   = 6,
        .IntrId                 = 114,
        .IntcType               = AXI_INTC_NOCASCADE,
        .IntrTrigMode           = LEVEL_HIGH_TRIGGER,
    },
#endif
};