#include <string.h>
#include "al_top.h"
#include "al_spi_nor.h"
#include "al_hal.h"


#ifdef HAVE_QSPIPS_DRIVER
/**
 * This function configures the QSPI hardware controller with appropriate settings based on
 * the QSPI clock frequency and device requirements. It initializes the QSPI HAL interface
 * and enables local interrupts.
 *
 * @param Controller Pointer to the AlSpiController structure containing QSPI controller context.
 * @return AL_S32
 *   - AL_OK: Initialization succeeded
 *   - Other error codes: See AlQspi_Hal_Init implementation
 *
 * @note
 * - Depends on QSPI_CLOCK macro to determine sampling delay configuration
 * - Modifies Controller->HalHandle with initialized QSPI HAL structure
 */
AL_S32 AlSpiController_PsQspiInit(AlSpiController *Controller)
{
    AL_S32 Status;
    AL_QSPI_HalStruct *Handle = (AL_QSPI_HalStruct *)Controller->HalHandle;
    AL_QSPI_ConfigsStruct QspiX4InitConfigs =
    {
#if QSPI_CLOCK <= 100*MHz
        .SamplDelay         = 1, /* For 100M QSPI_CLOCK and 50M IO freq, delay = 10ns * 1 = 10ns */
#elif QSPI_CLOCK <= 200*MHz
        .SamplDelay         = 2, /* For 200M QSPI_CLOCK and 50M IO freq, delay = 5ns * 2 = 10ns */
#else
        .SamplDelay         = 2, /* For other value of QSPI_CLOCK, adjust delay cycles here */
#endif
        .SlvToggleEnum      = QSPI_SLV_TOGGLE_DISABLE,
        .SpiFrameFormat     = SPI_QUAD_FORMAT,
        .ClockStretch       = QSPI_EnableClockStretch
    };

    Status = AlQspi_Hal_Init(&Handle, &QspiX4InitConfigs, AL_NULL, Controller->DevId);
    if (Status != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlQspi_Hal_Init error:0x%x\r\n", Status);
    }

    Controller->HalHandle = (AL_VOID *)Handle;

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    return AL_OK;
}

/**
 * Configures the QSPI controller based on operation parameters and performs data transfer.
 * Supports different bus widths (Standard/Dual/Quad), transfer types (TT0-TT2), and
 * handles both transmit-only and receive operations.
 *
 * @param Controller Pointer to the AlSpiController structure
 * @param Op Pointer to the AlSpiMemOp structure defining the operation parameters:
 *          - Command/Address/Data bus widths
 *          - Data direction (TX/RX/None)
 *          - Dummy cycles configuration
 *          - Data buffer pointers
 * @return AL_S32
 *   - AL_OK: Operation completed successfully
 *   - AL_SPI_CONTROLLER_FRAME_FORMAT_ERROR: Invalid configuration parameters
 *   - Other error codes: See AL_SPI_NOR_EVENTS_TO_ERRS macros
 *
 * @note
 * - Constructs the full command sequence (CMD + ADDR + DUMMY + DATA) in SendData buffer
 * - Supports both DMA and blocking transfer modes (via QSPI_USE_AHB_DMA macro)
 * - Timing critical: Uses 100,000 timeout cycles for transfers
 */
