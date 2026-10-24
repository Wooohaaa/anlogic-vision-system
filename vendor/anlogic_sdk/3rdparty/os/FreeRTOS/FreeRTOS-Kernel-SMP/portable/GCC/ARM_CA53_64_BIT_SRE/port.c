/*
 * FreeRTOS Kernel V10.5.1
 * Copyright (C) 2021 Amazon.com, Inc. or its affiliates.  All Rights Reserved.
 *
 * SPDX-License-Identifier: MIT
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * https://www.FreeRTOS.org
 * https://github.com/FreeRTOS
 *
 */

/* Standard includes. */
#include <stdlib.h>

/* Scheduler includes. */
#include "FreeRTOS.h"
#include "task.h"
#include <string.h>
#include "al_gicv3.h"
#include <al_core.h>

static void WaiteCoresReady(void);

#ifndef configUNIQUE_INTERRUPT_PRIORITIES
	#error configUNIQUE_INTERRUPT_PRIORITIES must be defined.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-Cortex-A-Embedded-Processors.html
#endif

#ifndef configSETUP_TICK_INTERRUPT
	#error configSETUP_TICK_INTERRUPT() must be defined.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-Cortex-A-Embedded-Processors.html
#endif /* configSETUP_TICK_INTERRUPT */

#ifndef configMAX_API_CALL_INTERRUPT_PRIORITY
	#error configMAX_API_CALL_INTERRUPT_PRIORITY must be defined.  See https://www.FreeRTOS.org/Using-FreeRTOS-on-Cortex-A-Embedded-Processors.html
#endif

#if configMAX_API_CALL_INTERRUPT_PRIORITY == 0
	#error configMAX_API_CALL_INTERRUPT_PRIORITY must not be set to 0
#endif

#if configMAX_API_CALL_INTERRUPT_PRIORITY > configUNIQUE_INTERRUPT_PRIORITIES
	#error configMAX_API_CALL_INTERRUPT_PRIORITY must be less than or equal to configUNIQUE_INTERRUPT_PRIORITIES as the lower the numeric priority value the higher the logical interrupt priority
#endif

#if configUSE_PORT_OPTIMISED_TASK_SELECTION == 1
	/* Check the configuration. */
	#if( configMAX_PRIORITIES > 32 )
		#error configUSE_PORT_OPTIMISED_TASK_SELECTION can only be set to 1 when configMAX_PRIORITIES is less than or equal to 32.  It is very rare that a system requires more than 10 to 15 difference priorities as tasks that share a priority will time slice.
	#endif
#endif /* configUSE_PORT_OPTIMISED_TASK_SELECTION */

/* In case security extensions are implemented. */
#if configMAX_API_CALL_INTERRUPT_PRIORITY <= ( configUNIQUE_INTERRUPT_PRIORITIES / 2 )
	#error configMAX_API_CALL_INTERRUPT_PRIORITY must be greater than ( configUNIQUE_INTERRUPT_PRIORITIES / 2 )
#endif

/* Some vendor specific files default configCLEAR_TICK_INTERRUPT() in
portmacro.h. */
#ifndef configCLEAR_TICK_INTERRUPT
	#define configCLEAR_TICK_INTERRUPT()
#endif

/* A critical section is exited when the critical section nesting count reaches
this value. */
#define portNO_CRITICAL_NESTING			( ( size_t ) 0 )

/* In all GICs 255 can be written to the priority mask register to unmask all
(but the lowest) interrupt priority. */
#define portUNMASK_VALUE				( 0xFFUL )

/* Tasks are not created with a floating point context, but can be given a
floating point context after they have been created.  A variable is stored as
part of the tasks context that holds portNO_FLOATING_POINT_CONTEXT if the task
does not have an FPU context, or any other value if the task does have an FPU
context. */
#define portNO_FLOATING_POINT_CONTEXT	( ( StackType_t ) 0 )

/* Constants required to setup the initial task context. */
#define portSP_ELx						( ( StackType_t ) 0x01 )
#define portSP_EL0						( ( StackType_t ) 0x00 )

