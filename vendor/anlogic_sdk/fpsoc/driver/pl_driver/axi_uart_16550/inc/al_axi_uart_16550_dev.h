/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_UART_16550_DEV_H_
#define AL_AXI_UART_16550_DEV_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_uart_16550_ll.h"

#define AL_AXI_UART_16550_EVENT_START_BIT    6

#define AL_AXI_UART_16550_ERR_NULL_PTR                 (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, AL_ERR_NULL_PTR))
#define AL_AXI_UART_16550_ERR_ILLEGAL_PARAM            (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, AL_ERR_ILLEGAL_PARAM))
#define AL_AXI_UART_16550_ERR_NOT_READY                (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_READY))
#define AL_AXI_UART_16550_ERR_NOT_SUPPORT              (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_SUPPORT))
#define AL_AXI_UART_16550_ERR_TIMEOUT                  (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, AL_ERR_TIMEOUT))
#define AL_AXI_UART_16550_ERR_BUSY                     (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, AL_ERR_BUSY))
#define AL_AXI_UART_16550_ERR_NOMEM                    (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, AL_ERR_NOMEM))
#define AL_AXI_UART_16550_EVENTS_TO_ERRS(Events)       (AL_DEF_ERR(AL_AxiUart16550, AL_LOG_LEVEL_ERROR, Events << AL_AXI_UART_16550_EVENT_START_BIT))


typedef struct
{
    AL_U32                       BaudRate;               /* Baud rate */
    AL_U32                       WordLength;             /* Data bits */
    AL_U32                       StopBits;               /* Stop bits */
    AL_BOOL                      CharTimeoutEnable;      /* Enable char timeout function */
    AlAxiUart16550_ParityEnum    Parity;                 /* Parity bit */
} AlAxiUart16550_InitStruct;

/**
 * @brief  Data buffer
 */
typedef struct
{
    AL_U8                     *BufferPtr;
    AL_U32                    RequestedCnt;        /* total size requested */
    AL_U32                    HandledCnt;          /* the size has handled */
} AlAxiUart16550_BufferStruct;

/**
 * @brief  Module running state enum
 */
typedef enum
{
    AL_AXI_UART_16550_STATE_NOT_INIT     = (0x0),
    AL_AXI_UART_16550_STATE_READY        = (0x01 << 0),
    AL_AXI_UART_16550_STATE_TX_BUSY      = (0x01 << 1),
    AL_AXI_UART_16550_STATE_RX_BUSY      = (0x01 << 2)
} AlAxiUart16550_StateEnum;


/**
 * @brief  Recv error enum
 */
typedef enum
{
    AL_AXI_UART_16550_OVERRUN_ERR    = BIT(1),
    AL_AXI_UART_16550_PARITY_ERR     = BIT(2),
    AL_AXI_UART_16550_FRAMING_ERR    = BIT(3),
    AL_AXI_UART_16550_BREAK_ERR      = BIT(4)
} AlAxiUart16550_RecvErrorTypeEnum;

/**
 * @brief  Event enum
 */
typedef enum
{
    AL_AXI_UART_16550_EVENT_SEND_DONE            = BIT(0),
    AL_AXI_UART_16550_EVENT_RECEIVE_DONE         = BIT(1),
    AL_AXI_UART_16550_EVENT_READY_TO_SEND        = BIT(2),
    AL_AXI_UART_16550_EVENT_READY_TO_RECEIVE     = BIT(3),
    AL_AXI_UART_16550_EVENT_CHAR_TIMEOUT         = BIT(4),
    AL_AXI_UART_16550_EVENT_PARE_FRAME_BRKE      = BIT(5),
    AL_AXI_UART_16550_EVENT_OVER_RUN_ERR         = BIT(6),
    AL_AXI_UART_16550_EVENT_PARITY_ERR           = BIT(7),
    AL_AXI_UART_16550_EVENT_FRAMING_ERR          = BIT(9),
    AL_AXI_UART_16550_EVENT_BREAK_INTR           = BIT(10),
    AL_AXI_UART_16550_EVENT_NO_INTR_PEDING       = BIT(11),
    AL_AXI_UART_16550_EVENT_MODEM_STATUS_INTR    = BIT(12),
} AlAxiUart16550_EventIdEnum;

/**
 * @brief  Io ctl cmd enum
 */
