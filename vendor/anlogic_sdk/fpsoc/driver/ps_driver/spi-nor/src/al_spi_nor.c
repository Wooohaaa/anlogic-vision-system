#include "al_core.h"
#include "al_spi_nor.h"
#include "al_spi_controller.h"

extern const AlSpiNorInfo SpiNorInfoList[];
extern const AL_U32 SpiNorInfoListSize;
extern const AlSpiNorInfo SpiNorDefaultInfo;
extern AlSpiController SpiControllerList[];
extern const AL_U32 SpiControllerListSize;

/**
 * [7:0]: Opcode
 * [10:8]: BusWidth
 * [13:11]: AddrBytes
 * [16:14]: CmdBusWidth
 * [19:17]: AddrBusWidth
 * [22:20]: DummyBusWidth
 * [25:23]: DataBusWidth
 * [31:26]: DummyCycles
 */
AL_U32 AlSpiRdCmdProtoList[] =
{
#define PROTO_RD_OPCODE_SHIFT                 0
#define PROTO_RD_OPCODE_MASK                  0xFF
#define PROTO_RD_BUS_WIDTH_SHIFT              8
#define PROTO_RD_BUS_WIDTH_MASK               (0x7 << PROTO_RD_BUS_WIDTH_SHIFT)
#define PROTO_RD_ADDR_BYTES_SHIFT             11
#define PROTO_RD_ADDR_BYTES_MASK              (0x7 << PROTO_RD_ADDR_BYTES_SHIFT)
#define PROTO_RD_CMD_BUS_WIDTH_SHIFT          14
#define PROTO_RD_CMD_BUS_WIDTH_MASK           (0x7 << PROTO_RD_CMD_BUS_WIDTH_SHIFT)
#define PROTO_RD_ADDR_BUS_WIDTH_SHIFT         17
#define PROTO_RD_ADDR_BUS_WIDTH_MASK          (0x7 <<  PROTO_RD_ADDR_BUS_WIDTH_SHIFT)
#define PROTO_RD_DUMMY_CYCLES_SHIFT           20
#define PROTO_RD_DUMMY_CYCLES_MASK            (0x1F << PROTO_RD_DUMMY_CYCLES_SHIFT)

#define PROTO_RD_INFO(OpCode, BusWidth, AddrBytes, CmdWidth, AddrWidth, DummyCycles)  \
            ((OpCode << PROTO_RD_OPCODE_SHIFT)               |                        \
            (BusWidth << PROTO_RD_BUS_WIDTH_SHIFT)           |                        \
            (AddrBytes << PROTO_RD_ADDR_BYTES_SHIFT)         |                        \
            (CmdWidth << PROTO_RD_CMD_BUS_WIDTH_SHIFT)       |                        \
            (AddrWidth << PROTO_RD_ADDR_BUS_WIDTH_SHIFT)     |                        \
            (DummyCycles << PROTO_RD_DUMMY_CYCLES_SHIFT))


    PROTO_RD_INFO(NOR_OP_READ, 1, 3, 1, 1, 0),
    PROTO_RD_INFO(NOR_OP_READ_FAST, 1, 3, 1, 1, 8),
    PROTO_RD_INFO(NOR_OP_READ_1_1_2, 2, 3, 1, 1, 8),
    PROTO_RD_INFO(NOR_OP_READ_1_2_2, 2, 3, 1, 2, 4),
    PROTO_RD_INFO(NOR_OP_READ_1_1_4, 4, 3, 1, 1, 8),
    PROTO_RD_INFO(NOR_OP_READ_1_4_4, 4, 3, 1, 4, 6),

    PROTO_RD_INFO(NOR_OP_READ_4B, 1, 4, 1, 1, 0),
    PROTO_RD_INFO(NOR_OP_READ_FAST_4B, 1, 4, 1, 1, 8),
    PROTO_RD_INFO(NOR_OP_READ_1_1_2_4B, 2, 4, 1, 1, 8),
    PROTO_RD_INFO(NOR_OP_READ_1_2_2_4B, 2, 4, 1, 2, 4),
    PROTO_RD_INFO(NOR_OP_READ_1_1_4_4B, 4, 4, 1, 1, 8),
    PROTO_RD_INFO(NOR_OP_READ_1_4_4_4B, 4, 4, 1, 4, 6),
};

AL_U32 AlSpiWrCmdProtoList[] =
{
#define PROTO_WR_OPCODE_SHIFT                 0
#define PROTO_WR_OPCODE_MASK                  0xFF
#define PROTO_WR_BUS_WIDTH_SHIFT              8
#define PROTO_WR_BUS_WIDTH_MASK               (0x7 << PROTO_WR_BUS_WIDTH_SHIFT)
#define PROTO_WR_ADDR_BYTES_SHIFT             11
#define PROTO_WR_ADDR_BYTES_MASK              (0x7 << PROTO_WR_ADDR_BYTES_SHIFT)
#define PROTO_WR_CMD_BUS_WIDTH_SHIFT          14
#define PROTO_WR_CMD_BUS_WIDTH_MASK           (0x7 << PROTO_WR_CMD_BUS_WIDTH_SHIFT)
#define PROTO_WR_ADDR_BUS_WIDTH_SHIFT         17
#define PROTO_WR_ADDR_BUS_WIDTH_MASK          (0x7 <<  PROTO_WR_ADDR_BUS_WIDTH_SHIFT)
#define PROTO_WR_DUMMY_CYCLES_SHIFT           20
#define PROTO_WR_DUMMY_CYCLES_MASK            (0x1F << PROTO_WR_DUMMY_CYCLES_SHIFT)

#define PROTO_WR_INFO(OpCode, BusWidth, AddrBytes, CmdWidth, AddrWidth, DummyCycles)  \
            ((OpCode << PROTO_WR_OPCODE_SHIFT)               |                        \
            (BusWidth << PROTO_WR_BUS_WIDTH_SHIFT)           |                        \
            (AddrBytes << PROTO_WR_ADDR_BYTES_SHIFT)         |                        \
            (CmdWidth << PROTO_WR_CMD_BUS_WIDTH_SHIFT)       |                        \
            (AddrWidth << PROTO_WR_ADDR_BUS_WIDTH_SHIFT)     |                        \
            (DummyCycles << PROTO_WR_DUMMY_CYCLES_SHIFT))

    PROTO_WR_INFO(NOR_OP_PP, 1, 3, 1, 1, 0),
    PROTO_WR_INFO(NOR_OP_PP_1_1_4, 4, 3, 1, 1, 0),
    PROTO_WR_INFO(NOR_OP_PP_1_4_4, 4, 3, 1, 4, 0),

    PROTO_WR_INFO(NOR_OP_PP_4B, 1, 4, 1, 1, 0),
    PROTO_WR_INFO(NOR_OP_PP_1_1_4_4B, 4, 4, 1, 1, 0),
    PROTO_WR_INFO(NOR_OP_PP_1_4_4_4B, 4, 4, 1, 4, 0),
};

