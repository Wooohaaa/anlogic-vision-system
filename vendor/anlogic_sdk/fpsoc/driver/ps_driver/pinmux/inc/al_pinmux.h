/*
 * Copyright (c) 2026, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_PINMUX_H_
#define __AL_PINMUX_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_type.h"
#include "al_core.h"
#include "al_chip.h"

/* Offset of each config item within BASEADDR */
#define AL_PINCTRL_FUNCSEL_OFFSET      (0x000UL)
#define AL_PINCTRL_EMIOSEL_OFFSET      (0x400UL)
#define AL_PINCTRL_PAD0_CTL_OFFSET     (0x800UL)
#define AL_PINCTRL_PAD1_CTL_OFFSET     (0x804UL)

#define AL_PINCTRL_EMIOSEL_STRIDE       0x4
#define AL_PINCTRL_FUNCSEL_STRIDE       0x4
#define AL_PINCTRL_PADxCTL_STRIDE       0x8


#ifndef AL_PINCTRL_PIN_BASE
#error "AL_PINCTRL_PIN_BASE(pin) must be defined in the chip-specific al_chip.h"
#endif

/* Per-pin register addresses (FUNCSEL / PAD0 / PAD1 = absolute pin number + that pin's base address) */
#define AL_PINCTRL_MIO_FUNCSEL_ADDR(pin)   \
    (AL_PINCTRL_PIN_BASE(pin) + AL_PINCTRL_FUNCSEL_OFFSET + (pin)  * AL_PINCTRL_FUNCSEL_STRIDE)
#define AL_PINCTRL_MIO_PAD0_CTL_ADDR(pin)  \
    (AL_PINCTRL_PIN_BASE(pin) + AL_PINCTRL_PAD0_CTL_OFFSET + (pin) * AL_PINCTRL_PADxCTL_STRIDE)
#define AL_PINCTRL_MIO_PAD1_CTL_ADDR(pin)  \
    (AL_PINCTRL_PIN_BASE(pin) + AL_PINCTRL_PAD1_CTL_OFFSET + (pin) * AL_PINCTRL_PADxCTL_STRIDE)

#define AL_PINCTRL_MIO_EMIOSEL_BASE    (AL_PINCTRL_EMIO_SELECT_BASE + AL_PINCTRL_EMIOSEL_OFFSET)

/****************************** PAD_CTL_0 Register *****************************/
#define AL_PINCTRL_PADCTL_SPEED_SHIFT          0
#define AL_PINCTRL_PADCTL_SPEED_MASK           3

/* reserved bit3~bit23*/

#define AL_PINCTRL_PADCTL_HYSTERESIS_SHIFT     24
#define AL_PINCTRL_PADCTL_RESERVED_MASK        4

#define AL_PINCTRL_PADCTL_PULLDOWN_OHM_SHIFT   28
#define AL_PINCTRL_PADCTL_PULLUP_OHM_SHIFT     29
#define AL_PINCTRL_PADCTL_PULLDOWN_EN_SHIFT    30
#define AL_PINCTRL_PADCTL_PULLUP_EN_SHIFT      31

/****************************** PAD_CTL_1 Register *****************************/
#define AL_PINCTRL_PADCTL_RECV_MODE_SHIFT      0
#define AL_PINCTRL_PADCTL_RECV_MODE_MASK       2

/* reserved bit2~bit7*/

#define AL_PINCTRL_PADCTL_PULL_UP_DRV_SHIFT    8
#define AL_PINCTRL_PADCTL_PULL_UP_DRV_MASK     5

#define AL_PINCTRL_PADCTL_INPUT_THRE_SHIFT     13

/* reserved bit14~bit15*/

#define AL_PINCTRL_PADCTL_PULL_DOWN_DRV_SHIFT  16
#define AL_PINCTRL_PADCTL_PULL_DOWN_DRV_MASK    5

/* reserved bit21~bit31*/

// ************************ EMIO support macro definitions ************************
#define AL_PINCTRL_EMIO_BIT        31U  // EMIO support bit:     Bit31
#define AL_PINCTRL_GROUP_BIT       8U   // Group field start:    Bit8
#define AL_PINCTRL_FUNC_BIT        0U   // FuncSel field start:  Bit0

#define AL_PINCTRL_EMIO_MASK       (1U << AL_PINCTRL_EMIO_BIT)     // EMIO support bit mask: 0x80000000
#define AL_PINCTRL_GROUP_MASK      (0xFFU << AL_PINCTRL_GROUP_BIT) // Group field mask:      0x0000FF00
#define AL_PINCTRL_FUNC_MASK       (0xFFU << AL_PINCTRL_FUNC_BIT)  // FuncSel field mask:    0x000000FF

#define AL_PINCTRL_GET_EMIO_SUPPORT(func_packed)  \
    (((func_packed) & AL_PINCTRL_EMIO_MASK) >> AL_PINCTRL_EMIO_BIT) // Shift right 31 bits, get 0/1 directly

#define AL_PINCTRL_GET_GROUP(func_packed)  \
    (((func_packed) & AL_PINCTRL_GROUP_MASK) >> AL_PINCTRL_GROUP_BIT) // Mask then shift right 8 bits, get raw group value

#define AL_PINCTRL_GET_FUNCSEL(func_packed)  \
    (((func_packed) & AL_PINCTRL_FUNC_MASK) >> AL_PINCTRL_FUNC_BIT)  // Mask then shift right 0 bits, get raw FuncSel value

typedef enum {
    AL_PINCTRL_EMIO_NOT_SUPPORT = 0,  // EMIO not supported
    AL_PINCTRL_EMIO_SUPPORT     = 1   // EMIO supported
} AlPinctrl_EmioSupportEnum;

#define EMIO_SUPPORT     AL_PINCTRL_EMIO_SUPPORT
#define EMIO_NOT_SUPPORT AL_PINCTRL_EMIO_NOT_SUPPORT

/****************************** PAD_CTL_0 Enums *****************************/
typedef enum {
    AL_PINCTRL_SPEED_SLOW = 0,
    AL_PINCTRL_SPEED_MEDIUM = 2,
    AL_PINCTRL_SPEED_FAST = 7
} AlPinctrl_SpeedEnum;


typedef enum {
    AL_PINCTRL_PULL_DISABLE = 0,
    AL_PINCTRL_PULL_UP = 1,
    AL_PINCTRL_PULL_DOWN = 2
} AlPinctrl_PullEnum;


typedef enum {
    AL_PINCTRL_RESISTOR_25K = 0,
    AL_PINCTRL_RESISTOR_10K = 1
} AlPinctrl_ResistorEnum;


/****************************** PAD_CTL_1 Enums *****************************/
typedef enum {
    MIO_RECV_DISABLED     = 0x0, /**< Receiver disabled */
    MIO_RECV_DIFFERENTIAL = 0x1, /**< Differential mode */
    MIO_RECV_1V8_OR_1V5   = 0x2, /**< 1.8V or 1.5V level */
    MIO_RECV_3V3_OR_2V5   = 0x3  /**< 3.3V or 2.5V level */
} AlPinctrl_RecvModeEnum;


typedef enum {
    MIO_VOLTAGE_3V3 = 0x0,
    MIO_VOLTAGE_2V5 = 0x1,
    MIO_VOLTAGE_1V8 = 0x2,
    MIO_VOLTAGE_1V5 = 0x3
} AlPinctrl_VoltageEnum;


typedef enum {
    MIO_DRIVE_4MA  = 0x0,
    MIO_DRIVE_8MA  = 0x1,
    MIO_DRIVE_12MA = 0x2,
    MIO_DRIVE_16MA = 0x3,
    MIO_DRIVE_20MA = 0x4
} AlPinctrl_DriveEnum;

typedef enum {
    FuncSel_0   = 0,
    FuncSel_1   = 1,
    FuncSel_2   = 2,
    FuncSel_3   = 3,
    FuncSel_4   = 4,
    FuncSel_5   = 5,
    FuncSel_6   = 6,
    FuncSel_7   = 7,
    FuncSel_8   = 8,
    FuncSel_9   = 9,
    FuncSel_10  = 10,
    FuncSel_11  = 11,
    FuncSel_12  = 12,
    FuncSel_13  = 13,
    FuncSel_14  = 14,
    FuncSel_15  = 15
} AlPinctrl_FuncSel;


typedef enum {
    AL_PINCTRL_SEL_EMIO = 0,
    AL_PINCTRL_SEL_MIO  = 1
} AlPinctrl_EmioSelEnum;


typedef enum {
    AL_PINCTRL_GROUP_I2C0    = 0,
    AL_PINCTRL_GROUP_I2C1    = 1,
    AL_PINCTRL_GROUP_CAN0    = 2,
    AL_PINCTRL_GROUP_CAN1    = 3,
    AL_PINCTRL_GROUP_UART0   = 4,
    AL_PINCTRL_GROUP_UART1   = 5,
    AL_PINCTRL_GROUP_TTC0    = 6,
    AL_PINCTRL_GROUP_TTC1    = 7,
    AL_PINCTRL_GROUP_WDT     = 8,
    AL_PINCTRL_GROUP_SPI0    = 9,
    AL_PINCTRL_GROUP_SPI1    = 10,
    AL_PINCTRL_GROUP_SDIO0   = 11,
    AL_PINCTRL_GROUP_SDIO1   = 12,
    AL_PINCTRL_GROUP_MDIO0   = 13,
    AL_PINCTRL_GROUP_MDIO1   = 14,
    AL_PINCTRL_GROUP_MAX
} AlPinctrl_GroupEnum;


