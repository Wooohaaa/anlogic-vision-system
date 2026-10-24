/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_IIC_LL_H_
#define AL_AXI_IIC_LL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_iic_hw.h"
#include "al_utils_def.h"
#include "al_reg_io.h"

typedef enum
{
    AL_AXI_IIC_FUNC_DISABLE     = 0,
    AL_AXI_IIC_FUNC_ENABLE      = 1
} AlAxiIic_FunctionEnum;

typedef enum
{
    MASTER_TX       = 0,
    MASTER_RX       = 1
} AlAxiIic_MasterDirEnum;

typedef enum
{
    SLAVE_RX       = 0,
    SLAVE_TX       = 1
} AlAxiIic_SlaveDirEnum;

typedef enum
{
    AL_AXI_IIC_CMD_NONE         = 0x0,
    AL_AXI_IIC_CMD_TRANS        = 0x1,
    AL_AXI_IIC_CMD_ACK          = 0x2,
    AL_AXI_IIC_CMD_NACK         = 0x3,
    AL_AXI_IIC_CMD_CLR_FIFO     = 0x4,
    AL_AXI_IIC_CMD_RST          = 0x5
} AlAxiIic_CmdEnum;

typedef enum
{
    AL_AXI_IIC_SCL_RATIO_1         = 0,
    AL_AXI_IIC_SCL_RATIO_2         = 1
} AlAxiIic_SclRatioEnum;

typedef enum
{
    AL_AXI_IIC_SLAVE            = 0,
    AL_AXI_IIC_MASTER           = 1
} AlAxiIic_ModeEnum;

typedef enum
{
    AL_AXI_IIC_7BIT            = 0,
    AL_AXI_IIC_10BIT           = 1
} AlAxiIic_AddressModeEnum;

/***************************** AXI_IIC_ID_OFFSET Register    *****************************/
static inline AL_U32 AlAxiIic_ll_ReadId(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AXI_IIC_ID_OFFSET, AXI_IIC_ID_START, AXI_IIC_ID_SIZE);
}

/***************************** AXI_IIC_CFG_OFFSET Register   *****************************/
static inline AL_U32 AlAxiIic_ll_GetFifoSize(AL_U64 BaseAddr)
{
    AL_U32 Cfg, FifoSize;
    Cfg = AL_PL_REG32_GET_BITS(BaseAddr + AXI_IIC_CFG_OFFSET, AXI_IIC_CFG_START, AXI_IIC_CFG_SIZE);
    switch (Cfg)
    {
        case 0: FifoSize = 2; break;
        case 1: FifoSize = 4; break;
        case 2: FifoSize = 8; break;
        case 3: FifoSize = 16; break;
        default: FifoSize = 0; break;
    }
    return FifoSize;
}

/***************************** AXI_IIC_INTEN_OFFSET Register *****************************/
static inline AL_VOID AlAxiIic_ll_EnableInt(AL_U64 BaseAddr, AL_U32 IntMask)
{
    AL_U32 CurrentIntMask;

    CurrentIntMask = AL_PL_REG32_READ(BaseAddr + AXI_IIC_INTEN_OFFSET);

    CurrentIntMask |= IntMask;

    AL_REG32_WRITE(BaseAddr + AXI_IIC_INTEN_OFFSET, CurrentIntMask);
}

static inline AL_VOID AlAxiIic_ll_DisableInt(AL_U64 BaseAddr, AL_U32 IntMask)
{
    AL_U32 CurrentIntMask;

    CurrentIntMask = AL_PL_REG32_READ(BaseAddr + AXI_IIC_INTEN_OFFSET);

    CurrentIntMask &= ~IntMask;

    AL_REG32_WRITE(BaseAddr + AXI_IIC_INTEN_OFFSET, CurrentIntMask);
}

static inline AL_U32 AlAxiIic_ll_GetIntMusk(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_IIC_INTEN_OFFSET);
}

static inline AL_VOID AlAxiIic_ll_ClearIntStatus(AL_U64 BaseAddr, AL_U32 IntMask)
{
    AL_REG32_WRITE(BaseAddr + AXI_IIC_SR_OFFSET, IntMask);
}

/***************************** AXI_IIC_SR_OFFSET Register    *****************************/
static inline AL_U32 AlAxiIic_ll_GetStatus(AL_U64 BaseAddr, AL_U32 StatusBit)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AXI_IIC_SR_OFFSET, StatusBit);
}

static inline AL_U32 AlAxiIic_ll_GetStatusAll(AL_U64 BaseAddr)
{
    return AL_PL_REG32_READ(BaseAddr + AXI_IIC_SR_OFFSET);
}

static inline AL_VOID AlAxiIic_ll_ClearStatus(AL_U64 BaseAddr, AL_U32 StatusBit)
{
    AL_REG32_WRITE(BaseAddr + AXI_IIC_SR_OFFSET, (1 << StatusBit));
}

static inline AL_VOID AlAxiIic_ll_ClearStatusAll(AL_U64 BaseAddr)
{
    AL_U32 CurrentStatus;

    CurrentStatus = AL_PL_REG32_READ(BaseAddr + AXI_IIC_SR_OFFSET);
    AL_REG32_WRITE(BaseAddr + AXI_IIC_SR_OFFSET, CurrentStatus);
}

