/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_axi_iic_dev.h"

extern AlAxiIic_HwConfigStruct AlAxiIic_HwConfig[AL_AXI_IIC_NUM_INSTANCE];

/**
 * This function reads and logs the ID of the IIC device.
 *
 * @param Iic Pointer to the IIC device structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_CheckID(AlAxiIic_DevStruct *Iic)
{
    AL_U32 ReadId = 0;
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    ReadId = AlAxiIic_ll_ReadId(BaseAddr);
    AL_LOG(AL_LOG_LEVEL_INFO, "axi iic id: 0x%x", ReadId);

    return AL_OK;
}

/**
 * This function searches through the list of hardware configurations to find the
 * configuration that matches the provided device ID.
 *
 * @param DevId The ID of the IIC device.
 *
 * @return AlAxiIic_HwConfigStruct* Pointer to the hardware configuration structure.
 */
AlAxiIic_HwConfigStruct *AlAxiIic_Dev_LookupConfig(AL_U32 DevId)
{
    AL_U32 Index;
    AlAxiIic_HwConfigStruct *ConfigPtr = AL_NULL;

    for (Index = 0; Index < AL_AXI_IIC_NUM_INSTANCE; Index++) {
        if (AlAxiIic_HwConfig[Index].DeviceId == DevId) {
            ConfigPtr = &AlAxiIic_HwConfig[Index];
            break;
        }
    }

    return ConfigPtr;
}

/**
 * This function registers an event callback function for the IIC device.
 *
 * @param Handle Pointer to the IIC device structure.
 * @param CallBack Pointer to the callback function.
 * @param CallBackRef Pointer to the callback reference.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_RegisterEventCallBack(AlAxiIic_DevStruct *Handle, AlAxiIic_EventCallBack CallBack, AL_VOID *CallBackRef)
{
    Handle->EventCallBack = CallBack;
    Handle->EventCallBackRef = CallBackRef;

    return AL_OK;
}

/**
 * This function starts an IIC transaction by setting the command register.
 *
 * @param Iic Pointer to the IIC device structure.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_StartTrans(AlAxiIic_DevStruct *Iic)
{
    AlAxiIic_ll_SetCmd(Iic->HwConfig.BaseAddress, AL_AXI_IIC_CMD_TRANS);
}

/**
 * This function resets the IIC device by setting the command register.
 *
 * @param Iic Pointer to the IIC device structure.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_Reset(AlAxiIic_DevStruct *Iic)
{
    AlAxiIic_ll_SetCmd(Iic->HwConfig.BaseAddress, AL_AXI_IIC_CMD_RST);
}

/**
 * This function clears the IIC FIFO by setting the command register.
 *
 * @param Iic Pointer to the IIC device structure.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_ClrFifo(AlAxiIic_DevStruct *Iic)
{
    AlAxiIic_ll_SetCmd(Iic->HwConfig.BaseAddress, AL_AXI_IIC_CMD_CLR_FIFO);
}

/**
 * This function initializes the IIC device with the specified hardware configuration and initialization configuration.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param HwConfig Pointer to the hardware configuration structure.
 * @param InitConfig Pointer to the initialization configuration structure.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_Init(AlAxiIic_DevStruct *Iic, AlAxiIic_HwConfigStruct *HwConfig, AlAxiIic_InitStruct *InitConfig)
{
    AL_S32 Ret;
    AL_U64 BaseAddr;

    Iic->HwConfig = *HwConfig;
    Iic->InitConfig = *InitConfig;

    BaseAddr = Iic->HwConfig.BaseAddress;
    Iic->FifoSize = AlAxiIic_ll_GetFifoSize(BaseAddr);
    Iic->Status = AL_AXI_IIC_IDLE;

    AlAxiIic_Dev_Reset(Iic);

    /* Check IIC ID */
    Ret = AlAxiIic_Dev_CheckID(Iic);
    if (Ret != AL_OK) {
        return Ret;
    }

    AlAxiIic_Dev_SetSpeedMode(Iic);
    AlAxiIic_ll_SetMode(BaseAddr, Iic->InitConfig.IIC_Mode);
    AlAxiIic_ll_SetAddressMode(BaseAddr, Iic->InitConfig.IIC_AddressMode);
    AlAxiIic_ll_EnableIP(BaseAddr, AL_AXI_IIC_FUNC_ENABLE);

    if (Iic->InitConfig.IIC_Mode == AL_AXI_IIC_SLAVE) {
        AlAxiIic_ll_SetSlaveAddr(BaseAddr, Iic->InitConfig.SlaveAddr);
    }

    return Ret;
}

