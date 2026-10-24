/*
 * Copyright (c) 2025, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/***************************** Include Files *********************************/

#ifndef __AL_AXI_CANFD_HW_H__
#define __AL_AXI_CANFD_HW_H__

#include "al_type.h"
#include "al_core.h"
#include "soc_plat.h"

#ifndef AL_AXI_CANFD_NUM_INSTANCE
#define AL_AXI_CANFD_NUM_INSTANCE    1
#endif

///////////////////////////////////////////////////////
// Register: Software Reset Register
// Software Reset Register
///////////////////////////////////////////////////////

#define AXI_CANFD_SW_RST_OFFSET         0x00ULL
#define AXI_CANFD_SW_RST_SRST_SHIFT                 0
#define AXI_CANFD_SW_RST_CEN_SHIFT            1

#define AXI_CANFD_SW_RST_SRST_SIZE                0
#define AXI_CANFD_SW_RST_CEN_SIZE           1

///////////////////////////////////////////////////////
// Register: Mode Select Register
// Mode Select Register
///////////////////////////////////////////////////////
#define AXI_CANFD_MODE_SEL_OFFSET         0x04ULL
#define AXI_CANFD_MODE_SEL_SLEEP_SHIFT                 0
#define AXI_CANFD_MODE_SEL_LBACK_SHIFT            1
#define AXI_CANFD_MODE_SEL_SNOOP_SHIFT            2
#define AXI_CANFD_MODE_SEL_BRSD_SHIFT             3
#define AXI_CANFD_MODE_SEL_DAR_SHIFT              4
#define AXI_CANFD_MODE_SEL_DPEE_SHIFT             5
#define AXI_CANFD_MODE_SEL_SBR_SHIFT              6
#define AXI_CANFD_MODE_SEL_ABR_SHIFT              7
#define AXI_CANFD_MODE_SEL_ITO_SHIFT              8

#define AXI_CANFD_MODE_SEL_SLEEP_SIZE                1
#define AXI_CANFD_MODE_SEL_LBACK_SIZE           1
#define AXI_CANFD_MODE_SEL_SNOOP_SIZE           1
#define AXI_CANFD_MODE_SEL_BRSD_SIZE            1
#define AXI_CANFD_MODE_SEL_DAR_SIZE             1
#define AXI_CANFD_MODE_SEL_DPEE_SIZE            1
#define AXI_CANFD_MODE_SEL_SBR_SIZE             1
#define AXI_CANFD_MODE_SEL_ABR_SIZE             1
#define AXI_CANFD_MODE_SEL_ITO_SIZE             8

#define AXI_CANFD_MODE_SEL_MODE_MASK            ((1 << AXI_CANFD_MODE_SEL_SLEEP_SHIFT) |\
                                                 (1 << AXI_CANFD_MODE_SEL_LBACK_SHIFT) |\
                                                 (1 << AXI_CANFD_MODE_SEL_SNOOP_SHIFT))

///////////////////////////////////////////////////////
// Register: Arbitration Phase (Nominal) Baud Rate Prescaler Register
// Arbitration Phase (Nominal) Baud Rate Prescaler Register
///////////////////////////////////////////////////////
#define AXI_CANFD_BRP_OFFSET         0x08ULL
#define AXI_CANFD_BRP_BRP_SHIFT                 0

#define AXI_CANFD_BRP_BRP_SIZE                8

///////////////////////////////////////////////////////
// Register: Arbitration Phase (Nominal) Bit Timing Register
// Arbitration Phase (Nominal) Bit Timing Register
///////////////////////////////////////////////////////
#define AXI_CANFD_APBT_OFFSET         0x0CULL
#define AXI_CANFD_APBT_TS1_SHIFT                 0
#define AXI_CANFD_APBT_TS2_SHIFT            8
#define AXI_CANFD_APBT_SJW_SHIFT            16

#define AXI_CANFD_APBT_TS1_SIZE                8
#define AXI_CANFD_APBT_TS2_SIZE           7
#define AXI_CANFD_APBT_SJW_SIZE           7

///////////////////////////////////////////////////////
// Register: Error Count Register
// Error Count Register
///////////////////////////////////////////////////////
#define AXI_CANFD_ERR_CNT_OFFSET         0x10ULL
#define AXI_CANFD_ERR_CNT_TEC_SHIFT                 0
#define AXI_CANFD_ERR_CNT_REC_SHIFT            8

#define AXI_CANFD_ERR_CNT_TEC_SIZE                8
#define AXI_CANFD_ERR_CNT_REC_SIZE           8

///////////////////////////////////////////////////////
// Register: Error Status Register
// Error Status Register
///////////////////////////////////////////////////////
#define AXI_CANFD_ERR_STS_OFFSET         0x14ULL
#define AXI_CANFD_ERR_STS_CRCER_SHIFT                 0
#define AXI_CANFD_ERR_STS_FMER_SHIFT            1
#define AXI_CANFD_ERR_STS_STER_SHIFT            2
#define AXI_CANFD_ERR_STS_BERR_SHIFT             3
#define AXI_CANFD_ERR_STS_ACKER_SHIFT             4
#define AXI_CANFD_ERR_STS_F_CRCER_SHIFT             8
#define AXI_CANFD_ERR_STS_F_FMER_SHIFT             9
#define AXI_CANFD_ERR_STS_F_STER_SHIFT             10
#define AXI_CANFD_ERR_STS_F_BERR_SHIFT             11

