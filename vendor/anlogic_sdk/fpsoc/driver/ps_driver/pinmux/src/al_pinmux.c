/*
 * Copyright (c) 2026, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_pinmux.h"


/**
 * This function selects the alternate function for the specified MIO pin. The Func parameter is a 32-bit packed value
 * that encodes the pure function selection, the function group and an EMIO support flag. The function parses these
 * fields, and when EMIO is supported it first forces the corresponding group to MIO mode before writing the function
 * selection value into the pin's FuncSel register.
 *
 * @param MioPin The MIO pin number to configure.
 * @param Func The packed function descriptor (FuncSel, group and EMIO support flag).
 * @return AL_OK if successful, error code otherwise.
 */
AL_U32 AlPinctrl_Mio_SetFunction(AL_U32 MioPin, AlPinctrl_FuncEnum Func)
{
    /* Step1: Check legal MIO pin number */
    AL_ASSERT(MioPin < AL_PINCTRL_MIO_PIN_MAX, AL_ERR_ILLEGAL_PARAM);

    /* Step2: Parse 3 fields from 32bit packed value */
    AL_U32 PureFuncSel = AL_PINCTRL_GET_FUNCSEL(Func);
    AlPinctrl_GroupEnum Group = (AlPinctrl_GroupEnum)AL_PINCTRL_GET_GROUP(Func);
    AlPinctrl_EmioSupportEnum EmioSupportFlag = AL_PINCTRL_GET_EMIO_SUPPORT(Func);

    /* Step3: If EMIO is supported, force group to MIO mode */
    if (EmioSupportFlag == AL_PINCTRL_EMIO_SUPPORT) {
        if (AlPinctrl_Emio_Select(Group, AL_PINCTRL_SEL_MIO) != AL_OK) {
            return AL_ERROR;
        }
    }

    /* Step4: Calculate MIO FuncSel register address (bank-aware) and write pure function value */
    AL_REG32_WRITE(AL_PINCTRL_MIO_FUNCSEL_ADDR(MioPin), PureFuncSel);

    return AL_OK;
}


/**
 * This function selects whether the specified function group is routed to the MIO or the EMIO interface. It writes the
 * selection value into the EMIO select register that corresponds to the given group.
 *
 * @param Group The function group to configure.
 * @param Select The routing selection (MIO or EMIO) for the group.
 * @return AL_OK if successful, error code otherwise.
 */
AL_U32 AlPinctrl_Emio_Select(AlPinctrl_GroupEnum Group, AlPinctrl_EmioSelEnum Select)
{
    AL_ASSERT(Group < AL_PINCTRL_GROUP_MAX, AL_ERR_ILLEGAL_PARAM);
    AL_REG32_WRITE(AL_PINCTRL_MIO_EMIOSEL_BASE + (Group * AL_PINCTRL_EMIOSEL_STRIDE), Select);
    return AL_OK;
}


/**
 * This function sets the slew rate (speed) of the specified MIO pin by updating the speed bit field of the pin's
 * PAD0 control register.
 *
 * @param MioPin The MIO pin number to configure.
 * @param Speed The slew rate (speed) level to apply.
 * @return AL_OK if successful, error code otherwise.
 */
AL_U32 AlPinctrl_Mio_SetSpeed(AL_U32 MioPin, AlPinctrl_SpeedEnum Speed)
{
    AL_ASSERT(Speed <= AL_PINCTRL_SPEED_FAST, AL_ERR_ILLEGAL_PARAM);

    /* Set the speed bit field of the target MIO pad control register */
    AL_REG32_SET_BITS(AL_PINCTRL_MIO_PAD0_CTL_ADDR(MioPin),
                      AL_PINCTRL_PADCTL_SPEED_SHIFT,
                      AL_PINCTRL_PADCTL_SPEED_MASK,
                      Speed);
    return AL_OK;
}


/**
 * This function configures the pull mode of the specified MIO pin. Depending on the PullConfig parameter it enables
 * the pull-up resistor, enables the pull-down resistor (each with the requested resistor value), or disables both.
 * The opposite pull direction is always disabled to avoid conflicting settings.
 *
 * @param MioPin The MIO pin number to configure.
 * @param PullConfig The pull mode to apply (pull-up, pull-down or disabled).
 * @param Resistor The resistor value to use when a pull-up or pull-down is enabled.
 * @return AL_OK if successful, error code otherwise.
 */