#if defined( GUEST )
	#define portEL1						( ( StackType_t ) 0x04 )
	#define portINITIAL_PSTATE				( portEL1 | portSP_EL0 )
#else
	#define portEL3						( ( StackType_t ) 0x0c )
	/* At the time of writing, the BSP only supports EL3. */
	#define portINITIAL_PSTATE			( portEL3 | portSP_EL0 )
#endif

/* Masks all bits in the APSR other than the mode bits. */
#define portAPSR_MODE_BITS_MASK			( 0x0C )

/* The I bit in the DAIF bits. */
#define portDAIF_I						( 0x80 )

#define portFPU_REGISTER_WORDS     		( 33 * 2 )

#ifdef portCLEAR_INTERRUPT_MASK
#undef portCLEAR_INTERRUPT_MASK
#endif

/*
 * portCLEAR_INTERRUPT_MASK: redefined with portmacro.h
*/
#define portCLEAR_INTERRUPT_MASK()						\
{														\
	__asm volatile (	"MSR DAIFSET, #3 		\n"		\
						"DSB SY					\n"		\
						"ISB SY					\n"		\
						"MSR ICC_PMR_EL1, %0 	\n"		\
						"DSB SY					\n"		\
						"ISB SY					\n"		\
						"MSR DAIFCLR, #3 		\n"		\
						"DSB SY					\n"		\
						"ISB SY					\n"		\
						::"r"( portUNMASK_VALUE ) );	\
}



UBaseType_t uxPortSetInterruptMask( void )
{
uint32_t ulReturn;
uint64_t ullPMRValue;

	/*do nothing if in isr*/
	if (ullPortInterruptNesting[portGET_CORE_ID()] > 0) {
		ulReturn = pdTRUE;
		return ulReturn;
	}

	portDISABLE_INTERRUPTS();

	/* ICC_PMR_EL1 is ICC_PMR_EL1. */
	__asm volatile ( "MRS %0, ICC_PMR_EL1" : "=r" ( ullPMRValue ) );
	if( ullPMRValue == ( configMAX_API_CALL_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ) )
	{
		/* Interrupts were already masked. */
		ulReturn = pdTRUE;
	}
	else
	{
		ulReturn = pdFALSE;
		/* ICC_PMR_EL1 is ICC_PMR_EL1. */
		__asm volatile ( "MSR ICC_PMR_EL1, %0		\n"
						 "DSB SY					\n"
						 "ISB SY					\n"
						 :: "r" ( configMAX_API_CALL_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ) : "memory" );
	}

	portENABLE_INTERRUPTS();

	return ulReturn;
}


void vPortClearInterruptMask( UBaseType_t uxNewMaskValue )
{
	if( uxNewMaskValue == pdFALSE )
	{
		__asm volatile ( "MSR ICC_PMR_EL1, %0		\n"
						 "DSB SY					\n"
						 "ISB SY					\n"
						 :: "r" ( portUNMASK_VALUE ) : "memory" );

	}
}


void vPortClearInterruptMaskFromIsr( UBaseType_t uxNewMaskValue )
{
	vAssertIfNotInIsr();

	if( uxNewMaskValue == pdFALSE )
	{
		__asm volatile ( "MSR ICC_PMR_EL1, %0		\n"
						 "DSB SY					\n"
						 "ISB SY					\n"
						 :: "r" ( portUNMASK_VALUE ) : "memory" );
	}
}

UBaseType_t uxPortSetInterruptMaskFromIsr( void )
{
uint32_t ulReturn;
uint64_t ullPMRValue;

	vAssertIfNotInIsr();

	/* ICC_PMR_EL1 is ICC_PMR_EL1. */
	__asm volatile ( "MRS %0, ICC_PMR_EL1" : "=r" ( ullPMRValue ) );
	if( ullPMRValue == ( configMAX_API_CALL_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ) )
	{
		/* Interrupts were already masked. */
		ulReturn = pdTRUE;
	}
	else
	{
		ulReturn = pdFALSE;
		/* ICC_PMR_EL1 is ICC_PMR_EL1. */
		__asm volatile ( "MSR ICC_PMR_EL1, %0		\n"
						 "DSB SY					\n"
						 "ISB SY					\n"
						 :: "r" ( configMAX_API_CALL_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ) : "memory" );
	}

	return ulReturn;
}