#define AXI_CANFD_ERR_STS_CRCER_SIZE                1
#define AXI_CANFD_ERR_STS_FMER_SIZE           1
#define AXI_CANFD_ERR_STS_STER_SIZE           1
#define AXI_CANFD_ERR_STS_BERR_SIZE            1
#define AXI_CANFD_ERR_STS_ACKER_SIZE            1
#define AXI_CANFD_ERR_STS_F_CRCER_SIZE            1
#define AXI_CANFD_ERR_STS_F_FMER_SIZE            1
#define AXI_CANFD_ERR_STS_F_STER_SIZE            1
#define AXI_CANFD_ERR_STS_F_BERR_SIZE            1

///////////////////////////////////////////////////////
// Register: Status Register
// Status Register
///////////////////////////////////////////////////////
#define AXI_CANFD_STS_OFFSET         0x18ULL
#define AXI_CANFD_STS_CONFIG_SHIFT                 0
#define AXI_CANFD_STS_LBACK_SHIFT            1
#define AXI_CANFD_STS_SLEEP_SHIFT            2
#define AXI_CANFD_STS_NORMAL_SHIFT             3
#define AXI_CANFD_STS_BIDLE_SHIFT             4
#define AXI_CANFD_STS_BBSY_SHIFT             5
#define AXI_CANFD_STS_ERRWRN_SHIFT             6
#define AXI_CANFD_STS_ESTAT_SHIFT             7
#define AXI_CANFD_STS_PEE_CONFIG_SHIFT             9
#define AXI_CANFD_STS_BSFR_CONFIG_SHIFT             10
#define AXI_CANFD_STS_SNOOP_SHIFT             12
#define AXI_CANFD_STS_TDCV_SHIFT             16

#define AXI_CANFD_STS_CONFIG_SIZE                1
#define AXI_CANFD_STS_LBACK_SIZE           1
#define AXI_CANFD_STS_SLEEP_SIZE           1
#define AXI_CANFD_STS_NORMAL_SIZE            1
#define AXI_CANFD_STS_BIDLE_SIZE            1
#define AXI_CANFD_STS_BBSY_SIZE            1
#define AXI_CANFD_STS_ERRWRN_SIZE            1
#define AXI_CANFD_STS_ESTAT_SIZE            2
#define AXI_CANFD_STS_PEE_CONFIG_SIZE            1
#define AXI_CANFD_STS_BSFR_CONFIG_SIZE            1
#define AXI_CANFD_STS_SNOOP_SIZE            1
#define AXI_CANFD_STS_TDCV_SIZE            7

#define AXI_CANFD_STS_MODE_MASK            ((1 << AXI_CANFD_STS_CONFIG_SHIFT) |\
                                            (1 << AXI_CANFD_STS_LBACK_SHIFT) |\
                                            (1 << AXI_CANFD_STS_SLEEP_SHIFT) |\
                                            (1 << AXI_CANFD_STS_NORMAL_SHIFT) |\
                                            (1 << AXI_CANFD_STS_SNOOP_SHIFT))

///////////////////////////////////////////////////////
// Register: Interrupt Status Register
// Interrupt Status Register
///////////////////////////////////////////////////////
#define AXI_CANFD_INT_STS_OFFSET         0x1CULL
#define AXI_CANFD_INT_STS_ARBLST_SHIFT                 0
#define AXI_CANFD_INT_STS_TXOK_SHIFT            1
#define AXI_CANFD_INT_STS_PEE_SHIFT            2
#define AXI_CANFD_INT_STS_BSFRD_SHIFT             3
#define AXI_CANFD_INT_STS_RXOK_SHIFT             4
#define AXI_CANFD_INT_STS_TSCNT_OFLW_SHIFT             5
#define AXI_CANFD_INT_STS_RXFOFLW_SHIFT             6
#define AXI_CANFD_INT_STS_ERROR_SHIFT             8
#define AXI_CANFD_INT_STS_BSOFF_SHIFT             9
#define AXI_CANFD_INT_STS_SLP_SHIFT             10
#define AXI_CANFD_INT_STS_WKUP_SHIFT             11
#define AXI_CANFD_INT_STS_RXFWMFLL_SHIFT             12
#define AXI_CANFD_INT_STS_TXRRS_SHIFT             13
#define AXI_CANFD_INT_STS_TXCRS_SHIFT             14
#define AXI_CANFD_INT_STS_RXRBF_RXFOFLW_1_SHIFT             15
#define AXI_CANFD_INT_STS_RXBOFLW_RXFWMFLL_1_SHIFT             16
#define AXI_CANFD_INT_STS_RXMNF_SHIFT             17
#define AXI_CANFD_INT_STS_RXLRM_BI_SHIFT             18
#define AXI_CANFD_INT_STS_RXBOFLW_BI_SHIFT             24
#define AXI_CANFD_INT_STS_TXEOFLW_SHIFT             30
#define AXI_CANFD_INT_STS_TXEWMFLL_SHIFT             31

