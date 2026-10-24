#ifndef __AL_SPI_NOR_H__
#define __AL_SPI_NOR_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "al_type.h"
#include "al_spi_mem.h"
#include "al_spi_controller.h"

#ifndef BIT
#define BIT(nr)        (1UL << (nr))
#endif

#define AL_SPI_NOR_FLAG_4BYTE_ADDR        BIT(0)
#define AL_SPI_NOR_FLAG_4BYTE_SET         BIT(1)
#define AL_SPI_NOR_FLAG_DUAL              BIT(2)
#define AL_SPI_NOR_FLAG_QUAD              BIT(3)
#define AL_SPI_NOR_FLAG_QE_MODE_SHIFT     4
#define AL_SPI_NOR_FLAG_QE_MODE0          (0x0 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE1          (0x1 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE2          (0x2 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE3          (0x3 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE4          (0x4 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE5          (0x5 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE6          (0x6 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE7          (0x7 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_QE_MODE_MASK      (0x7 << AL_SPI_NOR_FLAG_QE_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_WRAP_MODE_SHIFT   7
#define AL_SPI_NOR_FLAG_WRAP_MODE0        (0x0 << AL_SPI_NOR_FLAG_WRAP_MODE_SHIFT) /* Not support WRAP */
#define AL_SPI_NOR_FLAG_WRAP_MODE1        (0x1 << AL_SPI_NOR_FLAG_WRAP_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_WRAP_MODE2        (0x2 << AL_SPI_NOR_FLAG_WRAP_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_WRAP_MODE3        (0x3 << AL_SPI_NOR_FLAG_WRAP_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_WRAP_MODE4        (0x4 << AL_SPI_NOR_FLAG_WRAP_MODE_SHIFT)
#define AL_SPI_NOR_FLAG_WRAP_MODE_MASK    (0xF << AL_SPI_NOR_FLAG_WRAP_MODE_SHIFT)


/*
 * Note on opcode nomenclature: some opcodes have a format like
 * SPINOR_OP_FUNCTION{4,}_x_y_z. The numbers x, y, and z stand for the number
 * of I/O lines used for the opcode, address, and data (respectively). The
 * FUNCTION has an optional suffix of '4', to represent an opcode which
 * requires a 4-byte (32-bit) address.
 */

/* Flash opcodes. */
#define NOR_OP_WREN                    0x06    /* Write enable */
#define NOR_OP_RDSR                    0x05    /* Read status register */
#define NOR_OP_WRSR                    0x01    /* Write status register 1 byte */
#define NOR_OP_RDSR2                   0x3f    /* Read status register 2 */
#define NOR_OP_WRSR2                   0x3e    /* Write status register 2 */
#define NOR_OP_WRSR2_GIGADEVICE        0x31    /* Write status register 2 */
#define NOR_OP_READ                    0x03    /* Read data bytes (low frequency) */
#define NOR_OP_READ_FAST               0x0b    /* Read data bytes (high frequency) */
#define NOR_OP_READ_1_1_2              0x3b    /* Read data bytes (Dual Output SPI) */
#define NOR_OP_READ_1_2_2              0xbb    /* Read data bytes (Dual I/O SPI) */
#define NOR_OP_READ_1_1_4              0x6b    /* Read data bytes (Quad Output SPI) */
#define NOR_OP_READ_1_4_4              0xeb    /* Read data bytes (Quad I/O SPI) */
#define NOR_OP_READ_1_1_8              0x8b    /* Read data bytes (Octal Output SPI) */
#define NOR_OP_READ_1_8_8              0xcb    /* Read data bytes (Octal I/O SPI) */
#define NOR_OP_PP                      0x02    /* Page program (up to 256 bytes) */
#define NOR_OP_PP_1_1_4                0x32    /* Quad page program */
#define NOR_OP_PP_1_4_4                0x38    /* Quad page program */
#define NOR_OP_PP_1_1_8                0x82    /* Octal page program */
#define NOR_OP_PP_1_8_8                0xc2    /* Octal page program */
#define NOR_OP_BE_4K                   0x20    /* Erase 4KiB block */
#define NOR_OP_BE_4K_PMC               0xd7    /* Erase 4KiB block on PMC chips */
#define NOR_OP_BE_32K                  0x52    /* Erase 32KiB block */
#define NOR_OP_CHIP_ERASE              0xc7    /* Erase whole flash chip */
#define NOR_OP_SE                      0xd8    /* Sector erase (usually 64KiB) */
#define NOR_OP_RDID                    0x9f    /* Read JEDEC ID */
#define NOR_OP_RDSFDP                  0x5a    /* Read SFDP */
#define NOR_OP_RDCR                    0x35    /* Read configuration register */
#define NOR_OP_RDFSR                   0x70    /* Read flag status register */
#define NOR_OP_CLFSR                   0x50    /* Clear flag status register */
#define NOR_OP_RDEAR                   0xc8    /* Read Extended Address Register */
#define NOR_OP_WREAR                   0xc5    /* Write Extended Address Register */
#define NOR_OP_INFINEON_SRST           0xf0    /* Infineon Software Reset */
#define NOR_OP_SRSTEN                  0x66    /* Software Reset Enable */
#define NOR_OP_SRST                    0x99    /* Software Reset */