typedef enum
{
    AL_AXI_UART_16550_IOCTL_SET_BAUD_RATE,
    AL_AXI_UART_16550_IOCTL_GET_BAUD_RATE,
    AL_AXI_UART_16550_IOCTL_SET_DATA_WIDTH,
    AL_AXI_UART_16550_IOCTL_GET_DATA_WIDTH,
    AL_AXI_UART_16550_IOCTL_SET_STOP_BITS,
    AL_AXI_UART_16550_IOCTL_GET_STOP_BITS,
    AL_AXI_UART_16550_IOCTL_SET_PARITY,
    AL_AXI_UART_16550_IOCTL_GET_PARITY,
} AlAxiUart16550_IoCtlCmdEnum;

/**
 * @brief  Io ctl param enum
 */
typedef union {
    AL_U32     BaudRate;
    AL_U32     DataWidth;
    AL_U32     StopBits;
    AL_U32     Parity;
    AL_BOOL    AutoFlowState;
    AL_BOOL    LoopBack;
    AL_BOOL    DmaMode;
} AlAxiUart16550_IoctlParamUnion;

typedef enum
{
    AL_AXI_UART_16550_TX                = 0,
    AL_AXI_UART_16550_RX                = 1,
} AlAxiUart16550_TransferEnum;

/**
 * @brief  Events struct
 */
typedef struct
{
    AlAxiUart16550_EventIdEnum        Events;
    AL_U32                        EventData;
} AlAxiUart16550_EventStruct;

typedef AL_VOID (*AlAxiUart16550_EventCallBack)(AlAxiUart16550_EventStruct AxiUart16550Event, AL_VOID *CallbackRef);

typedef struct
{
    AlAxiUart16550_HwConfigStruct     HwConfig;
    AlAxiUart16550_InitStruct         InitConfig;
    AlAxiUart16550_BufferStruct       SendBuffer;
    AlAxiUart16550_BufferStruct       RecvBuffer;
    AlAxiUart16550_EventCallBack      EventCallBack;
    AL_VOID                           *EventCallBackRef;
    AlAxiUart16550_StateEnum          State;
} AlAxiUart16550_DevStruct;

AlAxiUart16550_HwConfigStruct *AlAxiUart16550_Dev_LookupConfig(AL_U32 DevId);
AL_S32 AlAxiUart16550_Dev_Init(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_HwConfigStruct *HwConfig, AlAxiUart16550_InitStruct *InitConfig);
AL_S32 AlAxiUart16550_Dev_SendDataPolling(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 Size);
AL_S32 AlAxiUart16550_Dev_RecvDataPolling(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 Size);
AL_S32 AlAxiUart16550_Dev_SendDataPollingNonBlock(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 RequestSize, AL_U32 *ActualSize, AL_U32 Timeout);
AL_S32 AlAxiUart16550_Dev_RecvDataPollingNonBlock(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 RequestSize, AL_U32 *ReceiveSize, AL_U32 Timeout);
AL_S32 AlAxiUart16550_Dev_SendData(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 Size);
AL_S32 AlAxiUart16550_Dev_RecvData(AlAxiUart16550_DevStruct *Uart, AL_U8 *Data, AL_U32 Size);
AL_VOID AlAxiUart16550_Dev_SetTxBusy(AlAxiUart16550_DevStruct *Uart);
AL_VOID AlAxiUart16550_Dev_SetRxBusy(AlAxiUart16550_DevStruct *Uart);
AL_BOOL AlAxiUart16550_Dev_IsTxBusy(AlAxiUart16550_DevStruct *Uart);
AL_BOOL AlAxiUart16550_Dev_IsRxBusy(AlAxiUart16550_DevStruct *Uart);
AL_VOID AlAxiUart16550_Dev_StopSend(AlAxiUart16550_DevStruct *Uart);
AL_VOID AlAxiUart16550_Dev_StopReceive(AlAxiUart16550_DevStruct *Uart);
AL_VOID AlAxiUart16550_Dev_IntrHandler(void *Instance);
AL_S32 AlAxiUart16550_Dev_RegisterEventCallBack(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_EventCallBack Callback, AL_VOID *CallbackRef);
AL_S32 AlAxiUart16550_Dev_UnRegisterEventCallBack(AlAxiUart16550_DevStruct *Uart);
AL_S32 AlAxiUart16550_Dev_IoCtl(AlAxiUart16550_DevStruct *Uart, AlAxiUart16550_IoCtlCmdEnum Cmd, AlAxiUart16550_IoctlParamUnion *IoctlParam);
AL_VOID AlAxiUart16550_Dev_SendByte(AlAxiUart16550_DevStruct *Uart, AL_U8 Char);

#ifdef __cplusplus
}
#endif

#endif