#define AXI_CANFD_INT_STS_ARBLST_SIZE                1
#define AXI_CANFD_INT_STS_TXOK_SIZE           1
#define AXI_CANFD_INT_STS_PEE_SIZE           1
#define AXI_CANFD_INT_STS_BSFRD_SIZE            1
#define AXI_CANFD_INT_STS_RXOK_SIZE            1
#define AXI_CANFD_INT_STS_TSCNT_OFLW_SIZE            1
#define AXI_CANFD_INT_STS_RXFOFLW_SIZE            1
#define AXI_CANFD_INT_STS_ERROR_SIZE            1
#define AXI_CANFD_INT_STS_BSOFF_SIZE            1
#define AXI_CANFD_INT_STS_SLP_SIZE            1
#define AXI_CANFD_INT_STS_WKUP_SIZE            1
#define AXI_CANFD_INT_STS_RXFWMFLL_SIZE            1
#define AXI_CANFD_INT_STS_TXRRS_SIZE            1
#define AXI_CANFD_INT_STS_TXCRS_SIZE            1
#define AXI_CANFD_INT_STS_RXRBF_RXFOFLW_1_SIZE            1
#define AXI_CANFD_INT_STS_RXBOFLW_RXFWMFLL_1_SIZE            1
#define AXI_CANFD_INT_STS_RXMNF_SIZE            1
#define AXI_CANFD_INT_STS_RXLRM_BI_SIZE            6
#define AXI_CANFD_INT_STS_RXBOFLW_BI_SIZE            6
#define AXI_CANFD_INT_STS_TXEOFLW_SIZE            1
#define AXI_CANFD_INT_STS_TXEWMFLL_SIZE            1

#define AXI_CANFD_INT_STS_RXLRM_BI_MASK         0x00FC0000U


///////////////////////////////////////////////////////
// Register: Interrupt Enable Register
// Interrupt Enable Register
///////////////////////////////////////////////////////
#define AXI_CANFD_INT_EN_OFFSET         0x20ULL
#define AXI_CANFD_INT_EN_ARBLST_SHIFT                 0
#define AXI_CANFD_INT_EN_TXOK_SHIFT            1
#define AXI_CANFD_INT_EN_PEE_SHIFT            2
#define AXI_CANFD_INT_EN_BSFRD_SHIFT             3
#define AXI_CANFD_INT_EN_RXOK_SHIFT             4
#define AXI_CANFD_INT_EN_TSCNT_OFLW_SHIFT             5
#define AXI_CANFD_INT_EN_RXFOFLW_SHIFT             6
#define AXI_CANFD_INT_EN_ERROR_SHIFT             8
#define AXI_CANFD_INT_EN_BSOFF_SHIFT             9
#define AXI_CANFD_INT_EN_SLP_SHIFT             10
#define AXI_CANFD_INT_EN_WKUP_SHIFT             11
#define AXI_CANFD_INT_EN_RXFWMFLL_SHIFT             12
#define AXI_CANFD_INT_EN_TXRRS_SHIFT             13
#define AXI_CANFD_INT_EN_TXCRS_SHIFT             14
#define AXI_CANFD_INT_EN_RXRBF_RXFOFLW_1_SHIFT             15
#define AXI_CANFD_INT_EN_RXBOFLW_RXFWMFLL_1_SHIFT             16
#define AXI_CANFD_INT_EN_RXMNF_SHIFT             17
#define AXI_CANFD_INT_EN_TXEOFLW_SHIFT             30
#define AXI_CANFD_INT_EN_TXEWMFLL_SHIFT             31

#define AXI_CANFD_INT_EN_ARBLST_SIZE                1
#define AXI_CANFD_INT_EN_TXOK_SIZE           1
#define AXI_CANFD_INT_EN_PEE_SIZE           1
#define AXI_CANFD_INT_EN_BSFRD_SIZE            1
#define AXI_CANFD_INT_EN_RXOK_SIZE            1
#define AXI_CANFD_INT_EN_TSCNT_OFLW_SIZE            1
#define AXI_CANFD_INT_EN_RXFOFLW_SIZE            1
#define AXI_CANFD_INT_EN_ERROR_SIZE            1
#define AXI_CANFD_INT_EN_BSOFF_SIZE            1
#define AXI_CANFD_INT_EN_SLP_SIZE            1
#define AXI_CANFD_INT_EN_WKUP_SIZE            1
#define AXI_CANFD_INT_EN_RXFWMFLL_SIZE            1
#define AXI_CANFD_INT_EN_TXRRS_SIZE            1
#define AXI_CANFD_INT_EN_TXCRS_SIZE            1
#define AXI_CANFD_INT_EN_RXRBF_RXFOFLW_1_SIZE            1
#define AXI_CANFD_INT_EN_RXBOFLW_RXFWMFLL_1_SIZE            1
#define AXI_CANFD_INT_EN_RXMNF_SIZE            1
#define AXI_CANFD_INT_EN_TXEOFLW_SIZE            1
#define AXI_CANFD_INT_EN_TXEWMFLL_SIZE            1

#define AXI_CANFD_TX_INTR_MASK      ((1U << AXI_CANFD_INT_EN_TXOK_SHIFT) | (1U << AXI_CANFD_INT_EN_RXFWMFLL_SHIFT) | \
                                     (1U << AXI_CANFD_INT_EN_TXCRS_SHIFT) | (1U << AXI_CANFD_INT_EN_TXEWMFLL_SHIFT))
#define AXI_CANFD_RX_INTR_MASK      ((1U << AXI_CANFD_INT_EN_RXOK_SHIFT) | (1U << AXI_CANFD_INT_EN_RXMNF_SHIFT) | \
                                     (1U << AXI_CANFD_INT_EN_RXRBF_RXFOFLW_1_SHIFT) | (1U << AXI_CANFD_INT_EN_RXBOFLW_RXFWMFLL_1_SHIFT))