AL_U32 AlSpiEraseCmdProtoList[] =
{
#define PROTO_ERASE_OPCODE_SHIFT              0
#define PROTO_ERASE_OPCODE_MASK               0xFF
#define PROTO_ERASE_ADDR_BYTES_SHIFT          8
#define PROTO_ERASE_ADDR_BYTES_MASK           (0x7 << PROTO_ERASE_ADDR_BYTES_SHIFT)
#define PROTO_ERASE_SECTOR_4K_SHIFT           12
#define PROTO_ERASE_SECTOR_4K_MASK            (0x1 << PROTO_ERASE_SECTOR_4K_SHIFT)
#define PROTO_ERASE_SECTOR_32K_SHIFT          15
#define PROTO_ERASE_SECTOR_32K_MASK           (0x1 << PROTO_ERASE_SECTOR_32K_SHIFT)
#define PROTO_ERASE_SECTOR_64K_SHIFT          16
#define PROTO_ERASE_SECTOR_64K_MASK           (0x1 << PROTO_ERASE_SECTOR_64K_SHIFT)
#define PROTO_ERASE_SECTOR_128K_SHIFT         17
#define PROTO_ERASE_SECTOR_128K_MASK          (0x1 << PROTO_ERASE_SECTOR_128K_SHIFT)
#define PROTO_ERASE_SECTOR_256K_SHIFT         18
#define PROTO_ERASE_SECTOR_256K_MASK          (0x1 << PROTO_ERASE_SECTOR_256K_SHIFT)

#define PROTO_EARSE_INFO(OpCode, AddrBytes, EraseSize)                                \
            ((OpCode << PROTO_ERASE_OPCODE_SHIFT)            |                        \
            (AddrBytes << PROTO_ERASE_ADDR_BYTES_SHIFT)      |                        \
            (EraseSize & 0xFFFFF000))

    PROTO_EARSE_INFO(NOR_OP_BE_4K, 3, 4 * 1024),
    PROTO_EARSE_INFO(NOR_OP_BE_32K, 3, 32 * 1024),
    PROTO_EARSE_INFO(NOR_OP_SE, 3, 64 * 1024),
    PROTO_EARSE_INFO(NOR_OP_BE_4K_4B, 4, 4 * 1024),
    PROTO_EARSE_INFO(NOR_OP_BE_32K_4B, 4, 32 * 1024),
    PROTO_EARSE_INFO(NOR_OP_SE_4B, 4, 64 * 1024),
    PROTO_EARSE_INFO(NOR_OP_SE_4B, 4, 256 * 1024),
};

/**
 * This function iterates through the `AlSpiRdCmdProtoList` to find a matching
 * read protocol based on the current bus width and the number of address bytes
 * of the given SPI NOR flash device (`SpiNor`). If a match is found, it sets
 * the read protocol fields (opcode, dummy cycles, command width, and address width)
 * in the `SpiNor` structure.
 *
 * @param SpiNor A pointer to the `AlSpiNor` structure representing the SPI NOR flash device.
 * @return AL_S32 Returns `AL_OK` if a matching read protocol is found and set successfully.
 *                Otherwise, it returns an error code converted from `AL_SPI_NOR_SET_READ_PROTO_ERROR`.
 */
AL_S32 AlSpiNor_SetReadProto(AlSpiNor *SpiNor)
{
    AL_U32 Index;

    for (Index = 0; Index < sizeof(AlSpiRdCmdProtoList) / sizeof(AlSpiRdCmdProtoList[0]); Index++) {
        if (SpiNor->CurBusWidth ==
            ((AlSpiRdCmdProtoList[Index] & PROTO_RD_BUS_WIDTH_MASK) >> PROTO_RD_BUS_WIDTH_SHIFT) &&
            SpiNor->AddrBytes ==
            ((AlSpiRdCmdProtoList[Index] & PROTO_RD_ADDR_BYTES_MASK) >> PROTO_RD_ADDR_BYTES_SHIFT)) {

            SpiNor->RdProto.OpCode = (AlSpiRdCmdProtoList[Index] & PROTO_RD_OPCODE_MASK);
            SpiNor->RdProto.DummyCycles =
                (AlSpiRdCmdProtoList[Index] & PROTO_RD_DUMMY_CYCLES_MASK) >> PROTO_RD_DUMMY_CYCLES_SHIFT;
            SpiNor->RdProto.CmdWidth =
                (AlSpiRdCmdProtoList[Index] & PROTO_RD_CMD_BUS_WIDTH_MASK) >> PROTO_RD_CMD_BUS_WIDTH_SHIFT;
            SpiNor->RdProto.AddrWidth =
                (AlSpiRdCmdProtoList[Index] & PROTO_RD_ADDR_BUS_WIDTH_MASK) >> PROTO_RD_ADDR_BUS_WIDTH_SHIFT;

            return AL_OK;
        }
    }

    return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_READ_PROTO_ERROR);
}

/**
 * This function goes through the `AlSpiWrCmdProtoList` to search for a matching
 * write protocol according to the current bus width and the number of address bytes
 * of the provided SPI NOR flash device (`SpiNor`). When a match is located, it configures
 * the write protocol fields (opcode, dummy cycles, command width, and address width)
 * in the `SpiNor` structure.
 *
 * @param SpiNor A pointer to the `AlSpiNor` structure representing the SPI NOR flash device.
 * @return AL_S32 Returns `AL_OK` if a matching write protocol is found and set correctly.
 *                Otherwise, it returns an error code converted from `AL_SPI_NOR_SET_WRITE_PROTO_ERROR`.
 */
