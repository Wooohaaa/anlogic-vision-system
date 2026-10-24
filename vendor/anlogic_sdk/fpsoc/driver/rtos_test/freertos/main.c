/*
    FreeRTOS V9.0.0 - Copyright (C) 2016 Real Time Engineers Ltd.
    All rights reserved

    VISIT http://www.FreeRTOS.org TO ENSURE YOU ARE USING THE LATEST VERSION.

    This file is part of the FreeRTOS distribution.

    FreeRTOS is free software; you can redistribute it and/or modify it under
    the terms of the GNU General Public License (version 2) as published by the
    Free Software Foundation >>>> AND MODIFIED BY <<<< the FreeRTOS exception.

    ***************************************************************************
    >>!   NOTE: The modification to the GPL is included to allow you to     !<<
    >>!   distribute a combined work that includes FreeRTOS without being   !<<
    >>!   obliged to provide the source code for proprietary components     !<<
    >>!   outside of the FreeRTOS kernel.                                   !<<
    ***************************************************************************

    FreeRTOS is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE.  Full license text is available on the following
    link: http://www.freertos.org/a00114.html

    ***************************************************************************
     *                                                                       *
     *    FreeRTOS provides completely free yet professionally developed,    *
     *    robust, strictly quality controlled, supported, and cross          *
     *    platform software that is more than just the market leader, it     *
     *    is the industry's de facto standard.                               *
     *                                                                       *
     *    Help yourself get started quickly while simultaneously helping     *
     *    to support the FreeRTOS project by purchasing a FreeRTOS           *
     *    tutorial book, reference manual, or both:                          *
     *    http://www.FreeRTOS.org/Documentation                              *
     *                                                                       *
    ***************************************************************************

    http://www.FreeRTOS.org/FAQHelp.html - Having a problem?  Start by reading
    the FAQ page "My application does not run, what could be wrong?".  Have you
    defined configASSERT()?

    http://www.FreeRTOS.org/support - In return for receiving this top quality
    embedded software for free we request you assist our global community by
    participating in the support forum.

    http://www.FreeRTOS.org/training - Investing in training allows your team to
    be as productive as possible as early as possible.  Now you can receive
    FreeRTOS training directly from Richard Barry, CEO of Real Time Engineers
    Ltd, and the world's leading authority on the world's leading RTOS.

    http://www.FreeRTOS.org/plus - A selection of FreeRTOS ecosystem products,
    including FreeRTOS+Trace - an indispensable productivity tool, a DOS
    compatible FAT file system, and our tiny thread aware UDP/IP stack.

    http://www.FreeRTOS.org/labs - Where new FreeRTOS products go to incubate.
    Come and try FreeRTOS+TCP, our new open source TCP/IP stack for FreeRTOS.

    http://www.OpenRTOS.com - Real Time Engineers ltd. license FreeRTOS to High
    Integrity Systems ltd. to sell under the OpenRTOS brand.  Low cost OpenRTOS
    licenses offer ticketed support, indemnification and commercial middleware.

    http://www.SafeRTOS.com - High Integrity Systems also provide a safety
    engineered and independently SIL3 certified version for use in safety and
    mission critical applications that require provable dependability.

    1 tab == 4 spaces!
*/


/* Kernel includes. */
#include "FreeRTOS.h" /* Must come first. */
#include "queue.h"    /* RTOS queue related API prototypes. */
#include "semphr.h"   /* Semaphore related API prototypes. */
#include "task.h"     /* RTOS task related API prototypes. */
#include "timers.h"   /* Software timer related API prototypes. */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "calculation_pi.h"
#include "al_tc_hal.h"

#define TERMS                           100
#define TASKDLYMS                       pdMS_TO_TICKS(100)
#define NUM_TASKS 5

static void prvSetupHardware(void);
extern void idle_task(void);

// static double results[NUM_TASKS];
static float results[NUM_TASKS];   
static TaskHandle_t tasks[NUM_TASKS];  
static SemaphoreHandle_t xSemaphore;  
static TaskHandle_t statistics_handler;


volatile AL_BOOL finish[NUM_TASKS];

AL_TC_HalStruct *TtcHandle[3];



void AlTc0_Handler(void)
{
    AL_LOG(AL_LOG_LEVEL_INFO, "tc 0 enter\r\n");


    float pi = calculate_PI();

    AlIntr_SetLocalInterrupt(AL_FUNC_DISABLE);

    printf("ttc0 interrupt: pi = %f\r\n", pi);

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AL_LOG(AL_LOG_LEVEL_INFO, "tc 0 exit\r\n");
}