///////////////////////////////////////////////////////
// Register: Interrupt Clear Register
// Interrupt Clear Register
///////////////////////////////////////////////////////
#define AXI_CANFD_INT_CLR_OFFSET         0x24ULL
#define AXI_CANFD_INT_CLR_ARBLST_SHIFT                 0
#define AXI_CANFD_INT_CLR_TXOK_SHIFT            1
#define AXI_CANFD_INT_CLR_PEE_SHIFT            2
#define AXI_CANFD_INT_CLR_BSFRD_SHIFT             3
#define AXI_CANFD_INT_CLR_RXOK_SHIFT             4
#define AXI_CANFD_INT_CLR_TSCNT_OFLW_SHIFT             5
#define AXI_CANFD_INT_CLR_RXFOFLW_SHIFT             6
#define AXI_CANFD_INT_CLR_ERROR_SHIFT             8
#define AXI_CANFD_INT_CLR_BSOFF_SHIFT             9
#define AXI_CANFD_INT_CLR_SLP_SHIFT             10
#define AXI_CANFD_INT_CLR_WKUP_SHIFT             11
#define AXI_CANFD_INT_CLR_RXFWMFLL_SHIFT             12
#define AXI_CANFD_INT_CLR_TXRRS_SHIFT             13
#define AXI_CANFD_INT_CLR_TXCRS_SHIFT             14
#define AXI_CANFD_INT_CLR_RXRBF_RXFOFLW_1_SHIFT             15
#define AXI_CANFD_INT_CLR_RXBOFLW_RXFWMFLL_1_SHIFT             16
#define AXI_CANFD_INT_CLR_RXMNF_SHIFT             17
#define AXI_CANFD_INT_CLR_TXEOFLW_SHIFT             30
#define AXI_CANFD_INT_CLR_TXEWMFLL_SHIFT             31

#define AXI_CANFD_INT_CLR_ARBLST_SIZE                1
#define AXI_CANFD_INT_CLR_TXOK_SIZE           1
#define AXI_CANFD_INT_CLR_PEE_SIZE           1
#define AXI_CANFD_INT_CLR_BSFRD_SIZE            1
#define AXI_CANFD_INT_CLR_RXOK_SIZE            1
#define AXI_CANFD_INT_CLR_TSCNT_OFLW_SIZE            1
#define AXI_CANFD_INT_CLR_RXFOFLW_SIZE            1
#define AXI_CANFD_INT_CLR_ERROR_SIZE            1
#define AXI_CANFD_INT_CLR_BSOFF_SIZE            1
#define AXI_CANFD_INT_CLR_SLP_SIZE            1
#define AXI_CANFD_INT_CLR_WKUP_SIZE            1
#define AXI_CANFD_INT_CLR_RXFWMFLL_SIZE            1
#define AXI_CANFD_INT_CLR_TXRRS_SIZE            1
#define AXI_CANFD_INT_CLR_TXCRS_SIZE            1
#define AXI_CANFD_INT_CLR_RXRBF_RXFOFLW_1_SIZE            1
#define AXI_CANFD_INT_CLR_RXBOFLW_RXFWMFLL_1_SIZE            1
#define AXI_CANFD_INT_CLR_RXMNF_SIZE            1
#define AXI_CANFD_INT_CLR_TXEOFLW_SIZE            1
#define AXI_CANFD_INT_CLR_TXEWMFLL_SIZE            1


///////////////////////////////////////////////////////
// Register: Timestamp Register
// Timestamp Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TS_OFFSET         0x28ULL
#define AXI_CANFD_TS_CTS_SHIFT                 0
#define AXI_CANFD_TS_TS_CNT_SHIFT                16

#define AXI_CANFD_TS_CTS_SIZE                1
#define AXI_CANFD_TS_TS_CNT_SIZE           16

///////////////////////////////////////////////////////
// Register: Data Phase Baud Rate Prescaler Register
// Data Phase Baud Rate Prescaler Register
///////////////////////////////////////////////////////
#define AXI_CANFD_DPBRP_OFFSET         0x88ULL
#define AXI_CANFD_DPBRP_DP_BRP_SHIFT                 0
#define AXI_CANFD_DPBRP_TDCOFF_SHIFT                8
#define AXI_CANFD_DPBRP_TDC_SHIFT                16

#define AXI_CANFD_DPBRP_DP_BRP_SIZE                8
#define AXI_CANFD_DPBRP_TDCOFF_SIZE           6
#define AXI_CANFD_DPBRP_TDC_SIZE           1

///////////////////////////////////////////////////////
// Register: Data Phase Bit Timing Register
// Data Phase Bit Timing Register
///////////////////////////////////////////////////////
#define AXI_CANFD_DPBT_OFFSET         0x8CULL
#define AXI_CANFD_DPBT_DP_TS1_SHIFT                 0
#define AXI_CANFD_DPBT_DP_TS2_SHIFT                8
#define AXI_CANFD_DPBT_DP_SJW_SHIFT                16

#define AXI_CANFD_DPBT_DP_TS1_SIZE                5
#define AXI_CANFD_DPBT_DP_TS2_SIZE           4
#define AXI_CANFD_DPBT_DP_SJW_SIZE           4

///////////////////////////////////////////////////////
// Register: TX Buffer Ready Request Register
// TX Buffer Ready Request Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TBRR_OFFSET         0x90ULL
#define AXI_CANFD_TBRR_RR_SHIFT              0

#define AXI_CANFD_TBRR_RR_SIZE                32

///////////////////////////////////////////////////////
// Register: Interrupt Enable TX Buffer Ready Request Served/Cleared
// Interrupt Enable TX Buffer Ready Request Served/Cleared
///////////////////////////////////////////////////////
#define AXI_CANFD_INT_EN_TBRR_OFFSET         0x94ULL
#define AXI_CANFD_INT_EN_TBRR_RR_SHIFT              0