AL_S32 AlSpiNor_SetWriteProto(AlSpiNor *SpiNor)
{
    AL_U32 Index;

    for (Index = 0; Index < sizeof(AlSpiWrCmdProtoList) / sizeof(AlSpiWrCmdProtoList[0]); Index++) {
        if (SpiNor->CurBusWidth ==
            ((AlSpiWrCmdProtoList[Index] & PROTO_WR_BUS_WIDTH_MASK) >> PROTO_WR_BUS_WIDTH_SHIFT) &&
            SpiNor->AddrBytes ==
            ((AlSpiWrCmdProtoList[Index] & PROTO_WR_ADDR_BYTES_MASK) >> PROTO_WR_ADDR_BYTES_SHIFT)) {

            SpiNor->WrProto.OpCode = (AlSpiWrCmdProtoList[Index] & PROTO_WR_OPCODE_MASK);
            SpiNor->WrProto.DummyCycles =
                (AlSpiWrCmdProtoList[Index] & PROTO_WR_DUMMY_CYCLES_MASK) >> PROTO_WR_DUMMY_CYCLES_SHIFT;
            SpiNor->WrProto.CmdWidth =
                (AlSpiWrCmdProtoList[Index] & PROTO_WR_CMD_BUS_WIDTH_MASK) >> PROTO_WR_CMD_BUS_WIDTH_SHIFT;
            SpiNor->WrProto.AddrWidth =
                (AlSpiWrCmdProtoList[Index] & PROTO_WR_ADDR_BUS_WIDTH_MASK) >> PROTO_WR_ADDR_BUS_WIDTH_SHIFT;

            return AL_OK;
        }
    }

    return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_WRITE_PROTO_ERROR);
}

/**
 * This function traverses the `AlSpiEraseCmdProtoList` to find a suitable
 * erase protocol based on the number of address bytes and the erase size
 * of the given SPI NOR flash device (`SpiNor`). Once a match is found, it sets
 * the erase protocol fields (opcode, command width, address width, and dummy cycles)
 * in the `SpiNor` structure.
 *
 * @param SpiNor A pointer to the `AlSpiNor` structure representing the SPI NOR flash device.
 * @return AL_S32 Returns `AL_OK` if a matching erase protocol is found and set successfully.
 *                Otherwise, it returns an error code converted from `AL_SPI_NOR_SET_ERASE_PROTO_ERROR`.
 */
AL_S32 AlSpiNor_SetEraseProto(AlSpiNor *SpiNor)
{
    AL_U32 Index;

    for (Index = 0; Index < sizeof(AlSpiEraseCmdProtoList) / sizeof(AlSpiEraseCmdProtoList[0]); Index++) {
        if (SpiNor->AddrBytes ==
            ((AlSpiEraseCmdProtoList[Index] & PROTO_ERASE_ADDR_BYTES_MASK) >> PROTO_ERASE_ADDR_BYTES_SHIFT) &&
            SpiNor->EraseSize ==
            (AlSpiEraseCmdProtoList[Index] & 0xFFFFF000)) {

            SpiNor->EraseProto.OpCode = (AlSpiEraseCmdProtoList[Index] & PROTO_ERASE_OPCODE_MASK);
            SpiNor->EraseProto.CmdWidth = 1;
            SpiNor->EraseProto.AddrWidth = 1;
            SpiNor->EraseProto.DummyCycles = 0;

            return AL_OK;
        }
    }

    return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_ERASE_PROTO_ERROR);
}

/**
 * This function configures the read, write, and erase protocols for the SPI NOR Flash.
 * It sequentially calls the protocol setting functions and returns immediately if any step fails.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance representing the SPI NOR Flash device.
 * @return AL_S32 Status of the operation:
 *         - AL_OK: All protocols set successfully.
 *         - Error code: If any protocol setting step fails.
 */
