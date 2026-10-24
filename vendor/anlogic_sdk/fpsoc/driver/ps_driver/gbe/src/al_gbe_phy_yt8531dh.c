/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_gbe_hal.h"
#include "al_gbe_phy.h"

#define PHY_SSR_REG                         0x11

#define REG_EXT_REG_ADDR_OFFSET             0x1E
#define REG_EXT_REG_DATA                    0x1F

#define REG_CHIP_CONFIG                     0xA001
#define REG_PAD_DRIVER_STRENGTH_CFG         0xA010

#define PHY_BCTL_RESET_MASK                 0x8000
#define PHY_BCTL_AUTONEG_MASK               0x1000
#define PHY_BCTL_RESTART_AUTONEG_MASK       0x0200

#define PHY_BSTATUS_AUTONEGCOMP_MASK        0x0020

#define PHY_ASYMMETRIC_PAUSE_MASK           0x0800
#define PHY_PAUSE_MASK                      0x0400

#define PHY_ADVERTISE_10HALF_MASK           0x0020  /* Try for 10mbps half-duplex  */
#define PHY_ADVERTISE_10FULL_MASK           0x0040  /* Try for 10mbps full-duplex  */
#define PHY_ADVERTISE_100HALF_MASK          0x0080  /* Try for 100mbps half-duplex */
#define PHY_ADVERTISE_100FULL_MASK          0x0100  /* Try for 100mbps full-duplex */
#define PHY_ADVERTISE_100BASE4_MASK         0x0200  /* Try for 100mbps 4k packets  */

#define PHY_1000BASET_FULLDUPLEX_MASK       0x0200
#define PHY_1000BASET_HALFDUPLEX_MASK       0x0100

#define PHY_ADVERTISE_100_AND_10_MASK       (PHY_ADVERTISE_10FULL_MASK | PHY_ADVERTISE_100FULL_MASK | \
                                             PHY_ADVERTISE_10HALF_MASK | PHY_ADVERTISE_100HALF_MASK)
#define PHY_ADVERTISE_100_MASK              (PHY_ADVERTISE_100FULL_MASK | PHY_ADVERTISE_100HALF_MASK)
#define PHY_ADVERTISE_10_MASK               (PHY_ADVERTISE_10FULL_MASK | PHY_ADVERTISE_10HALF_MASK)

#define PHY_ADVERTISE_1000_MASK             (PHY_1000BASET_FULLDUPLEX_MASK | PHY_1000BASET_HALFDUPLEX_MASK)

#define PHY_CFG_LDO_1V8_MASK1               0x20
#define PHY_CFG_LDO_1V8_MASK2               0x30
#define PHY_CFG_LDO_1V8_MASK                (PHY_CFG_LDO_1V8_MASK1 | PHY_CFG_LDO_1V8_MASK2)

AL_S32 AlPhy_YT8531WriteExtReg(AL_GBE_DevStruct *GbeDev, AL_U32 PHYAddr, AL_U32 PHYReg, AL_U16 RegValue)
{
    AL_S32 Ret = 0;

    Ret = AlGbe_Dev_WritePhyRegister(GbeDev, PHYAddr, REG_EXT_REG_ADDR_OFFSET, PHYReg);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    Ret = AlGbe_Dev_WritePhyRegister(GbeDev, PHYAddr, REG_EXT_REG_DATA, RegValue);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    return AL_OK;
}

AL_S32 AlPhy_YT8531ReadExtReg(AL_GBE_DevStruct *GbeDev, AL_U32 PHYAddr, AL_U32 PHYReg, AL_U16 *RegValue)
{
    AL_S32 Ret = 0;

    Ret = AlGbe_Dev_WritePhyRegister(GbeDev, PHYAddr, REG_EXT_REG_ADDR_OFFSET, PHYReg);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    Ret = AlGbe_Dev_ReadPhyRegister(GbeDev, PHYAddr, REG_EXT_REG_DATA, RegValue);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    return AL_OK;
}