#define AXI_CANFD_INT_EN_TBRR_RR_SIZE                32

///////////////////////////////////////////////////////
// Register: TX Buffer Cancel Request
// TX Buffer Cancel Request
///////////////////////////////////////////////////////
#define AXI_CANFD_TBCR_OFFSET         0x98ULL
#define AXI_CANFD_TBCR_CR_SHIFT              0

#define AXI_CANFD_TBCR_CR_SIZE                32

///////////////////////////////////////////////////////
// Register: Interrupt Enable TX Buffer Cancellation Served/Cleared
// Interrupt Enable TX Buffer Cancellation Served/Cleared
///////////////////////////////////////////////////////
#define AXI_CANFD_INT_EN_TBCSC_OFFSET         0x9CULL
#define AXI_CANFD_INT_EN_TBCSC_ECRS_SHIFT              0

#define AXI_CANFD_INT_EN_TBCSC_ECRS_SIZE                32

///////////////////////////////////////////////////////
// Register: TX Event FIFO Status Register
// TX Event FIFO Status Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TXE_FIFO_STS_OFFSET         0xA0ULL
#define AXI_CANFD_TXE_FIFO_STS_TXE_RI_SHIFT              0
#define AXI_CANFD_TXE_FIFO_STS_TXE_IRI_SHIFT              7
#define AXI_CANFD_TXE_FIFO_STS_TXE_FL_SHIFT              8

#define AXI_CANFD_TXE_FIFO_STS_TXE_RI_SIZE                5
#define AXI_CANFD_TXE_FIFO_STS_TXE_IRI_SIZE                1
#define AXI_CANFD_TXE_FIFO_STS_TXE_FL_SIZE                6

///////////////////////////////////////////////////////
// Register: TX Event FIFO Watermark Register
// TX Event FIFO Watermark Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TXE_FIFO_WM_OFFSET         0xA4ULL
#define AXI_CANFD_TXE_FIFO_WM_TXE_FWM_SHIFT              0

#define AXI_CANFD_TXE_FIFO_WM_TXE_FWM_SIZE                5

///////////////////////////////////////////////////////
// Register: RX Buffer Control Status Register 0
// RX Buffer Control Status Register 0
///////////////////////////////////////////////////////
#define AXI_CANFD_RXBC_STS0_OFFSET         0xB0ULL
#define AXI_CANFD_RXBC_STS0_HCB_SHIFT              0
#define AXI_CANFD_RXBC_STS0_CSB_SHIFT              16

#define AXI_CANFD_RXBC_STS0_HCB_SIZE                16
#define AXI_CANFD_RXBC_STS0_CSB_SIZE                16


///////////////////////////////////////////////////////
// Register: RX Buffer Control Status Register 1
// RX Buffer Control Status Register 1
///////////////////////////////////////////////////////

///////////////////////////////////////////////////////
// Register: RX Buffer Control Status Register 2
// RX Buffer Control Status Register 2
///////////////////////////////////////////////////////

///////////////////////////////////////////////////////
// Register: Interrupt Enable RX Buffer Full Register 0
// Interrupt Enable RX Buffer Full Register 0
///////////////////////////////////////////////////////
#define AXI_CANFD_INT_EN_RXBF0_OFFSET         0xC0ULL
#define AXI_CANFD_INT_EN_RXBF0_RBF0_SHIFT              0

#define AXI_CANFD_INT_EN_RXBF0_RBF0_SIZE                32

///////////////////////////////////////////////////////
// Register: Interrupt Enable RX Buffer Full Register 1
// Interrupt Enable RX Buffer Full Register 1
///////////////////////////////////////////////////////
#define AXI_CANFD_INT_EN_RXBF1_OFFSET         0xC4ULL
#define AXI_CANFD_INT_EN_RXBF1_RBF32_SHIFT              0

#define AXI_CANFD_INT_EN_RXBF1_RBF32_SIZE                16

///////////////////////////////////////////////////////
// Register: Acceptance Filter (Control) Register
// Acceptance Filter (Control) Register
///////////////////////////////////////////////////////
#define AXI_CANFD_AF_OFFSET         0xE0ULL
#define AXI_CANFD_AF_UAF0_SHIFT              0

#define AXI_CANFD_AF_UAF0_SIZE                32

///////////////////////////////////////////////////////
// Register: RX FIFO Status Register
// RX FIFO Status Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RXF_STS_OFFSET         0xE8ULL
#define AXI_CANFD_RXF_STS_RI_SHIFT              0
#define AXI_CANFD_RXF_STS_IRI_SHIFT              7
#define AXI_CANFD_RXF_STS_FL_SHIFT              8
#define AXI_CANFD_RXF_STS_RI_1_SHIFT              16
#define AXI_CANFD_RXF_STS_IRI_1_SHIFT              23
#define AXI_CANFD_RXF_STS_FL_1_SHIFT              24

#define AXI_CANFD_RXF_STS_RI_SIZE                6
#define AXI_CANFD_RXF_STS_IRI_SIZE                1
#define AXI_CANFD_RXF_STS_FL_SIZE                7
#define AXI_CANFD_RXF_STS_RI_1_SIZE                6
#define AXI_CANFD_RXF_STS_IRI_1_SIZE                1
#define AXI_CANFD_RXF_STS_FL_1_SIZE                7