AL_S32 AlSpiNor_SetProto(AlSpiNor *SpiNor)
{
    AL_S32 Status;

    Status = AlSpiNor_SetReadProto(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_SetWriteProto(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_SetEraseProto(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    return AL_OK;
}

/**
 * This function executes a Read ID (RDID) command to retrieve the 3-byte ID data
 * from the SPI NOR Flash device.
 *
 * @param[in]  SpiNor Pointer to the AlSpiNor instance representing the SPI NOR Flash device.
 * @param[out] Id     Pointer to the buffer where the 3-byte ID will be stored.
 * @return AL_S32 Status of the operation:
 *         - AL_OK: ID read successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_ReadId(AlSpiNor *SpiNor, AL_U8 *Id)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_RDID, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_IN(3, Id, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function executes a Read Status Register (RDSR) command to retrieve
 * the 1-byte status register value.
 *
 * @param[in]  SpiNor Pointer to the AlSpiNor instance representing the SPI NOR Flash device.
 * @param[out] Sr     Pointer to the buffer where the status register value will be stored.
 * @return AL_S32 Status of the operation:
 *         - AL_OK: Status register read successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_ReadSr(AlSpiNor *SpiNor, AL_U8 *Sr)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_RDSR, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_IN(1, Sr, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function executes a Read Configuration Register (RDCR) command to retrieve
 * the 1-byte configuration register value.
 *
 * @param[in]  SpiNor Pointer to the AlSpiNor instance representing the SPI NOR Flash device.
 * @param[out] Cr     Pointer to the buffer where the configuration register value will be stored.
 * @return AL_S32 Status of the operation:
 *         - AL_OK: Configuration register read successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_ReadCr(AlSpiNor *SpiNor, AL_U8 *Cr)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_RDCR, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_IN(1, Cr, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function executes a Read Status Register 2 (RDSR2) command to retrieve
 * the 1-byte secondary status register value. This register may contain
 * device-specific additional status bits.
 *
 * @param[in]  SpiNor Pointer to the AlSpiNor instance representing the SPI NOR Flash device.
 * @param[out] Sr2    Pointer to the buffer where the secondary status register value will be stored.
 * @return AL_S32 Status of the operation:
 *         - AL_OK: Secondary status register read successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_ReadSr2(AlSpiNor *SpiNor, AL_U8 *Sr2)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_RDSR2, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_IN(1, Sr2, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function executes a Write Status Register (WRSR) command to write
 * multiple bytes to the status register(s). The number of bytes written
 * depends on the device's implementation (1-2 bytes).
 *
 * @param[in] SpiNor    Pointer to the AlSpiNor instance.
 * @param[in] Sr        Pointer to the buffer containing status register data to write.
 * @param[in] Len       Number of bytes to write (1-2, device-dependent).
 * @return AL_S32 Operation status:
 *         - AL_OK: Write operation successful.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_WriteSr(AlSpiNor *SpiNor, AL_U8 *Sr, AL_U32 Len)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_WRSR, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_OUT(Len, Sr, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function executes a vendor-specific command (WRSR2 for GigaDevice) to
 * write the 1-byte configuration register value.
 *
 * @note This command may be specific to GigaDevice-compatible SPI NOR Flash devices.
 *
 * @param[in] SpiNor    Pointer to the AlSpiNor instance.
 * @param[in] Cr        1-byte configuration register value to write.
 * @return AL_S32 Operation status:
 *         - AL_OK: Write operation successful.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_WriteCr(AlSpiNor *SpiNor, AL_U8 Cr)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_WRSR2_GIGADEVICE, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_OUT(1, &Cr, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function executes a Write Status Register 2 (WRSR2) command to write
 * the 1-byte secondary status register value. Used for devices with extended status registers.
 *
 * @param[in] SpiNor    Pointer to the AlSpiNor instance.
 * @param[in] Sr2       1-byte secondary status register value to write.
 * @return AL_S32 Operation status:
 *         - AL_OK: Write operation successful.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_WriteSr2(AlSpiNor *SpiNor, AL_U8 Sr2)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_WRSR2, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_OUT(1, &Sr2, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function asserts the Write Enable Latch (WEL) bit, which is required
 * before any write/erase operation. The WEL bit is automatically cleared
 * after completion of a write/erase operation or on power-down.
 *
 * @param[in] SpiNor    Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Command executed successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_WriteEnable(AlSpiNor *SpiNor)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_WREN, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_NO_DATA);

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function periodically reads the Status Register and checks the
 * Write-In-Progress (WIP) bit. It blocks until:
 * - WIP bit clears (device ready), or
 * - A status read error occurs.
 *
 * @param[in] SpiNor        Pointer to the AlSpiNor instance.
 * @param[in] TimeStepMs    Sleep duration (milliseconds) between status checks.
 *                          Use 0 for non-blocking polling (not recommended).
 * @return AL_S32 Operation status:
 *         - AL_OK: Device ready within the polling period.
 *         - Error code: Status read failure or timeout (if implemented).
 */
AL_S32 AlSpiNor_WaitReady(AlSpiNor *SpiNor, AL_U32 TimeStepMs)
{
    AL_U8 Sr;
    AL_S32 Status;

    do {
        Status = AlSpiNor_ReadSr(SpiNor, &Sr);
        if (Status != AL_OK) {
            return Status;
        }

        if (TimeStepMs) {
            AlOsal_Sleep(TimeStepMs);
        }

    } while (Sr & SR_WIP);

    return AL_OK;
}

/**
 * This function sends a specific command sequence with a fixed address and data value (0x60)
 * to enable 64-byte wrap-around addressing mode. This mode is typically used for burst read optimization.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Wrap mode configured successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_SetWrap64_MODE1(AlSpiNor *SpiNor)
{
    AL_U8 Val = 0x60;
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_SBL_MODE1, 1),
                                  SPI_MEM_OP_ADDR(3, 0, 4),
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_OUT(1, &Val, 4));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This sequence:
 * 1. Writes 0xFE to a device-specific configuration register at address 0x07 using command 0x81.
 * 2. Reads back the register using command 0x85 with dummy cycles.
 * 3. Verifies the written value matches the read value.
 *
 * @note The command codes (0x81/0x85) and address 0x07 are implementation-specific,
 *       likely targeting GigaDevice-compatible devices.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Wrap mode configured and verified successfully.
 *         - AL_SPI_NOR_SET_WRAP64_MODE2_REG_VAL_ERROR: Register verification failed.
 *         - Other error codes: Operation failure at any step.
 */
AL_S32 AlSpiNor_SetWrap64_MODE2(AlSpiNor *SpiNor)
{
    AL_U32 Status;
    AL_U8 Val = 0xFE;
    AL_U8 Val_Read = 0;
    AlSpiMemOp MemOp_Wr = SPI_MEM_OP(SPI_MEM_OP_CMD(0x81, 1),
                                     SPI_MEM_OP_ADDR(3, 0x07, 1),
                                     SPI_MEM_OP_NO_DUMMY,
                                     SPI_MEM_OP_DATA_OUT(1, &Val, 1));
    AlSpiMemOp MemOp_Rd = SPI_MEM_OP(SPI_MEM_OP_CMD(0x85, 1),
                                     SPI_MEM_OP_ADDR(3, 0x07, 1),
                                     SPI_MEM_OP_DUMMY(8, 1),
                                     SPI_MEM_OP_DATA_IN(1, &Val_Read, 1));

    Status = AlSpiNor_WriteEnable(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Status = SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp_Wr);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_WaitReady(SpiNor, 0);
    if (Status != AL_OK) {
        return Status;
    }

    Status = SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp_Rd);
    if (Status != AL_OK) {
        return Status;
    }

    if (Val != Val_Read) {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_WRAP64_MODE2_REG_VAL_ERROR);
    }

    return AL_OK;
}

/**
 * This sequence:
 * 1. Writes 0xFA to a device-specific configuration register using command 0x81
 *    (address-less operation variant).
 * 2. Reads back the register using command 0x85 (address-less variant).
 * 3. Verifies the written value matches the read value.
 *
 * @note The command codes (0x81/0x85) and address-less operation suggest this targets
 *       a different register space than Mode 2, potentially for alternative configurations.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Wrap mode configured and verified successfully.
 *         - AL_SPI_NOR_SET_WRAP64_MODE3_REG_VAL_ERROR: Register verification failed.
 *         - Other error codes: Operation failure at any step.
 */
AL_S32 AlSpiNor_SetWrap64_MODE3(AlSpiNor *SpiNor)
{
    AL_U8 Val = 0xFA;
    AL_U8 Val_Read = 0;
    AL_S32 Status;
    AlSpiMemOp MemOp_Wr = SPI_MEM_OP(SPI_MEM_OP_CMD(0x81, 1),
                                     SPI_MEM_OP_NO_ADDR,
                                     SPI_MEM_OP_NO_DUMMY,
                                     SPI_MEM_OP_DATA_OUT(1, &Val, 1));
    AlSpiMemOp MemOp_Rd = SPI_MEM_OP(SPI_MEM_OP_CMD(0x85, 1),
                                     SPI_MEM_OP_NO_ADDR,
                                     SPI_MEM_OP_NO_DUMMY,
                                     SPI_MEM_OP_DATA_IN(1, &Val_Read, 1));

    Status = AlSpiNor_WriteEnable(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Status = SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp_Wr);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_WaitReady(SpiNor, 0);
    if (Status != AL_OK) {
        return Status;
    }

    Status = SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp_Rd);
    if (Status != AL_OK) {
        return Status;
    }

    if (Val != Val_Read) {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_WRAP64_MODE3_REG_VAL_ERROR);
    }

    return AL_OK;
}

