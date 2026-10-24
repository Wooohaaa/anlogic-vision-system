/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_dmacahb_single_mode_blocked.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   can in loopback blocked example
 * @example al_can_in_loopback_blocked.c
 */

/***************************** Include Files *********************************/
#include <string.h>
#include "al_can_hal.h"

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_CAN_EX_DEVICE_ID             (0)
#define AL_CAN_EX_BLOCKED_TIMEOUT_IN_MS (10000)
#define AL_CAN_EX_MEM_SIZE              (1)
#define AL_CAN_EX_ARRAY_SIZE            (256)

/************************** Variable Definitions *****************************/
static AL_CAN_InitStruct InLoopbackConfig = {
    .Protocol           = AL_CAN_TYPE_FD,
    .TxIntrMode         = AL_CAN_RUN_INTR,
    .RxIntrMode         = AL_CAN_RUN_INTR,
    .SlowBitRate        = AL_CAN_1M,
    .FastBitRate        = AL_CAN_5M,
};

static AL_CAN_FrameStruct ExFrame = {
    .BufferMode     = AL_CAN_BUFFER_MODE_PTB,
    .Id             = 0x11,
    .IsIdExt        = AL_FALSE,
    .IsRemote       = AL_FALSE,
    .IsBitSwitch    = AL_FALSE,
    .IsEnTts        = AL_FALSE,
    .Koer           = (AL_CAN_KoerEnum)0,
    .DataLen        = AL_CAN_LEN_8,
    .Data           = {0x01020304, 0x05060708},
    .Rts            = {0, 0},
};

static char *RunModeInfo[2] = {
    "Poll",
    "Intr",
};

static char *BlockInfo[2] = {
    "Non-block",
    "Block",
};

/************************** Function Prototypes ******************************/
static AL_S32 AlCan_Test_InLoopbackBlocked(AL_VOID);

/************************** Function Definitions ******************************/
/**
 *
 * This function initializes the test environment and starts the CAN in loopback blocked test by calling AlCan_Test_InLoopbackBlocked.
 * It logs the start of the test, checks the return value of the test function to determine success or failure, and logs the appropriate message before exiting.
 *
 * @return AL_OK if the test is successful, an error code otherwise.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "Can in loopback blocked test\r\n");

    Ret = AlCan_Test_InLoopbackBlocked();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Can in loopback blocked test failed\r\n");
        return Ret;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Can in loopback blocked test success\r\n");

    return Ret;
}

/**
 *
 * This function initializes the CAN hardware with a specific configuration for loopback mode and enters a loop
 * where it sends and receives CAN frames in a blocked manner. The function sends a predefined CAN frame
 * and waits for its reception using a blocking call with a specified timeout. If the frame is successfully sent and received,
 * it compares the sent and received data to ensure they match. The loop continues indefinitely, simulating
 * a real-world scenario where a device continuously sends and receives CAN frames in loopback mode.
 *
 * The function logs an error and returns immediately if any of the following operations fail:
 * - Hardware initialization
 * - Sending a frame
 * - Receiving a frame
 * - Data comparison between sent and received frames
 *
 * @return AL_OK if the loop runs without errors, an error code otherwise.
 */