/* 4-byte address opcodes - used on Spansion and some Macronix flashes. */
#define NOR_OP_READ_4B                 0x13    /* Read data bytes (low frequency) */
#define NOR_OP_READ_FAST_4B            0x0c    /* Read data bytes (high frequency) */
#define NOR_OP_READ_1_1_2_4B           0x3c    /* Read data bytes (Dual Output SPI) */
#define NOR_OP_READ_1_2_2_4B           0xbc    /* Read data bytes (Dual I/O SPI) */
#define NOR_OP_READ_1_1_4_4B           0x6c    /* Read data bytes (Quad Output SPI) */
#define NOR_OP_READ_1_4_4_4B           0xec    /* Read data bytes (Quad I/O SPI) */
#define NOR_OP_READ_1_1_8_4B           0x7c    /* Read data bytes (Octal Output SPI) */
#define NOR_OP_READ_1_8_8_4B           0xcc    /* Read data bytes (Octal I/O SPI) */
#define NOR_OP_PP_4B                   0x12    /* Page program (up to 256 bytes) */
#define NOR_OP_PP_1_1_4_4B             0x34    /* Quad page program */
#define NOR_OP_PP_1_4_4_4B             0x3e    /* Quad page program */
#define NOR_OP_PP_1_1_8_4B             0x84    /* Octal page program */
#define NOR_OP_PP_1_8_8_4B             0x8e    /* Octal page program */
#define NOR_OP_BE_4K_4B                0x21    /* Erase 4KiB block */
#define NOR_OP_BE_32K_4B               0x5c    /* Erase 32KiB block */
#define NOR_OP_SE_4B                   0xdc    /* Sector erase (usually 64KiB), 256KiB for S25FL512S */
#define NOR_OP_CE                      0x60    /* Chip Erase */

/* Double Transfer Rate opcodes - defined in JEDEC JESD216B. */
#define NOR_OP_READ_1_1_1_DTR          0x0d
#define NOR_OP_READ_1_2_2_DTR          0xbd
#define NOR_OP_READ_1_4_4_DTR          0xed

#define NOR_OP_READ_1_1_1_DTR_4B       0x0e
#define NOR_OP_READ_1_2_2_DTR_4B       0xbe
#define NOR_OP_READ_1_4_4_DTR_4B       0xee

/* Used for SST flashes only. */
#define NOR_OP_BP                      0x02    /* Byte program */
#define NOR_OP_WRDI                    0x04    /* Write disable */
#define NOR_OP_AAI_WP                  0xad    /* Auto address increment word program */

/* Used for SST26* flashes only. */
#define NOR_OP_READ_BPR                0x72    /* Read block protection register */
#define NOR_OP_WRITE_BPR               0x42    /* Write block protection register */

/* Used for S3AN flashes only */
#define NOR_OP_XSE                     0x50    /* Sector erase */
#define NOR_OP_XPP                     0x82    /* Page program */
#define NOR_OP_XRDSR                   0xd7    /* Read status register */