/**
 * This function sends command 0xC0 with data value 0x03 to enable a vendor-specific
 * 64-byte wrap addressing mode. Used for devices requiring a simple command-based configuration.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Wrap mode configured successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_SetWrap64_MODE4(AlSpiNor *SpiNor)
{
    AL_U8 Val = 0x03;
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(0xC0, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_OUT(1, &Val, 1));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This router function selects the wrap mode implementation according to the
 * AL_SPI_NOR_FLAG_WRAP_MODE_MASK flags in FlashInfo. Supports modes 1-4.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Supported mode configured successfully.
 *         - AL_SPI_NOR_SET_WRAP64_MODE_ERROR: Unsupported/unknown mode requested.
 *         - Mode-specific error codes from underlying functions.
 */
AL_S32 AlSpiNor_SetWrap64(AlSpiNor *SpiNor)
{
    switch (SpiNor->FlashInfo->Flags & AL_SPI_NOR_FLAG_WRAP_MODE_MASK)
    {
    case AL_SPI_NOR_FLAG_WRAP_MODE0:
        break;

    case AL_SPI_NOR_FLAG_WRAP_MODE1:
        return AlSpiNor_SetWrap64_MODE1(SpiNor);

    case AL_SPI_NOR_FLAG_WRAP_MODE2:
        return AlSpiNor_SetWrap64_MODE2(SpiNor);

    case AL_SPI_NOR_FLAG_WRAP_MODE3:
        return AlSpiNor_SetWrap64_MODE3(SpiNor);

    case AL_SPI_NOR_FLAG_WRAP_MODE4:
        return AlSpiNor_SetWrap64_MODE4(SpiNor);

    default:
        break;
    }

    return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_WRAP64_MODE_ERROR);
}

/**
 * This implementation:
 * 1. For QE_MODE5 devices: Checks CR[QE] bit first
 * 2. Writes both SR and CR registers to set QE bits
 * 3. Verifies both registers after writing
 *
 * @note Covers Quad Enable methods requiring 2-byte register writes (e.g., Mode1/Mode4/Mode5 devices).
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Quad mode enabled and verified.
 *         - AL_SPI_NOR_SET_QUAD_MODE_1_4_5_REG_VAL_ERROR: SR/CR value mismatch.
 *         - Other error codes from sub-operations.
 */
AL_S32 AlSpiNor_QuadEnableMode_1_4_5(AlSpiNor *SpiNor)
{
    AL_U8 Sr_Cr[2] = { 0 };
    AL_U8 Sr_Cr_Read[2];
    AL_S32 Status;

    if (SpiNor->FlashInfo->Flags & AL_SPI_NOR_FLAG_QE_MODE5) {
        Status = AlSpiNor_ReadCr(SpiNor, &Sr_Cr[1]);
        if (Status != AL_OK) {
            return Status;
        }

        if (Sr_Cr[1] & SR2_QUAD_EN_BIT1) {
            return AL_OK;
        }
    }

    Status = AlSpiNor_ReadSr(SpiNor, &Sr_Cr[0]);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_WriteEnable(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Sr_Cr[1] |= SR2_QUAD_EN_BIT1;
    Status = AlSpiNor_WriteSr(SpiNor, Sr_Cr, 2);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_WaitReady(SpiNor, 0);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_ReadSr(SpiNor, &Sr_Cr_Read[0]);
    if (Status != AL_OK) {
        return Status;
    }

    if (Sr_Cr[0] != Sr_Cr_Read[0]) {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_QUAD_MODE_1_4_5_REG_VAL_ERROR);
    }

    if (SpiNor->FlashInfo->Flags & AL_SPI_NOR_FLAG_QE_MODE5) {
        Status = AlSpiNor_ReadCr(SpiNor, &Sr_Cr_Read[1]);
        if (Status != AL_OK) {
            return Status;
        }

        if (Sr_Cr[1] != Sr_Cr_Read[1]) {
            return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_QUAD_MODE_1_4_5_REG_VAL_ERROR);
        }
    }

    return AL_OK;
}

/**
 * This implementation:
 * 1. Checks SR[BIT6] for existing Quad Enable status
 * 2. Sets SR[BIT6] through single-byte write
 * 3. Verifies SR value after writing
 *
 * @note Covers Quad Enable Method 2 devices where QE is controlled by SR bit 6.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Quad mode enabled and verified.
 *         - AL_SPI_NOR_SET_QUAD_MODE_2_REG_VAL_ERROR: SR value mismatch.
 *         - Other error codes from sub-operations.
 */
AL_S32 AlSpiNor_QuadEnableMode_2(AlSpiNor *SpiNor)
{
    AL_U8 Sr;
    AL_U8 Sr_Read;
    AL_S32 Status;

    Status = AlSpiNor_ReadSr(SpiNor, &Sr);
    if (Status != AL_OK) {
        return Status;
    }

    if (Sr & SR1_QUAD_EN_BIT6) {
        return AL_OK;
    }

    Status = AlSpiNor_WriteEnable(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Sr |= SR1_QUAD_EN_BIT6;
    Status = AlSpiNor_WriteSr(SpiNor, &Sr, 1);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_WaitReady(SpiNor, 0);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_ReadSr(SpiNor, &Sr_Read);
    if (Status != AL_OK) {
        return Status;
    }

    if (Sr != Sr_Read) {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_QUAD_MODE_2_REG_VAL_ERROR);
    }

    return AL_OK;
}

/**
 * This implementation:
 * 1. Checks SR2[BIT7] for existing Quad Enable status
 * 2. Sets SR2[BIT7] through single-byte write
 * 3. Verifies SR2 value after writing
 *
 * @note Covers Quad Enable Method 3 devices where QE is controlled by SR2 bit 7.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Quad mode enabled and verified.
 *         - AL_SPI_NOR_SET_QUAD_MODE_3_REG_VAL_ERROR: SR2 value mismatch.
 *         - Other error codes from sub-operations.
 */
AL_S32 AlSpiNor_QuadEnableMode_3(AlSpiNor *SpiNor)
{
    AL_U8 Sr2;
    AL_U8 Sr2_Read;
    AL_S32 Status;

    Status = AlSpiNor_ReadSr2(SpiNor, &Sr2);
    if (Status != AL_OK) {
        return Status;
    }

    if (Sr2 & SR2_QUAD_EN_BIT7) {
        return AL_OK;
    }

    Status = AlSpiNor_WriteEnable(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Sr2 |= SR2_QUAD_EN_BIT7;
    Status = AlSpiNor_WriteSr2(SpiNor, Sr2);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_WaitReady(SpiNor, 0);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_ReadSr2(SpiNor, &Sr2_Read);
    if (Status != AL_OK) {
        return Status;
    }

    if (Sr2 != Sr2_Read) {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_QUAD_MODE_3_REG_VAL_ERROR);
    }

    return AL_OK;
}

