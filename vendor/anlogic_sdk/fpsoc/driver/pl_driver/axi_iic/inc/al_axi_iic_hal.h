/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_IIC_HAL_H_
#define AL_AXI_IIC_HAL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_iic_dev.h"


typedef struct
{
    AlAxiIic_DevStruct      Iic;
    AL_Lock                 Lock;
    AL_MailBox              EventQueue;
} AlAxiIic_HalStruct;

AL_S32 AlAxiIic_Hal_Init(AlAxiIic_HalStruct **Dev, AL_U32 DevId, AlAxiIic_InitStruct *InitConfig, AlAxiIic_EventCallBack EventCallBack);

AL_S32 AlAxiIic_Hal_MasterSendDataPolling(AlAxiIic_HalStruct *Dev, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode);
AL_S32 AlAxiIic_Hal_MasterRecvDataPolling(AlAxiIic_HalStruct *Dev, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode);

AL_S32 AlAxiIic_Hal_MasterSendDataBlock(AlAxiIic_HalStruct *Handle, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode, AL_U32 Timeout);
AL_S32 AlAxiIic_Hal_MasterRecvDataBlock(AlAxiIic_HalStruct *Handle, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode, AL_U32 Timeout);

AL_S32 AlAxiIic_Hal_SlaveSendDataPolling(AlAxiIic_HalStruct *Dev, AL_U8 *SendBuf, AL_U32 SendSize);
AL_S32 AlAxiIic_Hal_SlaveRecvDataPolling(AlAxiIic_HalStruct *Dev, AL_U8 *RecvBuf, AL_U32 RecvSize);

AL_S32 AlAxiIic_Hal_SlaveSendDataBlock(AlAxiIic_HalStruct *Handle, AL_U8 *SendBuf, AL_U32 SendSize, AL_U32 Timeout);
AL_S32 AlAxiIic_Hal_SlaveRecvDataBlock(AlAxiIic_HalStruct *Handle, AL_U8 *RecvBuf, AL_U32 RecvSize, AL_U32 Timeout);

#ifdef __cplusplus
}
#endif

#endif /* AL_AXI_IIC_HAL_H_ */
