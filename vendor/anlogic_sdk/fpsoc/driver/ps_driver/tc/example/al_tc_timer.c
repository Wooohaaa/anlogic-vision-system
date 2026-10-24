/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

/**
 * @file    al_tc_timer.c
 * @author  Anlogic esw team
 * @version V0.0.1
 * @date    2023-09-01
 * @brief   tc timer example
 * @example al_tc_timer.c
 */

/***************************** Include Files *********************************/
#include <string.h>
#include <stdlib.h>
#include "al_tc_hal.h"

/************************** Constant Definitions *****************************/

/**************************** Type Definitions *******************************/

/***************** Macros (Inline Functions) Definitions *********************/
#define AL_TC_DEVICE_ID             (0)

#define AL_TC_INTERVAL_VAL      (48828) /* max val = 65535 */

/************************** Variable Definitions *****************************/
static AL_TC_TimerInitStruct TimerInitConfigs = {
    .CountDec            = AL_TC_CountUp,
    .ClkSrc              = AL_TC_PCLK,
    .EnablePrescale      = AL_TRUE,
    .PrescaleVal         = 11, /* max PrescaleVal = 15 */
};

/************************** Function Prototypes ******************************/
static AL_S32 AlTc_Test_Timer(AL_VOID);

/************************** Function Definitions ******************************/
/**
 * This function serves as the entry point for the program. It initializes the application,
 * runs the Timer test, and handles the return status. If the test fails, it logs an error
 * message and returns the error code. Otherwise, it returns AL_OK indicating success.
 *
 * @return AL_OK on success, or an error code on failure.
 */
AL_S32 main(AL_VOID)
{
    AL_S32 Ret = AL_OK;

    AL_LOG(AL_LOG_LEVEL_INFO, "Tc timer test\r\n");

    Ret = AlTc_Test_Timer();
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Tc timer test failed\r\n");
        return Ret;
    }

    return Ret;
}

static AL_VOID AlTc_Hal_TimerEventHandler(AL_TC_EventStruct TcEvent, AL_VOID *CallbackRef)
{
    switch (TcEvent.Events)
    {
    case AL_TC_EVENT_Interval:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al tc generated a interval interrupt");
        break;
    case AL_TC_EVENT_Match1:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al tc generated a match1 interrupt");
        break;
    case AL_TC_EVENT_Match2:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al tc generated a match2 interrupt");
        break;
    case AL_TC_EVENT_Match3:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al tc generated a match3 interrupt");
        break;
    case AL_TC_EVENT_Overflow:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al tc generated a overflow interrupt");
        break;
    case AL_TC_EVENT_EventTimer:
        AL_LOG(AL_LOG_LEVEL_INFO, "Al tc generated a event timer interrupt");
        break;
    default:
        break;
    }

}

static AL_S32 AlTc_Test_Timer(AL_VOID)
{
    AL_U32 Ret = AL_OK;
    AL_TC_HalStruct *TcHandle;

    Ret = AlTc_Hal_Init(&TcHandle, AL_TC_DEVICE_ID, &TimerInitConfigs, AlTc_Hal_TimerEventHandler);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Hal Init error:0x%x\r\n", Ret);
        return Ret;
    }

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AlTc_Hal_EnableIntervalMode(TcHandle);

    AlTc_Hal_SetIntervalMaxVal(TcHandle, AL_TC_INTERVAL_VAL);

    AlTc_Hal_EnableIntr(TcHandle, AL_TC_IntrInterval, AL_TRUE);

    AlTc_Hal_EnableCounter(TcHandle, AL_TRUE);

    while (1) {

    }

    return Ret;
}
