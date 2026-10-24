/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_utils_def.h"
#include "al_compiler.h"
#include "al_backtrace.h"

static AL_VOID panic(AL_VOID)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "warning: system hang here, waiting for exiting\r\n");
    while (1);
}

/**
 * @desc  : do_bad_sync handles the impossible case in the Synchronous Abort vector,
 *              you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_bad_sync(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "Bad mode in \"Synchronous Abort at current el with sp0\" handler, but not found your handle implement.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}

/**
 * @desc  : do_bad_irq handles the impossible case in the Irq vector,
 * you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_bad_irq(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "Bad mode in \"Irq at current el with sp0 \" handler\n, but not found your handle implement.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}

/**
 * @desc  : do_bad_fiq handles the impossible case in the Fiq vector,
 * you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_bad_fiq(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "Bad mode in \"Fiq at current el with sp0\" handler, but not found your handle implement.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}

/**
 * @desc  : do_bad_error handles the impossible case in the Error vector,
 *  you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_bad_error(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "Bad mode in \"Error at current el with sp0\" handler, but not found your handle implement.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}

/**
 * @desc  : do_sync handles the Synchronous Abort exception,
 * you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_sync_handle(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "\"Synchronous Abort at current el with spx\" handler, but not found your handle implement.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}

/**
 * @desc  : do_irq handles the Irq exception,
 * you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_irq_handle(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "do Irq handler at current el with spx, but can not found your irq handle.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}

/**
 * @desc  : do_fiq handles the Fiq exception, you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_fiq_handle(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "\"Fiq at current el with spx\" handler, but not found your handle implement.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}


/**
 * @desc  : do_error handles the Error exception, you must re-implement event handle.
 * @param {pt_regs} *pt_regs
 * @param {unsigned int} esr
 * @return {*}
 */
__WEAK AL_VOID do_error(AL_UINTPTR *Regs)
{
    AL_LOG(AL_LOG_LEVEL_ERROR, "\"Error at current el with spx\" handler, but not found your handle implement.\r\n");
    AlBackTrace_Fault(Regs);
    panic();
}