/*-----------------------------------------------------------*/

/*
 * Starts the first task executing.  This function is necessarily written in
 * assembly code so is implemented in portASM.s.
 */
extern void vPortRestoreTaskContext( void );

/*-----------------------------------------------------------*/

/* A variable is used to keep track of the critical section nesting.  This
variable has to be stored as part of the task context and must be initialised to
a non zero value to ensure interrupts don't inadvertently become unmasked before
the scheduler starts.  As it is stored as part of the task context it will
automatically be set to 0 when the first task is started. */
volatile uint64_t ullCriticalNesting = 9999ULL;

/* Saved as part of the task context.  If ullPortTaskHasFPUContext is non-zero
then floating point context must be saved and restored for the task. */
uint64_t ullPortTaskHasFPUContext = pdFALSE;

/* Set to 1 to pend a context switch from an ISR. */
uint64_t ullPortYieldRequired[configNUMBER_OF_CORES] = { pdFALSE };

/* Counts the interrupt nesting depth.  A context switch is only performed if
if the nesting depth is 0. */
volatile uint64_t ullPortInterruptNesting[configNUMBER_OF_CORES] = { 0 };

/* Used for check IN ISR */
volatile uint64_t ullCoreInIsr[configNUMBER_OF_CORES] = {0};

volatile uint64_t ullCoreStatus[configNUMBER_OF_CORES] = {0};

volatile uint64_t ullTSCIsrCnt[configNUMBER_OF_CORES] = {0};

volatile uint64_t vApplicationIRQHandlercnt[configNUMBER_OF_CORES] = {0};

volatile uint32_t IntCoreCnt[configNUMBER_OF_CORES] = {0};

/* Used in the ASM code. */
__attribute__(( used )) const uint64_t ullMaxAPIPriorityMask = ( configMAX_API_CALL_INTERRUPT_PRIORITY << portPRIORITY_SHIFT );

/*-----------------------------------------------------------*/

/*
 * See header file for description.
 */
