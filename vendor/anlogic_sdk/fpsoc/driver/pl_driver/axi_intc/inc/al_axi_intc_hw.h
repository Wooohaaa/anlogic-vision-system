/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_AXI_INTC_HW_H_
#define __AL_AXI_INTC_HW_H_

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files ********************************/
#include "al_core.h"

/************************** Constant Definitions ****************************/

/**************************** Type Definitions ******************************/

/***************** Macros (Inline Functions) Definitions ********************/


///////////////////////////////////////////////////////
// Register: ISR
// Interrupt Status Register
///////////////////////////////////////////////////////
#define AXI_INTC_ISR_OFFSET                             (0x0ULL)


///////////////////////////////////////////////////////
// Register: IPR
// Interrupt Pending Register
///////////////////////////////////////////////////////
#define AXI_INTC_IPR_OFFSET                             (0x4ULL)


///////////////////////////////////////////////////////
// Register: IER
// Interrupt Enable Register
///////////////////////////////////////////////////////
#define AXI_INTC_IER_OFFSET                             (0x8ULL)


///////////////////////////////////////////////////////
// Register: IAR
// Interrupt Acknowledge Register
///////////////////////////////////////////////////////
#define AXI_INTC_IAR_OFFSET                             (0xCULL)


///////////////////////////////////////////////////////
// Register: SIE
// Set Interrupt Enable
///////////////////////////////////////////////////////
#define AXI_INTC_SIE_OFFSET                             (0x10ULL)


///////////////////////////////////////////////////////
// Register: CIE
// Clear Interrupt Enable
///////////////////////////////////////////////////////
#define AXI_INTC_CIE_OFFSET                             (0x14ULL)


///////////////////////////////////////////////////////
// Register: IVR
// Interrupt Vector Register
///////////////////////////////////////////////////////
#define AXI_INTC_IVR_OFFSET                             (0x18ULL)


///////////////////////////////////////////////////////
// Register: MER
// Master Enable Register
///////////////////////////////////////////////////////
#define AXI_INTC_MER_OFFSET                             (0x1CULL)

#define AXI_INTC_MER_IRQ_ENABLE_SHIFT                   0
#define AXI_INTC_MER_HARDWARE_INTR_ENABLE_SHIFT         1

///////////////////////////////////////////////////////
// Register: IMR
// Interrupt Mode Register
///////////////////////////////////////////////////////
#define AXI_INTC_IMR_OFFSET                             (0x20ULL)


///////////////////////////////////////////////////////
// Register: ILR
// Interrupt Level Register
///////////////////////////////////////////////////////
#define AXI_INTC_ILR_OFFSET                             (0x24ULL)


///////////////////////////////////////////////////////
// Register: IVAR
// Interrupt Vector Address Register
///////////////////////////////////////////////////////
#define AXI_INTC_IVAR_OFFSET                            (0x100ULL)


typedef struct {
    AL_U32      DeviceId;
    AL_UINTPTR  BaseAddress;
    AL_U32      InputSoftIntrNum;
    AL_U32      InputHardWareIntrNum;
    AL_U32      IntrId;
    AL_U32      IntcType;
    AL_U32      IntrTrigMode;
    AL_U32      NextIntcDevId;
} AlAxiIntc_HwConfigStruct;

#ifdef __cplusplus
}
#endif

#endif /* __AL_AXI_ETHLITE_LITE_HW_H_ */