#define AXI_CANFD_RXF_STS_RI_MASK           0x0000003FU
#define AXI_CANFD_RXF_STS_FL_MASK           0x00007F00U
#define AXI_CANFD_RXF_STS_RI_1_MASK           0x003F0000U
#define AXI_CANFD_RXF_STS_FL_1_MASK           0x7F000000U

///////////////////////////////////////////////////////
// Register: RX FIFO Watermark Register
// RX FIFO Watermark Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RXF_WM_OFFSET         0xECULL
#define AXI_CANFD_RXF_WM_RXFWM_SHIFT              0
#define AXI_CANFD_RXF_WM_RXFWM_1_SHIFT              8
#define AXI_CANFD_RXF_WM_RXFP_SHIFT              16

#define AXI_CANFD_RXF_WM_RXFWM_SIZE                6
#define AXI_CANFD_RXF_WM_RXFWM_1_SIZE                6
#define AXI_CANFD_RXF_WM_RXFP_SIZE                5

///////////////////////////////////////////////////////
// Register: TB*-ID Register
// TB*-ID Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TB_ID_OFFSET(Index)         (0x100ULL + ((Index) * 0x48))
#define AXI_CANFD_TB_ID_RTR_RRS_SHIFT              0
#define AXI_CANFD_TB_ID_EXT_ID_SHIFT              1
#define AXI_CANFD_TB_ID_IDE_SHIFT              19
#define AXI_CANFD_TB_ID_SRR_RTR_RRS_SHIFT              20
#define AXI_CANFD_TB_ID_ID_SHIFT              21

#define AXI_CANFD_TB_ID_RTR_RRS_SIZE                1
#define AXI_CANFD_TB_ID_EXT_ID_SIZE                18
#define AXI_CANFD_TB_ID_IDE_SIZE                1
#define AXI_CANFD_TB_ID_SRR_RTR_RRS_SIZE                1
#define AXI_CANFD_TB_ID_ID_SIZE                11

#define AXI_CANFD_TX_MSG_SPACE_NUM                 32
#define AXI_CANFD_TX_MSG_SPACE_SIZE                 0x48U

///////////////////////////////////////////////////////
// Register: TB*-DLC Register
// TB*-DLC Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TB_DLC_OFFSET(Index)         (0x104ULL + ((Index) * 0x48))
#define AXI_CANFD_TB_DLC_MM_SHIFT              16
#define AXI_CANFD_TB_DLC_EFC_SHIFT              24
#define AXI_CANFD_TB_DLC_BRS_SHIFT              26
#define AXI_CANFD_TB_DLC_EDL_FDF_SHIFT              27
#define AXI_CANFD_TB_DLC_DLC_SHIFT              28

#define AXI_CANFD_TB_DLC_MM_SIZE                8
#define AXI_CANFD_TB_DLC_EFC_SIZE                1
#define AXI_CANFD_TB_DLC_BRS_SIZE                1
#define AXI_CANFD_TB_DLC_EDL_FDF_SIZE                1
#define AXI_CANFD_TB_DLC_DLC_SIZE                4

///////////////////////////////////////////////////////
// Register: TB*-DW0 Register
// TB*-DW0 Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TB_DW0_OFFSET(Index)         (0x108ULL + ((Index) * 0x48))
#define AXI_CANFD_TB_DW0_DATA3_SHIFT              0
#define AXI_CANFD_TB_DW0_DATA2_SHIFT              8
#define AXI_CANFD_TB_DW0_DATA1_SHIFT              16
#define AXI_CANFD_TB_DW0_DATA0_SHIFT              24

#define AXI_CANFD_TB_DW0_DATA3_SIZE                8
#define AXI_CANFD_TB_DW0_DATA2_SIZE                8
#define AXI_CANFD_TB_DW0_DATA1_SIZE                8
#define AXI_CANFD_TB_DW0_DATA0_SIZE                8

#define AXI_CANFD_TB_DW_REG_NUM                  16

///////////////////////////////////////////////////////
// Register: TX Event FIFO TB-ID Status Register
// TX Event FIFO TB-ID Status Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TXE_FIFO_TB_ID_OFFSET(Index)         (0x2000ULL + ((Index) * 0x8))
#define AXI_CANFD_TXE_FIFO_TB_ID_RTR_RRS_SHIFT              0
#define AXI_CANFD_TXE_FIFO_TB_ID_EXT_ID_SHIFT              1
#define AXI_CANFD_TXE_FIFO_TB_ID_IDE_SHIFT              19
#define AXI_CANFD_TXE_FIFO_TB_ID_SRR_RTR_RRS_SHIFT              20
#define AXI_CANFD_TXE_FIFO_TB_ID_ID_SHIFT              21

#define AXI_CANFD_TXE_FIFO_TB_ID_RTR_RRS_SIZE                1
#define AXI_CANFD_TXE_FIFO_TB_ID_EXT_ID_SIZE                18
#define AXI_CANFD_TXE_FIFO_TB_ID_IDE_SIZE                1
#define AXI_CANFD_TXE_FIFO_TB_ID_SRR_RTR_RRS_SIZE                1
#define AXI_CANFD_TXE_FIFO_TB_ID_ID_SIZE                11

///////////////////////////////////////////////////////
// Register:TX Event FIFO TB-DLC Status Register
// TX Event FIFO TB-DLC Status Register
///////////////////////////////////////////////////////
#define AXI_CANFD_TXE_FIFO_TB_DLC_OFFSET(Index)         (0x2004ULL + ((Index) * 0x8))
#define AXI_CANFD_TXE_FIFO_TB_DLC_TS_SHIFT              0
#define AXI_CANFD_TXE_FIFO_TB_DLC_MM_SHIFT              16
#define AXI_CANFD_TXE_FIFO_TB_DLC_ET_SHIFT              24
#define AXI_CANFD_TXE_FIFO_TB_DLC_BRS_SHIFT              26
#define AXI_CANFD_TXE_FIFO_TB_DLC_FDF_SHIFT              27
#define AXI_CANFD_TXE_FIFO_TB_DLC_DLC_SHIFT              28

