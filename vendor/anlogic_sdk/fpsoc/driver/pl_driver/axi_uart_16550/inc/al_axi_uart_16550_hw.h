/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef AL_AXI_UART_16550_HW_H_
#define AL_AXI_UART_16550_HW_H_

#ifdef __cplusplus
extern "C" {
#endif


/***************************** Include Files ********************************/
#include "al_core.h"
#include <stdbool.h>

#ifndef AL_AXI_UART_16550_NUM_INSTANCE
#define AL_AXI_UART_16550_NUM_INSTANCE 1
#endif


typedef struct {
    AL_U32      DeviceId;
    AL_U64      BaseAddress;
    AL_U32      InputClockHz;
    AL_U32      IntrId;
    AL_U32      FifoDepth;
} AlAxiUart16550_HwConfigStruct;

/***************************** Register Offset ********************************/
#define AL_AXI_UART_16550_RX_FIFO_OFFSET       (0x1000 + 0x00)
#define AL_AXI_UART_16550_TX_FIFO_OFFSET       (0x1000 + 0x00)
#define AL_AXI_UART_16550_INTR_CR_OFFSET       (0x1000 + 0x04)
#define AL_AXI_UART_16550_INTR_SR_OFFSET       (0x1000 + 0x08)
#define AL_AXI_UART_16550_FIFO_CR_OFFSET       (0x1000 + 0x08)
#define AL_AXI_UART_16550_LINE_CR_OFFSET       (0x1000 + 0x0C)
#define AL_AXI_UART_16550_MODEM_CR_OFFSET      (0x1000 + 0x10)
#define AL_AXI_UART_16550_LINE_SR_OFFSET       (0x1000 + 0x14)
#define AL_AXI_UART_16550_MODEM_SR_OFFSET      (0x1000 + 0x18)
#define AL_AXI_UART_16550_SCRATCH_CR_OFFSET    (0x1000 + 0x1C)
#define AL_AXI_UART_16550_DLL_OFFSET           (0x1000 + 0x00)
#define AL_AXI_UART_16550_DLH_OFFSET           (0x1000 + 0x04)

/***************************** AL_AXI_UART_16550_INTR_CR Register    *****************************/
#define AL_AXI_UART_16550_INTR_CR_RECV_SHIFT        0
#define AL_AXI_UART_16550_INTR_CR_THRE_SHIFT        1
#define AL_AXI_UART_16550_INTR_CR_LINE_SHIFT        2
#define AL_AXI_UART_16550_INTR_CR_MODEM_SHIFT       3

/***************************** AL_AXI_UART_16550_INTR_SR Register   *****************************/
#define AL_AXI_UART_16550_INTR_SR_PEND_SHIFT        0

#define AL_AXI_UART_16550_INTR_SR_ID_SHIFT          0
#define AL_AXI_UART_16550_INTR_SR_ID_SIZE           4

/***************************** AL_AXI_UART_16550_FIFO_CR Register    *****************************/
#define AL_AXI_UART_16550_FIFO_CR_ENABLE_SHIFT            0
#define AL_AXI_UART_16550_FIFO_CR_RXFIFO_RESET_SHIFT      1
#define AL_AXI_UART_16550_FIFO_CR_TXFIFO_RESET_SHIFT      2
#define AL_AXI_UART_16550_FIFO_CR_DMA_MODE_SHIFT          3

#define AL_AXI_UART_16550_FIFO_CR_RXFIFO_LEVEL_SHIFT      6
#define AL_AXI_UART_16550_FIFO_CR_RXFIFO_LEVEL_SIZE       2

/***************************** AL_AXI_UART_16550_LINE_CR Register    *****************************/
#define AL_AXI_UART_16550_LINE_CR_WORD_LEN_SHIFT        0
#define AL_AXI_UART_16550_LINE_CR_WORD_LEN_SIZE         2

#define AL_AXI_UART_16550_LINE_CR_STOP_BIT_SHIFT        2
#define AL_AXI_UART_16550_LINE_CR_PARITY_SHIFT          3
#define AL_AXI_UART_16550_LINE_CR_PARITY_SIZE           2
#define AL_AXI_UART_16550_LINE_CR_PARITY_STICK_SHIFT    5
#define AL_AXI_UART_16550_LINE_CR_BREAK_SET_SHIFT       6
#define AL_AXI_UART_16550_LINE_CR_DLAB_SHIFT            7

/***************************** AL_AXI_UART_16550_MODEM_CR Register    *****************************/
// Current not use

/***************************** AL_AXI_UART_16550_LINE_SR Register    *****************************/
#define AL_AXI_UART_16550_LINE_SR_DR_SHIFT               0
#define AL_AXI_UART_16550_LINE_SR_OE_SHIFT               1
#define AL_AXI_UART_16550_LINE_SR_PE_SHIFT               2
#define AL_AXI_UART_16550_LINE_SR_FE_SHIFT               3
#define AL_AXI_UART_16550_LINE_SR_BI_SHIFT               4
#define AL_AXI_UART_16550_LINE_SR_THRE_SHIFT             5
#define AL_AXI_UART_16550_LINE_SR_TEMT_SHIFT             6
#define AL_AXI_UART_16550_LINE_SR_ERR_RCVR_FIFO_SHIFT    3

/***************************** AL_AXI_UART_16550_MODEM_SR Register    *****************************/
// Current not use

/***************************** AL_AXI_UART_16550_SCRATCH_CR Register    *****************************/
#define AL_AXI_UART_16550_SCRATCH_CR_DATA_SHIFT          0
#define AL_AXI_UART_16550_SCRATCH_CR_DATA_SIZE           8

/***************************** AL_AXI_UART_16550_DLL Register    *****************************/
#define AL_AXI_UART_16550_DLL_DATA_SHIFT                 0
#define AL_AXI_UART_16550_DLL_DATA_SIZE                  8

/***************************** AL_AXI_UART_16550_DLM Register    *****************************/
#define AL_AXI_UART_16550_DLM_DATA_SHIFT                 0
#define AL_AXI_UART_16550_DLM_DATA_SIZE                  8

#ifdef __cplusplus
}
#endif

#endif


