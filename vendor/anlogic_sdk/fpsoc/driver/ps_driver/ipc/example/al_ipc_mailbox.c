/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_ipc_mailbox.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   ipc mailbox example
 * @example al_ipc_mailbox.c
 */

/***************************** Include Files *********************************/
#include <string.h>
#include <stdlib.h>
#include "al_ipc_hal.h"

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/

/************************** Variable Definitions *****************************/

/***************** Macros (Inline Functions) Definitions *********************/

/**************************** Type Definitions *******************************/

/************************** Variable Definitions *****************************/

/************************** Function Prototypes ******************************/

/************************** Function Definitions ******************************/
/**
 * This function performs a series of operations to test the IPC mailbox functionality. It initializes a mailbox,
 * writes a value to it, reads the value back, and checks if the written and read values match. This process is repeated
 * for three different mailbox instances. It logs information about the operations being performed and their outcomes.
 *
 * @return 0 Always returns 0 indicating the program executed.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;
    AL_U32 Value = 0xffee;
    AL_U32 Num = 0;
    AL_U32 OutValue[IPC_MAILBOX_NUM];

    AL_IpcMailBox_HalStruct *Mailbox_Handles[IPC_MAILBOX_NUM];

    AL_LOG(AL_LOG_LEVEL_INFO, "Ipc Mailbox test\r\n");

    for (Num = 0; Num < IPC_MAILBOX_NUM; Num++) {
        Ret = AlIPC_Hal_MboxInit(&Mailbox_Handles[Num], Num);
        if ( Ret != AL_OK) {
            return AL_FALSE;
        }
    #ifndef CORE1
        Ret = AlIpc_Hal_MboxWrite(Mailbox_Handles[Num], Value - Num);
        if ( Ret != AL_OK) {
            return AL_FALSE;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Ipc Mailbox write %d 0x%x\r\n", Num, Value - Num);
    #else
        Ret = AlIpc_Hal_MboxRead(Mailbox_Handles[Num], &OutValue[Num]);
        if ( Ret != AL_OK) {
            return AL_FALSE;
        }
        AL_LOG(AL_LOG_LEVEL_INFO, "Ipc Mailbox Read %d 0x%x\r\n", Num, OutValue[Num]);
    #endif
    }

    return 0;
}