#define AXI_CANFD_TXE_FIFO_TB_DLC_TS_SIZE                16
#define AXI_CANFD_TXE_FIFO_TB_DLC_MM_SIZE                8
#define AXI_CANFD_TXE_FIFO_TB_DLC_ET_SIZE                2
#define AXI_CANFD_TXE_FIFO_TB_DLC_BRS_SIZE                1
#define AXI_CANFD_TXE_FIFO_TB_DLC_FDF_SIZE                1
#define AXI_CANFD_TXE_FIFO_TB_DLC_DLC_SIZE                4


///////////////////////////////////////////////////////
// Register: RB*-ID Register
// RB*-ID Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RB_ID_OFFSET(FifoNo, Index)         ((((FifoNo) == 0) ? 0x2100ULL : 0x4100ULL) + ((Index) * 0x48))
#define AXI_CANFD_RB_ID_RTR_RRS_SHIFT              0
#define AXI_CANFD_RB_ID_EXT_ID_SHIFT              1
#define AXI_CANFD_RB_ID_IDE_SHIFT              19
#define AXI_CANFD_RB_ID_SRR_RTR_RRS_SHIFT              20
#define AXI_CANFD_RB_ID_ID_SHIFT              21

#define AXI_CANFD_RB_ID_RTR_RRS_SIZE                1
#define AXI_CANFD_RB_ID_EXT_ID_SIZE                18
#define AXI_CANFD_RB_ID_IDE_SIZE                1
#define AXI_CANFD_RB_ID_SRR_RTR_RRS_SIZE                1
#define AXI_CANFD_RB_ID_ID_SIZE                11

///////////////////////////////////////////////////////
// Register: RB*-DLC Register
// RB*-DLC Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RB_DLC_OFFSET(FifoNo, Index)         ((((FifoNo) == 0) ? 0x2104ULL : 0x4104ULL) + ((Index) * 0x48))
#define AXI_CANFD_RB_DLC_TS_SHIFT              0
#define AXI_CANFD_RB_DLC_MATCHED_FILTER_IDX_SHIFT              16
#define AXI_CANFD_RB_DLC_ESI_SHIFT              25
#define AXI_CANFD_RB_DLC_BRS_SHIFT              26
#define AXI_CANFD_RB_DLC_EDL_FDF_SHIFT              27
#define AXI_CANFD_RB_DLC_DLC_SHIFT              28

#define AXI_CANFD_RB_DLC_TS_SIZE                16
#define AXI_CANFD_RB_DLC_MATCHED_FILTER_IDX_SIZE                5
#define AXI_CANFD_RB_DLC_ESI_SIZE                1
#define AXI_CANFD_RB_DLC_BRS_SIZE                1
#define AXI_CANFD_RB_DLC_EDL_FDF_SIZE                1
#define AXI_CANFD_RB_DLC_DLC_SIZE                4

///////////////////////////////////////////////////////
// Register: RB*-DW0 Register
// RB*-DW0 Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RB_DW0_OFFSET(FifoNo, Index)         ((((FifoNo) == 0) ? 0x2108ULL : 0x4108ULL) + ((Index) * 0x48))
#define AXI_CANFD_RB_DW0_DATA3_SHIFT              0
#define AXI_CANFD_RB_DW0_DATA2_SHIFT              8
#define AXI_CANFD_RB_DW0_DATA1_SHIFT              16
#define AXI_CANFD_RB_DW0_DATA0_SHIFT              24

#define AXI_CANFD_RB_DW0_DATA3_SIZE                8
#define AXI_CANFD_RB_DW0_DATA2_SIZE                8
#define AXI_CANFD_RB_DW0_DATA1_SIZE                8
#define AXI_CANFD_RB_DW0_DATA0_SIZE                8

#define AXI_CANFD_RB_DW_REG_NUM                  16

///////////////////////////////////////////////////////
// Register: RB*-1-ID Register
// RB*-ID Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RB_1_ID_OFFSET(Index)         (0x4100ULL + ((Index) * 0x48))
#define AXI_CANFD_RB_1_ID_RTR_RRS_SHIFT              0
#define AXI_CANFD_RB_1_ID_EXT_ID_SHIFT              1
#define AXI_CANFD_RB_1_ID_IDE_SHIFT              19
#define AXI_CANFD_RB_1_ID_SRR_RTR_RRS_SHIFT              20
#define AXI_CANFD_RB_1_ID_ID_SHIFT              21

#define AXI_CANFD_RB_1_ID_RTR_RRS_SIZE                1
#define AXI_CANFD_RB_1_ID_EXT_ID_SIZE                18
#define AXI_CANFD_RB_1_ID_IDE_SIZE                1
#define AXI_CANFD_RB_1_ID_SRR_RTR_RRS_SIZE                1
#define AXI_CANFD_RB_1_ID_ID_SIZE                11