/* Used for Macronix and Winbond flashes. */
#define NOR_OP_EN4B                    0xb7    /* Enter 4-byte mode */
#define NOR_OP_EX4B                    0xe9    /* Exit 4-byte mode */

/* Used for Spansion flashes only. */
#define NOR_OP_BRWR                    0x17    /* Bank register write */
#define NOR_OP_BRRD                    0x16    /* Bank register read */
#define NOR_OP_CLSR                    0x30    /* Clear status register 1 */

/* Used for Micron flashes only. */
#define NOR_OP_RD_EVCR                 0x65    /* Read EVCR register */
#define NOR_OP_WD_EVCR                 0x61    /* Write EVCR register */

/* Set Burst/Wrap Length */
#define NOR_OP_SBL_MODE1               0x77    /* Set Burst/Wrap Length Mode 1 */

/* Status Register bits. */
#define SR_WIP                            BIT(0)    /* Write in progress */
#define SR_WEL                            BIT(1)    /* Write enable latch */
/* meaning of other SR_* bits may differ between vendors */
#define SR_BP0                            BIT(2)    /* Block protect 0 */
#define SR_BP1                            BIT(3)    /* Block protect 1 */
#define SR_BP2                            BIT(4)    /* Block protect 2 */
#define SR_BP3                            BIT(5)    /* Block protect 3 */
#define SR_TB_BIT5                        BIT(5)    /* Top/Bottom protect */
#define SR_BP3_BIT6                       BIT(6)    /* Block protect 3 */
#define SR_TB_BIT6                        BIT(6)    /* Top/Bottom protect */
#define SR_SRWD                           BIT(7)    /* SR write protect */
/* Spansion/Cypress specific status bits */
#define SR_E_ERR                          BIT(5)
#define SR_P_ERR                          BIT(6)

#define SR1_QUAD_EN_BIT6                  BIT(6)

#define SR_BP_SHIFT                       2

/* Enhanced Volatile Configuration Register bits */
#define EVCR_QUAD_EN_MICRON               BIT(7)    /* Micron Quad I/O */

/* Status Register 2 bits. */
#define SR2_QUAD_EN_BIT1                  BIT(1)
#define SR2_LB1                           BIT(3)    /* Security Register Lock Bit 1 */
#define SR2_LB2                           BIT(4)    /* Security Register Lock Bit 2 */
#define SR2_LB3                           BIT(5)    /* Security Register Lock Bit 3 */
#define SR2_QUAD_EN_BIT7                  BIT(7)



#define AL_SPI_NOR_SET_READ_PROTO_ERROR                      BIT(0)
#define AL_SPI_NOR_SET_WRITE_PROTO_ERROR                     BIT(1)
#define AL_SPI_NOR_SET_ERASE_PROTO_ERROR                     BIT(2)
#define AL_SPI_NOR_SET_WRAP64_MODE2_REG_VAL_ERROR            BIT(3)
#define AL_SPI_NOR_SET_WRAP64_MODE3_REG_VAL_ERROR            BIT(4)
#define AL_SPI_NOR_SET_WRAP64_MODE_ERROR                     BIT(5)
#define AL_SPI_NOR_SET_QUAD_MODE_1_4_5_REG_VAL_ERROR         BIT(6)
#define AL_SPI_NOR_SET_QUAD_MODE_2_REG_VAL_ERROR             BIT(7)
#define AL_SPI_NOR_SET_QUAD_MODE_3_REG_VAL_ERROR             BIT(8)
#define AL_SPI_NOR_SET_QUAD_MODE_6_REG_VAL_ERROR             BIT(9)
#define AL_SPI_NOR_SET_QUAD_MODE_ERROR                       BIT(10)
#define AL_SPI_CONTROLLER_FRAME_FORMAT_ERROR                 BIT(11)