StackType_t *pxPortInitialiseStack( StackType_t *pxTopOfStack, TaskFunction_t pxCode, void *pvParameters )
{
	/* Setup the initial stack of the task.  The stack is set exactly as
	expected by the portRESTORE_CONTEXT() macro. */

	/* First all the general purpose registers. */
	pxTopOfStack--;
	*pxTopOfStack = 0x0101010101010101ULL;	/* R1 */
	pxTopOfStack--;
	*pxTopOfStack = ( StackType_t ) pvParameters; /* R0 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0303030303030303ULL;	/* R3 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0202020202020202ULL;	/* R2 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0505050505050505ULL;	/* R5 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0404040404040404ULL;	/* R4 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0707070707070707ULL;	/* R7 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0606060606060606ULL;	/* R6 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0909090909090909ULL;	/* R9 */
	pxTopOfStack--;
	*pxTopOfStack = 0x0808080808080808ULL;	/* R8 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1111111111111111ULL;	/* R11 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1010101010101010ULL;	/* R10 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1313131313131313ULL;	/* R13 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1212121212121212ULL;	/* R12 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1515151515151515ULL;	/* R15 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1414141414141414ULL;	/* R14 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1717171717171717ULL;	/* R17 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1616161616161616ULL;	/* R16 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1919191919191919ULL;	/* R19 */
	pxTopOfStack--;
	*pxTopOfStack = 0x1818181818181818ULL;	/* R18 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2121212121212121ULL;	/* R21 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2020202020202020ULL;	/* R20 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2323232323232323ULL;	/* R23 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2222222222222222ULL;	/* R22 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2525252525252525ULL;	/* R25 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2424242424242424ULL;	/* R24 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2727272727272727ULL;	/* R27 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2626262626262626ULL;	/* R26 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2929292929292929ULL;	/* R29 */
	pxTopOfStack--;
	*pxTopOfStack = 0x2828282828282828ULL;	/* R28 */
	pxTopOfStack--;
	*pxTopOfStack = ( StackType_t ) 0x00;	/* XZR - has no effect, used so there are an even number of registers. */
	pxTopOfStack--;
	*pxTopOfStack = ( StackType_t ) 0x00;	/* R30 - procedure call link register. */
	pxTopOfStack--;

	*pxTopOfStack = portINITIAL_PSTATE;
	pxTopOfStack--;

	*pxTopOfStack = ( StackType_t ) pxCode; /* Exception return address. */

    #if ( configUSE_TASK_FPU_SUPPORT == 1 )
    {
        /* The task will start with a critical nesting count of 0 as interrupts are
        * enabled. */
        pxTopOfStack--;
        *pxTopOfStack = portNO_CRITICAL_NESTING;

        /* The task will start without a floating point context.  A task that
         * uses the floating point hardware must call vPortTaskUsesFPU() before
         * executing any floating point instructions. */
        pxTopOfStack--;
        *pxTopOfStack = portNO_FLOATING_POINT_CONTEXT;
    }
    #elif ( configUSE_TASK_FPU_SUPPORT == 2 )
    {
        /* The task will start with a floating point context.  Leave enough
         * space for the registers - and ensure they are initialised to 0. */
        pxTopOfStack -= portFPU_REGISTER_WORDS;
        memset( pxTopOfStack, 0x00, portFPU_REGISTER_WORDS * sizeof( StackType_t ) );

        /* The task will start with a critical nesting count of 0 as interrupts are
        * enabled. */
        pxTopOfStack--;
        *pxTopOfStack = portNO_CRITICAL_NESTING;

        pxTopOfStack--;
        *pxTopOfStack = pdTRUE;
        ullPortTaskHasFPUContext = pdTRUE;
    }
    #else /* if ( configUSE_TASK_FPU_SUPPORT == 1 ) */
    {
        #error "Invalid configUSE_TASK_FPU_SUPPORT setting - configUSE_TASK_FPU_SUPPORT must be set to 1, 2, or left undefined."
    }
    #endif /* if ( configUSE_TASK_FPU_SUPPORT == 1 ) */

	return pxTopOfStack;
}
/*-----------------------------------------------------------*/

void vTaskSwitchContextISR(void *p)
{
	(void)p;
    portEND_SWITCHING_ISR(pdTRUE);
    ullTSCIsrCnt[portGET_CORE_ID()]++;
}


void vInterruptCore(uint32_t ulInterruptID, uint32_t ulCoreID)
{
    configASSERT(ulCoreID < configNUMBER_OF_CORES);
    configASSERT(ulInterruptID < 16);

    AlIntr_GenSoftIntr(portYIELD_CORE_INT_ID, ulCoreID);
    IntCoreCnt[ulCoreID]++;
}

/*-----------------------------------------------------------*/

#define portMAX_CORE_COUNT      configNUMBER_OF_CORES

#define portMAX_CORE_COUNT      configNUMBER_OF_CORES

/* Which core owns the lock */
volatile uint64_t ucOwnedByCore[ portMAX_CORE_COUNT ];
/* Lock count a core owns */
volatile uint64_t ucRecursionCountByLock[ portMAX_CORE_COUNT ];
/* Index 0 is used for ISR lock and Index 1 is used for task lock */
uint32_t ulGateWord[ portMAX_CORE_COUNT ];


static inline void vSpinUnlock(uint32_t* ulLock)
{
    __asm volatile(
        "dmb sy\n"
        "mov w1, #0\n"
        "str w1, [%x0]\n"
        "dsb sy\n"
        "sev\n"
        :
        :"r" (ulLock)
        : "memory", "w1"
    );
}

static inline int32_t lSpinTrylock(uint32_t* ulLock)
{
    register int32_t lRet;

    __asm volatile(
        "1:\n"
        "ldxr w1, [%x1]\n"
        "cmp w1, #1\n"
        "beq 2f\n"
        "mov w2, #1\n"
        "stxr w1, w2, [%x1]\n"
        "cmp w1, #0\n"
        "bne 1b\n"
        "2:\n"
        "mov %w0, w1\n"
        :"=r" (lRet)
        :"r" (ulLock)
        : "memory", "w1", "w2"
    );

    return lRet;
}

