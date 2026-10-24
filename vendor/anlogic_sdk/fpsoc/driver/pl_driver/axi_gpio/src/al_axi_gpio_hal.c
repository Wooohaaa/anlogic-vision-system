/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */



/***************************** Include Files *********************************/
#include "al_axi_gpio_hal.h"


static AlAxiGpio_Hal_Struct AXI_GPIO_Handle[AL_AXI_GPIO_NUM_INSTANCE];
extern AlAxiGpio_HwConfigStruct AlAxiGpio_HwConfig[AL_AXI_GPIO_NUM_INSTANCE];

/**
 * This function is called when a GPIO event occurs. It handles the event by doing nothing.
 *
 * @param Event The GPIO event structure.
 * @param CallbackRef Pointer to the callback reference.
 *
 * @return None.
 */
static AL_VOID AlAxiGpio_Hal_DefEventHandler(AlAxiGpio_EventStruct Event, AL_VOID *CallbackRef)
{
    (AL_VOID)Event;
    (AL_VOID)CallbackRef;
}

/**
 * This function searches through the list of hardware configurations to find the
 * configuration that matches the provided device ID.
 *
 * @param DevId The ID of the GPIO device.
 *
 * @return AlAxiGpio_HwConfigStruct* Pointer to the hardware configuration structure.
 */
AlAxiGpio_HwConfigStruct *AlAxiGpio_Hal_LookupConfig(AL_U32 DevId)
{
    AL_U32 Index;
    AlAxiGpio_HwConfigStruct *HwConfig = AL_NULL;

    for (Index = 0; Index < AL_AXI_GPIO_NUM_INSTANCE; Index++)
    {
        if (AlAxiGpio_HwConfig[Index].DeviceId == DevId)
        {
            HwConfig = &AlAxiGpio_HwConfig[Index];
            break;
        }
    }

    return HwConfig;
}

