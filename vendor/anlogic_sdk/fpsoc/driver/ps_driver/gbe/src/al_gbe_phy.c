/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_hal.h"
#include "al_gbe_phy.h"

#include <string.h>

/**
 *
 * This function writes a specified value to a PHY register. It checks if the GMII interface is
 * busy before proceeding with the write operation. It prepares the MDIO Address Register value,
 * writes the value to the MII data register, and then writes the result into the MII Address
 * register. It waits for the GMII interface to become available before completing.
 *
 * @param Gbe Pointer to the GBE device structure.
 * @param PHYAddr The PHY device address.
 * @param PHYReg The PHY register address.
 * @param RegValue The value to write to the PHY register.
 * @return AL_OK on success, error code otherwise.
 */
AL_S32 AlGbe_Dev_WritePhyRegister(AL_VOID *GbeDev, AL_U32 PHYAddr, AL_U32 PHYReg, AL_U16 RegValue)
{
    AL_GBE_DevStruct *Gbe = (AL_GBE_DevStruct *)GbeDev;
    AL_REG GbeBaseAddr = (AL_REG)(Gbe->HwConfig.BaseAddress);
    AL_U32 TmpReg;

    if (Gbe->HwConfig.DeviceId == 0) {
#ifdef GBE0_MDIO_PSIO
        *(AL_U32 *)(0xf88030d0u) = 0xe; //PS_ETH_MDC     PS_IO52 mdc0__emio_o_13 (out)        Function_14
        *(AL_U32 *)(0xf88030d4u) = 0xe; //PS_ETH_MDIO    PS_IO53 mdio0__emio_io_13 (inout)    Function_14
        *(AL_U32 *)(0xf8803434u) = 0x1; //EMIOSEL_13     1:MIO 0:EMIO
#endif
    } else {
#ifdef GBE1_MDIO_PSIO
            *(AL_U32 *)(0xf88030d0u) = 0xf; //PS_ETH_MDC     PS_IO52 mdc1__emio_o_14 (out)        Function_15
            *(AL_U32 *)(0xf88030d4u) = 0xf; //PS_ETH_MDIO    PS_IO53 mdio1__emio_io_14 (inout)    Function_15
            *(AL_U32 *)(0xf8803438u) = 0x1; //EMIOSEL_13     1:MIO 0:EMIO
#endif
    }

    /* Check for the Busy flag */
    if (AlGbe_ll_IsGmiiBusy(GbeBaseAddr)) {
        return AL_GBE_ERR_PHY_BUSY;
    }

    /* Get the  MACMDIOAR value */
    TmpReg = AlGbe_ll_ReadMdioAddr(GbeBaseAddr);

    /*
       Prepare the MDIO Address Register value
     - Set the PHY device address
     - Set the PHY register address
     - Set the write mode
     - Set the MII Busy bit
    */
    AL_REG32_SET_BITS(&TmpReg, GBE__MAC_MDIO_ADDRESS__PA__SHIFT, GBE__MAC_MDIO_ADDRESS__PA__SIZE, PHYAddr);
    AL_REG32_SET_BITS(&TmpReg, GBE__MAC_MDIO_ADDRESS__RDA__SHIFT, GBE__MAC_MDIO_ADDRESS__RDA__SIZE, PHYReg);
    AL_REG32_SET_BITS(&TmpReg, GBE__MAC_MDIO_ADDRESS__GOC_0__SHIFT, GBE__MAC_MDIO_ADDRESS__GOC__SIZE, AL_GBE_GMII_CMD_WRITE);
    AL_REG32_SET_BIT(&TmpReg, GBE__MAC_MDIO_ADDRESS__GB__SHIFT, AL_GBE_FUNC_ENABLE);

    /* Give the value to the MII data register */
    AlGbe_ll_WriteMdioGmiiData(GbeBaseAddr, (AL_U16)RegValue);

    /* Write the result value into the MII Address register */
    AlGbe_ll_WriteMdioAddr(GbeBaseAddr, TmpReg);

    /* Wait for the Busy flag */
    while (AlGbe_ll_IsGmiiBusy(GbeBaseAddr)) {
        //ToDo: TimeOut
    }

  return AL_OK;
}

/**
 *
 * This function reads a value from a specified PHY register. It checks if the GMII interface is
 * busy before proceeding with the read operation. It prepares the MDIO Address Register value,
 * writes the result into the MII Address register, and waits for the GMII interface to become
 * available. It then reads the value from the MII data register.
 *
 * @param Gbe Pointer to the GBE device structure.
 * @param PHYAddr The PHY device address.
 * @param PHYReg The PHY register address.
 * @param RegValue Pointer to store the read value from the PHY register.
 * @return AL_OK on success, error code otherwise.
 */