static AL_S32 AlPhy_YT8531PadDriverCfg(AL_PHY_DevStruct *Phy)
{
    AL_S32 Ret = 0;
    AL_U16 RegValue = 0;

    AL_GBE_DevStruct *Gbe = Phy->DevObj;
    AL_U8 PHYAddress = Phy->PhyAddr;

    AlPhy_YT8531ReadExtReg(Gbe, PHYAddress, 0xf, &RegValue);
    if (0x31 != RegValue && 0x32 != RegValue) {
        Ret = AlPhy_YT8531WriteExtReg(Gbe, PHYAddress, 0x52, 0x231d);
        if (Ret < 0) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlPhy_YT8531WriteExtReg 0x52 error:%x\r\n", Ret);
            return Ret;
        }

        Ret = AlPhy_YT8531WriteExtReg(Gbe, PHYAddress, 0x51, 0x04a9);
        if (Ret < 0) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlPhy_YT8531WriteExtReg 0x51 error:%x\r\n", Ret);
            return Ret;
        }

        Ret = AlPhy_YT8531WriteExtReg(Gbe, PHYAddress, 0x57, 0x274c);
        if (Ret < 0) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlPhy_YT8531WriteExtReg 0x57 error:%x\r\n", Ret);
            return Ret;
        }

        if (0x500 == RegValue) {
            AlPhy_YT8531ReadExtReg(Gbe, PHYAddress, REG_CHIP_CONFIG, &RegValue);
            if ((PHY_CFG_LDO_1V8_MASK2 == (RegValue & PHY_CFG_LDO_1V8_MASK)) || (PHY_CFG_LDO_1V8_MASK1 == (RegValue & PHY_CFG_LDO_1V8_MASK))) {
                Ret = AlPhy_YT8531WriteExtReg(Gbe, PHYAddress, REG_PAD_DRIVER_STRENGTH_CFG, 0xabff);
                if (Ret < 0) {
                    AL_LOG(AL_LOG_LEVEL_ERROR, "AlPhy_YT8531WriteExtReg REG_PAD_DRIVER_STRENGTH_CFG error:%x\r\n", Ret);
                    return Ret;
                }
            }
        }

    }

    return AL_OK;
}


static AL_S32 AlPhy_YT8531Init(AL_PHY_DevStruct *Phy)
{
    AL_S32 Ret = 0;
    AL_U16 RegValue = 0;
    AL_U16 TmpRegValue = 0;

    AL_GBE_DevStruct *Gbe = Phy->DevObj;
    AL_U8 PHYAddress = Phy->PhyAddr;

    /* Reset the Phy */
    Ret = AlGbe_Dev_WritePhyRegister(Gbe, PHYAddress, PHY_BCR_REG, PHY_BCTL_RESET_MASK);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    /* Delay at least 10 ms */
    AlSys_MDelay(500);

    /* Check reset status complete */
    Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_BCR_REG, &RegValue);
    if ((Ret != AL_OK) || (RegValue & PHY_BCTL_RESET_MASK)) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
        return AL_GBE_ERR_PHY_RESET_FAILED;
    }

    AlPhy_YT8531PadDriverCfg(Phy);

    if (Gbe->MacDmaConfig.Speed == AL_GBE_SPEED_AUTONEG) {
        Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_AUTONEG_ADVERTISE_REG, &RegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
            return Ret;
        }

        RegValue |= PHY_ASYMMETRIC_PAUSE_MASK;
        RegValue |= PHY_PAUSE_MASK;
        RegValue |= PHY_ADVERTISE_100_MASK;
        RegValue |= PHY_ADVERTISE_10_MASK;
        Ret = AlGbe_Dev_WritePhyRegister(Gbe, PHYAddress, PHY_AUTONEG_ADVERTISE_REG, RegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
            return Ret;
        }

        Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_1000BASET_CONTROL_REG, &RegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
            return Ret;
        } 

        RegValue |= PHY_ADVERTISE_1000_MASK;
        Ret = AlGbe_Dev_WritePhyRegister(Gbe, PHYAddress, PHY_1000BASET_CONTROL_REG, RegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
            return Ret;
        }

    } else {

        Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_AUTONEG_ADVERTISE_REG, &RegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
            return Ret;
        }
        RegValue |= PHY_ASYMMETRIC_PAUSE_MASK;
        RegValue |= PHY_PAUSE_MASK;

        Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_1000BASET_CONTROL_REG, &TmpRegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
            return Ret;
        }

        if (Gbe->MacDmaConfig.Speed == AL_GBE_SPEED_100M) {
            RegValue |= PHY_ADVERTISE_100_MASK;
            RegValue &= ~(PHY_ADVERTISE_10_MASK);

            TmpRegValue &= ~(PHY_ADVERTISE_1000_MASK);
        } else if (Gbe->MacDmaConfig.Speed == AL_GBE_SPEED_10M) {
            RegValue &= ~(PHY_ADVERTISE_100_MASK);
            RegValue |= PHY_ADVERTISE_10_MASK;

            TmpRegValue &= ~(PHY_ADVERTISE_1000_MASK);
        } else {
            RegValue &= ~(PHY_ADVERTISE_100_MASK);
            RegValue &= ~(PHY_ADVERTISE_10_MASK);

            TmpRegValue |= PHY_ADVERTISE_1000_MASK;
        }

        Ret = AlGbe_Dev_WritePhyRegister(Gbe, PHYAddress, PHY_AUTONEG_ADVERTISE_REG, RegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
            return Ret;
        }
        Ret = AlGbe_Dev_WritePhyRegister(Gbe, PHYAddress, PHY_1000BASET_CONTROL_REG, TmpRegValue);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
            return Ret;
        }
    }

    Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_BCR_REG, &RegValue);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
        return Ret;
    }
    RegValue |= PHY_BCTL_AUTONEG_MASK;
    RegValue |= PHY_BCTL_RESTART_AUTONEG_MASK;
    Ret = AlGbe_Dev_WritePhyRegister(Gbe, PHYAddress, PHY_BCR_REG, RegValue);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_BCR_REG, &RegValue);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_ReadPhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    RegValue |= PHY_BCTL_RESET_MASK;
    Ret = AlGbe_Dev_WritePhyRegister(Gbe, PHYAddress, PHY_BCR_REG, RegValue);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlGbe_Dev_WritePhyRegister error:%x\r\n", Ret);
        return Ret;
    }

    while (1) {
        Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_BCR_REG, &RegValue);
        if ((Ret != AL_OK) || (RegValue & PHY_BCTL_RESET_MASK))
            continue;
        else
         break;
    }

    AL_U64 StartTick = AlSys_GetTimerTickCount();
    AL_U64 CurrentTick = 0;

    do {
        CurrentTick = AlSys_GetTimerTickCount();
        if (((CurrentTick - StartTick) * 1000) / AlSys_GetTimerFreq() > AL_GBE_PHY_READ_TIMEOUT_MS) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Phy Auto negotiation failed\r\n");
            return AL_GBE_ERR_TIMEOUT;
        }

        Ret = AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_BSR_REG, &RegValue);
    } while ((Ret != AL_OK) || (!(RegValue & PHY_BSTATUS_AUTONEGCOMP_MASK)));

    AL_LOG(AL_LOG_LEVEL_INFO, "Phy Auto negotiation complete\r\n");

    return AL_OK;
}

