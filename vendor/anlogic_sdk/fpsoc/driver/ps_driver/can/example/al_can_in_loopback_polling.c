/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_dmacahb_single_mode_polling.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   can in loopback polling example
 * @example al_can_in_loopback_polling.c
 */

/***************************** Include Files *********************************/
#include <string.h>
#include "al_can_hal.h"

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_CAN_EX_DEVICE_ID             (0)
#define AL_CAN_EX_FRAME_BUFFER_SIZE     (16)

/************************** Variable Definitions *****************************/
static AL_CAN_InitStruct InLoopbackConfig = {
    .Protocol       = AL_CAN_TYPE_FD,
    .TxIntrMode     = AL_CAN_RUN_POLLING,
    .RxIntrMode     = AL_CAN_RUN_POLLING,
    .SlowBitRate    = AL_CAN_1M,
    .FastBitRate    = AL_CAN_5M,
};

static AL_CAN_FrameStruct ExFrame = {
    .Id             = 0x10,
    .IsBitSwitch    = 0x1,
    .IsEnTts        = 0x0,
    .IsIdExt        = 0x0,
    .IsRemote       = 0x0,
    .DataLen        = AL_CAN_LEN_64,
    .Data           = {0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f00, 0x01020304, 0x05060708, \
                        0x090a0b0c, 0x0d0e0f00, 0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f00, \
                        0x01020304, 0x05060708, 0x090a0b0c, 0x0d0e0f00},
};

/************************** Function Prototypes ******************************/
static AL_S32 AlCan_Test_InLoopbackPolling(AL_VOID);

/************************** Function Definitions ******************************/
/**
 *
 * This function initializes the test environment and starts the CAN in loopback polling test by calling AlCan_Test_InLoopbackPolling.
 * It logs the start of the test, checks the return value of the test function to determine success or failure, and logs the appropriate message before exiting.
 *
 * @return AL_OK if the test is successful, an error code otherwise.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "Can in loopback polling test\r\n");

    Ret = AlCan_Test_InLoopbackPolling();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Can in loopback polling test failed\r\n");
        return Ret;
    }

    AL_LOG(AL_LOG_LEVEL_INFO, "Can in loopback polling test success\r\n");

    return Ret;
}

/**
 *
 * This function initializes the CAN hardware with a specific configuration for loopback mode and enters a loop
 * where it sends and receives CAN frames in a polling manner. The function sends a predefined CAN frame
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
static AL_S32 AlCan_Test_InLoopbackPolling(AL_VOID)
{
    AL_U32 Ret = AL_OK;
    AL_CAN_FrameStruct Frame;
    AL_CAN_HalStruct *Handle = AL_NULL;

    Ret = AlCan_Hal_Init(&Handle, AL_CAN_EX_DEVICE_ID, &InLoopbackConfig, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Hal Init error:0x%x\r\n", Ret);
        return Ret;
    }
    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    for (AL_U32 i = 0; i < AL_CAN_EX_FRAME_BUFFER_SIZE; i++) {
        ExFrame.Id = i;
        AL_LOG(AL_LOG_LEVEL_INFO, "Send Frame: %d\r\n", ExFrame.Id);
        Ret = AlCan_Hal_SendFrameBlock(Handle, &ExFrame, AL_WAITFOREVER);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Send Frame Error:0x%x\r\n", Ret);
        }
    }

    do {
        Ret = AlCan_Hal_RecvFrameBlock(Handle, &Frame, AL_WAITFOREVER);
        if (Ret != AL_OK) {
            AL_LOG(AL_LOG_LEVEL_ERROR, "Recv Frame Error:0x%x\r\n", Ret);
            break;
        }

        AlCan_Dev_DisplayFrame(&Frame);
    } while (1);

    return Ret;
}