AL_S32 AlGbe_Dev_ReadPhyRegister(AL_VOID *GbeDev, AL_U32 PHYAddr, AL_U32 PHYReg, AL_U16 *RegValue)
{
    AL_GBE_DevStruct *Gbe = (AL_GBE_DevStruct *)GbeDev;
    AL_REG GbeBaseAddr = (AL_REG)(Gbe->HwConfig.BaseAddress);
    AL_U32 TmpReg;

    if (Gbe->HwConfig.DeviceId == 0) {

#ifdef GBE0_MDIO_PSIO
        *(AL_U32 *)(0xf88030d0u) = 0xe; //PS_ETH_MDC     PS_IO52 mdc0__emio_o_13 (out)        Function_14
        *(AL_U32 *)(0xf88030d4u) = 0xe; //PS_ETH_MDIO    PS_IO53 mdio0__emio_io_13 (inout)    Function_14
        *(AL_U32 *)(0xf8803434u) = 0x1; //EMIOSEL_13     1:MIO 0:EMIO
#endif
    } else {

#ifdef GBE1_MDIO_PSIO
            *(AL_U32 *)(0xf88030d0u) = 0xf; //PS_ETH_MDC     PS_IO52 mdc1__emio_o_14 (out)        Function_15
            *(AL_U32 *)(0xf88030d4u) = 0xf; //PS_ETH_MDIO    PS_IO53 mdio1__emio_io_14 (inout)    Function_15
            *(AL_U32 *)(0xf8803438u) = 0x1; //EMIOSEL_13     1:MIO 0:EMIO
#endif
    }

    /* Check for the Busy flag */
    if (AlGbe_ll_IsGmiiBusy(GbeBaseAddr)) {
        return AL_GBE_ERR_PHY_BUSY;
    }

    /* Get the  MACMDIOAR value */
    TmpReg = AlGbe_ll_ReadMdioAddr(GbeBaseAddr);

    /*
       Prepare the MDIO Address Register value
     - Set the PHY device address
     - Set the PHY register address
     - Set the read mode
     - Set the MII Busy bit
    */
    AL_REG32_SET_BITS(&TmpReg, GBE__MAC_MDIO_ADDRESS__PA__SHIFT, GBE__MAC_MDIO_ADDRESS__PA__SIZE, PHYAddr);
    AL_REG32_SET_BITS(&TmpReg, GBE__MAC_MDIO_ADDRESS__RDA__SHIFT, GBE__MAC_MDIO_ADDRESS__RDA__SIZE, PHYReg);
    AL_REG32_SET_BITS(&TmpReg, GBE__MAC_MDIO_ADDRESS__GOC_0__SHIFT, GBE__MAC_MDIO_ADDRESS__GOC__SIZE, AL_GBE_GMII_CMD_READ);
    AL_REG32_SET_BIT(&TmpReg, GBE__MAC_MDIO_ADDRESS__GB__SHIFT, AL_GBE_FUNC_ENABLE);

    /* Write the result value into the MII Address register */
    AlGbe_ll_WriteMdioAddr(GbeBaseAddr, TmpReg);

    /* Wait for the Busy flag */
    while (AlGbe_ll_IsGmiiBusy(GbeBaseAddr)) {
        //ToDo: TimeOut
    }

    /* Get MACMIIDR value */
    *RegValue = (AL_U16)AlGbe_ll_ReadMdioGmiiData(GbeBaseAddr);

    return AL_OK;
}