/* Read 64b value shared between cores */
static inline uint64_t uxGet64(volatile uint64_t* x)
{
    __asm("dsb sy");
    return *x;
}

/* Write 64b value shared between cores */
static inline void vSet64(volatile uint64_t* x, uint64_t value)
{
    *x = value;
    __asm("dsb sy");
}

void vPortRecursiveLock(BaseType_t xCoreID, uint32_t ulLockNum, BaseType_t uxAcquire)
{
    uint32_t ulLockBit = 1u << ulLockNum;

    /* Lock acquire */
    if (uxAcquire)
    {
        /* Check if spinlock is available */
        /* If spinlock is not available check if the core owns the lock */
        /* If the core owns the lock wait increment the lock count by the core */
        /* If core does not own the lock wait for the spinlock */
        if( lSpinTrylock(&ulGateWord[ulLockNum]) != 0)
        {
            /* Check if the core owns the spinlock */
            if( uxGet64(&ucOwnedByCore[xCoreID]) & ulLockBit )
            {
                configASSERT( uxGet64(&ucRecursionCountByLock[ulLockNum]) != 255u);
                vSet64(&ucRecursionCountByLock[ulLockNum], (uxGet64(&ucRecursionCountByLock[ulLockNum])+1));
                return;
            }

            /* Preload the gate word into the cache */
            uint32_t dummy = ulGateWord[ulLockNum];
            dummy++;

            while (lSpinTrylock(&ulGateWord[ulLockNum]) != 0)
                __asm volatile ("wfe");
        }

         /* Add barrier to ensure lock is taken before we proceed */
        __asm__ __volatile__ ( "dmb sy" ::: "memory" );

        /* Assert the lock count is 0 when the spinlock is free and is acquired */
        configASSERT(uxGet64(&ucRecursionCountByLock[ulLockNum]) == 0);

        /* Set lock count as 1 */
        vSet64(&ucRecursionCountByLock[ulLockNum], 1);
        /* Set ucOwnedByCore */
        vSet64(&ucOwnedByCore[xCoreID], (uxGet64(&ucOwnedByCore[xCoreID]) | ulLockBit));
    }
    /* Lock release */
    else
    {
        /* Assert the lock is not free already */
        configASSERT( (uxGet64(&ucOwnedByCore[xCoreID]) & ulLockBit) != 0 );
        configASSERT( uxGet64(&ucRecursionCountByLock[ulLockNum]) != 0 );

        /* Reduce ucRecursionCountByLock by 1 */
        vSet64(&ucRecursionCountByLock[ulLockNum], (uxGet64(&ucRecursionCountByLock[ulLockNum]) - 1) );

        if( !uxGet64(&ucRecursionCountByLock[ulLockNum]) )
        {
            vSet64(&ucOwnedByCore[xCoreID], (uxGet64(&ucOwnedByCore[xCoreID]) & ~ulLockBit));
            vSpinUnlock(&ulGateWord[ulLockNum]);
            __asm volatile("sev");
            /* Add barrier to ensure lock is taken before we proceed */
            __asm__ __volatile__ (  "dmb sy" ::: "memory" );
        }
    }
}


void entry(void)
{
	uint64_t CoreID = xPortGetCoreID();
	if (CoreID != 0) {
		WaiteCoresReady();
	}
}

void WaiteCoresReady(void)
{
    uint64_t CoreID = xPortGetCoreID();

    static volatile uint32_t CoreStatus[2] = {0};

	AL_INTR_AttrStrct IntrAttr = {
            .TrigMode   =  LEVEL_LOW_TRIGGER,
            .Priority   =  ( uint32_t ) ( portLOWEST_USABLE_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ),
	};

    (AL_VOID)AlIntr_RegHandler(portYIELD_CORE_INT_ID, &IntrAttr, vTaskSwitchContextISR, AL_NULL);

    CoreStatus[CoreID] = 1;
    AL_U32 CpuIndex = 0;

    do
    {
        if (CoreStatus[CpuIndex] != 0)
        {
            CpuIndex++;
        }
    } while (CpuIndex < 1);

    if (CoreID != 0) {
        vPortRestoreTaskContext();
    }
}

