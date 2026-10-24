/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_UART_16550_HAL_H_
#define AL_AXI_UART_16550_HAL_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_axi_uart_16550_dev.h"


typedef struct
{
    AlAxiUart16550_DevStruct     Dev;
    AL_Lock                      TxLock;
    AL_Lock                      RxLock;
    AL_MailBox                   TxEventQueue;
    AL_MailBox                   RxEventQueue;
} AlAxiUart16550_HalStruct;


AL_S32 AlAxiUart16550_Hal_Init(AlAxiUart16550_HalStruct **Handle, AL_U32 DevId, AlAxiUart16550_InitStruct *InitConfig, AlAxiUart16550_EventCallBack Callback);
AL_S32 AlAxiUart16550_Hal_SendDataBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size, AL_U32 Timeout);
AL_S32 AlAxiUart16550_Hal_RecvDataBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 RequestSize, AL_U32 *ReceiveSize, AL_U32 Timeout);
AL_S32 AlAxiUart16550_Hal_SendDataPolling(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size);
AL_S32 AlAxiUart16550_Hal_RecvDataPolling(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size);
AL_S32 AlAxiUart16550_Hal_SendData(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size);
AL_S32 AlAxiUart16550_Hal_RecvData(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 Size);
AL_S32 AlAxiUart16550_Hal_SendDataPollingNonBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 RequestSize,
                                       AL_U32 *ActualSize, AL_U32 Timeout);
AL_S32 AlAxiUart16550_Hal_RecvDataPollingNonBlock(AlAxiUart16550_HalStruct *Handle, AL_U8 *Data, AL_U32 RequestSize,
                                       AL_U32 *ReceiveSize, AL_U32 Timeout);
AL_S32 AlAxiUart16550_Hal_IoCtl(AlAxiUart16550_HalStruct *Handle, AlAxiUart16550_IoCtlCmdEnum Cmd, AlAxiUart16550_IoctlParamUnion *IoctlParam);


#ifdef __cplusplus
}
#endif

#endif /* AL_AXI_UART_16550_HAL_H_ */