extern AL_UINTPTR _gbe_phy_section_start, _gbe_phy_section_end;
AL_S32 AlGbe_Dev_DetectPhy(AL_VOID *GbeDev)
{
    AL_S32 Index;
    AL_U8  PhyAddr = 0;
    AL_U16 PhyId1, PhyId2;
    AL_U32 PhyId;

    AL_UINTPTR Ptr;
    struct AL_PHY_DevStruct *Phy = AL_NULL;

    AL_GBE_DevStruct *Gbe = (AL_GBE_DevStruct *)GbeDev;
    PhyAddr = Gbe->PhyDev.PhyAddr;

    if (PhyAddr != 0) {

        AlGbe_Dev_ReadPhyRegister(Gbe, PhyAddr, PHY_ID1_REG, &PhyId1);
        AlGbe_Dev_ReadPhyRegister(Gbe, PhyAddr, PHY_ID2_REG, &PhyId2);
    } else {

        /*
        Read the ID register of the phy from address 31 until address 0.
        Some boards may use broadcast address 0 as the address of the Phy.
        */
        for (Index = 31; Index >= 0; Index--) {
            AlGbe_Dev_ReadPhyRegister(Gbe, Index, PHY_ID1_REG, &PhyId1);
            AlGbe_Dev_ReadPhyRegister(Gbe, Index, PHY_ID2_REG, &PhyId2);

            if ((PhyId1 != 0xFFFF && PhyId1 != 0x00) || (PhyId2 != 0xFFFF && PhyId2 != 0x00)) {
                PhyAddr = Index;
                break;
            }
        }

        if (Index < 0) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "No Phy device detected.\r\n");
            return AL_GBE_ERR_PHY_NOT_FOUND;
        }

    }

    PhyId = ((PhyId1 & 0xffff) << 16) | (PhyId2 & 0xffff);
    for (Ptr = (AL_UINTPTR)(&_gbe_phy_section_start); Ptr < (AL_UINTPTR)(&_gbe_phy_section_end);) {
        Phy = (struct AL_PHY_DevStruct *)Ptr;

        if (Phy->PhyId == PhyId) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Phy detected, Phy is %s\r\n", Phy->PhyName);
            break;
        }

        Ptr += sizeof(struct AL_PHY_DevStruct);
        Phy = AL_NULL;
    }

    if (Phy == AL_NULL) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Unsupport PHY, Phy ID:%x\r\n", PhyId);
        return AL_GBE_ERR_PHY_UNSUPPORT;
    }

    memcpy(&Gbe->PhyDev, Phy, sizeof(AL_PHY_DevStruct));
    Gbe->PhyDev.PhyAddr = PhyAddr;
    Gbe->PhyDev.DevObj = Gbe;

    return AL_OK;
}

AL_S32 AlGbe_DetectPhy(AL_VOID *GbeHandle)
{
    AL_S32 Ret;

    AL_ASSERT((GbeHandle != AL_NULL), AL_GBE_ERR_ILLEGAL_PARAM);

    AL_GBE_HalStruct *Handle = (AL_GBE_HalStruct *)GbeHandle;
    Ret = AlGbe_Dev_DetectPhy(&Handle->Dev);

    return Ret;
}

/**
 * This function performs several operations to initialize the PHY device, including reading the PHY ID,
 * resetting the PHY, configuring RGMII delays, setting up auto-negotiation, and enabling or disabling
 * 1000BaseT full duplex mode based on the MAC DMA configuration. It handles different PHY models by checking
 * the PHY ID and applies specific initialization sequences for each. The function also ensures that the PHY
 * is reset properly and waits for auto-negotiation to complete if applicable.
 *
 * @param Gbe Pointer to the GBE device structure.
 * @param PHYAddress The address of the PHY device to initialize.
 * @return AL_OK on success, or an error code on failure.
 *
 * @retval AL_GBE_ERR_ILLEGAL_PARAM Indicates an illegal parameter error.
 * @retval AL_GBE_ERR_PHY_RESET_FAILED Indicates that resetting the PHY device failed.
 */
AL_S32 AlGbe_PhyInit(AL_PHY_DevStruct *Phy)
{
    AL_S32 Ret;

    AL_ASSERT((Phy != AL_NULL), AL_GBE_ERR_ILLEGAL_PARAM);

    Ret = Phy->Init(Phy);

    return Ret;
}

/**
 * Gets the PHY link status.
 *
 * @param Handle Pointer to the GBE HAL structure.
 * @param PhyAddr PHY address.
 * @param Speed Pointer to store the speed.
 * @param Duplex Pointer to store the duplex mode.
 * @return AL_OK on success, error code otherwise.
 */
AL_S32 AlGbe_GetPhyLinkStatus(AL_PHY_DevStruct *Phy, AL_BOOL *Status)
{
    AL_S32 Ret;

    AL_ASSERT((Phy != AL_NULL) && (Status != AL_NULL), AL_GBE_ERR_ILLEGAL_PARAM);

    Ret = Phy->GetLinkStatus(Phy, Status);

    return Ret;
}

/**
 * This function queries the PHY link status, including speed and duplex mode, for a specified PHY address.
 *
 * @param Gbe Pointer to the GBE device structure.
 * @param PHYAddress The address of the PHY to query.
 * @param Speed Pointer to a variable where the link speed will be stored.
 * @param Duplex Pointer to a variable where the duplex mode will be stored.
 * @return Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlGbe_GetPhyLinkSpeedDuplex(AL_PHY_DevStruct *Phy, AL_U8 *Speed, AL_U8 *Duplex)
{
    AL_S32 Ret;

    AL_ASSERT((Phy != AL_NULL) && (Speed != AL_NULL) && (Duplex != AL_NULL), AL_GBE_ERR_ILLEGAL_PARAM);

    Ret = Phy->GetLinkSpeedDuplex(Phy, Speed, Duplex);

    return Ret;
}