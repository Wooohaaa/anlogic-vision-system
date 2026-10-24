/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/********************************* including Files *********************************/
#include "al_hal.h"
#include "al_axi_ethernet_lite_hw.h"

/********************************* Constant Definitions *****************************/


/********************************* Type definitions *********************************/


/********************************* Macros  & Inline Functions Definitions ***********/


#if (defined _AARCH_64 || defined __aarch64__ || defined __arm__)
#define AXI_ETH_LITE0_BASE_ADDR             0x1C0000000ULL
#else
#define AXI_ETH_LITE0_BASE_ADDR             0x1F0000000ULL
#endif

#define AXI_ETH_LITE_CLOCK (100*MHz)

/******************************** Function Prototypes ******************************/


/******************************** Variable Prototypes ******************************/

AlAxiEthLite_HwConfigStruct AlAxiEthLite_HwConfig[] =
{
#if (AL_AXI_ETH_LITE_NUM_INSTANCE > 0)
    {
        .DeviceId       = 0,
        .BaseAddress    = AXI_ETH_LITE0_BASE_ADDR,
        .InputClk       = AXI_ETH_LITE_CLOCK,
        .IntrId         = AXI_ETH_LITE0_INTR_ID,
    }
#endif
};