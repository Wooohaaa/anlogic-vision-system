/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_type.h"
#include "al_core.h"

#define TSG_CTRL_EN_CNT_BIT_POS  (0)

#define TOP_NS_PLS_PROT_OFFSET                 0x80UL
#define TOP_CRP_SRST_CTRL2_OFFSET              0x78UL

#define TOP_S_GLOBAL_SRST_N_OFFSET            0x330UL
#define TOP_S_GLOBAL_SRST_N_FCLK_SRST_N_SHIFT       4

#define TOP_NS_PLS_PROT_GP_PROTEN_SHIFT             1
#define TOP_CRP_SRST_CTRL2_GP0_SRST_N_SHIFT         4
#define TOP_CRP_SRST_CTRL2_HP0_SRST_N_SHIFT         0

AL_VOID Altop_Syscnts_CounterCtrl(AL_FUNCTION CntStatus)
{
    AL_REG32_SET_BIT(TOP_SYSCNT_S_BASE_ADDR, TSG_CTRL_EN_CNT_BIT_POS, CntStatus);
}

AL_VOID AlTop_GPPortEnable(AL_VOID)
{
    AL_U32 val = 0;

    /* Enable gp normal access */
    val = AL_REG32_READ(TOP_NS_BASE_ADDR + TOP_NS_PLS_PROT_OFFSET);
    val &= ~0x3;
    AL_REG32_WRITE(TOP_NS_BASE_ADDR + TOP_NS_PLS_PROT_OFFSET, val);

    /* Soft reset hp0, hp1, gp0, gp1 */
    val = 0;
    val = AL_REG32_READ(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET);
    AL_REG32_WRITE(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET, val & (~0x33));
    AlSys_MDelay(1);
    AL_REG32_WRITE(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET, val | 0x33);
}

/**
 * @brief: Reset assert for p2f signal.
 * @param: Index: 0~3
 */
AL_VOID AlTop_P2F_RstAssert(AL_U32 Index)
{
    AL_U32 val = 0;

    val = AL_REG32_READ(TOP_S_BASE_ADDR + TOP_S_GLOBAL_SRST_N_OFFSET);
    val &= ~(1 << (Index + TOP_S_GLOBAL_SRST_N_FCLK_SRST_N_SHIFT));
    AL_REG32_WRITE(TOP_S_BASE_ADDR + TOP_S_GLOBAL_SRST_N_OFFSET, val);
}

/**
 * @brief: Reset release for p2f signal.
 * @param: Index: 0~3
 */
AL_VOID AlTop_P2F_RstRelease(AL_U32 Index)
{
    AL_U32 val = 0;

    val = AL_REG32_READ(TOP_S_BASE_ADDR + TOP_S_GLOBAL_SRST_N_OFFSET);
    val |= (1 << (Index + TOP_S_GLOBAL_SRST_N_FCLK_SRST_N_SHIFT));
    AL_REG32_WRITE(TOP_S_BASE_ADDR + TOP_S_GLOBAL_SRST_N_OFFSET, val);
}

/**
 * @brief: Enable access protection for GP0 and GP1.
 */
AL_VOID AlTop_GP_ProtetionEnable(AL_VOID)
{
    AL_U32 val = 0;

    /* Enable gp normal access */
    val = AL_REG32_READ(TOP_NS_BASE_ADDR + TOP_NS_PLS_PROT_OFFSET);
    val |= (1 << TOP_NS_PLS_PROT_GP_PROTEN_SHIFT);
    AL_REG32_WRITE(TOP_NS_BASE_ADDR + TOP_NS_PLS_PROT_OFFSET, val);
}

/**
 * @brief: Disable access protection for GP0 and GP1.
 */
AL_VOID AlTop_GP_ProtetionDisable(AL_VOID)
{
    AL_U32 val = 0;

    /* Enable gp normal access */
    val = AL_REG32_READ(TOP_NS_BASE_ADDR + TOP_NS_PLS_PROT_OFFSET);
    val &= ~(1 << TOP_NS_PLS_PROT_GP_PROTEN_SHIFT);
    AL_REG32_WRITE(TOP_NS_BASE_ADDR + TOP_NS_PLS_PROT_OFFSET, val);
}

/**
 * @brief: Reset assert for GP.
 * @param: Index: 0~1
 */
AL_VOID AlTop_GP_RstAssert(AL_U32 GpIdx)
{
    AL_U32 val = 0;

    val = AL_REG32_READ(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET);
    val &= ~(1 << (GpIdx + TOP_CRP_SRST_CTRL2_GP0_SRST_N_SHIFT));
    AL_REG32_WRITE(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET, val);
}

/**
 * @brief: Reset release for GP.
 * @param: Index: 0~1
 */
AL_VOID AlTop_GP_RstRelease(AL_U32 GpIdx)
{
    AL_U32 val = 0;

    val = AL_REG32_READ(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET);
    val |= (1 << (GpIdx + TOP_CRP_SRST_CTRL2_GP0_SRST_N_SHIFT));
    AL_REG32_WRITE(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET, val);
}

/**
 * @brief: Reset assert for HP.
 * @param: Index: 0~1
 */
AL_VOID AlTop_HP_RstAssert(AL_U32 HpIdx)
{
    AL_U32 val = 0;

    val = AL_REG32_READ(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET);
    val &= ~(1 << (HpIdx + TOP_CRP_SRST_CTRL2_GP0_SRST_N_SHIFT));
    AL_REG32_WRITE(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET, val);
}

/**
 * @brief: Reset release for HP.
 * @param: Index: 0~1
 */
AL_VOID AlTop_HP_RstRelease(AL_U32 HpIdx)
{
    AL_U32 val = 0;

    val = AL_REG32_READ(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET);
    val |= (1 << (HpIdx + TOP_CRP_SRST_CTRL2_GP0_SRST_N_SHIFT));
    AL_REG32_WRITE(TOP_CRP_BASE_ADDR + TOP_CRP_SRST_CTRL2_OFFSET, val);
}