/**
 * This function creates an IIC transaction by setting the phase registers.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param StopMode The stop mode to use for the transaction.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_CreateTrans(AlAxiIic_DevStruct *Iic, AlAxiIic_StopModeEnum StopMode)
{
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    AlAxiIic_ll_SetPhaseStart(BaseAddr, AL_AXI_IIC_FUNC_ENABLE);
    AlAxiIic_ll_SetPhaseAddr(BaseAddr, AL_AXI_IIC_FUNC_ENABLE);
    AlAxiIic_ll_SetPhaseData(BaseAddr, AL_AXI_IIC_FUNC_ENABLE);

    if (StopMode == AL_AXI_IIC_STOP) {
        AlAxiIic_ll_SetPhaseStop(BaseAddr, AL_AXI_IIC_FUNC_ENABLE);
    } else {
        AlAxiIic_ll_SetPhaseStop(BaseAddr, AL_AXI_IIC_FUNC_DISABLE);
    }
}

/**
 * This function sends data to the specified slave address in master mode using polling method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param SlaveAddr The address of the slave device.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 * @param StopMode The stop mode to use after sending data.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_MasterSendDataPolling(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode)
{
    AL_S32 i = 0;
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->Status = AL_AXI_IIC_MASTER_TX_BUSY;

    AlAxiIic_ll_SetSlaveAddr(BaseAddr, SlaveAddr);
    AlAxiIic_ll_SetDir(BaseAddr, MASTER_TX);
    AlAxiIic_ll_SetDataCnt(BaseAddr, SendSize);
    AlAxiIic_Dev_CreateTrans(Iic, StopMode);
    AlAxiIic_Dev_StartTrans(Iic);

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_ADDR_HIT));
    AlAxiIic_ll_ClearStatus(BaseAddr, SR_ADDR_HIT);

    for (i = 0; i < SendSize; i++) {
        while (AlAxiIic_ll_GetStatus(BaseAddr, SR_FIFO_FULL));
        AlAxiIic_ll_SetData(BaseAddr, SendBuf[i]);
    }

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_CMPL));
    AlAxiIic_ll_ClearStatusAll(BaseAddr);

    Iic->Status = AL_AXI_IIC_MASTER_TX_DONE;

    return AL_OK;
}

/**
 * This function sends data to the specified slave address in master mode using blocking method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param SlaveAddr The address of the slave device.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 * @param StopMode The stop mode to use after sending data.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_MasterSendDataBlock(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *SendBuf, AL_U32 SendSize, AlAxiIic_StopModeEnum StopMode)
{
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->TransBuffer.BuffPtr = SendBuf;
    Iic->TransBuffer.ReqCnt = SendSize;
    Iic->TransBuffer.DataCnt = 0;
    Iic->Status = AL_AXI_IIC_MASTER_TX_BUSY;

    AlAxiIic_ll_SetSlaveAddr(BaseAddr, SlaveAddr);
    AlAxiIic_ll_SetDataCnt(BaseAddr, SendSize);
    AlAxiIic_ll_SetDir(BaseAddr, MASTER_TX);
    AlAxiIic_Dev_CreateTrans(Iic, StopMode);
    AlAxiIic_ll_EnableInt(BaseAddr, I2C_INIT_INT);
    AlAxiIic_Dev_StartTrans(Iic);

    return AL_OK;
}

/**
 * This function receives data from the specified slave address in master mode using polling method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param SlaveAddr The address of the slave device.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 * @param StopMode The stop mode to use after receiving data.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_MasterRecvDataPolling(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode)
{
    AL_S32 i = 0;
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->Status = AL_AXI_IIC_MASTER_RX_BUSY;

    AlAxiIic_ll_SetSlaveAddr(BaseAddr, SlaveAddr);
    AlAxiIic_ll_SetDir(BaseAddr, MASTER_RX);
    AlAxiIic_ll_SetDataCnt(BaseAddr, RecvSize);
    AlAxiIic_Dev_CreateTrans(Iic, StopMode);
    AlAxiIic_Dev_StartTrans(Iic);

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_ADDR_HIT));
    AlAxiIic_ll_ClearStatus(BaseAddr, SR_ADDR_HIT);

    for (i = 0; i < RecvSize; i++) {
        while (AlAxiIic_ll_GetStatus(BaseAddr, SR_FIFO_EMPTY));
        RecvBuf[i] = (AL_U8)AlAxiIic_ll_GetData(BaseAddr);
    }

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_CMPL));
    AlAxiIic_ll_ClearStatusAll(BaseAddr);

    Iic->Status = AL_AXI_IIC_MASTER_RX_DONE;

    return AL_OK;
}

/**
 * This function receives data from the specified slave address in master mode using blocking method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param SlaveAddr The address of the slave device.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 * @param StopMode The stop mode to use after receiving data.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_MasterRecvDataBlock(AlAxiIic_DevStruct *Iic, AL_U32 SlaveAddr, AL_U8 *RecvBuf, AL_U32 RecvSize, AlAxiIic_StopModeEnum StopMode)
{
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->RecvBuffer.BuffPtr = RecvBuf;
    Iic->RecvBuffer.ReqCnt = RecvSize;
    Iic->RecvBuffer.DataCnt = 0;
    Iic->Status = AL_AXI_IIC_MASTER_RX_BUSY;

    AlAxiIic_ll_SetSlaveAddr(BaseAddr, SlaveAddr);
    AlAxiIic_ll_SetDataCnt(BaseAddr, RecvSize);
    AlAxiIic_ll_SetDir(BaseAddr, MASTER_RX);
    AlAxiIic_Dev_CreateTrans(Iic, StopMode);
    AlAxiIic_ll_EnableInt(BaseAddr, I2C_INIT_INT);
    AlAxiIic_Dev_StartTrans(Iic);

    return AL_OK;
}

/**
 * This function sends data in slave mode using polling method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_SlaveSendDataPolling(AlAxiIic_DevStruct *Iic, AL_U8 *SendBuf, AL_U32 SendSize)
{
    AL_U32 i = 0;
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->Status = AL_AXI_IIC_SLAVE_TX_BUSY;

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_ADDR_HIT));
    AlAxiIic_ll_ClearStatus(BaseAddr, SR_ADDR_HIT);

    for (i = 0; i < SendSize; i++) {
        while (AlAxiIic_ll_GetStatus(BaseAddr, SR_FIFO_FULL));
        AlAxiIic_ll_SetData(BaseAddr, SendBuf[i]);
    }

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_CMPL));
    AlAxiIic_ll_ClearStatusAll(BaseAddr);

    AlAxiIic_Dev_ClrFifo(Iic);
    Iic->Status = AL_AXI_IIC_SLAVE_TX_DONE;

    return AL_OK;
}

/**
 * This function sends data in slave mode using blocking method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param SendBuf Pointer to the buffer containing data to send.
 * @param SendSize The size of the data to send.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_SlaveSendDataBlock(AlAxiIic_DevStruct *Iic, AL_U8 *SendBuf, AL_U32 SendSize)
{
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->TransBuffer.BuffPtr = SendBuf;
    Iic->TransBuffer.ReqCnt = SendSize;
    Iic->TransBuffer.DataCnt = 0;
    Iic->Status = AL_AXI_IIC_SLAVE_TX_BUSY;

    AlAxiIic_ll_EnableInt(BaseAddr, I2C_INIT_INT);

    return AL_OK;
}

/**
 * This function receives data in slave mode using polling method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_SlaveRecvDataPolling(AlAxiIic_DevStruct *Iic, AL_U8 *RecvBuf, AL_U32 RecvSize)
{
    AL_U32 i = 0;
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->Status = AL_AXI_IIC_SLAVE_RX_BUSY;

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_ADDR_HIT));
    AlAxiIic_ll_ClearStatus(BaseAddr, SR_ADDR_HIT);

    for (i = 0; i < RecvSize; i++) {
        while (AlAxiIic_ll_GetStatus(BaseAddr, SR_FIFO_EMPTY));
        RecvBuf[i] = AlAxiIic_ll_GetData(BaseAddr);
    }

    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_CMPL));
    AlAxiIic_ll_ClearStatusAll(BaseAddr);

    AlAxiIic_Dev_ClrFifo(Iic);
    Iic->Status = AL_AXI_IIC_SLAVE_RX_DONE;

    return AL_OK;
}

/**
 * This function receives data in slave mode using blocking method.
 *
 * @param Iic Pointer to the IIC device structure.
 * @param RecvBuf Pointer to the buffer to store received data.
 * @param RecvSize The size of the data to receive.
 *
 * @return AL_S32 Returns AL_OK on success, or an error code on failure.
 */
