/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_axi_iic_hal.h"

AlAxiIic_HalStruct AXI_IIC_Handle[AL_AXI_IIC_NUM_INSTANCE];

/**
  This function is called when an IIC event occurs. It updates the status and logs the event.
 *
 * @param AxiIicEvent Pointer to the IIC event structure.
 * @param CallbackRef Pointer to the callback reference.
 *
 * @return None.
 */
static AL_VOID AlAxiIic_Hal_DefEventHandler(AlAxiIic_EventStruct *AxiIicEvent, AL_VOID *CallbackRef)
{
    AlAxiIic_HalStruct *Handle = (AlAxiIic_HalStruct *)CallbackRef;

    if(AxiIicEvent->Event == EVENT_ARB_LOSE) {
        /* Update status for EVENT_ARB_LOSE */
        Handle->Iic.Status = AL_AXI_IIC_IDLE;
        AL_LOG(AL_LOG_LEVEL_ERROR, "Arbitration Lost Error, SR: 0x%x", AxiIicEvent->EventData);

        /* Update status for RX_DONE */
    } else if (AxiIicEvent->Event == EVENT_RX_DONE) {
        Handle->Iic.Status = (Handle->Iic.InitConfig.IIC_Mode == AL_AXI_IIC_MASTER)
                             ? AL_AXI_IIC_MASTER_RX_DONE
                             : AL_AXI_IIC_SLAVE_RX_DONE;
        /* Update status for TX_DONE */
    } else if (AxiIicEvent->Event == EVENT_TX_DONE) {
        Handle->Iic.Status = (Handle->Iic.InitConfig.IIC_Mode == AL_AXI_IIC_MASTER)
                             ? AL_AXI_IIC_MASTER_TX_DONE
                             : AL_AXI_IIC_SLAVE_TX_DONE;
    }

    AlOsal_Mb_Send(&Handle->EventQueue, AxiIicEvent);
}

