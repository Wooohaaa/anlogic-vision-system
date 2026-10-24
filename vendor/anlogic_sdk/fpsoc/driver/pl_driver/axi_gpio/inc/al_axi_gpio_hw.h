/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_GPIO_HW_H_
#define AL_AXI_GPIO_HW_H_

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files ********************************/
#include "al_core.h"

#define AL_AXI_GPIO_DATA        0x00
#define AL_AXI_GPIO_TRI         0x04
#define AL_AXI_GPIO_DATA2       0x08
#define AL_AXI_GPIO_TRI2        0x0c
#define AL_AXI_GPIO_ISR         0x104
#define AL_AXI_GPIO_IER         0x100

#define AXI_GPIO_MAX_PIN        32
#define AXI_GPIO_MAX_CHANNEL    2

typedef struct {
    AL_U32                  DeviceId;
    AL_REG                  BaseAddress;
    AL_U32                  IntrId;
} AlAxiGpio_HwConfigStruct;

#ifdef __cplusplus
}
#endif

#endif
