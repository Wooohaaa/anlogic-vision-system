/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_ipc_intr.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   ipc interrupt example
 * @example al_ipc_intr.c
 */

/***************************** Include Files *********************************/
#include <string.h>
#include <stdlib.h>
#include "al_ipc_hal.h"
#include "al_core.h"

/************************** Constant Definitions *****************************/
#define IPC_MAILBOX_NUM      16
/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/
#define CORE_RPU
/************************** Variable Definitions *****************************/
AL_IpcMailBox_HalStruct *MailBoxes[IPC_MAILBOX_NUM];
AL_U8 *Tx_Data = (AL_U8 *)0x00000000;
AL_U8 *Rx_Data = (AL_U8 *)0x04000000;

AL_IpcIntr_HalStruct *IpcInter2Apu;
AL_IpcIntr_HalStruct *IpcInter2Rpu;

AL_IpcSpinLock_HalStruct *Spinlock_Handle;
/************************** Function Prototypes ******************************/
volatile int Err_Flag = 0;
/************************** Function Definitions ******************************/
/**
 * This function is called when an interrupt from the RPU to the APU (Application Processing Unit) is received.
 * It notifies the APU about the interrupt and logs a success message if the notification is successful.
 *
 * @param arg Pointer to user-defined data or NULL if no data is passed. This parameter is not used in the function.
 * @return None.
 */
AL_VOID CallBack2Rpu(AL_VOID * arg)
{
    AL_S32 Ret;
    AL_U32 i = 0;

    for (i = 0; i < IPC_MAILBOX_NUM; i++) {
		if (AlIpc_Hal_MboxRead(MailBoxes[i], &Rx_Data[i]) == AL_OK) {
			if (Rx_Data[i] != Tx_Data[i]) {
				Err_Flag = 1;
			}
		}
		Tx_Data[i] += 1;
	}

    AlIpc_Hal_IntrNotify(AL_IPC_APU2RPU_REQ);
}

/**
 * This function is called when an interrupt from the APU to the RPU (Remote Processing Unit) is received.
 * It logs a message indicating the success of the interrupt test.
 *
 * @param arg Pointer to user-defined data or NULL if no data is passed. This parameter is not used in the function.
 * @return None.
 */
AL_VOID CallBack2Apu(AL_VOID * arg)
{
    AL_S32 Ret;
    AL_U32 i = 0;

    for (i = 0; i < IPC_MAILBOX_NUM; i++) {
		Ret = AlIpc_Hal_MboxWrite(MailBoxes[i], Tx_Data[i]);
		if (Ret != AL_OK) {
			AL_LOG(AL_LOG_LEVEL_ERROR, "write error!\r\n");
		}
	}

    AlIpc_Hal_IntrNotify(AL_IPC_RPU2APU_REQ);
}

AL_S32 IpcSystemInit()
{
    AL_U32 i = 0;

    for (i = 0; i < IPC_MAILBOX_NUM; i++) {
        if (AlIPC_Hal_MboxInit(&MailBoxes[i], i) != AL_OK) {
            return AL_FALSE;
        }
    }

    if (AlIpc_Hal_SpinLockInit(&Spinlock_Handle, 0) != AL_OK) {
        return AL_FALSE;
    }

#ifdef CORE_APU
    if (AlIpc_Hal_IntrInit(&IpcInter2Apu, AL_IPC_RPU2APU_REQ, CallBack2Rpu, AL_NULL) != AL_OK) {
        return AL_FALSE;
    }
#endif

#ifdef CORE_RPU
    if (AlIpc_Hal_IntrInit(&IpcInter2Rpu, AL_IPC_APU2RPU_REQ, CallBack2Apu, AL_NULL) != AL_OK) {
        return AL_FALSE;
    }
#endif

    return AL_OK;
}

/**
 * This function initializes IPC interrupts for communication between the APU and RPU. It sets up callback functions for handling interrupts
 * from the other processor and enables local interrupts. It also sends a notification to the other processor and checks for errors
 * during the initialization and notification process.
 *
 * @return AL_OK if the test runs successfully and all initializations and notifications are successful.
 *         Returns an error code if any initialization or notification fails.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;
    AL_U32 i = 0;

    AL_LOG(AL_LOG_LEVEL_INFO, "Ipc Inter test\r\n");

    for (i = 0; i < IPC_MAILBOX_NUM; i++) {
		Tx_Data[i] = 0x33 + i;
	}

    Ret = IpcSystemInit();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Ipc interrupt init error!");
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

#ifdef CORE_APU
    if (AlIpc_Hal_IntrNotify(AL_IPC_APU2RPU_REQ) != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "ipc notify apu error");
        return AL_FALSE;
    }
#endif

    while (1) {
        if (Err_Flag == 1) {
            Err_Flag = 0;
            AL_LOG(AL_LOG_LEVEL_ERROR, "Mailbox data check error!\r\n");
        }
    }

    return Ret;
}