/**
 * This function initializes the IIC HAL with the specified device ID, initialization configuration, and event callback.
 *
 * @param Handle Pointer to the handle structure.
 * @param DevId The ID of the IIC device.
 * @param InitConfig Pointer to the initialization configuration structure.
 * @param EventCallBack Pointer to the event callback function.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_Init(AlAxiIic_HalStruct **Handle, AL_U32 DevId, AlAxiIic_InitStruct *InitConfig, AlAxiIic_EventCallBack EventCallBack)
{
    AL_S32 Ret;
    AlAxiIic_HwConfigStruct *HwConfig = AL_NULL;

    AL_ASSERT((Handle != AL_NULL), AL_AxiIic_ERR_ILLEGAL_PARAM);

    HwConfig = AlAxiIic_Dev_LookupConfig(DevId);
    if (HwConfig != AL_NULL) {
        *Handle = &AXI_IIC_Handle[DevId];
    } else {
        return AL_AxiIic_ERR_ILLEGAL_PARAM;
    }

    Ret = AlAxiIic_Dev_Init(&(*Handle)->Iic, HwConfig, InitConfig);
    if (Ret != AL_OK) {
        return Ret;
    }

    if (EventCallBack != AL_NULL) {
        Ret = AlAxiIic_Dev_RegisterEventCallBack(&(*Handle)->Iic, EventCallBack, (AL_VOID *)*Handle);
    } else {
        Ret = AlAxiIic_Dev_RegisterEventCallBack(&(*Handle)->Iic, AlAxiIic_Hal_DefEventHandler, (AL_VOID *)*Handle);
    }

    AL_INTR_AttrStrct AxiDmaRstAttrStrct = {
        .TrigMode   = POSTIVE_EDGE_TRIGGER,
        .Priority   = 137,
    };
    AlIntr_RegHandler((*Handle)->Iic.HwConfig.IntrId, &AxiDmaRstAttrStrct, AlAxiIic_Dev_IrqHandler, &(*Handle)->Iic);

    Ret = AlOsal_Lock_Init(&(*Handle)->Lock, "AxiIic_Lock");
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlOsal_Mb_Init(&(*Handle)->EventQueue, "AxiIic_MailBox");
    if (Ret != AL_OK) {
        return Ret;
    }

    return Ret;
}

/**
 * This function sends data to the specified slave address in master mode using polling method.
 *
 * @param Dev Pointer to the IIC HAL structure.
 * @param SlaveAddr The address of the slave device.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 * @param StopMode The stop mode to use after sending data.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_MasterSendDataPolling(AlAxiIic_HalStruct *Dev, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode)
{
    AL_S32 Ret = AL_OK;

    Ret = AlOsal_Lock_Take(&Dev->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_MasterSendDataPolling(&Dev->Iic, SlaveAddr, SendBuf, SendSize, StopMode);
    if (Ret != AL_OK) {
        return Ret;
    }

    (AL_VOID)AlOsal_Lock_Release(&Dev->Lock);

    return AL_OK;
}

/**
 * This function sends data to the specified slave address in master mode using blocking method.
 *
 * @param Handle Pointer to the IIC HAL structure.
 * @param SlaveAddr The address of the slave device.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 * @param StopMode The stop mode to use after sending data.
 * @param Timeout The timeout value for the transfer.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_MasterSendDataBlock(AlAxiIic_HalStruct *Handle, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    AlAxiIic_EventStruct AxiIicEvent = {0};
    AL_MailBox_t EventQueue = &Handle->EventQueue;

    AL_ASSERT((Handle != AL_NULL), AL_AxiIic_ERR_NULL_PTR);

    Ret = AlOsal_Lock_Take(&Handle->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_MasterSendDataBlock(&Handle->Iic, SlaveAddr, SendBuf, SendSize, StopMode);
    if (Ret != AL_OK) {
        return Ret;
    }

    // Wait for the completion event
    Ret = AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, Timeout);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, AL_WAITING_NO);
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->Lock);

    if (Ret == AL_OK && AxiIicEvent.Event == EVENT_TX_DONE) {
        return Ret;
    }

    // Return appropriate error code
    return (Ret != AL_OK) ? Ret : AL_AxiIic_EVENTS_TO_ERRS(AxiIicEvent.Event);
}

/**
 * This function receives data from the specified slave address in master mode using polling method.
 *
 * @param Dev Pointer to the IIC HAL structure.
 * @param SlaveAddr The address of the slave device.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 * @param StopMode The stop mode to use after receiving data.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_MasterRecvDataPolling(AlAxiIic_HalStruct *Dev, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode)
{
    AL_S32 Ret = AL_OK;

    Ret = AlOsal_Lock_Take(&Dev->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_MasterRecvDataPolling(&Dev->Iic, SlaveAddr, RecvBuf, RecvSize, StopMode);
    if (Ret != AL_OK) {
        return Ret;
    }

    (AL_VOID)AlOsal_Lock_Release(&Dev->Lock);

    return AL_OK;
}

/**
 * This function receives data from the specified slave address in master mode using blocking method.
 *
 * @param Handle Pointer to the IIC HAL structure.
 * @param SlaveAddr The address of the slave device.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 * @param StopMode The stop mode to use after receiving data.
 * @param Timeout The timeout value for the transfer.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_MasterRecvDataBlock(AlAxiIic_HalStruct *Handle, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    AlAxiIic_EventStruct AxiIicEvent = {0};
    AL_MailBox_t EventQueue = &Handle->EventQueue;

    AL_ASSERT((Handle != AL_NULL), AL_AxiIic_ERR_NULL_PTR);

    Ret = AlOsal_Lock_Take(&Handle->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_MasterRecvDataBlock(&Handle->Iic, SlaveAddr, RecvBuf, RecvSize, StopMode);
    if (Ret != AL_OK) {
        return Ret;
    }

    // Wait for the completion event
    Ret = AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, Timeout);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, AL_WAITING_NO);
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->Lock);

    if (Ret == AL_OK && AxiIicEvent.Event == EVENT_RX_DONE) {
        return Ret;
    }

    // Return appropriate error code
    return (Ret != AL_OK) ? Ret : AL_AxiIic_EVENTS_TO_ERRS(AxiIicEvent.Event);
}

/**
 * This function sends data in slave mode using polling method.
 *
 * @param Dev Pointer to the IIC HAL structure.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_SlaveSendDataPolling(AlAxiIic_HalStruct *Dev, AL_U8 *SendBuf, AL_U32 SendSize)
{
    AL_S32 Ret = AL_OK;

    Ret = AlOsal_Lock_Take(&Dev->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_SlaveSendDataPolling(&Dev->Iic, SendBuf, SendSize);
    if (Ret != AL_OK) {
        return Ret;
    }

    (AL_VOID)AlOsal_Lock_Release(&Dev->Lock);

    return AL_OK;
}

/**
 * This function sends data in slave mode using blocking method.
 *
 * @param Handle Pointer to the IIC HAL structure.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 * @param Timeout The timeout value for the transfer.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_SlaveSendDataBlock(AlAxiIic_HalStruct *Handle, AL_U8 *SendBuf, AL_U32 SendSize, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    AlAxiIic_EventStruct AxiIicEvent = {0};
    AL_MailBox_t EventQueue = &Handle->EventQueue;

    AL_ASSERT((Handle != AL_NULL), AL_AxiIic_ERR_NULL_PTR);

    Ret = AlOsal_Lock_Take(&Handle->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_SlaveSendDataBlock(&Handle->Iic, SendBuf, SendSize);
    if (Ret != AL_OK) {
        return Ret;
    }

    // Wait for the completion event
    Ret = AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, Timeout);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, AL_WAITING_NO);
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->Lock);

    if (Ret == AL_OK && AxiIicEvent.Event == EVENT_TX_DONE) {
        return Ret;
    }

    // Return appropriate error code
    return (Ret != AL_OK) ? Ret : AL_AxiIic_EVENTS_TO_ERRS(AxiIicEvent.Event);
}

/**
 * This function receives data in slave mode using polling method.
 *
 * @param Dev Pointer to the IIC HAL structure.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_SlaveRecvDataPolling(AlAxiIic_HalStruct *Dev, AL_U8 *RecvBuf, AL_U32 RecvSize)
{
    AL_S32 Ret = AL_OK;

    Ret = AlOsal_Lock_Take(&Dev->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_SlaveRecvDataPolling(&Dev->Iic, RecvBuf, RecvSize);
    if (Ret != AL_OK) {
        return Ret;
    }

    (AL_VOID)AlOsal_Lock_Release(&Dev->Lock);

    return AL_OK;
}

/**
 * This function receives data in slave mode using blocking method.
 *
 * @param Handle Pointer to the IIC HAL structure.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 * @param Timeout The timeout value for the transfer.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Hal_SlaveRecvDataBlock(AlAxiIic_HalStruct *Handle, AL_U8 *RecvBuf, AL_U32 RecvSize, AL_U32 Timeout)
{
    AL_S32 Ret = AL_OK;
    AlAxiIic_EventStruct AxiIicEvent = {0};
    AL_MailBox_t EventQueue = &Handle->EventQueue;

    Ret = AlOsal_Lock_Take(&Handle->Lock, AL_WAITFOREVER);
    if (Ret != AL_OK) {
        return Ret;
    }

    Ret = AlAxiIic_Dev_SlaveRecvDataBlock(&Handle->Iic, RecvBuf, RecvSize);
    if (Ret != AL_OK) {
        return Ret;
    }

    // Wait for the completion event
    Ret = AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, Timeout);
    if (Ret != AL_OK) {
        (AL_VOID)AlOsal_Mb_Receive(EventQueue, &AxiIicEvent, AL_WAITING_NO);
    }

    (AL_VOID)AlOsal_Lock_Release(&Handle->Lock);

    if (Ret == AL_OK && AxiIicEvent.Event == EVENT_RX_DONE) {
        return Ret;
    }

    // Return appropriate error code
    return (Ret != AL_OK) ? Ret : AL_AxiIic_EVENTS_TO_ERRS(AxiIicEvent.Event);
}