AL_S32 AlSpiController_PsQspiExecOp(AlSpiController *Controller, const AlSpiMemOp *Op)
{
    AL_U32 Index = 0;
    AL_QSPI_HalStruct *Handle = (AL_QSPI_HalStruct *)Controller->HalHandle;
    AL_U8 SendData[16 + 512] = { 0 };
    AL_U32 SendSize = 0;
    AL_U32 RecvSize = 0;
    AL_U32 DummyBytes = 0;

    if (Op->Data.BusWidth == 1 || Op->Data.NumBytes == 0) {
        Handle->Dev.Configs.SpiFrameFormat = SPI_STANDARD_FORMAT;
    } else if (Op->Data.BusWidth == 2) {
        Handle->Dev.Configs.SpiFrameFormat = SPI_DUAL_FORMAT;
    } else if (Op->Data.BusWidth == 4) {
        Handle->Dev.Configs.SpiFrameFormat = SPI_QUAD_FORMAT;
    } else {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_CONTROLLER_FRAME_FORMAT_ERROR);
    }

    if (Op->Data.Dir == AL_SPI_MEM_NO_DATA || Op->Data.Dir == AL_SPI_MEM_DIR_OUT) {
        Handle->Dev.Configs.Trans.TransMode  = QSPI_TX_ONLY;
    } else {
        if (Handle->Dev.Configs.SpiFrameFormat == SPI_STANDARD_FORMAT) {
            Handle->Dev.Configs.Trans.TransMode  = QSPI_EEPROM;
        } else {
            Handle->Dev.Configs.Trans.TransMode  = QSPI_RX_ONLY;
        }
    }

    if (Op->Cmd.BusWidth < 2 && Op->Addr.BusWidth < 2) {
        Handle->Dev.Configs.Trans.EnSpiCfg.TransType = QSPI_TT0;
    } else if (Op->Cmd.BusWidth < 2 && Op->Addr.BusWidth == Op->Data.BusWidth) {
        Handle->Dev.Configs.Trans.EnSpiCfg.TransType = QSPI_TT1;
    } else if (Op->Cmd.BusWidth == Op->Data.BusWidth && Op->Addr.BusWidth == Op->Data.BusWidth) {
        Handle->Dev.Configs.Trans.EnSpiCfg.TransType = QSPI_TT2;
    } else {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_CONTROLLER_FRAME_FORMAT_ERROR);
    }

    if (Op->Cmd.NumBytes == 1) {
        Handle->Dev.Configs.Trans.EnSpiCfg.InstLength = QSPI_INST_L8;
    } else if (Op->Cmd.NumBytes == 2) {
        Handle->Dev.Configs.Trans.EnSpiCfg.InstLength = QSPI_INST_L16;
    } else {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_CONTROLLER_FRAME_FORMAT_ERROR);
    }

    Handle->Dev.Configs.Trans.EnSpiCfg.AddrLength = Op->Addr.NumBytes * 2;

    for (Index = 0; Index < Op->Cmd.NumBytes; Index++) {
        SendData[Index] = (Op->Cmd.OpCode >> (8 * (Op->Cmd.NumBytes - 1 - Index))) & 0xFF;
    }
    SendSize = Op->Cmd.NumBytes;

    for (Index = 0; Index < Op->Addr.NumBytes; Index++) {
        SendData[SendSize + Index] =
            (Op->Addr.Val >> (8 * (Op->Addr.NumBytes - 1 - Index))) & 0xFF;
    }
    SendSize += Op->Addr.NumBytes;

    if (Handle->Dev.Configs.SpiFrameFormat == SPI_STANDARD_FORMAT) {
        DummyBytes = Op->Dummy.NumCycles * Op->Dummy.BusWidth / 8;
        for (Index = 0; Index < DummyBytes; Index++) {
            SendData[SendSize + Index] = 0;
        }
        SendSize += DummyBytes;
    } else {
        Handle->Dev.Configs.Trans.EnSpiCfg.WaitCycles = Op->Dummy.NumCycles;
    }

    if (Op->Data.Dir == AL_SPI_MEM_DIR_OUT) {
        // if (Op->Data.NumBytes) {
        //     return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_CONTROLLER_FRAME_FORMAT_ERROR);
        // }

        memcpy(&SendData[SendSize], Op->Data.Buf.Out, Op->Data.NumBytes);
        SendSize += Op->Data.NumBytes;
    } else if (Op->Data.Dir == AL_SPI_MEM_DIR_IN) {
        RecvSize = Op->Data.NumBytes;
    }

#ifdef QSPI_USE_AHB_DMA
    if (RecvSize) {
        AlQspi_Hal_DmaStartTranferBlock(Handle, SendData, SendSize, Op->Data.Buf.In, RecvSize, 100000);
    } else {
        /* to do */
    }