static AL_S32 AlCan_Test_InLoopbackBlocked(AL_VOID)
{
    AL_U32 Ret = AL_OK;
    AL_U32 i, j, m, n, Round = 0;
    AL_CAN_FrameStruct Frame;
    AL_CAN_HalStruct *Handle = (AL_CAN_HalStruct*)AL_NULL;
    AL_CAN_IntrMaskEnum TxIntr, RxIntr;
    AL_CAN_OpsModeEnum OpsMode = AL_CAN_MODE_CONFIG;
    AL_CAN_ProtocolEnum Protocol = AL_CAN_TYPE_FD;
    AL_CAN_TsModeEnum TsMode = AL_CAN_TS_MODE_PRIO;
    AL_CAN_BitRateEnum BitRateS = AL_CAN_1M, BitRateF = AL_CAN_5M;
    AL_CAN_TimePosEnum TimePos = AL_CAN_TIMEPOS_EOF;
    AL_CAN_FilterCfgStruct Filter = {
                                        .FilterEn       = AL_TRUE,
                                        .FilterIndex    = AL_CAN_FILTER_0,
                                        .MaskType       = AL_CAN_FILTER_MASK_BOTH,
                                        .MaskValue      = 0x7FE,
                                        .IdValue        = 0x1,
                                    };

    Ret = AlCan_Hal_Init(&Handle, AL_CAN_EX_DEVICE_ID, &InLoopbackConfig, (AL_CAN_EventCallBack)AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Hal Init error:0x%x\r\n", Ret);
        return Ret;
    }
    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_PROTOCOL, &Protocol);

    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_TS_MODE, &TsMode);

    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_TIME_STAMP, &TimePos);

    /* Switch to config mode */
    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SWITCH_MODE, &OpsMode);

    /* Set slow bit rate */
    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_BIT_RATE_S_ENUM, &BitRateS);

    /* Set fast bit rate */
    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_BIT_RATE_F_ENUM, &BitRateF);

    /* Set filter 0 */
    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_FILTER, &Filter);

    /* Switch to in loop back mode */
    OpsMode = AL_CAN_MODE_IN_LOOPBACK;
    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SWITCH_MODE, &OpsMode);

    AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_DISPLAY_HOST, AL_NULL);

    while (1) {
        /* i:tx run mode, j:rx run mode, m:send interface, n:recv interface */
        AL_LOG(AL_LOG_LEVEL_INFO, "----------------- Round %d -----------------\r\n", ++Round);
        /* tx: 0 - poll, 1 - intr */
        for (i = 0; i < 2; i++) {
            /* rx: 0 - poll, 1 - intr */
            for (j = 0; j < 2; j++) {
                /* send: 0 - non-block, 1 - block */
                for (m = 0; m < 2; m++) {
                    /* recv: 0 - non-block, 1 - block */
                    for (n = 0; n < 2; n++) {
                        AL_LOG(AL_LOG_LEVEL_INFO, "[TX]: %s\t,[RX]: %s\t,[SEND]: %s\t,[RECV]: %s.\r\n",
                                RunModeInfo[i], RunModeInfo[j], BlockInfo[m], BlockInfo[n]);
                        memset(&Frame, 0, sizeof(AL_CAN_FrameStruct));
                        if (Handle->Dev.Host.TxIntrMode != (AL_CAN_RunModeEnum)i) {
                            TxIntr = AL_CAN_INTR_MASK_EN_TX;
                            if (i == AL_CAN_RUN_INTR) {
                                AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_INTR, &TxIntr);
                            } else {
                                AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_CLR_INTR, &TxIntr);
                            }
                        }

                        if (Handle->Dev.Host.RxIntrMode != (AL_CAN_RunModeEnum)j) {
                            RxIntr = AL_CAN_INTR_MASK_EN_RX;
                            if (i == AL_CAN_RUN_INTR) {
                                AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_SET_INTR, &RxIntr);
                            } else {
                                AlCan_Hal_IoCtl(Handle, AL_CAN_IOCTL_CLR_INTR, &RxIntr);
                            }
                        }

                        if (m == 0) {
                            Ret = AlCan_Hal_SendFrame(Handle, &ExFrame);
                        } else {
                            Ret = AlCan_Hal_SendFrameBlock(Handle, &ExFrame, AL_CAN_EX_BLOCKED_TIMEOUT_IN_MS);
                        }
                        if (Ret != AL_OK) {
                            AL_LOG(AL_LOG_LEVEL_ERROR, "Send Frame Error:0x%x\r\n", Ret);
                        }

                        AlOsal_Sleep(100);

                        if (n == 0) {
                            Ret = AlCan_Hal_RecvFrame(Handle, &Frame);
                        } else {
                            Ret = AlCan_Hal_RecvFrameBlock(Handle, &Frame, AL_CAN_EX_BLOCKED_TIMEOUT_IN_MS);
                        }
                        if (Ret != AL_OK) {
                            AL_LOG(AL_LOG_LEVEL_ERROR, "Recv Frame Error:0x%x\r\n", Ret);
                        }

                        AlCan_Dev_DisplayFrame(&Frame);

                        Ret = memcmp(ExFrame.Data, Frame.Data, AL_CAN_LEN_8);
                        if (Ret != AL_OK) {
                            AL_LOG(AL_LOG_LEVEL_ERROR, "Data check error:0x%x\r\n", Ret);
                            return Ret;
                        }
                    }
                }
            }
        }

        AlSys_MDelay(500);
    }

    return Ret;
}
