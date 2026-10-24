/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_GPIO_HAL_H_
#define AL_AXI_GPIO_HAL_H_

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files ********************************/
#include "al_axi_gpio_ll.h"

#define AL_AXI_GPIO_ERR_ILLEGAL_PARAM    (AL_DEF_ERR(AL_AxiGpio, AL_LOG_LEVEL_ERROR, AL_ERR_ILLEGAL_PARAM))

typedef struct
{
    AL_U32                  Channel;
    AL_U32                  EventData;
} AlAxiGpio_EventStruct;

typedef AL_VOID (*AlAxiGpio_EventCallBack)(AlAxiGpio_EventStruct Event, AL_VOID *CallbackRef);

typedef struct
{
    AlAxiGpio_HwConfigStruct     HwConfig;
    AlAxiGpio_EventCallBack     EventCallBack;
    AL_VOID                     *EventCallBackRef;
    AL_Lock                     Lock;
    AL_MailBox                  EventQueue;
} AlAxiGpio_Hal_Struct;

AL_S32 AlAxiGpio_Hal_Init(AlAxiGpio_Hal_Struct **Handle, AL_U32 DevId, AlAxiGpio_EventCallBack CallBack);
AL_S32 AlAxiGpio_Hal_SetChannelDirection(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Direction);
AL_S32 AlAxiGpio_Hal_SetPinDirection(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Pin, AlAxiGpio_ll_DirEnum Direction);
AL_S32 AlAxiGpio_Hal_WritePin(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Pin, AL_U32 Value);
AL_U32 AlAxiGpio_Hal_ReadPin(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Pin);
AL_S32 AlAxiGpio_Hal_WriteChannel(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Value);
AL_U32 AlAxiGpio_Hal_ReadChannel(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel);
AL_S32 AlAxiGpio_Hal_RegisterEventCallBack(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_EventCallBack CallBack, AL_VOID *CallBackRef);
AL_S32 AlAxiGpio_Hal_IntInit(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_INTR_AttrStrct *Attr);
AL_VOID AlAxiGpio_Hal_IntrHandler(AL_VOID *Instance);

#ifdef __cplusplus
}
#endif

#endif