/*-----------------------------------------------------------*/

BaseType_t xPortStartScheduler( void )
{
	uint32_t ulAPSR;
	uint64_t CoreID = xPortGetCoreID();

	__asm volatile ( "MRS %0, CurrentEL" : "=r" ( ulAPSR ) );
	ulAPSR &= portAPSR_MODE_BITS_MASK;

#if defined( GUEST )
	configASSERT( ulAPSR == portEL1 );
	if( ulAPSR == portEL1 )
#else
	configASSERT( ulAPSR == portEL3 );
	if( ulAPSR == portEL3 )
#endif
	{
		/* Interrupts are turned off in the CPU itself to ensure a tick does
		not execute	while the scheduler is being started.  Interrupts are
		automatically turned back on in the CPU when the first task starts
		executing. */
		portDISABLE_INTERRUPTS();

        if (CoreID == 0) {
            /* Start the timer that generates the tick ISR. */
            configSETUP_TICK_INTERRUPT();
        }

		WaiteCoresReady();

		/* Start the first task executing. */
		vPortRestoreTaskContext();
	}

	return 0;
}
/*-----------------------------------------------------------*/

void vPortEndScheduler( void )
{
	/* Not implemented in ports where there is nothing to return to.
	Artificially force an assert. */
	configASSERT( ullCriticalNesting == 1000ULL );
}
/*-----------------------------------------------------------*/

void vPortEnterCritical( void )
{
	/* Mask interrupts up to the max syscall interrupt priority. */
	uxPortSetInterruptMask();

	/* Now interrupts are disabled ullCriticalNesting can be accessed
	directly.  Increment ullCriticalNesting to keep a count of how many times
	portENTER_CRITICAL() has been called. */
	ullCriticalNesting++;

	/* This is not the interrupt safe version of the enter critical function so
	assert() if it is being called from an interrupt context.  Only API
	functions that end in "FromISR" can be used in an interrupt.  Only assert if
	the critical nesting count is 1 to protect against recursive calls if the
	assert function also uses a critical section. */
	if( ullCriticalNesting == 1ULL )
	{
		configASSERT( ullPortInterruptNesting[xPortGetCoreID()] == 0 );
	}
}
/*-----------------------------------------------------------*/

void vPortExitCritical( void )
{
	if( ullCriticalNesting > portNO_CRITICAL_NESTING )
	{
		/* Decrement the nesting count as the critical section is being
		exited. */
		ullCriticalNesting--;

		/* If the nesting level has reached zero then all interrupt
		priorities must be re-enabled. */
		if( ullCriticalNesting == portNO_CRITICAL_NESTING )
		{
			/* Critical nesting has reached zero so all interrupt priorities
			should be unmasked. */
			portCLEAR_INTERRUPT_MASK();
		}
	}
}
/*-----------------------------------------------------------*/

void FreeRTOS_Tick_Handler( void *p)
{
	unsigned int ulRpr;

	ulRpr = AlGicv3_GetRunningPriority();
	configASSERT( ulRpr == ( uint32_t ) ( portLOWEST_USABLE_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ) );

	configCLEAR_TICK_INTERRUPT();

	UBaseType_t ulPreviousMask = portENTER_CRITICAL_FROM_ISR();

	if( xTaskIncrementTick() != pdFALSE )
	{
		ullPortYieldRequired[portGET_CORE_ID()] = pdTRUE;
	}

	portEXIT_CRITICAL_FROM_ISR( ulPreviousMask );
}
/*-----------------------------------------------------------*/

#if ( configUSE_TASK_FPU_SUPPORT != 2 )

