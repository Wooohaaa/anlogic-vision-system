/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */
/***************************** Include Files ********************************/
#include "al_axi_canfd_hw.h"

/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/

/************************** Variable Definitions *****************************/

AlAxiCanFd_HwConfigStruct AlAxiCanFd_HwConfig[AL_AXI_CANFD_NUM_INSTANCE] =
{
#if (AL_AXI_CANFD_NUM_INSTANCE > 0)
    {
        .DeviceId       = 0,
        .IntrId         = 114,
        .BaseAddress    = 0x80000000ULL,
        .InputClk       = 30000000,

        .BusType        = 0,
        .TxBufNum       = 32,
        .RxMode         = 0,
        .RxBufNum       = 48,
        .IsFifo1En      = 1,
        .RxFifoDepth0   = 64,
        .RxFifoDepth1   = 64,
        .IsTxEventEn    = 1,
    },
#endif
};