#else
    if (RecvSize) {
        return AlQspi_Hal_TranferDataBlock(Handle, SendData, SendSize, Op->Data.Buf.In, RecvSize, 100000);
    } else {
        return AlQspi_Hal_SendDataBlock(Handle, SendData, SendSize, 100000);
    }
#endif

    return 0;
}

/**
 * This function sets the chip select value for the PS QSPI controller.
 * It calls the AlQspi_Hal_IoCtl function with the appropriate parameters
 * to perform the chip select operation.
 *
 * @param Controller A pointer to the AlSpiController structure representing the QSPI controller.
 * @param ChipSelect The chip select value to be set.
 * @return AL_S32 The return value of the AlQspi_Hal_IoCtl function, indicating the operation status.
 */
AL_S32 AlSpiController_PsQspiSetCs(AlSpiController *Controller, AL_U32 ChipSelect)
{
    AL_QSPI_HalStruct *Handle = (AL_QSPI_HalStruct *)Controller->HalHandle;
    return AlQspi_Hal_IoCtl(Handle, AL_QSPI_IOCTL_SET_SLAVE_SELECT, &ChipSelect, 100000);
}
#endif

#ifdef HAVE_SPIPS_DRIVER
/**
 * This function initializes the PS SPI controller by configuring the SPI settings
 * such as mode, protocol format, clock mode, and slave toggle. It then calls the
 * AlSpi_Hal_Init function to perform the low - level initialization.
 *
 * @param Controller A pointer to the AlSpiController structure representing the SPI controller.
 * @return AL_S32 Returns AL_OK if the initialization is successful, otherwise logs an error.
 */
AL_S32 AlSpiController_PsSpiInit(AlSpiController *Controller)
{
    AL_S32 Ret = AL_OK;

    AL_SPI_ConfigsStruct SpiInitConfigs = {
        .Mode               = SPI_MASTER_MODE,
        .ProtFormat         = MOTOROLA_SPI,
        .ClockEnum          = SPI_CLK_MODE0,
        .SlvToggleEnum      = SPI_SLV_TOGGLE_DISABLE,
    };

    AL_SPI_HalStruct *Handle = (AL_SPI_HalStruct *)Controller->HalHandle;
    Ret = AlSpi_Hal_Init(&Handle, &SpiInitConfigs, AL_NULL, Controller->DevId);
    if (AL_OK != Ret) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlSpi_Hal_Init error, Ret:0x%x\r\n", Ret);
    }

    Controller->HalHandle = (AL_VOID *)Handle;

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    return AL_OK;
}

/**
 * This function executes a SPI memory operation based on the provided operation
 * parameters. It configures the transfer mode, prepares the data to be sent,
 * and calls the appropriate data transfer function.
 *
 * @param Controller A pointer to the AlSpiController structure representing the SPI controller.
 * @param Op A pointer to the AlSpiMemOp structure containing the operation details.
 * @return AL_S32 The return value of the data transfer function, indicating the operation status.
 */