#define AL_SPI_NOR_ERR_ILLEGAL_PARAM        AL_DEF_ERR(AL_SPINOR, AL_LOG_LEVEL_ERROR, AL_ERR_ILLEGAL_PARAM)
#define AL_SPI_NOR_ERR_BUSY                 AL_DEF_ERR(AL_SPINOR, AL_LOG_LEVEL_ERROR, AL_ERR_BUSY)
#define AL_SPI_NOR_ERR_TIMEOUT              AL_DEF_ERR(AL_SPINOR, AL_LOG_LEVEL_ERROR, AL_ERR_TIMEOUT)
#define AL_SPI_NOR_ERR_NOT_SUPPORT          AL_DEF_ERR(AL_SPINOR, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_SUPPORT)
#define AL_SPI_NOR_ERR_NOT_READY            AL_DEF_ERR(AL_SPINOR, AL_LOG_LEVEL_ERROR, AL_ERR_NOT_READY)
#define AL_SPI_NOR_EVENTS_TO_ERRS(Event)    AL_DEF_ERR(AL_SPINOR, AL_LOG_LEVEL_ERROR, (Event << AL_ERR_MAX))


typedef struct {
    const char *Name;
    AL_U8 Id[3];
    AL_U32 SectorSize;
    AL_U32 SectorNum;
    AL_U16 PageSize;
    AL_U8 ModeBits;
    AL_U8 ModeBitsMask;
    AL_U32 Flags;
} AlSpiNorInfo;

typedef struct {
    AL_U8 OpCode;
    AL_U8 DummyCycles;
    AL_U8 CmdWidth;
    AL_U8 AddrWidth;
} AlSpiProtocol;

typedef struct {
    AL_U32 IsForceStandardMode;              /* 1: force x1 mode, 0: default */

#ifdef AL_SPI_NOR_SUPPORT_DUAL_STACK
    AL_U32 IsDualStack;                      /* 1: dual stack, 0: default. To be realized. */
#endif

    const AlSpiNorInfo *UserFlashInfoList;   /* If the flash model is not in the default
                                                flash info list, user can use their own flash
                                                info list */
    AL_U32 UserFlashInfoListSize;            /* Size of UserFlashInfoList */
} AlSpiNorUserParams;

typedef AL_S32 (*SpiNorSetWrap64)(AL_VOID *);

/**
 * @brief The main structure for the SPI-NOR driver
 * @note When defining a new structure variable, initialize it to a definite value
 */
typedef struct {
    const AlSpiNorInfo *FlashInfo;
    AlSpiController *Controller;

    AlSpiNorUserParams UserParams;

    AL_U32 DeviceSize;
    AL_U32 EraseSize;
    AL_U8 CurBusWidth;
    AL_U8 AddrBytes;

    AlSpiProtocol RdProto;
    AlSpiProtocol WrProto;
    AlSpiProtocol EraseProto;

    SpiNorSetWrap64 SetWrap64;
} AlSpiNor;

AL_S32 AlSpiNor_Init(AlSpiNor *SpiNor, AL_U32 ControllerType, AL_U32 DevId);
AL_S32 AlSpiNor_Read(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len, AL_U8 *Data);
AL_S32 AlSpiNor_Write(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len, AL_U8 *Data);
AL_S32 AlSpiNor_Erase(AlSpiNor *SpiNor, AL_U32 Addr, AL_U32 Len);

#ifdef HAVE_QSPIPS_DRIVER
AL_S32 AlSpiController_PsQspiInit(AlSpiController *Controller);
AL_S32 AlSpiController_PsQspiExecOp(AlSpiController *Controller, const AlSpiMemOp *Op);

#endif

#ifdef HAVE_SPIPS_DRIVER
AL_S32 AlSpiController_PsSpiInit(AlSpiController *Controller);
AL_S32 AlSpiController_PsSpiExecOp(AlSpiController *Controller, const AlSpiMemOp *Op);
#endif

#if AL_AXI_QSPI_NUM_INSTANCE >= 1
AL_S32 AlSpiController_PlQspiInit(AlSpiController *Controller);
AL_S32 AlSpiController_PlQspiExecOp(AlSpiController *Controller, const AlSpiMemOp *Op);
#endif


#ifdef __cplusplus
}
#endif

#endif /* __AL_SPI_NOR_H__ */