// function 0: iic
#define FUNC0_IIC0_SCL         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_I2C0 << 8)  |  FuncSel_0)
#define FUNC0_IIC0_SDA         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_I2C0 << 8)  |  FuncSel_0)
#define FUNC0_IIC1_SCL         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_I2C1 << 8)  |  FuncSel_0)
#define FUNC0_IIC1_SDA         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_I2C1 << 8)  |  FuncSel_0)

// function 1: can, qspi
#define FUNC1_CAN0_TX          ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_CAN0 << 8)  |  FuncSel_1)
#define FUNC1_CAN0_RX          ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_CAN0 << 8)  |  FuncSel_1)
#define FUNC1_CAN1_TX          ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_CAN1 << 8)  |  FuncSel_1)
#define FUNC1_CAN1_RX          ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_CAN1 << 8)  |  FuncSel_1)

#define FUNC1_QSPI_SS          ((EMIO_NOT_SUPPORT << 31)  | FuncSel_1)
#define FUNC1_QSPI_CLK         ((EMIO_NOT_SUPPORT << 31)  | FuncSel_1)
#define FUNC1_QSPI_DATA0       ((EMIO_NOT_SUPPORT << 31)  | FuncSel_1)
#define FUNC1_QSPI_DATA1       ((EMIO_NOT_SUPPORT << 31)  | FuncSel_1)
#define FUNC1_QSPI_DATA2       ((EMIO_NOT_SUPPORT << 31)  | FuncSel_1)
#define FUNC1_QSPI_DATA3       ((EMIO_NOT_SUPPORT << 31)  | FuncSel_1)

// function 2: nand, sdio
#define FUNC2_NAND             ((EMIO_NOT_SUPPORT << 31)  | FuncSel_2)
#define FUNC2_SD1_WP           ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SDIO1 << 8)  |  FuncSel_2)
#define FUNC2_SD0_PWR          ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_2)

// function 3: uart
#define FUNC3_UART0_TX         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_UART0 << 8)  |  FuncSel_3)
#define FUNC3_UART0_RX         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_UART0 << 8)  |  FuncSel_3)
#define FUNC3_UART1_TX         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_UART1 << 8)  |  FuncSel_3)
#define FUNC3_UART1_RX         ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_UART1 << 8)  |  FuncSel_3)

// function 4: gpio
#define FUNC4_GPIO             ((EMIO_NOT_SUPPORT << 31)  | FuncSel_4)

// function 5: can clk
#define FUNC5_CAN0_CLK         ((EMIO_NOT_SUPPORT << 31)  | FuncSel_5)

// function 6: can clk
#define FUNC6_CAN1_CLK         ((EMIO_NOT_SUPPORT << 31)  | FuncSel_6)

// function 7: ttc, sdio_pwr
#define FUNC7_SD1_PWR     ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SDIO1 << 8)  |  FuncSel_7)
#define FUNC7_SD0_PWR     ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_7)
#define FUNC7_TTC0_CLK    ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_TTC0 << 8)   |  FuncSel_7)
#define FUNC7_TTC0_WAVE   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_TTC0 << 8)   |  FuncSel_7)
#define FUNC7_TTC1_CLK    ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_TTC1 << 8)   |  FuncSel_7)
#define FUNC7_TTC1_WAVE   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_TTC1 << 8)   |  FuncSel_7)

// function 8: sdio_wp
#define FUNC8_SD0_WP      ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_8)

// function 9: spi
#define FUNC9_SPI0_MOSI   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI0 << 8)  |  FuncSel_9)
#define FUNC9_SPI0_MISO   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI0 << 8)  |  FuncSel_9)
#define FUNC9_SPI0_SCLK   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI0 << 8)  |  FuncSel_9)
#define FUNC9_SPI0_SEL0   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI0 << 8)  |  FuncSel_9)
#define FUNC9_SPI0_SEL1   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI0 << 8)  |  FuncSel_9)
#define FUNC9_SPI0_SEL2   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI0 << 8)  |  FuncSel_9)
#define FUNC9_SPI1_MOSI   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI1 << 8)  |  FuncSel_9)
#define FUNC9_SPI1_MISO   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI1 << 8)  |  FuncSel_9)
#define FUNC9_SPI1_SCLK   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI1 << 8)  |  FuncSel_9)
#define FUNC9_SPI1_SEL0   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI1 << 8)  |  FuncSel_9)
#define FUNC9_SPI1_SEL1   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI1 << 8)  |  FuncSel_9)
#define FUNC9_SPI1_SEL2   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SPI1 << 8)  |  FuncSel_9)

// function 10: sdio
#define FUNC10_SD0_4BIT_CLK     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_10)
#define FUNC10_SD0_4BIT_CMD     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_10)
#define FUNC10_SD0_4BIT_DATA0   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_10)
#define FUNC10_SD0_4BIT_DATA1   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_10)
#define FUNC10_SD0_4BIT_DATA2   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_10)
#define FUNC10_SD0_4BIT_DATA3   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |  FuncSel_10)
#define FUNC10_SD1_4BIT_CLK     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |  FuncSel_10)
#define FUNC10_SD1_4BIT_CMD     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_10)
#define FUNC10_SD1_4BIT_DATA0   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_10)
#define FUNC10_SD1_4BIT_DATA1   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_10)
#define FUNC10_SD1_4BIT_DATA2   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_10)
#define FUNC10_SD1_4BIT_DATA3   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_10)

// function 11: sdio 8bit
#define FUNC11_SD1_WP      ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_11)
#define FUNC11_SD1_PWR     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_11)
#define FUNC11_SD0_PWR     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |   FuncSel_11)

#define FUNC11_SD0_8BIT_CLK     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_CMD     ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA0   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA1   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA2   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA3   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA4   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA5   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA6   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)
#define FUNC11_SD0_8BIT_DATA7   ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_11)

// function 12: sdio_cd
#define FUNC12_SD0_CD      ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO0 << 8)  |    FuncSel_12)

// function 13: sdio_cd
#define FUNC13_SD1_CD      ((EMIO_SUPPORT  << 31)  |   (AL_PINCTRL_GROUP_SDIO1 << 8)  |    FuncSel_13)

// function 14: sdio_pwr, mdio, gbe
#define FUNC14_RGMII_0_PHY_INT         ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_1_PHY_INT         ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_SD1_PWR                 ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SDIO1 << 8)  |   FuncSel_14)
#define FUNC14_SD0_PWR                 ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_SDIO0 << 8)  |   FuncSel_14)
#define FUNC14_MDC0                    ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_MDIO0 << 8)  |   FuncSel_14)
#define FUNC14_MDIO0                   ((EMIO_SUPPORT  << 31)  |  (AL_PINCTRL_GROUP_MDIO0 << 8)  |   FuncSel_14)
#define FUNC14_RGMII_RMII_0_TX_CTL     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_0_TX_CLK     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_0_TX_DATA0   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_0_TX_DATA1   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_0_TX_DATA2        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_0_TX_DATA3        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_0_RX_CTL     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_0_RX_CLK     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_0_RX_DATA0   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_0_RX_DATA1   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_0_RX_DATA2        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_0_RX_DATA3        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)

#define FUNC14_RGMII_RMII_1_TX_CTL     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_1_TX_CLK     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_1_TX_DATA0   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_1_TX_DATA1   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_1_TX_DATA2        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_1_TX_DATA3        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_1_RX_CTL     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_1_RX_CLK     ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_1_RX_DATA0   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_RMII_1_RX_DATA1   ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_1_RX_DATA2        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)
#define FUNC14_RGMII_1_RX_DATA3        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_14)

// function 15: sdio_wp, mdio, usb
#define FUNC15_MDC1            ((EMIO_SUPPORT  << 31)   |  (AL_PINCTRL_GROUP_MDIO1 << 8)  |   FuncSel_15)
#define FUNC15_MDIO1           ((EMIO_SUPPORT  << 31)   |  (AL_PINCTRL_GROUP_MDIO1 << 8)  |   FuncSel_15)
#define FUNC15_SD0_WP          ((EMIO_SUPPORT   << 31)  |  (AL_PINCTRL_GROUP_SDIO0 << 8)  |   FuncSel_15)
#define FUNC15_USB0_CLK        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DIR        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_STP        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_NXT        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA0      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA1      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA2      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA3      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA4      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA5      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA6      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB0_DATA7      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_CLK        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DIR        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_STP        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_NXT        ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA0      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA1      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA2      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA3      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA4      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA5      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA6      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)
#define FUNC15_USB1_DATA7      ((EMIO_NOT_SUPPORT  << 31)  | FuncSel_15)