AL_S32 AlSpiController_PsSpiExecOp(AlSpiController *Controller, const AlSpiMemOp *Op)
{
    AL_U32 Index = 0;
    AL_U32 SendSize = 0;
    AL_U32 RecvSize = 0;
    AL_U32 DummyBytes = 0;
    AL_U8 SendData[16 + 512] = { 0 };
    AL_SPI_HalStruct *Handle = (AL_SPI_HalStruct *)Controller->HalHandle;

    if (Op->Data.Dir == AL_SPI_MEM_NO_DATA || Op->Data.Dir == AL_SPI_MEM_DIR_OUT) {
        Handle->Dev.Configs.Trans.TransMode  = SPI_TX_ONLY;
    } else {
        Handle->Dev.Configs.Trans.TransMode  = SPI_EEPROM;
    }

    for (Index = 0; Index < Op->Cmd.NumBytes; Index++) {
        SendData[Index] = (Op->Cmd.OpCode >> (8 * (Op->Cmd.NumBytes - 1 - Index))) & 0xFF;
    }
    SendSize = Op->Cmd.NumBytes;

    for (Index = 0; Index < Op->Addr.NumBytes; Index++) {
        SendData[SendSize + Index] =
            (Op->Addr.Val >> (8 * (Op->Addr.NumBytes - 1 - Index))) & 0xFF;
    }
    SendSize += Op->Addr.NumBytes;

    DummyBytes = Op->Dummy.NumCycles * Op->Dummy.BusWidth / 8;
    for (Index = 0; Index < DummyBytes; Index++) {
        SendData[SendSize + Index] = 0;
    }
    SendSize += DummyBytes;

    if (Op->Data.Dir == AL_SPI_MEM_DIR_OUT) {
        memcpy(&SendData[SendSize], Op->Data.Buf.Out, Op->Data.NumBytes);
        SendSize += Op->Data.NumBytes;
    } else if (Op->Data.Dir == AL_SPI_MEM_DIR_IN) {
        RecvSize = Op->Data.NumBytes;
    }

    if (RecvSize) {
        return AlSpi_Hal_TranferDataBlock(Handle, SendData, SendSize, Op->Data.Buf.In, RecvSize, 100000);
    } else {
        return AlSpi_Hal_SendDataBlock(Handle, SendData, SendSize, 100000);
    }

    return 0;
}
#endif

#if AL_AXI_QSPI_NUM_INSTANCE >= 1
/**
 * This function initializes the Programmable Logic (PL) QSPI controller.
 * It enables the GPIO ports, calls the low - level initialization function
 * `AlAxiQspi_Hal_Init`, and sets up the interrupts. Additionally, it checks
 * the QSPI mode and sets the appropriate flags in the controller structure.
 *
 * @param Controller A pointer to the `AlSpiController` structure that represents the QSPI controller.
 * @return AL_S32 Returns `AL_OK` if the initialization is successful. Otherwise, it logs an error
 *                and returns the error status from `AlAxiQspi_Hal_Init`.
 */
AL_S32 AlSpiController_PlQspiInit(AlSpiController *Controller)
{
    AL_S32 Status;
    AlAxiQspi_HalStruct *Handle = (AlAxiQspi_HalStruct *)Controller->HalHandle;

    AlTop_GPPortEnable();

    Status = AlAxiQspi_Hal_Init(&Handle, Controller->DevId, AL_NULL, AL_NULL);
    if (Status != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Axi-qspi init error: 0x%x\r\n", Status);
        return Status;
    }

    Controller->HalHandle = (AL_VOID *)Handle;

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    if (Handle->Dev.HwConfig.SpiMode == AXI_QSPI_DUAL) {
        Controller->Flags |= AL_SPI_CONTROLLER_DUAL;
    }

    if (Handle->Dev.HwConfig.SpiMode == AXI_QSPI_QUAD) {
        Controller->Flags |= (AL_SPI_CONTROLLER_QUAD | AL_SPI_CONTROLLER_DUAL);
    }

    return AL_OK;
}
/**
 * This function executes a QSPI memory operation on the PL QSPI controller.
 * It prepares the data to be sent by combining the command, address, and dummy bytes.
 * Depending on the data direction (input or output), it configures the send and receive sizes.
 * Finally, it calls the low - level data transfer function `AlAxiQspi_Hal_TransferDataBlock`.
 *
 * @param Controller A pointer to the `AlSpiController` structure that represents the QSPI controller.
 * @param Op A pointer to the `AlSpiMemOp` structure that contains the details of the memory operation.
 * @return AL_S32 Returns the status of the data transfer operation from `AlAxiQspi_Hal_TransferDataBlock`.
 */