AL_S32 AlAxiIic_Dev_SlaveRecvDataBlock(AlAxiIic_DevStruct *Iic, AL_U8 *RecvBuf, AL_U32 RecvSize)
{
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    Iic->RecvBuffer.BuffPtr = RecvBuf;
    Iic->RecvBuffer.ReqCnt = RecvSize;
    Iic->RecvBuffer.DataCnt = 0;
    Iic->Status = AL_AXI_IIC_SLAVE_RX_BUSY;

    AlAxiIic_ll_EnableInt(BaseAddr, I2C_INIT_INT);

    return AL_OK;
}

/**
 * This function sets the speed mode of the IIC device.
 *
 * @param Iic Pointer to the IIC device structure.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_SetSpeedMode(AlAxiIic_DevStruct *Iic)
{
    AL_U64 T_sp, T_setup, T_hold, Tsclh = 0;
    AL_U32 Taclk = 1e9 / Iic->HwConfig.InputClk;
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    /* PulseWidth = T_sp * taclk * (TPM + 1)
     * T_sp = PulseWidth / taclk / (TPM + 1)
     */
    T_sp = 50 / Taclk;
    AlAxiIic_ll_SetSp(BaseAddr, T_sp);

    /* SetupTime = (2 * taclk) + (2 + T_sp + T_setup) * taclk * (TPM + 1);
     * T_setup = ((SetupTime - (2 * taclk)) / taclk / (TPM + 1)) - 2 - T_sp
     */
    T_setup = (Iic->InitConfig.SetupTime / Taclk) - 2 - 2 - T_sp;
    AlAxiIic_ll_SetSuTime(BaseAddr, T_setup);

    /* HoldTime = (2 * taclk) + (2 + T_sp + T_HDDAT) * taclk * (TPM + 1)
     * T_HDDAT = ((HoldTime - (2 * taclk)) / taclk / (TPM + 1)) - 2 - T_sp;
     */
    T_hold = (Iic->InitConfig.HoldTime / Taclk) - 2 - 2 - T_sp;
    AlAxiIic_ll_SetHdTime(BaseAddr, T_hold);

    /* SCL_HIGH_period = (2 * taclk) + (2 + T_sp + T_SCLHi) * taclk * (TPM + 1)
     * T_SCLHi = ((SCL_HIGH_period - (2 * taclk)) / taclk / (TPM + 1)) - 2 - T_sp;
     */
    switch (Iic->InitConfig.SpeedMode) {
        case AL_AXI_IIC_STANDARD_MODE:      // T = 10000ns, Thigh = 5000ns, Tlow = 5000ns;
            Tsclh = (5000 / Taclk) - 2 - 2 - T_sp;
            break;
        case AL_AXI_IIC_FAST_MODE:          // T = 2600ns, Thigh = 1300ns, Tlow = 1300ns;
            Tsclh = (1300 / Taclk) - 2 - 2 - T_sp;
            break;
        case AL_AXI_IIC_HIGH_SPEED_MODE:    // T = 1000ns, Thigh = 500ns, Tlow = 500ns;
            Tsclh = (500 / Taclk) - 2 - 2 - T_sp;
            break;
    }

    AlAxiIic_ll_SetSclRatio(BaseAddr, AL_AXI_IIC_SCL_RATIO_1);
    AlAxiIic_ll_SetSclHighTime(BaseAddr, Tsclh);
}