AL_U32 AlPinctrl_Mio_SetPullConfig(AL_U32 MioPin, AlPinctrl_PullEnum PullConfig,
                                   AlPinctrl_ResistorEnum Resistor)
{
    AL_U64 RegAddr = AL_PINCTRL_MIO_PAD0_CTL_ADDR(MioPin);

    switch (PullConfig) {
    case AL_PINCTRL_PULL_UP:
        /* Disable pull-down, enable pull-up, set resistor value */
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLDOWN_EN_SHIFT, AL_FUNC_DISABLE);
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLUP_EN_SHIFT, AL_FUNC_ENABLE);
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLUP_OHM_SHIFT, Resistor);
        break;

    case AL_PINCTRL_PULL_DOWN:
        /* Disable pull-up, enable pull-down, set resistor value */
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLUP_EN_SHIFT, AL_FUNC_DISABLE);
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLDOWN_EN_SHIFT, AL_FUNC_ENABLE);
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLDOWN_OHM_SHIFT, Resistor);
        break;

    case AL_PINCTRL_PULL_DISABLE:
    default:
        /* Disable pull-up and pull-down */
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLUP_EN_SHIFT, AL_FUNC_DISABLE);
        AL_REG32_SET_BIT(RegAddr, AL_PINCTRL_PADCTL_PULLDOWN_EN_SHIFT, AL_FUNC_DISABLE);
        break;
    }

    return AL_OK;
}


/**
 * This function configures the electrical characteristics of the specified MIO pin. It sets the receiver mode and
 * looks up the pull-up and pull-down drive strengths from internal tables indexed by the selected voltage level and
 * the requested drive strengths, then writes the assembled value into the pin's PAD1 control register.
 *
 * @param MioPin The MIO pin number to configure.
 * @param RecvMode The receiver mode to apply.
 * @param Voltage The I/O voltage level used to index the drive strength tables.
 * @param UpDrive The pull-up drive strength to apply.
 * @param DownDrive The pull-down drive strength to apply.
 * @return The value written to the PAD1 control register.
 */
AL_U32 AlPinctrl_Mio_SetElecConfig(AL_U32 MioPin,
                                   AlPinctrl_RecvModeEnum RecvMode,
                                   AlPinctrl_VoltageEnum Voltage,
                                   AlPinctrl_DriveEnum UpDrive,
                                   AlPinctrl_DriveEnum DownDrive)
{
    AL_ASSERT(RecvMode  <= MIO_RECV_3V3_OR_2V5, AL_ERR_ILLEGAL_PARAM);
    AL_ASSERT(Voltage   <= MIO_VOLTAGE_1V5, AL_ERR_ILLEGAL_PARAM);
    AL_ASSERT(UpDrive   <= MIO_DRIVE_20MA, AL_ERR_ILLEGAL_PARAM);
    AL_ASSERT(DownDrive <= MIO_DRIVE_20MA, AL_ERR_ILLEGAL_PARAM);

    /* Pull-up drive strength table [voltage][drive] */
    static const AL_U8 PullUpConfig[4][5] = {
        /* 3.3V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x0B, 0x01, 0x17, 0x12, 0x13},
        /* 2.5V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x09, 0x0B, 0x1B, 0x17, 0x11},
        /* 1.8V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x09, 0x06, 0x18, 0x15, 0x17},
        /* 1.5V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x09, 0x1D, 0x19, 0x17, 0x11}
    };

    /* Pull-down drive strength table [voltage][drive] */
    static const AL_U8 PullDownConfig[4][5] = {
        /* 3.3V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x0A, 0x1E, 0x15, 0x17, 0x12},
        /* 2.5V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x0A, 0x1E, 0x15, 0x17, 0x12},
        /* 1.8V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x0A, 0x1E, 0x15, 0x17, 0x12},
        /* 1.5V:  4mA,  8mA, 12mA, 16mA, 20mA */
                {0x0A, 0x1E, 0x15, 0x17, 0x12}
    };

    AL_U32 RegValue = 0;
    RegValue |= (AL_U32)RecvMode;
    RegValue |= (AL_U32)PullUpConfig[Voltage][UpDrive] << AL_PINCTRL_PADCTL_PULL_UP_DRV_SHIFT;
    RegValue |= (AL_U32)PullDownConfig[Voltage][DownDrive] << AL_PINCTRL_PADCTL_PULL_DOWN_DRV_SHIFT;

    AL_REG32_WRITE(AL_PINCTRL_MIO_PAD1_CTL_ADDR(MioPin), RegValue);

    return RegValue;
}