///////////////////////////////////////////////////////
// Register: RB*-1-DLC Register
// RB*-DLC Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RB_1_DLC_OFFSET(Index)         (0x4104ULL + ((Index) * 0x48))
#define AXI_CANFD_RB_1_DLC_TS_SHIFT              0
#define AXI_CANFD_RB_1_DLC_MATCHED_FILTER_IDX_SHIFT              16
#define AXI_CANFD_RB_1_DLC_ESI_SHIFT              25
#define AXI_CANFD_RB_1_DLC_BRS_SHIFT              26
#define AXI_CANFD_RB_1_DLC_EDL_FDF_SHIFT              27
#define AXI_CANFD_RB_1_DLC_DLC_SHIFT              28

#define AXI_CANFD_RB_1_DLC_TS_SIZE                16
#define AXI_CANFD_RB_1_DLC_MATCHED_FILTER_IDX_SIZE                5
#define AXI_CANFD_RB_1_DLC_ESI_SIZE                1
#define AXI_CANFD_RB_1_DLC_BRS_SIZE                1
#define AXI_CANFD_RB_1_DLC_EDL_FDF_SIZE                1
#define AXI_CANFD_RB_1_DLC_DLC_SIZE                4

///////////////////////////////////////////////////////
// Register: RB*-1-DW0 Register
// RB*-DW0 Register
///////////////////////////////////////////////////////
#define AXI_CANFD_RB_1_DW0_OFFSET(Index)         (0x4108ULL + ((Index) * 0x48))
#define AXI_CANFD_RB_1_DW0_DATA3_SHIFT              0
#define AXI_CANFD_RB_1_DW0_DATA2_SHIFT              8
#define AXI_CANFD_RB_1_DW0_DATA1_SHIFT              16
#define AXI_CANFD_RB_1_DW0_DATA0_SHIFT              24

#define AXI_CANFD_RB_1_DW0_DATA3_SIZE                8
#define AXI_CANFD_RB_1_DW0_DATA2_SIZE                8
#define AXI_CANFD_RB_1_DW0_DATA1_SIZE                8
#define AXI_CANFD_RB_1_DW0_DATA0_SIZE                8

#define AXI_CANFD_RB_1_DW_REG_NUM                  16

///////////////////////////////////////////////////////
// Register: Acceptance Filter Mask Register
// Acceptance Filter Mask Register
///////////////////////////////////////////////////////
#define AXI_CANFD_AFMR_OFFSET(Index)       (0xA00ULL + (Index) * 8)
#define AXI_CANFD_AFMR_AMRTR_SHIFT              0
#define AXI_CANFD_AFMR_EXT_AMID_SHIFT              1
#define AXI_CANFD_AFMR_AMIDE_SHIFT              19
#define AXI_CANFD_AFMR_AMSRR_SHIFT              20
#define AXI_CANFD_AFMR_AMID_SHIFT              21

#define AXI_CANFD_AFMR_AMRTR_SIZE                1
#define AXI_CANFD_AFMR_EXT_AMID_SIZE                18
#define AXI_CANFD_AFMR_AMIDE_SIZE                1
#define AXI_CANFD_AFMR_AMSRR_SIZE                1
#define AXI_CANFD_AFMR_AMID_SIZE                11

///////////////////////////////////////////////////////
// Register: Acceptance Filter ID Register
// Acceptance Filter ID Register
///////////////////////////////////////////////////////
#define AXI_CANFD_AFID_OFFSET(Index)       (0xA04ULL + (Index) * 8)
#define AXI_CANFD_AFID_AIRTR_SHIFT              0
#define AXI_CANFD_AFID_EXT_AIID_SHIFT              1
#define AXI_CANFD_AFID_AIIDE_SHIFT              19
#define AXI_CANFD_AFID_AISRR_SHIFT              20
#define AXI_CANFD_AFID_AIID_SHIFT              21

#define AXI_CANFD_AFID_AIRTR_SIZE                1
#define AXI_CANFD_AFID_EXT_AIID_SIZE                18
#define AXI_CANFD_AFID_AIIDE_SIZE                1
#define AXI_CANFD_AFID_AISRR_SIZE                1
#define AXI_CANFD_AFID_AIID_SIZE                11

///////////////////////////////////////////////////////
// Register: Software Reset Register
// Software Reset Register
///////////////////////////////////////////////////////
#define AXI_CANFD_MAILBOX_MASK_OFFSET(Index)         (0x2F00ULL + (Index) * 4)
///////////////////////////////////////////////////////
// Register: Software Reset Register
// Software Reset Register
///////////////////////////////////////////////////////

///////////////////////////////////////////////////////
// Register: Software Reset Register
// Software Reset Register
///////////////////////////////////////////////////////

///////////////////////////////////////////////////////
// Register: Software Reset Register
// Software Reset Register
///////////////////////////////////////////////////////

///////////////////////////////////////////////////////
// Register: Software Reset Register
// Software Reset Register
///////////////////////////////////////////////////////


typedef struct {
    AL_U32 DeviceId;
    AL_U32 IntrId;
    AL_U64 BaseAddress;
    AL_U32 InputClk;

    AL_U32 BusType;        /* AXI Lite or APB */
    AL_U32 TxBufNum;
    AL_U32 RxMode;         /* Sequential or MailBox */
    AL_U32 RxBufNum;       /* Valid if RxMode is MailBox */
    AL_U32 IsFifo1En;      /* Valid if RxMode is Sequential */
    AL_U32 RxFifoDepth0;   /* Valid if RxMode is Sequential */
    AL_U32 RxFifoDepth1;   /* Valid if RxMode is Sequential */
    AL_U32 IsTxEventEn;
} AlAxiCanFd_HwConfigStruct;

#endif /* __AL_AXI_CANFD_HW_H__ */