/**
 * This function reads data from the FIFO.
 *
 * @param Iic Pointer to the IIC device structure.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_ReadFifo(AlAxiIic_DevStruct *Iic)
{
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;
    AL_U32 RemainByte = Iic->RecvBuffer.ReqCnt - Iic->RecvBuffer.DataCnt;
    AL_U32 ReadCount = RemainByte < (Iic->FifoSize / 2) ? RemainByte : (Iic->FifoSize / 2);

    /* Read data from the FIFO */
    while (ReadCount--)
        Iic->RecvBuffer.BuffPtr[Iic->RecvBuffer.DataCnt++] = AlAxiIic_ll_GetData(BaseAddr);

    /* Disable FIFO Half interrupt if all data has been received */
    if (Iic->RecvBuffer.DataCnt == Iic->RecvBuffer.ReqCnt) {
        AlAxiIic_ll_DisableInt(BaseAddr, INT_FIFO_HALF);
    }
}

/**
 * This function writes data to the FIFO.
 *
 * @param Iic Pointer to the IIC device structure.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_WriteFifo(AlAxiIic_DevStruct *Iic)
{
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;

    /* Write data to the FIFO until the FIFO is full
     * or all data has been transmitted
     */
    while (!AlAxiIic_ll_GetStatus(BaseAddr, SR_FIFO_FULL)) {
        if (Iic->TransBuffer.DataCnt == Iic->TransBuffer.ReqCnt) {
            AlAxiIic_ll_DisableInt(BaseAddr, INT_FIFO_HALF);
            break;
        }
        AlAxiIic_ll_SetData(BaseAddr, Iic->TransBuffer.BuffPtr[Iic->TransBuffer.DataCnt++]);
    }
}