void vPortTaskUsesFPU( void )
{
	/* A task is registering the fact that it needs an FPU context.  Set the
	FPU flag (which is saved as part of the task context). */
	ullPortTaskHasFPUContext = pdTRUE;

	/* Consider initialising the FPSR here - but probably not necessary in
	AArch64. */
}
#endif /* configUSE_TASK_FPU_SUPPORT */
/*-----------------------------------------------------------*/

/*-----------------------------------------------------------*/

/*-----------------------------------------------------------*/

#if( configASSERT_DEFINED == 1 )

	void vPortValidateInterruptPriority( void )
	{
		/* The following assertion will fail if a service routine (ISR) for
		an interrupt that has been assigned a priority above
		configMAX_SYSCALL_INTERRUPT_PRIORITY calls an ISR safe FreeRTOS API
		function.  ISR safe FreeRTOS API functions must *only* be called
		from interrupts that have been assigned a priority at or below
		configMAX_SYSCALL_INTERRUPT_PRIORITY.

		Numerically low interrupt priority numbers represent logically high
		interrupt priorities, therefore the priority of the interrupt must
		be set to a value equal to or numerically *higher* than
		configMAX_SYSCALL_INTERRUPT_PRIORITY.

		FreeRTOS maintains separate thread and ISR API functions to ensure
		interrupt entry is as fast and simple as possible. */
		uint64_t ullRunningInterruptPriority;
		/* s3_0_c12_c11_3 is ICC_RPR_EL1. */
		__asm volatile ( "MRS %0, s3_0_c12_c11_3" : "=r" ( ullRunningInterruptPriority ) );
		configASSERT( ullRunningInterruptPriority >= ( configMAX_API_CALL_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ) );
	}

#endif /* configASSERT_DEFINED */
/*-----------------------------------------------------------*/

extern AL_VOID do_irq_handle(AL_VOID);
extern AL_VOID do_fiq_handle(AL_VOID);

void vApplicationIRQHandler(AL_VOID)
{
    BaseType_t xCoreId = portGET_CORE_ID();
    ullCoreInIsr[xCoreId]++;
#ifdef GUEST
	do_irq_handle();
#else
	do_fiq_handle();
#endif
    ullCoreInIsr[xCoreId]--;

	vApplicationIRQHandlercnt[xCoreId] ++;
}
/*-----------------------------------------------------------*/

void vSetupTickInterrupt( void )
{
	AL_U64 cntfrq = 0;

	ISB();

	// get timer frequency
	__asm volatile ("mrs %0, cntfrq_el0" : "=r" (cntfrq));

	DSB();

	cntfrq /= configTICK_RATE_HZ;

	// disable timer
	__asm volatile ("msr cntp_ctl_el0, xzr":::"memory");

	// set timer value
    __asm volatile ("msr cntp_tval_el0, %0" :
                                            : "r" (cntfrq)
                                            :"memory");

	// enable timer
    __asm volatile ("msr cntp_ctl_el0, %0"  :
                                            : "r" (AL_FUNC_ENABLE)
                                            :"memory");

	AL_INTR_AttrStrct IntrAttr = {
            .TrigMode   =  LEVEL_LOW_TRIGGER,
            .Priority   =  ( uint32_t ) ( portLOWEST_USABLE_INTERRUPT_PRIORITY << portPRIORITY_SHIFT ),
	};

	(AL_VOID)AlIntr_RegHandler(SOC_NONE_SECURE_PHYSICAL_TIMER, &IntrAttr, FreeRTOS_Tick_Handler, AL_NULL);
}
/*-----------------------------------------------------------*/

void clear_tick()
{
	AL_U64 cntfrq = 0;

	ISB();

	// get timer frequency
	__asm volatile ("mrs %0, cntfrq_el0" : "=r" (cntfrq));

	DSB();

	cntfrq /= configTICK_RATE_HZ;

	// disable timer
	__asm volatile ("msr cntp_ctl_el0, xzr":::"memory");

	// set timer value
    __asm volatile ("msr cntp_tval_el0, %0" :
                                            : "r" (cntfrq)
                                            :"memory");

	// enable timer
    __asm volatile ("msr cntp_ctl_el0, %0"  :
                                            : "r" (AL_FUNC_ENABLE)
                                            :"memory");
}