/****************************** Function Selection Enums *****************************/
typedef enum {
    mio0_nand_cs   = FUNC2_NAND,
    mio0_gpio0     = FUNC4_GPIO,
    mio0_can0_clk  = FUNC5_CAN0_CLK,
    mio0_can1_clk  = FUNC6_CAN1_CLK,
    mio0_sd1_wp    = FUNC11_SD1_WP,
    mio0_sd0_cd    = FUNC12_SD0_CD,
    mio0_sd1_cd    = FUNC13_SD1_CD,
    mio0_sd0_pwr   = FUNC14_SD0_PWR,
    mio0_sd0_wp    = FUNC15_SD0_WP,

    mio1_qspi_ss   = FUNC1_QSPI_SS,
    mio1_gpio1     = FUNC4_GPIO,
    mio1_can0_clk  = FUNC5_CAN0_CLK,
    mio1_can1_clk  = FUNC6_CAN1_CLK,
    mio1_sd1_wp    = FUNC11_SD1_WP,
    mio1_sd0_cd    = FUNC12_SD0_CD,
    mio1_sd1_cd    = FUNC13_SD1_CD,
    mio1_sd1_pwr   = FUNC14_SD1_PWR,
    mio1_sd0_wp    = FUNC15_SD0_WP,

    mio2_qspi_data0 = FUNC1_QSPI_DATA0,
    mio2_nand_ale   = FUNC2_NAND,
    mio2_gpio2      = FUNC4_GPIO,
    mio2_can0_clk   = FUNC5_CAN0_CLK,
    mio2_can1_clk   = FUNC6_CAN1_CLK,
    mio2_sd1_wp     = FUNC11_SD1_WP,
    mio2_sd0_cd     = FUNC12_SD0_CD,
    mio2_sd1_cd     = FUNC13_SD1_CD,
    mio2_sd0_pwr    = FUNC14_SD0_PWR,
    mio2_sd0_wp     = FUNC15_SD0_WP,

    mio3_qspi_data1 = FUNC1_QSPI_DATA1,
    mio3_nand_we_b  = FUNC2_NAND,
    mio3_gpio3      = FUNC4_GPIO,
    mio3_can0_clk   = FUNC5_CAN0_CLK,
    mio3_can1_clk   = FUNC6_CAN1_CLK,
    mio3_sd1_wp     = FUNC11_SD1_WP,
    mio3_sd0_cd     = FUNC12_SD0_CD,
    mio3_sd1_cd     = FUNC13_SD1_CD,
    mio3_sd1_pwr    = FUNC14_SD1_PWR,
    mio3_sd0_wp     = FUNC15_SD0_WP,

    mio4_qspi_data2 = FUNC1_QSPI_DATA2,
    mio4_nand_data2 = FUNC2_NAND,
    mio4_gpio4      = FUNC4_GPIO,
    mio4_can0_clk   = FUNC5_CAN0_CLK,
    mio4_can1_clk   = FUNC6_CAN1_CLK,
    mio4_sd1_wp     = FUNC11_SD1_WP,
    mio4_sd0_cd     = FUNC12_SD0_CD,
    mio4_sd1_cd     = FUNC13_SD1_CD,
    mio4_sd0_pwr    = FUNC14_SD0_PWR,
    mio4_sd0_wp     = FUNC15_SD0_WP,

    mio5_qspi_data3 = FUNC1_QSPI_DATA3,
    mio5_nand_data0 = FUNC2_NAND,
    mio5_gpio5      = FUNC4_GPIO,
    mio5_can0_clk   = FUNC5_CAN0_CLK,
    mio5_can1_clk   = FUNC6_CAN1_CLK,
    mio5_sd1_wp     = FUNC11_SD1_WP,
    mio5_sd0_cd     = FUNC12_SD0_CD,
    mio5_sd1_cd     = FUNC13_SD1_CD,
    mio5_sd1_pwr    = FUNC14_SD1_PWR,
    mio5_sd0_wp     = FUNC15_SD0_WP,

    mio6_qspi_clk   = FUNC1_QSPI_CLK,
    mio6_nand_data1 = FUNC2_NAND,
    mio6_gpio6      = FUNC4_GPIO,
    mio6_can0_clk   = FUNC5_CAN0_CLK,
    mio6_can1_clk   = FUNC6_CAN1_CLK,
    mio6_sd1_wp     = FUNC11_SD1_WP,
    mio6_sd0_cd     = FUNC12_SD0_CD,
    mio6_sd1_cd     = FUNC13_SD1_CD,
    mio6_sd0_pwr    = FUNC14_SD0_PWR,
    mio6_sd0_wp     = FUNC15_SD0_WP,

    mio7_nand_cle   = FUNC2_NAND,
    mio7_gpio7      = FUNC4_GPIO,
    mio7_can0_clk   = FUNC5_CAN0_CLK,
    mio7_can1_clk   = FUNC6_CAN1_CLK,
    mio7_sd1_wp     = FUNC11_SD1_WP,
    mio7_sd0_cd     = FUNC12_SD0_CD,
    mio7_sd1_cd     = FUNC13_SD1_CD,
    mio7_sd1_pwr    = FUNC14_SD1_PWR,
    mio7_sd0_wp     = FUNC15_SD0_WP,

    mio8_can1_tx    = FUNC1_CAN1_TX,
    mio8_nand_re_b  = FUNC2_NAND,
    mio8_uart1_tx   = FUNC3_UART1_TX,
    mio8_gpio8      = FUNC4_GPIO,
    mio8_can0_clk   = FUNC5_CAN0_CLK,
    mio8_can1_clk   = FUNC6_CAN1_CLK,
    mio8_sd1_wp     = FUNC11_SD1_WP,
    mio8_sd0_cd     = FUNC12_SD0_CD,
    mio8_sd1_cd     = FUNC13_SD1_CD,
    mio8_sd0_pwr    = FUNC14_SD0_PWR,
    mio8_sd0_wp     = FUNC15_SD0_WP,

    mio9_can1_rx    = FUNC1_CAN1_RX,
    mio9_nand_data4 = FUNC2_NAND,
    mio9_uart1_rx   = FUNC3_UART1_RX,
    mio9_gpio9      = FUNC4_GPIO,
    mio9_can0_clk   = FUNC5_CAN0_CLK,
    mio9_can1_clk   = FUNC6_CAN1_CLK,
    mio9_sd1_wp     = FUNC11_SD1_WP,
    mio9_sd0_cd     = FUNC12_SD0_CD,
    mio9_sd1_cd     = FUNC13_SD1_CD,
    mio9_sd1_pwr    = FUNC14_SD1_PWR,
    mio9_sd0_wp     = FUNC15_SD0_WP,

    mio10_i2c0_scl   = FUNC0_IIC0_SCL,
    mio10_can0_rx    = FUNC1_CAN0_RX,
    mio10_nand_data5 = FUNC2_NAND,
    mio10_uart0_rx   = FUNC3_UART0_RX,
    mio10_gpio10     = FUNC4_GPIO,
    mio10_can0_clk   = FUNC5_CAN0_CLK,
    mio10_can1_clk   = FUNC6_CAN1_CLK,
    mio10_spi1_mosi  = FUNC9_SPI1_MOSI,
    mio10_sd1_4bit_data0  = FUNC10_SD1_4BIT_DATA0,
    mio10_sd1_wp     = FUNC11_SD1_WP,
    mio10_sd0_cd     = FUNC12_SD0_CD,
    mio10_sd1_cd     = FUNC13_SD1_CD,
    mio10_sd0_wp     = FUNC15_SD0_WP,

    mio11_i2c0_sda   = FUNC0_IIC0_SDA,
    mio11_can0_tx    = FUNC1_CAN0_TX,
    mio11_nand_data6 = FUNC2_NAND,
    mio11_uart0_tx   = FUNC3_UART0_TX,
    mio11_gpio11     = FUNC4_GPIO,
    mio11_can0_clk   = FUNC5_CAN0_CLK,
    mio11_can1_clk   = FUNC6_CAN1_CLK,
    mio11_spi1_miso  = FUNC9_SPI1_MISO,
    mio11_sd1_4bit_cmd    = FUNC10_SD1_4BIT_CMD,
    mio11_sd1_wp     = FUNC11_SD1_WP,
    mio11_sd0_cd     = FUNC12_SD0_CD,
    mio11_sd1_cd     = FUNC13_SD1_CD,
    mio11_sd0_wp     = FUNC15_SD0_WP,

    mio12_i2c1_scl   = FUNC0_IIC1_SCL,
    mio12_can1_tx    = FUNC1_CAN1_TX,
    mio12_nand_data7 = FUNC2_NAND,
    mio12_uart1_tx   = FUNC3_UART1_TX,
    mio12_gpio12     = FUNC4_GPIO,
    mio12_can0_clk   = FUNC5_CAN0_CLK,
    mio12_can1_clk   = FUNC6_CAN1_CLK,
    mio12_spi1_sclk  = FUNC9_SPI1_SCLK,
    mio12_sd1_4bit_clk    = FUNC10_SD1_4BIT_CLK,
    mio12_sd1_wp     = FUNC11_SD1_WP,
    mio12_sd0_cd     = FUNC12_SD0_CD,
    mio12_sd1_cd     = FUNC13_SD1_CD,
    mio12_sd0_wp     = FUNC15_SD0_WP,

    mio13_i2c1_sda   = FUNC0_IIC1_SDA,
    mio13_can1_rx    = FUNC1_CAN1_RX,
    mio13_nand_data3 = FUNC2_NAND,
    mio13_uart1_rx   = FUNC3_UART1_RX,
    mio13_gpio13     = FUNC4_GPIO,
    mio13_can0_clk   = FUNC5_CAN0_CLK,
    mio13_can1_clk   = FUNC6_CAN1_CLK,
    mio13_spi1_ss_0  = FUNC9_SPI1_SEL0,
    mio13_sd1_4bit_data1  = FUNC10_SD1_4BIT_DATA0,
    mio13_sd1_wp     = FUNC11_SD1_WP,
    mio13_sd0_cd     = FUNC12_SD0_CD,
    mio13_sd1_cd     = FUNC13_SD1_CD,
    mio13_sd0_wp     = FUNC15_SD0_WP,

    mio14_i2c0_scl   = FUNC0_IIC0_SCL,
    mio14_can0_rx    = FUNC1_CAN0_RX,
    mio14_nand_busy  = FUNC2_NAND,
    mio14_uart0_rx   = FUNC3_UART0_RX,
    mio14_gpio14     = FUNC4_GPIO,
    mio14_can0_clk   = FUNC5_CAN0_CLK,
    mio14_can1_clk   = FUNC6_CAN1_CLK,
    mio14_spi1_ss_1  = FUNC9_SPI1_SEL1,
    mio14_sd1_4bit_data2  = FUNC10_SD1_4BIT_DATA2,
    mio14_sd1_wp     = FUNC11_SD1_WP,
    mio14_sd0_cd     = FUNC12_SD0_CD,
    mio14_sd1_cd     = FUNC13_SD1_CD,
    mio14_sd0_pwr    = FUNC14_SD0_PWR,
    mio14_sd0_wp     = FUNC15_SD0_WP,

    mio15_i2c0_sda   = FUNC0_IIC0_SDA,
    mio15_can0_tx    = FUNC1_CAN0_TX,
    mio15_uart0_tx   = FUNC3_UART0_TX,
    mio15_gpio15     = FUNC4_GPIO,
    mio15_can0_clk   = FUNC5_CAN0_CLK,
    mio15_can1_clk   = FUNC6_CAN1_CLK,
    mio15_spi1_ss_2  = FUNC9_SPI1_SEL2,
    mio15_sd1_4bit_data3  = FUNC10_SD1_4BIT_DATA3,
    mio15_sd1_wp     = FUNC11_SD1_WP,
    mio15_sd0_cd     = FUNC12_SD0_CD,
    mio15_sd1_cd     = FUNC13_SD1_CD,
    mio15_sd1_pwr    = FUNC14_SD1_PWR,
    mio15_sd0_wp     = FUNC15_SD0_WP,

    mio16_i2c1_scl   = FUNC0_IIC1_SCL,
    mio16_can1_tx    = FUNC1_CAN1_TX,
    mio16_nand_data8 = FUNC2_NAND,
    mio16_uart1_tx   = FUNC3_UART1_TX,
    mio16_gpio16     = FUNC4_GPIO,
    mio16_can0_clk   = FUNC5_CAN0_CLK,
    mio16_can1_clk   = FUNC6_CAN1_CLK,
    mio16_ttc1_wave  = FUNC7_TTC1_WAVE,
    mio16_spi0_sclk  = FUNC9_SPI0_SCLK,
    mio16_sd0_4bit_clk    = FUNC10_SD0_4BIT_CLK,
    mio16_sd1_wp     = FUNC11_SD1_WP,
    mio16_sd0_cd     = FUNC12_SD0_CD,
    mio16_sd1_cd     = FUNC13_SD1_CD,
    mio16_rgmii_rmii_0_tx_clk = FUNC14_RGMII_RMII_0_TX_CLK,
    mio16_sd0_wp     = FUNC15_SD0_WP,

    mio17_i2c1_sda   = FUNC0_IIC1_SDA,
    mio17_can1_rx    = FUNC1_CAN1_RX,
    mio17_nand_data9 = FUNC2_NAND,
    mio17_uart1_rx   = FUNC3_UART1_RX,
    mio17_gpio17     = FUNC4_GPIO,
    mio17_can0_clk   = FUNC5_CAN0_CLK,
    mio17_can1_clk   = FUNC6_CAN1_CLK,
    mio17_ttc1_clk   = FUNC7_TTC1_CLK,
    mio17_spi0_miso  = FUNC9_SPI0_MISO,
    mio17_sd0_4bit_cmd    = FUNC10_SD0_4BIT_CMD,
    mio17_sd1_wp     = FUNC11_SD1_WP,
    mio17_sd0_cd     = FUNC12_SD0_CD,
    mio17_sd1_cd     = FUNC13_SD1_CD,
    mio17_rgmii_rmii_0_tx_data0 = FUNC14_RGMII_RMII_0_TX_DATA0,
    mio17_sd0_wp     = FUNC15_SD0_WP,

    mio18_i2c0_scl    = FUNC0_IIC0_SCL,
    mio18_can0_rx     = FUNC1_CAN0_RX,
    mio18_nand_data10 = FUNC2_NAND,
    mio18_uart0_rx    = FUNC3_UART0_RX,
    mio18_gpio18      = FUNC4_GPIO,
    mio18_can0_clk    = FUNC5_CAN0_CLK,
    mio18_can1_clk    = FUNC6_CAN1_CLK,
    mio18_ttc0_wave   = FUNC7_TTC0_WAVE,
    mio18_spi0_ss_0   = FUNC9_SPI0_SEL0,
    mio18_sd0_4bit_data0   = FUNC10_SD0_4BIT_DATA0,
    mio18_sd1_wp      = FUNC11_SD1_WP,
    mio18_sd0_cd      = FUNC12_SD0_CD,
    mio18_sd1_cd      = FUNC13_SD1_CD,
    mio18_rgmii_rmii_0_tx_data1 = FUNC14_RGMII_RMII_0_TX_DATA1,
    mio18_sd0_wp      = FUNC15_SD0_WP,

    mio19_i2c0_sda    = FUNC0_IIC0_SDA,
    mio19_can0_tx     = FUNC1_CAN0_TX,
    mio19_nand_data11 = FUNC2_NAND,
    mio19_uart0_tx    = FUNC3_UART0_TX,
    mio19_gpio19      = FUNC4_GPIO,
    mio19_can0_clk    = FUNC5_CAN0_CLK,
    mio19_can1_clk    = FUNC6_CAN1_CLK,
    mio19_ttc0_clk    = FUNC7_TTC0_CLK,
    mio19_spi0_ss_1   = FUNC9_SPI0_SEL1,
    mio19_sd0_4bit_data1   = FUNC10_SD0_4BIT_DATA1,
    mio19_sd1_wp      = FUNC11_SD1_WP,
    mio19_sd0_cd      = FUNC12_SD0_CD,
    mio19_sd1_cd      = FUNC13_SD1_CD,
    mio19_rgmii0_tx_data2 = FUNC14_RGMII_0_TX_DATA2,
    mio19_sd0_wp      = FUNC15_SD0_WP,

    mio20_i2c1_scl    = FUNC0_IIC1_SCL,
    mio20_can1_tx     = FUNC1_CAN1_TX,
    mio20_nand_data12 = FUNC2_NAND,
    mio20_uart1_tx    = FUNC3_UART1_TX,
    mio20_gpio20      = FUNC4_GPIO,
    mio20_can0_clk    = FUNC5_CAN0_CLK,
    mio20_can1_clk    = FUNC6_CAN1_CLK,
    mio20_sd0_pwr     = FUNC7_SD0_PWR,
    mio20_spi0_ss_2   = FUNC9_SPI0_SEL2,
    mio20_sd0_4bit_data2   = FUNC10_SD0_4BIT_DATA2,
    mio20_sd1_wp      = FUNC11_SD1_WP,
    mio20_sd0_cd      = FUNC12_SD0_CD,
    mio20_sd1_cd      = FUNC13_SD1_CD,
    mio20_rgmii0_tx_data3 = FUNC14_RGMII_0_TX_DATA3,
    mio20_sd0_wp      = FUNC15_SD0_WP,

    mio21_i2c1_sda    = FUNC0_IIC1_SDA,
    mio21_can1_rx     = FUNC1_CAN1_RX,
    mio21_nand_data13 = FUNC2_NAND,
    mio21_uart1_rx    = FUNC3_UART1_RX,
    mio21_gpio21      = FUNC4_GPIO,
    mio21_can0_clk    = FUNC5_CAN0_CLK,
    mio21_can1_clk    = FUNC6_CAN1_CLK,
    mio21_sd1_pwr     = FUNC7_SD1_PWR,
    mio21_spi0_mosi   = FUNC9_SPI0_MOSI,
    mio21_sd0_4bit_data3   = FUNC10_SD0_4BIT_DATA3,
    mio21_sd1_wp      = FUNC11_SD1_WP,
    mio21_sd0_cd      = FUNC12_SD0_CD,
    mio21_sd1_cd      = FUNC13_SD1_CD,
    mio21_rgmii_rmii_0_tx_ctl = FUNC14_RGMII_RMII_0_TX_CTL,
    mio21_sd0_wp      = FUNC15_SD0_WP,

    mio22_i2c0_scl    = FUNC0_IIC0_SCL,
    mio22_can0_rx     = FUNC1_CAN0_RX,
    mio22_nand_data14 = FUNC2_NAND,
    mio22_uart0_rx    = FUNC3_UART0_RX,
    mio22_gpio22      = FUNC4_GPIO,
    mio22_can0_clk    = FUNC5_CAN0_CLK,
    mio22_can1_clk    = FUNC6_CAN1_CLK,
    mio22_spi1_mosi   = FUNC9_SPI1_MOSI,
    mio22_sd1_4bit_data0   = FUNC10_SD1_4BIT_DATA0,
    mio22_sd1_wp      = FUNC11_SD1_WP,
    mio22_sd0_cd      = FUNC12_SD0_CD,
    mio22_sd1_cd      = FUNC13_SD1_CD,
    mio22_rgmii_rmii_0_rx_clk = FUNC14_RGMII_RMII_0_RX_CLK,
    mio22_sd0_wp      = FUNC15_SD0_WP,

    mio23_i2c0_sda    = FUNC0_IIC0_SDA,
    mio23_can0_tx     = FUNC1_CAN0_TX,
    mio23_nand_data15 = FUNC2_NAND,
    mio23_uart0_tx    = FUNC3_UART0_TX,
    mio23_gpio23      = FUNC4_GPIO,
    mio23_can0_clk    = FUNC5_CAN0_CLK,
    mio23_can1_clk    = FUNC6_CAN1_CLK,
    mio23_spi1_miso   = FUNC9_SPI1_MISO,
    mio23_sd1_4bit_cmd     = FUNC10_SD1_4BIT_CMD,
    mio23_sd1_wp      = FUNC11_SD1_WP,
    mio23_sd0_cd      = FUNC12_SD0_CD,
    mio23_sd1_cd      = FUNC13_SD1_CD,
    mio23_rgmii_rmii_0_rx_data0 = FUNC14_RGMII_RMII_0_RX_DATA0,
    mio23_sd0_wp      = FUNC15_SD0_WP,

    mio24_i2c1_scl    = FUNC0_IIC1_SCL,
    mio24_can1_tx     = FUNC1_CAN1_TX,
    mio24_sd0_pwr     = FUNC2_SD0_PWR,
    mio24_uart1_tx    = FUNC3_UART1_TX,
    mio24_gpio24      = FUNC4_GPIO,
    mio24_can0_clk    = FUNC5_CAN0_CLK,
    mio24_can1_clk    = FUNC6_CAN1_CLK,
    mio24_spi1_sclk   = FUNC9_SPI1_SCLK,
    mio24_sd1_4bit_clk     = FUNC10_SD1_4BIT_CLK,
    mio24_sd1_wp      = FUNC11_SD1_WP,
    mio24_sd0_cd      = FUNC12_SD0_CD,
    mio24_sd1_cd      = FUNC13_SD1_CD,
    mio24_rgmii_rmii_0_rx_data1 = FUNC14_RGMII_RMII_0_RX_DATA1,
    mio24_sd0_wp      = FUNC15_SD0_WP,

    mio25_i2c1_sda    = FUNC0_IIC1_SDA,
    mio25_can1_rx     = FUNC1_CAN1_RX,
    mio25_sd1_wp      = FUNC2_SD1_WP,
    mio25_uart1_rx    = FUNC3_UART1_RX,
    mio25_gpio25      = FUNC4_GPIO,
    mio25_can0_clk    = FUNC5_CAN0_CLK,
    mio25_can1_clk    = FUNC6_CAN1_CLK,
    mio25_spi1_ss_0   = FUNC9_SPI1_SEL0,
    mio25_sd1_4bit_data1   = FUNC10_SD1_4BIT_DATA1,
    mio25_sd1_pwr     = FUNC11_SD1_PWR,
    mio25_sd0_cd      = FUNC12_SD0_CD,
    mio25_sd1_cd      = FUNC13_SD1_CD,
    mio25_rgmii0_rx_data2 = FUNC14_RGMII_0_RX_DATA2,
    mio25_sd0_wp      = FUNC15_SD0_WP,

    mio26_i2c0_scl    = FUNC0_IIC0_SCL,
    mio26_can0_rx     = FUNC1_CAN0_RX,
    mio26_sd1_wp      = FUNC2_SD1_WP,
    mio26_uart0_rx    = FUNC3_UART0_RX,
    mio26_gpio26      = FUNC4_GPIO,
    mio26_can0_clk    = FUNC5_CAN0_CLK,
    mio26_can1_clk    = FUNC6_CAN1_CLK,
    mio26_spi1_ss_1   = FUNC9_SPI1_SEL1,
    mio26_sd1_4bit_data2   = FUNC10_SD1_4BIT_DATA2,
    mio26_sd0_pwr     = FUNC11_SD0_PWR,
    mio26_sd0_cd      = FUNC12_SD0_CD,
    mio26_sd1_cd      = FUNC13_SD1_CD,
    mio26_rgmii0_rx_data3 = FUNC14_RGMII_0_RX_DATA3,
    mio26_sd0_wp      = FUNC15_SD0_WP,

    mio27_i2c0_sda    = FUNC0_IIC0_SDA,
    mio27_can0_tx     = FUNC1_CAN0_TX,
    mio27_sd1_wp      = FUNC2_SD1_WP,
    mio27_uart0_tx    = FUNC3_UART0_TX,
    mio27_gpio27      = FUNC4_GPIO,
    mio27_can0_clk    = FUNC5_CAN0_CLK,
    mio27_can1_clk    = FUNC6_CAN1_CLK,
    mio27_spi1_ss_2   = FUNC9_SPI1_SEL2,
    mio27_sd1_4bit_data3   = FUNC10_SD1_4BIT_DATA3,
    mio27_sd1_pwr     = FUNC11_SD1_PWR,
    mio27_sd0_cd      = FUNC12_SD0_CD,
    mio27_sd1_cd      = FUNC13_SD1_CD,
    mio27_rgmii_rmii_0_rx_ctl = FUNC14_RGMII_RMII_0_RX_CTL,
    mio27_sd0_wp      = FUNC15_SD0_WP,

    mio28_i2c1_scl    = FUNC0_IIC1_SCL,
    mio28_can1_tx     = FUNC1_CAN1_TX,
    mio28_sd1_wp      = FUNC2_SD1_WP,
    mio28_uart1_tx    = FUNC3_UART1_TX,
    mio28_gpio28      = FUNC4_GPIO,
    mio28_can0_clk    = FUNC5_CAN0_CLK,
    mio28_can1_clk    = FUNC6_CAN1_CLK,
    mio28_ttc1_wave   = FUNC7_TTC1_WAVE,
    mio28_sd0_wp      = FUNC8_SD0_WP,
    mio28_spi0_sclk   = FUNC9_SPI0_SCLK,
    mio28_sd0_4bit_clk     = FUNC10_SD0_4BIT_CLK,
    mio28_sd0_8bit_clk     = FUNC11_SD0_8BIT_CLK,
    mio28_sd0_cd      = FUNC12_SD0_CD,
    mio28_sd1_cd      = FUNC13_SD1_CD,
    mio28_rgmii_rmii_1_tx_clk = FUNC14_RGMII_RMII_1_TX_CLK,
    mio28_usb0_data4  = FUNC15_USB0_DATA4,

    mio29_i2c1_sda    = FUNC0_IIC1_SDA,
    mio29_can1_rx     = FUNC1_CAN1_RX,
    mio29_sd1_wp      = FUNC2_SD1_WP,
    mio29_uart1_rx    = FUNC3_UART1_RX,
    mio29_gpio29      = FUNC4_GPIO,
    mio29_can0_clk    = FUNC5_CAN0_CLK,
    mio29_can1_clk    = FUNC6_CAN1_CLK,
    mio29_sd0_wp      = FUNC8_SD0_WP,
    mio29_spi0_miso   = FUNC9_SPI0_MISO,
    mio29_sd0_4bit_cmd     = FUNC10_SD0_4BIT_CMD,
    mio29_sd0_8bit_cmd     = FUNC11_SD0_8BIT_CMD,
    mio29_sd0_cd      = FUNC12_SD0_CD,
    mio29_sd1_cd      = FUNC13_SD1_CD,
    mio29_rgmii_rmii_1_tx_data0 = FUNC14_RGMII_RMII_1_TX_DATA0,
    mio29_usb0_dir    = FUNC15_USB0_DIR,

    mio30_i2c0_scl    = FUNC0_IIC0_SCL,
    mio30_can0_rx     = FUNC1_CAN0_RX,
    mio30_sd1_wp      = FUNC2_SD1_WP,
    mio30_uart0_rx    = FUNC3_UART0_RX,
    mio30_gpio30      = FUNC4_GPIO,
    mio30_can0_clk    = FUNC5_CAN0_CLK,
    mio30_can1_clk    = FUNC6_CAN1_CLK,
    mio30_ttc0_wave   = FUNC7_TTC0_WAVE,
    mio30_sd0_wp      = FUNC8_SD0_WP,
    mio30_spi0_ss_0   = FUNC9_SPI0_SEL0,
    mio30_sd0_4bit_data0   = FUNC10_SD0_4BIT_DATA0,
    mio30_sd0_8bit_data0   = FUNC11_SD0_8BIT_DATA0,
    mio30_sd0_cd      = FUNC12_SD0_CD,
    mio30_sd1_cd      = FUNC13_SD1_CD,
    mio30_rgmii_rmii_1_tx_data1 = FUNC14_RGMII_RMII_1_TX_DATA1,
    mio30_usb0_stp    = FUNC15_USB0_STP,

    mio31_i2c0_sda    = FUNC0_IIC0_SDA,
    mio31_can0_tx     = FUNC1_CAN0_TX,
    mio31_sd1_wp      = FUNC2_SD1_WP,
    mio31_uart0_tx    = FUNC3_UART0_TX,
    mio31_gpio31      = FUNC4_GPIO,
    mio31_can0_clk    = FUNC5_CAN0_CLK,
    mio31_can1_clk    = FUNC6_CAN1_CLK,
    mio31_ttc0_clk    = FUNC7_TTC0_CLK,
    mio31_sd0_wp      = FUNC8_SD0_WP,
    mio31_spi0_ss_1   = FUNC9_SPI0_SEL1,
    mio31_sd0_4bit_data1   = FUNC10_SD0_4BIT_DATA1,
    mio31_sd0_8bit_data1   = FUNC11_SD0_8BIT_DATA1,
    mio31_sd0_cd      = FUNC12_SD0_CD,
    mio31_sd1_cd      = FUNC13_SD1_CD,
    mio31_rgmii_1_tx_data2 = FUNC14_RGMII_1_TX_DATA2,
    mio31_usb0_nxt    = FUNC15_USB0_NXT,

    mio32_i2c1_scl    = FUNC0_IIC1_SCL,
    mio32_can1_tx     = FUNC1_CAN1_TX,
    mio32_sd1_wp      = FUNC2_SD1_WP,
    mio32_uart1_tx    = FUNC3_UART1_TX,
    mio32_gpio32      = FUNC4_GPIO,
    mio32_can0_clk    = FUNC5_CAN0_CLK,
    mio32_can1_clk    = FUNC6_CAN1_CLK,
    mio32_sd0_pwr     = FUNC7_SD0_PWR,
    mio32_sd0_wp      = FUNC8_SD0_WP,
    mio32_spi0_ss_2   = FUNC9_SPI0_SEL2,
    mio32_sd0_4bit_data2   = FUNC10_SD0_4BIT_DATA2,
    mio32_sd0_8bit_data2   = FUNC11_SD0_8BIT_DATA2,
    mio32_sd0_cd      = FUNC12_SD0_CD,
    mio32_sd1_cd      = FUNC13_SD1_CD,
    mio32_rgmii_1_tx_data3 = FUNC14_RGMII_1_TX_DATA3,
    mio32_usb0_data0  = FUNC15_USB0_DATA0,

    mio33_i2c1_sda    = FUNC0_IIC1_SDA,
    mio33_can1_rx     = FUNC1_CAN1_RX,
    mio33_sd1_wp      = FUNC2_SD1_WP,
    mio33_uart1_rx    = FUNC3_UART1_RX,
    mio33_gpio33      = FUNC4_GPIO,
    mio33_can0_clk    = FUNC5_CAN0_CLK,
    mio33_can1_clk    = FUNC6_CAN1_CLK,
    mio33_sd1_pwr     = FUNC7_SD1_PWR,
    mio33_sd0_wp      = FUNC8_SD0_WP,
    mio33_spi0_mosi   = FUNC9_SPI0_MOSI,
    mio33_sd0_4bit_data3   = FUNC10_SD0_4BIT_DATA3,
    mio33_sd0_8bit_data3   = FUNC11_SD0_8BIT_DATA3,
    mio33_sd0_cd      = FUNC12_SD0_CD,
    mio33_sd1_cd      = FUNC13_SD1_CD,
    mio33_rgmii_rmii_1_tx_ctl = FUNC14_RGMII_RMII_1_TX_CTL,
    mio33_usb0_data1  = FUNC15_USB0_DATA1,

    mio34_i2c0_scl    = FUNC0_IIC0_SCL,
    mio34_can0_rx     = FUNC1_CAN0_RX,
    mio34_sd1_wp      = FUNC2_SD1_WP,
    mio34_uart0_rx    = FUNC3_UART0_RX,
    mio34_gpio34      = FUNC4_GPIO,
    mio34_can0_clk    = FUNC5_CAN0_CLK,
    mio34_sd0_wp      = FUNC8_SD0_WP,
    mio34_spi1_mosi   = FUNC9_SPI1_MOSI,
    mio34_sd1_4bit_data0   = FUNC10_SD1_4BIT_DATA0,
    mio34_sd0_8bit_data4   = FUNC11_SD0_8BIT_DATA4,
    mio34_sd0_cd      = FUNC12_SD0_CD,
    mio34_sd1_cd      = FUNC13_SD1_CD,
    mio34_rgmii_rmii_1_rx_clk = FUNC14_RGMII_RMII_1_RX_CLK,
    mio34_usb0_data2  = FUNC15_USB0_DATA2,

    mio35_i2c0_sda    = FUNC0_IIC0_SDA,
    mio35_can0_tx     = FUNC1_CAN0_TX,
    mio35_sd1_wp      = FUNC2_SD1_WP,
    mio35_uart0_tx    = FUNC3_UART0_TX,
    mio35_gpio35      = FUNC4_GPIO,
    mio35_can0_clk    = FUNC5_CAN0_CLK,
    mio35_can1_clk    = FUNC6_CAN1_CLK,
    mio35_sd0_wp      = FUNC8_SD0_WP,
    mio35_spi1_miso   = FUNC9_SPI1_MISO,
    mio35_sd1_4bit_cmd     = FUNC10_SD1_4BIT_CMD,
    mio35_sd0_cd      = FUNC12_SD0_CD,
    mio35_sd1_cd      = FUNC13_SD1_CD,
    mio35_rgmii_rmii_1_rx_data0 = FUNC14_RGMII_RMII_1_RX_DATA0,
    mio35_usb0_data3  = FUNC15_USB0_DATA3,

    mio36_i2c1_scl    = FUNC0_IIC1_SCL,
    mio36_can1_tx     = FUNC1_CAN1_TX,
    mio36_sd1_wp      = FUNC2_SD1_WP,
    mio36_uart1_tx    = FUNC3_UART1_TX,
    mio36_gpio36      = FUNC4_GPIO,
    mio36_can0_clk    = FUNC5_CAN0_CLK,
    mio36_can1_clk    = FUNC6_CAN1_CLK,
    mio36_sd0_wp      = FUNC8_SD0_WP,
    mio36_spi1_sclk   = FUNC9_SPI1_SCLK,
    mio36_sd1_4bit_clk     = FUNC10_SD1_4BIT_CLK,
    mio36_sd0_cd      = FUNC12_SD0_CD,
    mio36_sd1_cd      = FUNC13_SD1_CD,
    mio36_rgmii_rmii_1_rx_data1 = FUNC14_RGMII_RMII_1_RX_DATA1,
    mio36_usb0_clk    = FUNC15_USB0_CLK,

    mio37_i2c1_sda    = FUNC0_IIC1_SDA,
    mio37_can1_rx     = FUNC1_CAN1_RX,
    mio37_sd1_wp      = FUNC2_SD1_WP,
    mio37_uart1_rx    = FUNC3_UART1_RX,
    mio37_gpio37      = FUNC4_GPIO,
    mio37_can0_clk    = FUNC5_CAN0_CLK,
    mio37_sd0_wp      = FUNC8_SD0_WP,
    mio37_spi1_ss_0   = FUNC9_SPI1_SEL0,
    mio37_sd1_4bit_data1   = FUNC10_SD1_4BIT_DATA1,
    mio37_sd0_8bit_data5   = FUNC11_SD0_8BIT_DATA5,
    mio37_sd0_cd      = FUNC12_SD0_CD,
    mio37_sd1_cd      = FUNC13_SD1_CD,
    mio37_rgmii_1_rx_data2 = FUNC14_RGMII_1_RX_DATA2,
    mio37_usb0_data5  = FUNC15_USB0_DATA5,

    mio38_i2c0_scl    = FUNC0_IIC0_SCL,
    mio38_can0_rx     = FUNC1_CAN0_RX,
    mio38_sd1_wp      = FUNC2_SD1_WP,
    mio38_uart0_rx    = FUNC3_UART0_RX,
    mio38_gpio38      = FUNC4_GPIO,
    mio38_can0_clk    = FUNC5_CAN0_CLK,
    mio38_can1_clk    = FUNC6_CAN1_CLK,
    mio38_sd0_wp      = FUNC8_SD0_WP,
    mio38_spi1_ss_1   = FUNC9_SPI1_SEL1,
    mio38_sd1_4bit_data2   = FUNC10_SD1_4BIT_DATA2,
    mio38_sd0_8bit_data6   = FUNC11_SD0_8BIT_DATA6,
    mio38_sd0_cd      = FUNC12_SD0_CD,
    mio38_sd1_cd      = FUNC13_SD1_CD,
    mio38_rgmii_1_rx_data3 = FUNC14_RGMII_1_RX_DATA3,
    mio38_usb0_data6  = FUNC15_USB0_DATA6,

    mio39_i2c0_sda    = FUNC0_IIC0_SDA,
    mio39_can0_tx     = FUNC1_CAN0_TX,
    mio39_sd1_wp      = FUNC2_SD1_WP,
    mio39_uart0_tx    = FUNC3_UART0_TX,
    mio39_gpio39      = FUNC4_GPIO,
    mio39_can0_clk    = FUNC5_CAN0_CLK,
    mio39_can1_clk    = FUNC6_CAN1_CLK,
    mio39_sd0_wp      = FUNC8_SD0_WP,
    mio39_spi1_ss_2   = FUNC9_SPI1_SEL2,
    mio39_sd1_4bit_data3   = FUNC10_SD1_4BIT_DATA3,
    mio39_sd0_8bit_data7   = FUNC11_SD0_8BIT_DATA7,
    mio39_sd0_cd      = FUNC12_SD0_CD,
    mio39_sd1_cd      = FUNC13_SD1_CD,
    mio39_rgmii_rmii_1_rx_ctl = FUNC14_RGMII_RMII_1_RX_CTL,
    mio39_usb0_data7  = FUNC15_USB0_DATA7,

    mio40_i2c1_scl    = FUNC0_IIC1_SCL,
    mio40_can1_tx     = FUNC1_CAN1_TX,
    mio40_sd1_wp      = FUNC2_SD1_WP,
    mio40_uart1_tx    = FUNC3_UART1_TX,
    mio40_gpio40      = FUNC4_GPIO,
    mio40_can0_clk    = FUNC5_CAN0_CLK,
    mio40_can1_clk    = FUNC6_CAN1_CLK,
    mio40_ttc1_wave   = FUNC7_TTC1_WAVE,
    mio40_sd0_wp      = FUNC8_SD0_WP,
    mio40_spi0_sclk   = FUNC9_SPI0_SCLK,
    mio40_sd0_4bit_clk     = FUNC10_SD0_4BIT_CLK,
    mio40_sd0_8bit_clk     = FUNC11_SD0_8BIT_CLK,
    mio40_sd0_cd      = FUNC12_SD0_CD,
    mio40_sd1_cd      = FUNC13_SD1_CD,
    mio40_sd0_pwr     = FUNC14_SD0_PWR,
    mio40_usb1_data4  = FUNC15_USB1_DATA4,

    mio41_i2c1_sda    = FUNC0_IIC1_SDA,
    mio41_can1_rx     = FUNC1_CAN1_RX,
    mio41_sd1_wp      = FUNC2_SD1_WP,
    mio41_uart1_rx    = FUNC3_UART1_RX,
    mio41_gpio41      = FUNC4_GPIO,
    mio41_can0_clk    = FUNC5_CAN0_CLK,
    mio41_can1_clk    = FUNC6_CAN1_CLK,
    mio41_ttc1_clk    = FUNC7_TTC1_CLK,
    mio41_sd0_wp      = FUNC8_SD0_WP,
    mio41_spi0_miso   = FUNC9_SPI0_MISO,
    mio41_sd0_4bit_cmd     = FUNC10_SD0_4BIT_CMD,
    mio41_sd0_8bit_cmd     = FUNC11_SD0_8BIT_CMD,
    mio41_sd0_cd      = FUNC12_SD0_CD,
    mio41_sd1_cd      = FUNC13_SD1_CD,
    mio41_sd1_pwr     = FUNC14_SD1_PWR,
    mio41_usb1_dir    = FUNC15_USB1_DIR,

    mio42_i2c0_scl    = FUNC0_IIC0_SCL,
    mio42_can0_rx     = FUNC1_CAN0_RX,
    mio42_sd1_wp      = FUNC2_SD1_WP,
    mio42_uart0_rx    = FUNC3_UART0_RX,
    mio42_gpio42      = FUNC4_GPIO,
    mio42_can0_clk    = FUNC5_CAN0_CLK,
    mio42_can1_clk    = FUNC6_CAN1_CLK,
    mio42_ttc0_wave   = FUNC7_TTC0_WAVE,
    mio42_sd0_wp      = FUNC8_SD0_WP,
    mio42_spi0_ss_0   = FUNC9_SPI0_SEL0,
    mio42_sd0_4bit_data0   = FUNC10_SD0_4BIT_DATA0,
    mio42_sd0_8bit_data0   = FUNC11_SD0_8BIT_DATA0,
    mio42_sd0_cd      = FUNC12_SD0_CD,
    mio42_sd1_cd      = FUNC13_SD1_CD,
    mio42_sd0_pwr     = FUNC14_SD0_PWR,
    mio42_usb1_stp    = FUNC15_USB1_STP,

    mio43_i2c0_sda    = FUNC0_IIC0_SDA,
    mio43_can0_tx     = FUNC1_CAN0_TX,
    mio43_sd1_wp      = FUNC2_SD1_WP,
    mio43_uart0_tx    = FUNC3_UART0_TX,
    mio43_gpio43      = FUNC4_GPIO,
    mio43_can0_clk    = FUNC5_CAN0_CLK,
    mio43_can1_clk    = FUNC6_CAN1_CLK,
    mio43_ttc0_clk    = FUNC7_TTC0_CLK,
    mio43_sd0_wp      = FUNC8_SD0_WP,
    mio43_spi0_ss_1   = FUNC9_SPI0_SEL1,
    mio43_sd0_4bit_data1   = FUNC10_SD0_4BIT_DATA1,
    mio43_sd0_8bit_data1   = FUNC11_SD0_8BIT_DATA1,
    mio43_sd0_cd      = FUNC12_SD0_CD,
    mio43_sd1_cd      = FUNC13_SD1_CD,
    mio43_sd1_pwr     = FUNC14_SD1_PWR,
    mio43_usb1_nxt    = FUNC15_USB1_NXT,

    mio44_i2c1_scl    = FUNC0_IIC1_SCL,
    mio44_can1_tx     = FUNC1_CAN1_TX,
    mio44_sd1_wp      = FUNC2_SD1_WP,
    mio44_uart1_tx    = FUNC3_UART1_TX,
    mio44_gpio44      = FUNC4_GPIO,
    mio44_can0_clk    = FUNC5_CAN0_CLK,
    mio44_can1_clk    = FUNC6_CAN1_CLK,
    mio44_sd0_wp      = FUNC8_SD0_WP,
    mio44_spi0_ss_2   = FUNC9_SPI0_SEL2,
    mio44_sd0_4bit_data2   = FUNC10_SD0_4BIT_DATA2,
    mio44_sd0_8bit_data2   = FUNC11_SD0_8BIT_DATA2,
    mio44_sd0_cd      = FUNC12_SD0_CD,
    mio44_sd1_cd      = FUNC13_SD1_CD,
    mio44_sd0_pwr     = FUNC14_SD0_PWR,
    mio44_usb1_data0  = FUNC15_USB1_DATA0,

    mio45_i2c1_sda    = FUNC0_IIC1_SDA,
    mio45_can1_rx     = FUNC1_CAN1_RX,
    mio45_sd1_wp      = FUNC2_SD1_WP,
    mio45_uart1_rx    = FUNC3_UART1_RX,
    mio45_gpio45      = FUNC4_GPIO,
    mio45_can0_clk    = FUNC5_CAN0_CLK,
    mio45_can1_clk    = FUNC6_CAN1_CLK,
    mio45_sd0_wp      = FUNC8_SD0_WP,
    mio45_spi0_mosi   = FUNC9_SPI0_MOSI,
    mio45_sd0_4bit_data3   = FUNC10_SD0_4BIT_DATA3,
    mio45_sd0_8bit_data3   = FUNC11_SD0_8BIT_DATA3,
    mio45_sd0_cd      = FUNC12_SD0_CD,
    mio45_sd1_cd      = FUNC13_SD1_CD,
    mio45_sd1_pwr     = FUNC14_SD1_PWR,
    mio45_usb1_data1  = FUNC15_USB1_DATA1,

    mio46_i2c0_scl    = FUNC0_IIC0_SCL,
    mio46_can0_rx     = FUNC1_CAN0_RX,
    mio46_sd1_wp      = FUNC2_SD1_WP,
    mio46_uart0_rx    = FUNC3_UART0_RX,
    mio46_gpio46      = FUNC4_GPIO,
    mio46_can0_clk    = FUNC5_CAN0_CLK,
    mio46_can1_clk    = FUNC6_CAN1_CLK,
    mio46_sd0_wp      = FUNC8_SD0_WP,
    mio46_spi1_mosi   = FUNC9_SPI1_MOSI,
    mio46_sd1_4bit_data0   = FUNC10_SD1_4BIT_DATA0,
    mio46_sd0_8bit_data4   = FUNC11_SD0_8BIT_DATA4,
    mio46_sd0_cd      = FUNC12_SD0_CD,
    mio46_sd1_cd      = FUNC13_SD1_CD,
    mio46_usb1_data2  = FUNC15_USB1_DATA2,

    mio47_i2c0_sda    = FUNC0_IIC0_SDA,
    mio47_can0_tx     = FUNC1_CAN0_TX,
    mio47_sd1_wp      = FUNC2_SD1_WP,
    mio47_uart0_tx    = FUNC3_UART0_TX,
    mio47_gpio47      = FUNC4_GPIO,
    mio47_can0_clk    = FUNC5_CAN0_CLK,
    mio47_can1_clk    = FUNC6_CAN1_CLK,
    mio47_sd0_wp      = FUNC8_SD0_WP,
    mio47_spi1_miso   = FUNC9_SPI1_MISO,
    mio47_sd1_4bit_cmd   = FUNC10_SD1_4BIT_CMD,
    mio47_sd0_8bit_data5   = FUNC11_SD0_8BIT_DATA5,
    mio47_sd0_cd      = FUNC12_SD0_CD,
    mio47_sd1_cd      = FUNC13_SD1_CD,
    mio47_usb1_data3  = FUNC15_USB1_DATA3,

    mio48_i2c1_scl    = FUNC0_IIC1_SCL,
    mio48_can1_tx     = FUNC1_CAN1_TX,
    mio48_sd1_wp      = FUNC2_SD1_WP,
    mio48_uart1_tx    = FUNC3_UART1_TX,
    mio48_gpio48      = FUNC4_GPIO,
    mio48_can0_clk    = FUNC5_CAN0_CLK,
    mio48_can1_clk    = FUNC6_CAN1_CLK,
    mio48_sd0_wp      = FUNC8_SD0_WP,
    mio48_spi1_sclk   = FUNC9_SPI1_SCLK,
    mio48_sd1_4bit_clk   = FUNC10_SD1_4BIT_CLK,
    mio48_sd0_8bit_data6   = FUNC11_SD0_8BIT_DATA6,
    mio48_sd0_cd      = FUNC12_SD0_CD,
    mio48_sd1_cd      = FUNC13_SD1_CD,
    mio48_usb1_clk    = FUNC15_USB1_CLK,

    mio49_i2c1_sda    = FUNC0_IIC1_SDA,
    mio49_can1_rx     = FUNC1_CAN1_RX,
    mio49_sd1_wp      = FUNC2_SD1_WP,
    mio49_uart1_rx    = FUNC3_UART1_RX,
    mio49_gpio49      = FUNC4_GPIO,
    mio49_can0_clk    = FUNC5_CAN0_CLK,
    mio49_can1_clk    = FUNC6_CAN1_CLK,
    mio49_sd0_wp      = FUNC8_SD0_WP,
    mio49_spi1_ss_0   = FUNC9_SPI1_SEL0,
    mio49_sd1_4bit_data1   = FUNC10_SD1_4BIT_DATA1,
    mio49_sd0_8bit_data7   = FUNC11_SD0_8BIT_DATA7,
    mio49_sd0_cd      = FUNC12_SD0_CD,
    mio49_sd1_cd      = FUNC13_SD1_CD,
    mio49_usb1_data5  = FUNC15_USB1_DATA5,

    mio50_i2c0_scl    = FUNC0_IIC0_SCL,
    mio50_can0_rx     = FUNC1_CAN0_RX,
    mio50_sd1_wp      = FUNC2_SD1_WP,
    mio50_uart0_rx    = FUNC3_UART0_RX,
    mio50_gpio50      = FUNC4_GPIO,
    mio50_can0_clk    = FUNC5_CAN0_CLK,
    mio50_can1_clk    = FUNC6_CAN1_CLK,
    mio50_sd0_wp      = FUNC8_SD0_WP,
    mio50_spi1_ss_1   = FUNC9_SPI1_SEL1,
    mio50_sd1_4bit_data2   = FUNC10_SD1_4BIT_DATA2,
    mio50_sd0_pwr     = FUNC11_SD0_PWR,
    mio50_sd0_cd      = FUNC12_SD0_CD,
    mio50_sd1_cd      = FUNC13_SD1_CD,
    mio50_rgmii_0_phy_int = FUNC14_RGMII_0_PHY_INT,
    mio50_usb1_data6  = FUNC15_USB1_DATA6,

    mio51_i2c0_sda    = FUNC0_IIC0_SDA,
    mio51_can0_tx     = FUNC1_CAN0_TX,
    mio51_sd1_wp      = FUNC2_SD1_WP,
    mio51_uart0_tx    = FUNC3_UART0_TX,
    mio51_gpio51      = FUNC4_GPIO,
    mio51_can0_clk    = FUNC5_CAN0_CLK,
    mio51_can1_clk    = FUNC6_CAN1_CLK,
    mio51_sd0_wp      = FUNC8_SD0_WP,
    mio51_spi1_ss_2   = FUNC9_SPI1_SEL2,
    mio51_sd1_4bit_data3   = FUNC10_SD1_4BIT_DATA3,
    mio51_sd1_pwr     = FUNC11_SD1_PWR,
    mio51_sd0_cd      = FUNC12_SD0_CD,
    mio51_sd1_cd      = FUNC13_SD1_CD,
    mio51_rgmii_1_phy_int = FUNC14_RGMII_1_PHY_INT,
    mio51_usb1_data7  = FUNC15_USB1_DATA7,

    mio52_i2c1_scl    = FUNC0_IIC1_SCL,
    mio52_can1_tx     = FUNC1_CAN1_TX,
    mio52_sd1_wp      = FUNC2_SD1_WP,
    mio52_uart1_tx    = FUNC3_UART1_TX,
    mio52_gpio52      = FUNC4_GPIO,
    mio52_can0_clk    = FUNC5_CAN0_CLK,
    mio52_can1_clk    = FUNC6_CAN1_CLK,
    mio52_sd0_wp      = FUNC8_SD0_WP,
    mio52_sd0_pwr     = FUNC11_SD0_PWR,
    mio52_sd0_cd      = FUNC12_SD0_CD,
    mio52_sd1_cd      = FUNC13_SD1_CD,
    mio52_mdc0        = FUNC14_MDC0,
    mio52_mdc1        = FUNC15_MDC1,

    mio53_i2c1_sda    = FUNC0_IIC1_SDA,
    mio53_can1_rx     = FUNC1_CAN1_RX,
    mio53_sd1_wp      = FUNC2_SD1_WP,
    mio53_uart1_rx    = FUNC3_UART1_RX,
    mio53_gpio53      = FUNC4_GPIO,
    mio53_can0_clk    = FUNC5_CAN0_CLK,
    mio53_can1_clk    = FUNC6_CAN1_CLK,
    mio53_sd0_wp      = FUNC8_SD0_WP,
    mio53_sd1_pwr     = FUNC11_SD1_PWR,
    mio53_sd0_cd      = FUNC12_SD0_CD,
    mio53_sd1_cd      = FUNC13_SD1_CD,
    mio53_mdio0       = FUNC14_MDIO0,
    mio53_mdio1       = FUNC15_MDIO1
} AlPinctrl_FuncEnum;



AL_U32 AlPinctrl_Mio_SetFunction(AL_U32 MioPin, AlPinctrl_FuncEnum Func);
AL_U32 AlPinctrl_Emio_Select(AlPinctrl_GroupEnum Group, AlPinctrl_EmioSelEnum Select);
AL_U32 AlPinctrl_Mio_SetSpeed(AL_U32 MioPin, AlPinctrl_SpeedEnum Speed);
AL_U32 AlPinctrl_Mio_SetPullConfig(AL_U32 MioPin, AlPinctrl_PullEnum PullConfig,
                                   AlPinctrl_ResistorEnum Resistor);
AL_U32 AlPinctrl_Mio_SetElecConfig(AL_U32 MioPin,
                                   AlPinctrl_RecvModeEnum RecvMode,
                                   AlPinctrl_VoltageEnum Voltage,
                                   AlPinctrl_DriveEnum UpDrive,
                                   AlPinctrl_DriveEnum DownDrive);



#ifdef __cplusplus
}
#endif

#endif /* __AL_PINMUX_H_ */