void AlTc1_Handler(void)
{
    AL_LOG(AL_LOG_LEVEL_INFO, "tc 1 enter\r\n");


    float pi = calculate_PI();

    AlIntr_SetLocalInterrupt(AL_FUNC_DISABLE);

    printf("ttc1 interrupt: pi = %f\r\n", pi);

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AL_LOG(AL_LOG_LEVEL_INFO, "tc 1 exit\r\n");
}

void AlTc2_Handler(void)
{
    AL_LOG(AL_LOG_LEVEL_INFO, "tc 2 enter\r\n");


    float pi = calculate_PI();

    AlIntr_SetLocalInterrupt(AL_FUNC_DISABLE);

    printf("ttc2 interrupt: pi = %f\r\n", pi);

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

    AL_LOG(AL_LOG_LEVEL_INFO, "tc 2 exit\r\n");
}



void pre_setup(void)
{
    // AL_TC_HalStruct *TtcHandle[3];
    void (*handler[3])(void);
    handler[0] = AlTc0_Handler;
    handler[1] = AlTc1_Handler;
    handler[2] = AlTc2_Handler;

    int Ret;

    AL_TC_TimerInitStruct PwmInitConfigs = {
        .CountDec            = AL_TC_CountUp,
        .ClkSrc              = AL_TC_PCLK,
        .EnablePrescale      = AL_TRUE,
        .PrescaleVal         = 15,
    };


    for (int i = 0; i < 1; i++) {
    Ret =  AlTc_Hal_Init(&TtcHandle[i], i, &PwmInitConfigs,  handler[i]);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Hal Init error:0x%x\r\n", Ret);
        return Ret;
    }

    AL_INTR_AttrStrct test_ttc_attr = {
            .TrigMode   =  LEVEL_HIGH_TRIGGER,
            .Priority   =  0,
#if (defined __riscv || defined __riscv__)
            .VectorMode =  NON_VECTOR_INTERRUPT,
#endif
    };
    (AL_VOID)AlIntr_RegHandler(TtcHandle[i]->Dev.IntrNum, &test_ttc_attr,  AlTc_Dev_IntrHandler, &TtcHandle[i]->Dev);

    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);

     AlTc_Hal_EnableIntervalMode(TtcHandle[i]);
     AlTc_Hal_SetIntervalMaxVal(TtcHandle[i], 10000);

     AlTc_Hal_EnableIntr(TtcHandle[i], AL_TC_IntrInterval, AL_TRUE);

     AlTc_Hal_EnableWaveOutput(TtcHandle[i], AL_TRUE);
     AlTc_Hal_EnableCounter(TtcHandle[i], AL_TRUE);
    }
    
}

void calculate(void* pvParameters)
{
    int task_id = (int)pvParameters;  

#if defined __aarch64__ || defined __arm__
    portTASK_USES_FLOATING_POINT();
#endif

    while (1)
    {
    vTaskSuspendAll();
    printf("calculate task %d start\r\n", task_id);
    xTaskResumeAll();


    results[task_id] = calculate_PI();
    finish[task_id] = AL_TRUE;


    for (int i = 0; i < NUM_TASKS; i++) {  
          while (!finish[i])
          {
            vTaskDelay(TASKDLYMS);
          }
    }

    taskENTER_CRITICAL();


    // 检查计算结果是否一致  
    int consistent = 1;  
    for (int i = 0; i < NUM_TASKS; i++) {  
        printf("results[%d] %f\r\n", i, results[i]);
        float abs = fabsf(results[i] - results[0]);
        if (abs > 0.001) { // 判断精度  
            consistent = 0;  
            break;  
        }  
    }  

    if (consistent) {  
        printf("All task calculations have consistent results, and the value of π is:%f\r\n", results[0]);  
    } else {  
        printf("The task calculation results are inconsistent.\r\n");  
        while(1);
    } 
    taskEXIT_CRITICAL();



    vTaskSuspendAll();
    printf("task %d pi = %f\r\n", task_id, results[task_id]);
    xTaskResumeAll();

    }
 

}

void init(void)
{
    pre_setup();

    xSemaphore = xSemaphoreCreateCounting(NUM_TASKS, 0);  

    // 创建任务  
    for (int i = 0; i < NUM_TASKS; i++) {  
        xTaskCreate(calculate, "calculate", 1024, (void *)i, 1, &tasks[i]);  
    } 

    vTaskDelete(NULL);
}


int main(void)
{
    TaskHandle_t xHandle = NULL;

    xTaskCreate(init, "initial", 512, NULL, tskIDLE_PRIORITY, &xHandle);

    vTaskStartScheduler();

    printf("OS should never run to here\r\n");

    while (1);
}