/**
 * This function initializes the GPIO HAL with the specified device ID and event callback.
 *
 * @param Handle Pointer to the handle structure.
 * @param DevId The ID of the GPIO device.
 * @param CallBack Pointer to the event callback function.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiGpio_Hal_Init(AlAxiGpio_Hal_Struct **Handle, AL_U32 DevId, AlAxiGpio_EventCallBack CallBack)
{
    AL_ASSERT(Handle != AL_NULL, AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    AL_S32 Ret = AL_OK;
    AlAxiGpio_HwConfigStruct *HwConfig = AL_NULL;

    HwConfig = AlAxiGpio_Hal_LookupConfig(DevId);
    if (HwConfig != AL_NULL) {
        (*Handle) = &AXI_GPIO_Handle[DevId];
    } else {
        return AL_ERR_ILLEGAL_PARAM;
    }

    (*Handle)->HwConfig = *HwConfig;

    if (CallBack != AL_NULL) {
        Ret = AlAxiGpio_Hal_RegisterEventCallBack(*Handle, CallBack, (AL_VOID *)(*Handle));
    } else {
        Ret = AlAxiGpio_Hal_RegisterEventCallBack(*Handle, AlAxiGpio_Hal_DefEventHandler, (AL_VOID *)(*Handle));
    }

    Ret = AlOsal_Lock_Init(&(*Handle)->Lock, "AxiGpio_Lock");
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlOsal_Mb_Init(&(*Handle)->EventQueue, "AxiGpio_MailBox");
    if (Ret != AL_OK) {
        return Ret;
    }

    return Ret;
}

/**
 * This function sets the direction of the specified GPIO channel.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param Channel The GPIO channel to set the direction for.
 * @param Direction The direction to set (input or output).
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiGpio_Hal_SetChannelDirection(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Direction)
{
    AL_ASSERT((Handle != AL_NULL) && (Channel < AXI_GPIO_MAX_CHANNEL), AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    AL_REG BaseAddr = Handle->HwConfig.BaseAddress;

    if (Channel == AL_AXI_GPIO_CHANNEL1) {
        AlAxiGpio_ll_SetChannelDir(BaseAddr, Direction);
    } else if (Channel == AL_AXI_GPIO_CHANNEL2) {
        AlAxiGpio_ll_SetChannelDir2(BaseAddr, Direction);
    }

    return AL_OK;
}

/**
 * This function sets the direction of the specified GPIO pin.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param Channel The GPIO channel to set the direction for.
 * @param Pin The GPIO pin to set the direction for.
 * @param Direction The direction to set (input or output).
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiGpio_Hal_SetPinDirection(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Pin, AlAxiGpio_ll_DirEnum Direction)
{
    AL_ASSERT((Handle != AL_NULL) && (Channel < AXI_GPIO_MAX_CHANNEL) && (Pin < AXI_GPIO_MAX_PIN), AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    if ((Direction != AL_AXI_GPIO_IN) && (Direction != AL_AXI_GPIO_OUT)) {
        return AL_ERR_ILLEGAL_PARAM;
    }

    AL_REG BaseAddr = Handle->HwConfig.BaseAddress;
    AL_U32 Dir = 0;
    AL_U32 Dir2 = 0;

    Dir = AlAxiGpio_ll_GetDir(BaseAddr, Pin);
    Dir2 = AlAxiGpio_ll_GetDir2(BaseAddr, Pin);

    if (Channel == AL_AXI_GPIO_CHANNEL1) {
        if (Direction != Dir) {
            AlAxiGpio_ll_SetDir(BaseAddr, Pin, Direction);
        }
    } else if (Channel == AL_AXI_GPIO_CHANNEL2) {
        if (Direction != Dir2) {
            AlAxiGpio_ll_SetDir2(BaseAddr, Pin, Direction);
        }
    }

    return AL_OK;
}

/**
 * This function writes a value to the specified GPIO pin.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param Channel The GPIO channel to write the value to.
 * @param Pin The GPIO pin to write the value to.
 * @param Value The value to write to the GPIO pin.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiGpio_Hal_WritePin(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Pin, AL_U32 Value)
{

    AL_ASSERT((Handle != AL_NULL) && (Channel < AXI_GPIO_MAX_CHANNEL) && (Pin < AXI_GPIO_MAX_PIN), AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    AL_REG BaseAddr = Handle->HwConfig.BaseAddress;

    if (Channel == AL_AXI_GPIO_CHANNEL1) {
        AlAxiGpio_ll_SetData(BaseAddr, Pin, Value);
    } else if (Channel == AL_AXI_GPIO_CHANNEL2) {
        AlAxiGpio_ll_SetData2(BaseAddr, Pin, Value);
    }

    return AL_OK;
}

/**
 * This function reads a value from the specified GPIO pin.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param Channel The GPIO channel to read the value from.
 * @param Pin The GPIO pin to read the value from.
 *
 * @return AL_U32 Returns the value read from the GPIO pin.
 */