/**
 * This implementation:
 * 1. Checks CR[BIT1] for existing Quad Enable status
 * 2. Sets CR[BIT1] through single-byte write
 * 3. Verifies CR value after writing
 *
 * @note Covers Quad Enable Method 6 devices where QE is controlled by CR bit 1.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Quad mode enabled and verified.
 *         - AL_SPI_NOR_SET_QUAD_MODE_6_REG_VAL_ERROR: CR value mismatch.
 *         - Other error codes from sub-operations.
 */
AL_S32 AlSpiNor_QuadEnableMode_6(AlSpiNor *SpiNor)
{
    AL_U8 Cr;
    AL_U8 Cr_Read;
    AL_S32 Status;

    Status = AlSpiNor_ReadCr(SpiNor, &Cr);
    if (Status != AL_OK) {
        return Status;
    }

    if (Cr & SR2_QUAD_EN_BIT1) {
        return AL_OK;
    }

    Status = AlSpiNor_WriteEnable(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    Cr |= SR2_QUAD_EN_BIT1;
    Status = AlSpiNor_WriteCr(SpiNor, Cr);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_WaitReady(SpiNor, 0);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_ReadCr(SpiNor, &Cr_Read);
    if (Status != AL_OK) {
        return Status;
    }

    if (Cr != Cr_Read) {
        return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_QUAD_MODE_6_REG_VAL_ERROR);
    }

    return AL_OK;
}

/**
 * This function determines the appropriate Quad Enable method based on the
 * AL_SPI_NOR_FLAG_QE_MODE_MASK flags in FlashInfo. It calls the corresponding
 * Quad Enable mode function to set the flash into quad mode.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Quad mode set successfully.
 *         - AL_SPI_NOR_SET_QUAD_MODE_ERROR: Unsupported/unknown mode requested.
 *         - Mode-specific error codes from underlying functions.
 */
AL_S32 AlSpiNor_SetQuadEnable(AlSpiNor *SpiNor)
{
    switch (SpiNor->FlashInfo->Flags & AL_SPI_NOR_FLAG_QE_MODE_MASK)
    {
    case AL_SPI_NOR_FLAG_QE_MODE0:
        return AL_OK;

    case AL_SPI_NOR_FLAG_QE_MODE1:
    case AL_SPI_NOR_FLAG_QE_MODE4:
    case AL_SPI_NOR_FLAG_QE_MODE5:
        return AlSpiNor_QuadEnableMode_1_4_5(SpiNor);

    case AL_SPI_NOR_FLAG_QE_MODE2:
        return AlSpiNor_QuadEnableMode_2(SpiNor);

    case AL_SPI_NOR_FLAG_QE_MODE3:
        return AlSpiNor_QuadEnableMode_3(SpiNor);

    case AL_SPI_NOR_FLAG_QE_MODE6:
        return AlSpiNor_QuadEnableMode_6(SpiNor);

    default:
        break;
    }

    return AL_SPI_NOR_EVENTS_TO_ERRS(AL_SPI_NOR_SET_QUAD_MODE_ERROR);
}

/**
 * This function deasserts the Write Enable Latch (WEL), preventing accidental
 * write/erase operations. Typically called after successful write/erase completion.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Command executed successfully.
 *         - Error code: If the operation fails.
 */
AL_S32 AlSpiNor_WriteDisable(AlSpiNor *SpiNor)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_WRDI, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_NO_DATA);

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * Executes a read operation using pre-configured protocol parameters (OpCode,
 * address/dummy cycles, bus width). Supports variable-length reads from any valid address.
 *
 * @param[in]  SpiNor Pointer to the AlSpiNor instance.
 * @param[in]  Addr   Starting address to read from (must be within device bounds).
 * @param[in]  Len    Number of bytes to read (non-zero, device-dependent max).
 * @param[out] Data   Buffer to store the read data (must have at least Len bytes capacity).
 * @return AL_S32 Operation status:
 *         - AL_OK: Read successful.
 *         - Error code: Controller failure or invalid parameters.
 */
AL_S32 AlSpiNor_ReadData(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len, AL_U8 *Data)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(SpiNor->RdProto.OpCode, SpiNor->RdProto.CmdWidth),
                                  SPI_MEM_OP_ADDR(SpiNor->AddrBytes, Addr, SpiNor->RdProto.AddrWidth),
                                  SPI_MEM_OP_DUMMY(SpiNor->RdProto.DummyCycles, SpiNor->RdProto.AddrWidth),
                                  SPI_MEM_OP_DATA_IN(Len, Data, SpiNor->CurBusWidth));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * Executes a page/byte program operation using pre-configured write protocol.
 * Requires explicit Write Enable (WREN) before invocation.
 *
 * @warning Ensure address + length does not cross page boundaries (device-specific behavior).
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @param[in] Addr   Starting address to write (must be erased and within device bounds).
 * @param[in] Len    Number of bytes to write (device-dependent max per operation).
 * @param[in] Data   Buffer containing data to write (must have at least Len bytes).
 * @return AL_S32 Operation status:
 *         - AL_OK: Write initiated successfully.
 *         - Error code: Controller failure or invalid parameters.
 */
AL_S32 AlSpiNor_WriteData(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len, AL_U8 *Data)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(SpiNor->WrProto.OpCode, SpiNor->WrProto.CmdWidth),
                                  SPI_MEM_OP_ADDR(SpiNor->AddrBytes, Addr, SpiNor->WrProto.AddrWidth),
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_DATA_OUT(Len, Data, SpiNor->CurBusWidth));

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * Issues a sector erase command (e.g., SE 0x20/D8) based on pre-configured erase protocol.
 * Sector size is device-dependent (typically 4KB/64KB).
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @param[in] Addr   Any address within the target sector (automatically aligned by device).
 * @return AL_S32 Operation status:
 *         - AL_OK: Erase initiated successfully.
 *         - Error code: Controller failure or address out of range.
 */
AL_S32 AlSpiNor_EraseSector(AlSpiNor *SpiNor, AL_U32 Addr)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(SpiNor->EraseProto.OpCode, SpiNor->EraseProto.CmdWidth),
                                  SPI_MEM_OP_ADDR(SpiNor->AddrBytes, Addr, SpiNor->EraseProto.AddrWidth),
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_NO_DATA);

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * Issues the Chip Erase command (0x60/0xC7), erasing all programmable memory cells.
 * Execution time is significantly longer than sector erase.
 *
 * @warning Use with extreme caution - irreversible data loss.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Erase initiated successfully.
 *         - Error code: Controller failure or device protection active.
 */