/**
 * This function is the interrupt handler for the IIC device. It checks the interrupt status and calls the
 * appropriate handler function for the specific interrupt condition.
 *
 * @param Instance Pointer to the IIC device structure.
 *
 * @return None.
 */
AL_VOID AlAxiIic_Dev_IrqHandler(AL_VOID *Instance)
{
    AlAxiIic_DevStruct *Iic = (AlAxiIic_DevStruct *)Instance;
    AL_U64 BaseAddr = Iic->HwConfig.BaseAddress;
    AL_U32 IntMask = AlAxiIic_ll_GetIntMusk(BaseAddr);
    AL_U32 OriginalIntStatus = AlAxiIic_ll_GetStatusAll(BaseAddr);

    /* Process only enabled interrupts */
    AL_U32 IntStatus = OriginalIntStatus & IntMask;
    AlAxiIic_ll_ClearIntStatus(BaseAddr, IntStatus);

    /* 1. Handle Arbitration Lost interrupt */
    if (IntStatus & INT_ARB_LOSE) {
        AlAxiIic_ll_DisableInt(BaseAddr, INT_ARB_LOSE);

        /* Trigger ARB_LOSE event */
        AlAxiIic_EventStruct EventStruct = {
            .Event = EVENT_ARB_LOSE,
            .EventData = OriginalIntStatus
        };
        Iic->EventCallBack(&EventStruct, Iic->EventCallBackRef);

        /* 2. Handle Address Hit interrupt */
    } else if (IntStatus & INT_ADDR_HIT) {
        AlAxiIic_ll_DisableInt(BaseAddr, INT_ADDR_HIT);
        AlAxiIic_ll_EnableInt(BaseAddr, I2C_TRANS_INT);

        /* 3. Handle FIFO Half interrupt */
        /* Receiver: An interrupt is triggered when the amount of data
         * in the Data FIFO is greater than or equal to half of the FIFO depth.
         *
         * Transmitter: An interrupt is triggered when the amount of data
         * in the Data FIFO is less than or equal to half of the FIFO depth.
         */
    } else if (IntStatus & INT_FIFO_HALF) {
        /* If receiving, read data from the FIFO */
        if (Iic->Status == AL_AXI_IIC_SLAVE_RX_BUSY ||
            Iic->Status == AL_AXI_IIC_MASTER_RX_BUSY) {
            AlAxiIic_Dev_ReadFifo(Iic);

        /* If transmitting, write data to the FIFO */
        } else if (Iic->Status == AL_AXI_IIC_SLAVE_TX_BUSY ||
                   Iic->Status == AL_AXI_IIC_MASTER_TX_BUSY) {
            AlAxiIic_Dev_WriteFifo(Iic);
        }
    }

    /* 4. Handle Completion interrupt */
    if (IntStatus & INT_CMPL) {
        /* 4.1 In read operation, ensure any remaining data */
        if (Iic->Status == AL_AXI_IIC_MASTER_RX_BUSY ||
            Iic->Status == AL_AXI_IIC_SLAVE_RX_BUSY) {
            AlAxiIic_Dev_ReadFifo(Iic);

            /* Trigger RX_DONE event */
            AlAxiIic_EventStruct EventStruct = {
                .Event = EVENT_RX_DONE,
                .EventData = Iic->RecvBuffer.DataCnt
            };
            Iic->EventCallBack(&EventStruct, Iic->EventCallBackRef);

        /* 4.2 In write operation, just trigger TX_DONE event */
        } else if (Iic->Status == AL_AXI_IIC_MASTER_TX_BUSY ||
                   Iic->Status == AL_AXI_IIC_SLAVE_TX_BUSY) {

                /* Trigger TX_DONE event */
                AlAxiIic_EventStruct EventStruct = {
                    .Event = EVENT_TX_DONE,
                    .EventData = Iic->TransBuffer.DataCnt
                };
                Iic->EventCallBack(&EventStruct, Iic->EventCallBackRef);
        }

        /* 4.3 Disable Transfer intr and Clear FIFO && SR register */
        AlAxiIic_ll_DisableInt(BaseAddr, I2C_TRANS_INT);
        AlAxiIic_ll_ClearStatusAll(BaseAddr);
        AlAxiIic_Dev_ClrFifo(Iic);
    }
}