AL_S32 AlSpiController_PlQspiExecOp(AlSpiController *Controller, const AlSpiMemOp *Op)
{
    AL_U32 Index = 0;
    AlAxiQspi_HalStruct *Handle = (AlAxiQspi_HalStruct *)Controller->HalHandle;
    AL_U8 SendData[16 + 512] = { 0 };
    AL_U32 DummyBytes = 0;
    AL_U32 SendSize = 0;
    AL_U32 RecvSize = 0;

    if (Op->Dummy.NumCycles) {
        DummyBytes = Op->Dummy.NumCycles * Op->Dummy.BusWidth / 8;
    }
    SendSize = DummyBytes + Op->Cmd.NumBytes + Op->Addr.NumBytes;

    for (Index = 0; Index < Op->Cmd.NumBytes; Index++) {
        SendData[Index] = (Op->Cmd.OpCode >> (8 * (Op->Cmd.NumBytes - 1 - Index))) & 0xFF;
    }

    for (Index = 0; Index < Op->Addr.NumBytes; Index++) {
        SendData[Op->Cmd.NumBytes + Index] =
            (Op->Addr.Val >> (8 * (Op->Addr.NumBytes - 1 - Index))) & 0xFF;
    }

    if (Op->Data.Dir == AL_SPI_MEM_DIR_OUT) {
        if (Op->Data.NumBytes) {
            return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_CONTROLLER_FRAME_FORMAT_ERROR);
        }

        memcpy(&SendData[SendSize], Op->Data.Buf.Out, Op->Data.NumBytes);
        SendSize += Op->Data.NumBytes;
    } else if (Op->Data.Dir == AL_SPI_MEM_DIR_IN) {
        RecvSize = Op->Data.NumBytes;
    }

    return AlAxiQspi_Hal_TransferDataBlock(Handle, SendData, SendSize,
                                           Op->Data.Buf.In, RecvSize, 100000);
}
#endif

AlSpiController __WEAK SpiControllerList[] =
{
#ifdef HAVE_QSPIPS_DRIVER
    {AL_CONTROLLER_PS_QSPI, 0, AL_SPI_CONTROLLER_DUAL | AL_SPI_CONTROLLER_QUAD, NULL,
        (SpiNorInitOp)AlSpiController_PsQspiInit,
        (SpiNorExecOp)AlSpiController_PsQspiExecOp,
        (SpiNorSetCs)AlSpiController_PsQspiSetCs},
#endif

#ifdef HAVE_SPIPS_DRIVER
#ifdef SPI0PS_ENABLE
    {AL_CONTROLLER_PS_SPI, 0, 0, NULL,
        (SpiNorInitOp)AlSpiController_PsSpiInit,
        (SpiNorExecOp)AlSpiController_PsSpiExecOp,
        AL_NULL},
#endif
#ifdef SPI1PS_ENABLE
    {AL_CONTROLLER_PS_SPI, 1, 0, NULL,
        (SpiNorInitOp)AlSpiController_PsSpiInit,
        (SpiNorExecOp)AlSpiController_PsSpiExecOp,
        AL_NULL},
#endif
#endif

#if AL_AXI_QSPI_NUM_INSTANCE >= 1
    {AL_CONTROLLER_PL_QSPI, 0, AL_SPI_CONTROLLER_DUAL | AL_SPI_CONTROLLER_QUAD, NULL,
        (SpiNorInitOp)AlSpiController_PlQspiInit,
        (SpiNorExecOp)AlSpiController_PlQspiExecOp,
        AL_NULL},
#endif
#if AL_AXI_QSPI_NUM_INSTANCE >= 2
    {AL_CONTROLLER_PL_QSPI, 1, AL_SPI_CONTROLLER_DUAL | AL_SPI_CONTROLLER_QUAD, NULL,
        (SpiNorInitOp)AlSpiController_PlQspiInit,
        (SpiNorExecOp)AlSpiController_PlQspiExecOp,
        AL_NULL},
#endif

};

const AL_U32 __WEAK SpiControllerListSize = sizeof(SpiControllerList) / sizeof(SpiControllerList[0]);