AL_S32 AlSpiNor_EraseChip(AlSpiNor *SpiNor)
{
    AlSpiMemOp MemOp = SPI_MEM_OP(SPI_MEM_OP_CMD(NOR_OP_CHIP_ERASE, 1),
                                  SPI_MEM_OP_NO_ADDR,
                                  SPI_MEM_OP_NO_DUMMY,
                                  SPI_MEM_OP_NO_DATA);

    return SpiNor->Controller->ExecOp(SpiNor->Controller, &MemOp);
}

/**
 * This function sets the current operation bus width based on the flash and controller capabilities.
 * It also attempts to enable Quad mode if applicable.
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance.
 * @return AL_S32 Operation status:
 *         - AL_OK: Operation width set successfully.
 *         - Error code: If setting Quad mode fails.
 */
AL_S32 AlSpiNor_SetOperationWidth(AlSpiNor *SpiNor)
{
    AL_S32 Status = AL_OK;

    if ((SpiNor->FlashInfo->Flags & AL_SPI_NOR_FLAG_QUAD) &&
         SpiNor->Controller->Flags & AL_SPI_CONTROLLER_QUAD) {
        SpiNor->CurBusWidth = 4;
    } else if ((SpiNor->FlashInfo->Flags & AL_SPI_NOR_FLAG_DUAL) &&
         SpiNor->Controller->Flags & AL_SPI_CONTROLLER_DUAL) {
        SpiNor->CurBusWidth = 2;
    } else {
        SpiNor->CurBusWidth = 1;
    }

    if (SpiNor->UserParams.IsForceStandardMode) {
        SpiNor->CurBusWidth = 1;
    }

    if (SpiNor->CurBusWidth == 4) {
        Status = AlSpiNor_SetQuadEnable(SpiNor);
        if (Status != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_INFO, "Set QUAD mode failed\r\n");
            return Status;
        }
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Flash is in x%d mode\r\n", SpiNor->CurBusWidth);
    return AL_OK;
}

/**
 * This function:
 * 1. Reads the 3-byte JEDEC ID from the flash device
 * 2. Searches for matching flash parameters in:
 *    - User-provided flash info list (priority)
 *    - Default system-wide flash info list
 * 3. Falls back to default x1/3-byte addressing mode if no match found
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance
 * @return AL_S32 Operation status:
 *         - AL_OK: Identification completed (matched or using defaults)
 *         - Error code: ID read failure
 */
AL_S32 AlSpiNor_Scan(AlSpiNor *SpiNor)
{
    AL_S32 Status;
    AL_U32 Index;
    AL_U8 Id[3];
    AL_U32 FlashListSize;
    const AlSpiNorInfo *FlashList;

    Status = AlSpiNor_ReadId(SpiNor, &Id[0]);
    if (Status != AL_OK) {
        return Status;
    }

    FlashList = SpiNorInfoList;
    FlashListSize = SpiNorInfoListSize;
    if (SpiNor->UserParams.UserFlashInfoList != AL_NULL &&
        SpiNor->UserParams.UserFlashInfoListSize != 0) {
        FlashList = SpiNor->UserParams.UserFlashInfoList;
        FlashListSize = SpiNor->UserParams.UserFlashInfoListSize;
        AL_LOG(AL_LOG_LEVEL_INFO, "Use flash list from user\r\n");
    }

    SpiNor->FlashInfo = AL_NULL;
    while (1) {
        for (Index = 0; Index < FlashListSize; Index++) {
            if (Id[0] == FlashList[Index].Id[0] &&
                Id[1] == FlashList[Index].Id[1] &&
                Id[2] == FlashList[Index].Id[2]) {
                SpiNor->FlashInfo = &FlashList[Index];
            }
        }

        if (SpiNor->FlashInfo == AL_NULL &&
            FlashList == SpiNor->UserParams.UserFlashInfoList) {
            FlashList = SpiNorInfoList;
            FlashListSize = SpiNorInfoListSize;
            AL_LOG(AL_LOG_LEVEL_WARNING, "No matching flash info, try normal process\r\n");
        } else {
            break;
        }
    }

    if (SpiNor->FlashInfo == AL_NULL) {
        SpiNor->FlashInfo = &SpiNorDefaultInfo;
        AL_LOG(AL_LOG_LEVEL_WARNING,
            "Unknow flash id: %02x%02x%02x, try default(x1 and 3byte) operations\r\n",
            Id[0], Id[1], Id[2]);
        return AL_OK;
    }

    return AL_OK;
}

/**
 * Implements segmented reads to handle large transfers. Segment size depends on:
 * - 4032-byte chunks when using AHB DMA (QSPI_USE_AHB_DMA defined)
 * - 65532-byte chunks otherwise (64KB - 4 bytes)
 *
 * @param[in]  SpiNor Pointer to the AlSpiNor instance
 * @param[in]  Addr   Starting read address (aligned to device boundaries)
 * @param[in]  Len    Number of bytes to read (non-zero)
 * @param[out] Data   Read data buffer (minimum Len bytes capacity)
 * @return AL_S32 Operation status:
 *         - AL_OK: Full read completed successfully
 *         - AL_SPI_NOR_ERR_ILLEGAL_PARAM: Invalid address/length or NULL pointers
 *         - Error codes from underlying read operations
 */
AL_S32 AlSpiNor_Read(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len, AL_U8 *Data)
{
    AL_S32 Status;
    AL_U32 CurAddr;
    AL_U32 CurLen;
    AL_U32 WriteCount;

    if (!SpiNor || (Addr + Len > SpiNor->DeviceSize)) {
        return AL_SPI_NOR_ERR_ILLEGAL_PARAM;
    }

#ifdef QSPI_USE_AHB_DMA
    AL_U32 ReadStep = 4032;
#else
    AL_U32 ReadStep = 64 * 1024 - 4;
#endif

    WriteCount = 0;
    while (WriteCount < Len) {

        CurAddr = Addr + WriteCount;
        CurLen = (Len - WriteCount) > ReadStep ? ReadStep : (Len - WriteCount);
        Status = AlSpiNor_ReadData(SpiNor, CurAddr, CurLen, Data + WriteCount);
        if (Status != AL_OK) {
            return Status;
        }

        WriteCount += CurLen;
    }

    return AL_OK;
}