static AL_S32 AlPhy_Yt8531GetLinkStatus(AL_PHY_DevStruct *Phy, AL_BOOL *Status)
{
    AL_GBE_DevStruct *Gbe = Phy->DevObj;
    AL_U8 PHYAddress = Phy->PhyAddr;
    AL_U16 RegValue;

    AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_SSR_REG, &RegValue);

    RegValue = RegValue & 0x400;

    if (RegValue) {
        *Status = AL_TRUE;
    } else {
        *Status = AL_FALSE;
    }

    return AL_OK;
}

static AL_S32 AlPhy_Yt8531GetLinkSpeedDuplex(AL_PHY_DevStruct *Phy, AL_U8 *Speed, AL_U8 *Duplex)
{
    AL_GBE_DevStruct *Gbe = Phy->DevObj;
    AL_U8 PHYAddress = Phy->PhyAddr;
    AL_U16 RegValue;

     AL_U16 TempSpeed;

     AlGbe_Dev_ReadPhyRegister(Gbe, PHYAddress, PHY_SSR_REG, &RegValue);
     TempSpeed = RegValue >> 14;

     switch (TempSpeed)
     {
     case (AL_U32)PHY_SPEED_10M:
         *Speed = PHY_SPEED_10M;
         break;
     case (AL_U32)PHY_SPEED_100M:
         *Speed = PHY_SPEED_100M;
         break;
     case (AL_U32)PHY_SPEED_1000M:
         *Speed = PHY_SPEED_1000M;
         break;
     default:
         *Speed = PHY_SPEED_10M;
         break;
     }

     if ((RegValue & 0x2000) != 0U) {
         *Duplex = PHY_FULL_DUPLEX;
     } else {
         *Duplex = PHY_HALF_DUPLEX;
     }

    return AL_OK;
}

USED const struct AL_PHY_DevStruct PhyYt8531dh SECTION("gbe_phy_section") = {
    .PhyName = "YT8531DH",
    .PhyId = PHY_ID_YT8531,
#if (((GBE_DEVICE_ID == 0) && (PSGBE0_INTERFACE_TYPE == 0)) || ((GBE_DEVICE_ID == 1) && (PSGBE1_INTERFACE_TYPE == 0)))
    .PhyPhase100M  = PHY_YT8531_PHASE_100M,
    .PhyPhase1000M = PHY_YT8531_PHASE_1000M,

#elif (((GBE_DEVICE_ID == 0) && (PSGBE0_INTERFACE_TYPE == 1)) || ((GBE_DEVICE_ID == 1) && (PSGBE1_INTERFACE_TYPE == 1)))
    .PhyPhase100M  = 0xC90,
    .PhyPhase1000M = 0xC50,

#else
    .PhyPhase100M  = PHY_YT8531_PHASE_100M,
    .PhyPhase1000M = PHY_YT8531_PHASE_1000M,
#endif
    .Init = AlPhy_YT8531Init,
    .GetLinkStatus = AlPhy_Yt8531GetLinkStatus,
    .GetLinkSpeedDuplex = AlPhy_Yt8531GetLinkSpeedDuplex,
};