/***************************** AXI_IIC_ADDR_OFFSET Register  *****************************/
static inline AL_VOID AlAxiIic_ll_SetSlaveAddr(AL_U64 BaseAddr, AL_U32 SlaveAddr)
{
    AL_REG32_WRITE(BaseAddr + AXI_IIC_ADDR_OFFSET, SlaveAddr);
}

/***************************** AXI_IIC_DATA_OFFSET Register  *****************************/
static inline AL_VOID AlAxiIic_ll_SetData(AL_U64 BaseAddr, AL_U32 Data)
{
    AL_REG32_WRITE(BaseAddr + AXI_IIC_DATA_OFFSET, Data);
}

static inline AL_U32 AlAxiIic_ll_GetData(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BITS(BaseAddr + AXI_IIC_DATA_OFFSET, 0, 8);
}

/***************************** AXI_IIC_CR_OFFSET Register    *****************************/
static inline AL_VOID AlAxiIic_ll_SetPhaseStart(AL_U64 BaseAddr, AlAxiIic_FunctionEnum State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_CR_OFFSET, CR_PHASE_START, State);
}

static inline AL_VOID AlAxiIic_ll_SetPhaseAddr(AL_U64 BaseAddr, AlAxiIic_FunctionEnum State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_CR_OFFSET, CR_PHASE_ADDR, State);
}

static inline AL_VOID AlAxiIic_ll_SetPhaseData(AL_U64 BaseAddr, AlAxiIic_FunctionEnum State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_CR_OFFSET, CR_PHASE_DATA, State);
}

static inline AL_VOID AlAxiIic_ll_SetPhaseStop(AL_U64 BaseAddr, AlAxiIic_FunctionEnum State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_CR_OFFSET, CR_PHASE_STOP, State);
}

static inline AL_VOID AlAxiIic_ll_SetDir(AL_U64 BaseAddr, AL_BOOL IicDir)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_CR_OFFSET, CR_DIR, IicDir);
}

static inline AL_BOOL AlAxiIic_ll_GetDir(AL_U64 BaseAddr)
{
    return AL_PL_REG32_GET_BIT(BaseAddr + AXI_IIC_CR_OFFSET, CR_DIR);
}

static inline AL_VOID AlAxiIic_ll_SetDataCnt(AL_U64 BaseAddr, AL_U32 DataCnt)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_IIC_CR_OFFSET, CR_DATA_CNT, CR_DATA_CNT_SIZE, DataCnt);
}

/***************************** AXI_IIC_CMD_OFFSET Register   *****************************/
static inline AL_VOID AlAxiIic_ll_SetCmd(AL_U64 BaseAddr, AlAxiIic_CmdEnum Cmd)
{
    AL_REG32_WRITE(BaseAddr + AXI_IIC_CMD_OFFSET, Cmd);
}

/***************************** AXI_IIC_SETUP_OFFSET Register *****************************/
static inline AL_VOID AlAxiIic_ll_SetSuTime(AL_U64 BaseAddr, AL_U32 SuTime)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_IIC_SETUP_OFFSET, T_SUDAT, T_SUDAT_SIZE, SuTime);
}

static inline AL_VOID AlAxiIic_ll_SetSp(AL_U64 BaseAddr, AL_U32 Sp)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_IIC_SETUP_OFFSET, T_SP, T_SP_SIZE, Sp);
}

static inline AL_VOID AlAxiIic_ll_SetHdTime(AL_U64 BaseAddr, AL_U32 HdTime)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_IIC_SETUP_OFFSET, T_HDDAT, T_HDDAT_SIZE, HdTime);
}

static inline AL_VOID AlAxiIic_ll_SetSclRatio(AL_U64 BaseAddr, AlAxiIic_SclRatioEnum SclRatio)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_SETUP_OFFSET, T_SCL_RATIO, SclRatio);
}

static inline AL_VOID AlAxiIic_ll_SetSclHighTime(AL_U64 BaseAddr, AL_U32 SclHighTime)
{
    AL_PL_REG32_SET_BITS(BaseAddr + AXI_IIC_SETUP_OFFSET, T_SCL_HIGH, T_SCL_HIGH_SIZE, SclHighTime);
}

static inline AL_VOID AlAxiIic_ll_SetMode(AL_U64 BaseAddr, AlAxiIic_ModeEnum Mode)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_SETUP_OFFSET, IIC_MODE, Mode);
}

static inline AL_VOID AlAxiIic_ll_SetAddressMode(AL_U64 BaseAddr, AlAxiIic_AddressModeEnum AddressMode)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_SETUP_OFFSET, IIC_ADDRESS_MODE, AddressMode);
}

static inline AL_VOID AlAxiIic_ll_EnableIP(AL_U64 BaseAddr, AlAxiIic_FunctionEnum State)
{
    AL_PL_REG32_SET_BIT(BaseAddr + AXI_IIC_SETUP_OFFSET, IIC_EN, State);
}

/***************************** AXI_IIC_TPM_OFFSET Register   *****************************/


#ifdef __cplusplus
}
#endif

#endif /* AL_AXI_IIC_LL_H_ */