/**
 * Implements page-aware writes with:
 * - Automatic write enable management
 * - Page boundary alignment enforcement
 * - Status polling between writes
 *
 * @warning Requires pre-erased target sectors/pages
 *
 * @param[in] SpiNor Pointer to the AlSpiNor instance
 * @param[in] Addr   Starting write address (must be erased)
 * @param[in] Len    Number of bytes to write (non-zero)
 * @param[in] Data   Data buffer to write (minimum Len bytes)
 * @return AL_S32 Operation status:
 *         - AL_OK: Full write completed successfully
 *         - AL_SPI_NOR_ERR_ILLEGAL_PARAM: Invalid address/length or NULL pointers
 *         - Error codes from write enable/data/wait operations
 */
AL_S32 AlSpiNor_Write(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len, AL_U8 *Data)
{
    AL_S32 Status;
    AL_U32 CurAddr;
    AL_U32 CurLen;
    AL_U32 WriteCount = 0;
    AL_U32 PageSize = 0;

    if (!SpiNor || (Addr + Len > SpiNor->DeviceSize)) {
        return AL_SPI_NOR_ERR_ILLEGAL_PARAM;
    }

    PageSize = SpiNor->FlashInfo->PageSize;

    while (WriteCount < Len) {
        CurAddr = Addr + WriteCount;
        CurLen = PageSize - (CurAddr & (PageSize - 1));
        CurLen = (CurLen > (Len - WriteCount)) ? (Len - WriteCount) : CurLen;

        Status = AlSpiNor_WriteEnable(SpiNor);
        if (Status != AL_OK) {
            return Status;
        }

        Status = AlSpiNor_WriteData(SpiNor, CurAddr, CurLen, Data + WriteCount);
        if (Status != AL_OK) {
            return Status;
        }

        Status = AlSpiNor_WaitReady(SpiNor, 0);
        if (Status != AL_OK) {
            return Status;
        }

        WriteCount += CurLen;
    }

    return AL_OK;
}

/**
 * This function performs a bulk erase operation on the specified address range.
 * It supports both full chip erase and sector-wise erasure based on the provided length.
 *
 * @param SpiNor: The spi-nor device.
 * @param Addr: The starting address for the erase operation.
 * @param Len: The length of the area to be erased.
 * @return AL_S32: Operation status:
 *         - AL_OK: Erase completed successfully.
 *         - AL_SPI_NOR_ERR_ILLEGAL_PARAM: Invalid parameters (e.g., out of bounds).
 *         - Other error codes from underlying operations.
 */
AL_S32 AlSpiNor_Erase(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len)
{
    AL_S32 Status;
    AL_U32 EraseCount = 0;

    if (!SpiNor || (Addr + Len > SpiNor->DeviceSize) ||
        (Addr % SpiNor->EraseSize) || (Len % SpiNor->EraseSize)) {
        return AL_SPI_NOR_ERR_ILLEGAL_PARAM;
    }

    if (Len == SpiNor->DeviceSize) {
        Status = AlSpiNor_WriteEnable(SpiNor);
        if (Status != AL_OK) {
            return Status;
        }

        Status = AlSpiNor_EraseChip(SpiNor);
        if (Status != AL_OK) {
            return Status;
        }

        Status = AlSpiNor_WaitReady(SpiNor, 10);
        if (Status != AL_OK) {
            return Status;
        }

    } else {
        while (EraseCount < Len)
        {
            Status = AlSpiNor_WriteEnable(SpiNor);
            if (Status != AL_OK) {
                return Status;
            }

            Status = AlSpiNor_EraseSector(SpiNor, Addr + EraseCount);
            if (Status != AL_OK) {
                return Status;
            }

            Status = AlSpiNor_WaitReady(SpiNor, 1);
            if (Status != AL_OK) {
                return Status;
            }

            EraseCount += SpiNor->EraseSize;
        }
    }

    Status = AlSpiNor_WriteDisable(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    return AL_OK;
}

/**
 * @brief Initialize the selected controller and the flash device.
 * @param SpiNor: The spi-nor device.
 * @param ControllerType: The type of the controller. 0: PS QSPI, 1: PS SPI, 2: PL QSPI.
 * @param DevId: Refers to the specific controller of a certain type.
 *
 * @note Get the ControllerType and DevId information in al_spi_controller.c
 */
AL_S32 AlSpiNor_Init(AlSpiNor *SpiNor, AL_U32 ControllerType, AL_U32 DevId)
{
    AL_U32 Index = 0;
    AL_S32 Status;

    if (SpiNor == AL_NULL) {
        return AL_SPI_NOR_ERR_ILLEGAL_PARAM;
    }

    for (Index = 0; Index < SpiControllerListSize; Index++) {
        if (ControllerType == SpiControllerList[Index].ControllerType &&
            DevId == SpiControllerList[Index].DevId) {
            SpiNor->Controller = &SpiControllerList[Index];
            break;
        }
    }

    if (SpiNor->Controller == AL_NULL) {
        return AL_SPI_NOR_ERR_NOT_SUPPORT;
    }

    Status = SpiNor->Controller->Init(SpiNor->Controller);
    if (Status != AL_OK) {
        return Status;
    }

    Status = AlSpiNor_Scan(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Flash model: %s\r\n", SpiNor->FlashInfo->Name);

    SpiNor->DeviceSize = SpiNor->FlashInfo->SectorSize * SpiNor->FlashInfo->SectorNum;
    SpiNor->AddrBytes = (SpiNor->DeviceSize > 0x1000000) ? 4 : 3;
    SpiNor->EraseSize = SpiNor->FlashInfo->SectorSize;

    Status = AlSpiNor_SetOperationWidth(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    if (SpiNor->Controller->Flags & AL_SPI_NOR_FLAG_4BYTE_SET) {
        ; /* Program configuration register to set the flash into 4byte mode. */
    }

    Status = AlSpiNor_SetProto(SpiNor);
    if (Status != AL_OK) {
        return Status;
    }

    SpiNor->SetWrap64 = (SpiNorSetWrap64)AlSpiNor_SetWrap64;

#ifdef DEBUG_SPI_NOR
    AL_LOG(AL_LOG_LEVEL_INFO,
        "Spi-nor debug info:\r\n"
        "  Cur buswidth: %d\r\n"
        "  Addr bytes: %d\r\n"
        "  Read opcode: %02xh\r\n"
        "  Write opcode: %02xh\r\n"
        "  Erase opcode: %02xh\r\n",
        SpiNor->CurBusWidth, SpiNor->AddrBytes,
        SpiNor->RdProto.OpCode, SpiNor->WrProto.OpCode, SpiNor->EraseProto.OpCode);
#endif

    return AL_OK;
}