AL_U32 AlAxiGpio_Hal_ReadPin(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Pin)
{
    AL_ASSERT((Handle != AL_NULL) && (Channel < AXI_GPIO_MAX_CHANNEL) && (Pin < AXI_GPIO_MAX_PIN), AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    AL_REG BaseAddr = Handle->HwConfig.BaseAddress;
    AL_U32 Value = 0;

    if (Channel == AL_AXI_GPIO_CHANNEL1) {
        Value = AlAxiGpio_ll_GetData(BaseAddr, Pin);
    } else if (Channel == AL_AXI_GPIO_CHANNEL2) {
        Value = AlAxiGpio_ll_GetData2(BaseAddr, Pin);
    }

    return Value;
}

/**
 * This function writes a value to the specified GPIO channel.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param Channel The GPIO channel to write the value to.
 * @param Value The value to write to the GPIO channel.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiGpio_Hal_WriteChannel(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_U32 Value)
{
    AL_ASSERT((Handle != AL_NULL) && (Channel < AXI_GPIO_MAX_CHANNEL), AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    AL_REG BaseAddr = Handle->HwConfig.BaseAddress;

    if (Channel == AL_AXI_GPIO_CHANNEL1) {
        AlAxiGpio_ll_SetChannelData(BaseAddr, Value);
    } else if (Channel == AL_AXI_GPIO_CHANNEL2) {
        AlAxiGpio_ll_SetChannelData2(BaseAddr, Value);
    }

    return AL_OK;
}

/**
 * This function reads a value from the specified GPIO channel.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param Channel The GPIO channel to read the value from.
 *
 * @return AL_U32 Returns the value read from the GPIO channel.
 */
AL_U32 AlAxiGpio_Hal_ReadChannel(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel)
{
    AL_ASSERT((Handle != AL_NULL) && (Channel < AXI_GPIO_MAX_CHANNEL), AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    AL_REG BaseAddr = Handle->HwConfig.BaseAddress;
    AL_U32 Value = 0;

    if (Channel == AL_AXI_GPIO_CHANNEL1) {
        Value = AlAxiGpio_ll_GetChannelData(BaseAddr);
    } else if (Channel == AL_AXI_GPIO_CHANNEL2) {
        Value = AlAxiGpio_ll_GetChannelData2(BaseAddr);
    }

    return Value;
}

/**
 * This function is the interrupt handler for the GPIO device. It checks the interrupt status and calls the
 * appropriate handler function for the specific interrupt condition.
 *
 * @param Instance Pointer to the GPIO HAL structure.
 * @return None.
 */
AL_VOID AlAxiGpio_Hal_IntrHandler(AL_VOID *Instance)
{
    AlAxiGpio_Hal_Struct *Handle = (AlAxiGpio_Hal_Struct *)Instance;
    AL_U32 IntStatus = AlAxiGpio_ll_GetIntStatus(Handle->HwConfig.BaseAddress);

    AlAxiGpio_ll_ClearInt(Handle->HwConfig.BaseAddress, IntStatus);

    AlAxiGpio_EventStruct Event =
    {
        .Channel = (IntStatus & BIT(AL_AXI_GPIO_CHANNEL1)) | (IntStatus & BIT(AL_AXI_GPIO_CHANNEL2)),
        .EventData = IntStatus
    };
    Handle->EventCallBack(Event, Handle->EventCallBackRef);
}

/**
 * This function initializes the GPIO interrupts for the specified channel.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param Channel The GPIO channel to initialize interrupts for.
 * @param Attr Pointer to the interrupt attribute structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiGpio_Hal_IntInit(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_ll_ChannelEnum Channel, AL_INTR_AttrStrct *Attr)
{
    AL_ASSERT((Handle != AL_NULL) && (Channel < AXI_GPIO_MAX_CHANNEL), AL_AXI_GPIO_ERR_ILLEGAL_PARAM);

    AL_REG BaseAddr = Handle->HwConfig.BaseAddress;

    switch (Channel)
    {
    case AL_AXI_GPIO_CHANNEL1:
        AlAxiGpio_ll_SetChannelInt(BaseAddr, AL_AXI_GPIO_CHANNEL1, AL_AXI_GPIO_INT_ENABLE);
        break;
    case AL_AXI_GPIO_CHANNEL2:
        AlAxiGpio_ll_SetChannelInt(BaseAddr, AL_AXI_GPIO_CHANNEL2, AL_AXI_GPIO_INT_ENABLE);
        break;
    default:
        break;
    }

    AlIntr_RegHandler(Handle->HwConfig.IntrId, Attr, AlAxiGpio_Hal_IntrHandler, Handle);

    return AL_OK;
}

/**
 * This function registers an event callback function for the GPIO device.
 *
 * @param Handle Pointer to the GPIO HAL structure.
 * @param CallBack Pointer to the callback function.
 * @param CallBackRef Pointer to the callback reference.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiGpio_Hal_RegisterEventCallBack(AlAxiGpio_Hal_Struct *Handle, AlAxiGpio_EventCallBack CallBack, AL_VOID *CallBackRef)
{
    Handle->EventCallBack = CallBack;
    Handle->EventCallBackRef = CallBackRef;
    return AL_OK;
}
