/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef __AL_TOP_H_
#define __AL_TOP_H_

#ifdef __cplusplus
extern "C" {
#endif

#include "al_type.h"

AL_VOID Altop_Syscnts_CounterCtrl(AL_FUNCTION CntStatus);
AL_VOID AlTop_GPPortEnable(AL_VOID);

AL_VOID AlTop_P2F_RstAssert(AL_U32 Index);
AL_VOID AlTop_P2F_RstRelease(AL_U32 Index);
AL_VOID AlTop_GP_ProtetionEnable(AL_VOID);
AL_VOID AlTop_GP_ProtetionDisable(AL_VOID);
AL_VOID AlTop_GP_RstAssert(AL_U32 GpIdx);
AL_VOID AlTop_GP_RstRelease(AL_U32 GpIdx);
AL_VOID AlTop_HP_RstAssert(AL_U32 HpIdx);
AL_VOID AlTop_HP_RstRelease(AL_U32 HpIdx);

#ifdef __cplusplus
}
#endif

#endif /* AL_TOP_H */

