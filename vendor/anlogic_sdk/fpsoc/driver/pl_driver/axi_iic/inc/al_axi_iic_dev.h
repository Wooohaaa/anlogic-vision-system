/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_IIC_DEV_H_
#define AL_AXI_IIC_DEV_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_errno.h"
#include "al_axi_iic_ll.h"

#define AXI_IIC_ID 0x020210

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_AxiIic_EVENT_START_BIT    6
#define AL_AxiIic_ERR_NULL_PTR                 (AL_DEF_ERR(AL_AxiIic, AL_LOG_LEVEL_ERROR, AL_ERR_NULL_PTR))
#define AL_AxiIic_ERR_ILLEGAL_PARAM            (AL_DEF_ERR(AL_AxiIic, AL_LOG_LEVEL_ERROR, AL_ERR_ILLEGAL_PARAM))
#define AL_AxiIic_ERR_BUSY                     (AL_DEF_ERR(AL_AxiIic, AL_LOG_LEVEL_ERROR, AL_ERR_BUSY))
#define AL_AxiIic_ERR_NOT_SUPPORT              (AL_DEF_ERR(AL_AxiIic, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_SUPPORT))
#define AL_AxiIic_EVENTS_TO_ERRS(Events)       (AL_DEF_ERR(AL_AxiIic, AL_LOG_LEVEL_ERROR, Events << AL_AxiIic_EVENT_START_BIT))

typedef enum {
    // Idle state
    AL_AXI_IIC_IDLE             = 0,

    // Slave states
    AL_AXI_IIC_SLAVE_RX_BUSY    = 1,
    AL_AXI_IIC_SLAVE_RX_DONE    = 2,
    AL_AXI_IIC_SLAVE_TX_BUSY    = 3,
    AL_AXI_IIC_SLAVE_TX_DONE    = 4,

    // Master states
    AL_AXI_IIC_MASTER_RX_BUSY   = 5,
    AL_AXI_IIC_MASTER_RX_DONE   = 6,
    AL_AXI_IIC_MASTER_TX_BUSY   = 7,
    AL_AXI_IIC_MASTER_TX_DONE   = 8
} AlAxiIic_StatusEnum;

typedef struct {
    AlAxiIic_FunctionEnum         PhaseStart;
    AlAxiIic_FunctionEnum         PhaseAddr;
    AlAxiIic_FunctionEnum         PhaseData;
    AlAxiIic_FunctionEnum         PhaseStop;
    AL_U32                        SlaveAddr;
} AlAxiIic_TransactionStruct;

typedef struct {
    AL_U8   *BuffPtr;
    AL_U32  DataCnt;
    AL_U32  ReqCnt;
} AlAxiIic_BufferStruct;

typedef enum {
    AL_AXI_IIC_STANDARD_MODE        = 0,
    AL_AXI_IIC_FAST_MODE            = 1,
    AL_AXI_IIC_HIGH_SPEED_MODE      = 2
} AlAxiIic_SpeedModeEnum;

typedef struct {
    AlAxiIic_ModeEnum               IIC_Mode;           // Specifies the IIC operating mode: Master Mode / Slave Mode
    AlAxiIic_AddressModeEnum        IIC_AddressMode;    // Specifies the IIC addressing mode: 7-bit Address / 10-bit Address
    AlAxiIic_SpeedModeEnum          SpeedMode;          // Specifies the IIC transfer speed mode
    AL_U32                          SlaveAddr;          // Specifies the IIC slave address
    AL_U64                          SetupTime;          // Specifies the IIC data setup time
    AL_U64                          HoldTime;           // Specifies the IIC data hold time
} AlAxiIic_InitStruct;

typedef enum {
    EVENT_RX_DONE     = 0,
    EVENT_TX_DONE     = 1,
    EVENT_ARB_LOSE    = 2,
} AlAxiIic_EventEnum;

typedef struct {
    AlAxiIic_EventEnum      Event;
    AL_U32                  EventData;
} AlAxiIic_EventStruct;

typedef AL_VOID (*AlAxiIic_EventCallBack)(AlAxiIic_EventStruct *Event, AL_VOID *CallbackRef);

typedef struct {
    AlAxiIic_HwConfigStruct         HwConfig;
    AlAxiIic_InitStruct             InitConfig;
    AL_U32                          FifoSize;
    AlAxiIic_BufferStruct           RecvBuffer;
    AlAxiIic_BufferStruct           TransBuffer;
    AlAxiIic_StatusEnum             Status;
    AlAxiIic_EventCallBack          EventCallBack;
    AL_VOID                         *EventCallBackRef;
} AlAxiIic_DevStruct;

typedef enum {
    AL_AXI_IIC_STOP ,
    AL_AXI_IIC_NSTOP
} AlAxiIic_StopModeEnum;

AL_S32 AlAxiIic_Dev_Init(AlAxiIic_DevStruct *Iic, AlAxiIic_HwConfigStruct *HwConfig, AlAxiIic_InitStruct *InitConfig);
AlAxiIic_HwConfigStruct *AlAxiIic_Dev_LookupConfig(AL_U32 DevId);

AL_S32 AlAxiIic_Dev_MasterSendDataPolling(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode);
AL_S32 AlAxiIic_Dev_MasterRecvDataPolling(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode);
AL_S32 AlAxiIic_Dev_MasterSendDataBlock(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode);
AL_S32 AlAxiIic_Dev_MasterRecvDataBlock(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode);

AL_S32 AlAxiIic_Dev_SlaveSendDataPolling(AlAxiIic_DevStruct *Iic, AL_U8 *SendBuf, AL_U32 SendSize);
AL_S32 AlAxiIic_Dev_SlaveRecvDataPolling(AlAxiIic_DevStruct *Iic, AL_U8 *RecvBuf, AL_U32 RecvSize);
AL_S32 AlAxiIic_Dev_SlaveSendDataBlock(AlAxiIic_DevStruct *Iic, AL_U8 *SendBuf, AL_U32 SendSize);
AL_S32 AlAxiIic_Dev_SlaveRecvDataBlock(AlAxiIic_DevStruct *Iic, AL_U8 *RecvBuf, AL_U32 RecvSize);

AL_VOID AlAxiIic_Dev_WriteFifo(AlAxiIic_DevStruct *Iic);
AL_VOID AlAxiIic_Dev_ReadFifo(AlAxiIic_DevStruct *Iic);

AL_S32 AlAxiIic_Dev_CheckID(AlAxiIic_DevStruct *Iic);
AL_VOID AlAxiIic_Dev_SetSpeedMode(AlAxiIic_DevStruct *Iic);
AL_VOID AlAxiIic_Dev_StartTrans(AlAxiIic_DevStruct *Iic);
AL_VOID AlAxiIic_Dev_Reset(AlAxiIic_DevStruct *Iic);
AL_VOID AlAxiIic_Dev_ClrFifo(AlAxiIic_DevStruct *Iic);
AL_VOID AlAxiIic_Dev_IrqHandler(AL_VOID *Instance);
AL_VOID AlAxiIic_Dev_CreateTrans(AlAxiIic_DevStruct *Iic, AlAxiIic_StopModeEnum StopMode);
AL_S32 AlAxiIic_Dev_RegisterEventCallBack(AlAxiIic_DevStruct *Handle, AlAxiIic_EventCallBack CallBack, AL_VOID *CallBackRef);

#ifdef __cplusplus
}
#endif

#endif