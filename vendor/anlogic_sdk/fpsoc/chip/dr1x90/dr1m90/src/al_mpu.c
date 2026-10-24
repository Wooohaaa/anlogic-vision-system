
/*
 * Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "al_type.h"
#include "al_chip.h"
#include "al_core.h"
#include "al_hal.h"
#include <string.h>

#if MPU_PROTECT_MODE == 2
#define AL_MPU_CODE_SECTION_ATTR    MPU_REGION_READWRITE
#elif MPU_PROTECT_MODE == 3
#define AL_MPU_CODE_SECTION_ATTR    MPU_REGION_READONLY
#else
#define AL_MPU_CODE_SECTION_ATTR    MPU_REGION_READWRITE
#endif

#define AL_MPU_APU_REGION_NUM   32

extern AL_UINTPTR _text_start;
extern AL_UINTPTR _rodata_start;
extern AL_UINTPTR _data_start;
extern AL_UINTPTR stack_top;

AL_MPU_HalStruct *Dr1m90MpuHandle;

/*--------------------------------------------------------
    name        start       end         size        attr
----------------------------------------------------------
    ddr         0x0         0x5fffffff  0x60000000  if run in ddr, have rodata, rdwrdata
                                                    if not and ddr init, read write
                                                    if not init, no read write
    rpu + rsvd  0x60000000  0x60ffffff  0x10000000  no read write
    ocm         0x61000000  0x6103ffff  0x40000     if run in ocm, have rodata, rdwrdata
                                                    if not, read write
    rsvd        0x61040000  0x63dfffff  0x2db0000   no read write
    npu sram    0x63e00000  0x63e3ffff  0x40000     read write
    npu rsvd    0x63e40000  0x63efffff  0xb0000     no read write
    npu reg     0x63f00000  0x63ffffff  0x200000    read write
    nandc xip   0x64000000  0x64ffffff  0x1000000   read only
    rsvd + rpu  0x65000000  0x6fffffff  0xb000000   no read write
    qspi xip    0x70000000  0x8fffffff  0x10000000  read only
    gp0         0x80000000  0x9fffffff  0x20000000  if no use, no read write
                                                    if use, some addr read write
                                                    default read write
    gp1         0xa0000000  0xbfffffff  0x20000000  if no use, no read write
                                                    if use, some addr read write
                                                    default read write
    rsvd        0xc0000000  0xdcffffff  0x1d000000  no read write
    gic         0xdd000000  0xdd3fffff  0x400000    read write
    rsvd        0xdd400000  0xf8048fff  0x1ac49000  no read write
    spbus       0xf8049000  0xf93fffff  0x13b7000   spbus ip, read write,
                                                    include some rsvd addr, no read write
    rsvd        0xf9400000  0xfbffffff  0x2c00000   no read write
    fahb        0xfc000000  0xffffffff  0x4000000   no read write
--------------------------------------------------------*/

AL_MPU_RegionConfigStruct Dr1m90MemMap[] = {
    {// rpu tcm and reserved mem, no read write fail, why read only?
        .StartAddr  = 0x60000000,
        .Size       = 0x1000000,
        .ReadWrite  = MPU_REGION_READONLY,
    }, {// rsvd, no read write
        .StartAddr  = 0x61040000,
        .Size       = 0x2db0000,
        .ReadWrite  = MPU_REGION_NOREADWRITE,
    }, {// npu sram, read write
        .StartAddr  = 0x63e00000,
        .Size       = 0x40000,
        .ReadWrite  = MPU_REGION_READWRITE,
    }, {// npu rsvd, no read write
        .StartAddr  = 0x63e40000,
        .Size       = 0xb0000,
        .ReadWrite  = MPU_REGION_NOREADWRITE,
    }, {// npu reg, read write
        .StartAddr  = 0x63e40000,
        .Size       = 0xb0000,
        .ReadWrite  = MPU_REGION_READWRITE,
    }, {// nandc xip, read only
        .StartAddr  = 0x64000000,
        .Size       = 0x1000000,
        .ReadWrite  = MPU_REGION_READONLY,
    }, {// reserved and rpu private, no read write
        .StartAddr  = 0x65000000,
        .Size       = 0xb000000,
        .ReadWrite  = MPU_REGION_NOREADWRITE,
    }, {// qspi xip, read only
        .StartAddr  = 0x70000000,
        .Size       = 0x10000000,
        .ReadWrite  = MPU_REGION_READONLY,
    }, {// gpm0, default no read write, if use, need modify this region
        .StartAddr  = 0x80000000,
        .Size       = 0x20000000,
        .ReadWrite  = MPU_REGION_READWRITE,
    }, {// gpm1, default no read write, if use, need modify this region
        .StartAddr  = 0xa0000000,
        .Size       = 0x20000000,
        .ReadWrite  = MPU_REGION_READWRITE,
    }, {// reserved, no read write
        .StartAddr  = 0xc0000000,
        .Size       = 0x1d000000,
        .ReadWrite  = MPU_REGION_NOREADWRITE,
    }, {// gic, read write
        .StartAddr  = 0xdd000000,
        .Size       = 0x400000,
        .ReadWrite  = MPU_REGION_READWRITE,
    }, {// reserved, no read write
        .StartAddr  = 0xdd400000,
        .Size       = 0x1ac49000,
        .ReadWrite  = MPU_REGION_NOREADWRITE,
    }, {// spbus ip, read write, have some rsvd space, optimise later
        .StartAddr  = 0xf8049000,
        .Size       = 0x13b7000,
        .ReadWrite  = MPU_REGION_READWRITE,
    }, {// reserved, no read write
        .StartAddr  = 0xf9400000,
        .Size       = 0x2c00000,
        .ReadWrite  = MPU_REGION_NOREADWRITE,
    }, {// fahb, no read write
        .StartAddr  = 0xfc000000,
        .Size       = 0x4000000,
        .ReadWrite  = MPU_REGION_NOREADWRITE,
    }
};

AL_VOID __attribute__((optimize("0"))) AlMpu_Init(AL_VOID)
{
    AL_S32 Ret = AL_OK;
    AL_U32 FixedRegionNum = sizeof(Dr1m90MemMap) / sizeof(AL_MPU_RegionConfigStruct);

#if DOWNLOAD_MODE == 0
    /* download in ocm */
    AL_MPU_RegionConfigStruct RamRegion[] = {
        {// ddr, read write
            .StartAddr  = 0x0,
            .Size       = 0x40000000,
            .ReadWrite  = MPU_REGION_READWRITE,
        }, {// code, read only data
            .StartAddr  = (AL_U32)((AL_UINTPTR)&_text_start),
            .Size       = (AL_U32)((AL_UINTPTR)&_data_start - (AL_UINTPTR)&_text_start),
            .ReadWrite  = AL_MPU_CODE_SECTION_ATTR,
        }, {// read write data
            .StartAddr  = (AL_U32)((AL_UINTPTR)&_data_start),
            .Size       = (AL_U32)((AL_UINTPTR)&stack_top - (AL_UINTPTR)&_data_start),
            .ReadWrite  = MPU_REGION_READWRITE,
        }
    };
#elif DOWNLOAD_MODE == 1
    /* download in ddr */
    AL_MPU_RegionConfigStruct RamRegion[] = {
        {// ocm, read write
            .StartAddr  = 0x61000000,
            .Size       = 0x40000,
            .ReadWrite  = MPU_REGION_READWRITE,
        }, {// ddr, read write
            .StartAddr  = 0x0,
            .Size       = (AL_U32)((AL_UINTPTR)&_rodata_start),
            .ReadWrite  = MPU_REGION_READWRITE,
        }, {// code, read only data
            .StartAddr  = (AL_U32)((AL_UINTPTR)&_rodata_start),
            .Size       = (AL_U32)((AL_UINTPTR)&_data_start - (AL_UINTPTR)&_rodata_start),
            .ReadWrite  = AL_MPU_CODE_SECTION_ATTR,
        }, {// code, read write data
            .StartAddr  = (AL_U32)((AL_UINTPTR)&_data_start),
            .Size       = (AL_U32)((AL_UINTPTR)&stack_top - (AL_UINTPTR)&_data_start),
            .ReadWrite  = MPU_REGION_READWRITE,
        }, {// ddr, read write
            .StartAddr  = (AL_U32)((AL_UINTPTR)&stack_top),
            .Size       = (AL_U32)(0x40000000 - (AL_UINTPTR)&stack_top),
            .ReadWrite  = MPU_REGION_READWRITE,
        }
    };
#elif DOWNLOAD_MODE == 3
    /* download in xip */
    AL_MPU_RegionConfigStruct RamRegion[] = {
        {// ddr, read write
            .StartAddr  = 0x0,
            .Size       = 0x40000000,
            .ReadWrite  = MPU_REGION_READWRITE,
        }
    };
#else
#error "error download mode!"
#endif

#if MPU_PROTECT_MODE == 1
    AL_U32 RamRegionNum = sizeof(RamRegion) / sizeof(AL_MPU_RegionConfigStruct);
#else
    AL_U32 RamRegionNum = 0;
#endif
    AL_U32 RegionNum = FixedRegionNum + RamRegionNum;
    AL_MPU_RegionConfigStruct RegionConfig[RegionNum];

    for (AL_U32 i = 0; i < RegionNum; i++) {
        if (i < FixedRegionNum) {
            memcpy(&RegionConfig[i], &Dr1m90MemMap[i], sizeof(AL_MPU_RegionConfigStruct));
        } else {
            memcpy(&RegionConfig[i], &RamRegion[i - FixedRegionNum],
                   sizeof(AL_MPU_RegionConfigStruct));
        }

        RegionConfig[i].GroupId             = 0;
        RegionConfig[i].Secure              = MPU_REGION_SECURE;
        RegionConfig[i].Privilege           = MPU_REGION_PRIVILEGE;
        RegionConfig[i].ConfigRegionNumber  = i;
        RegionConfig[i].InterruptEnable     = MPU_REGION_INTERRUPT_ENABLE;
        AL_LOG(AL_LOG_LEVEL_DEBUG, "Region %02d : start at 0x%08lx, size is 0x%08lx, attr is %s.\r\n",
               i, RegionConfig[i].StartAddr, RegionConfig[i].Size,
               (RegionConfig[i].ReadWrite == MPU_REGION_READWRITE) ? "read write" :
               ((RegionConfig[i].ReadWrite == MPU_REGION_READONLY) ? "read only" :
               (RegionConfig[i].ReadWrite == MPU_REGION_WRITEONLY) ? "write only" :
               "no read write"));
    }

    Ret = AlMpu_Hal_ConfigInit(6, &Dr1m90MpuHandle, AL_NULL, RegionConfig, RegionNum);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Dr1m90 mpu init \033[31mfail\033[0m.\r\n");
    } else {
        AL_LOG(AL_LOG_LEVEL_DEBUG, "Dr1m90 mpu init \033[32msuccess\033[0m.\r\n");
    }
}

AL_VOID AlMpu_DisableAll(AL_VOID)
{
    if (AlMpu_Hal_MpuDisable(Dr1m90MpuHandle) == AL_OK) {
        AL_LOG(AL_LOG_LEVEL_DEBUG, "Dr1m90 mpu disable \033[32msuccess\033[0m.\r\n");
    } else {
        AL_LOG(AL_LOG_LEVEL_ERROR, "Dr1m90 mpu disable \033[31mfail\033[0m.\r\n");
    }
}

AL_VOID AlMpu_DecodeErrRegion(AL_VOID)
{
    AL_REG MpuBaseAddr = Dr1m90MpuHandle->Dev->HwConfig.BaseAddress;
    AL_U32 IntrRegionNumber = 0;
    AL_REG RegionBaseAddr, Sar, Ear, RdWr;
    AL_U32 IntrRegion = AlMpu_ll_GetIntrRegionNumber(MpuBaseAddr);

    if (!IntrRegion)
        return;

    while (!(IntrRegion & (BIT(IntrRegionNumber)))) {
        IntrRegionNumber++;
    }

    RegionBaseAddr = MPU_REGION_BASE_ADDR(MpuBaseAddr, IntrRegionNumber);
    Sar = AL_REG32_READ(RegionBaseAddr + MPU_SAR_REGION_OFFSET) << 12;
    Ear = AL_REG32_READ(RegionBaseAddr + MPU_EAR_REGION_OFFSET) << 12;
    RdWr = AL_REG32_GET_BITS(RegionBaseAddr + MPU_RASR_REGION_OFFSET,
                             MPU_RASR_REGION_RW_SHIFT, MPU_RASR_REGION_RW_SIZE);

    AL_LOG(AL_LOG_LEVEL_DEBUG, "err access region sar: 0x%016lx, ear: 0x%016lx, RdWr: %s\r\n",
           Sar, Ear, (RdWr == MPU_REGION_READWRITE) ? "read write" :
           ((RdWr == MPU_REGION_READONLY) ? "read only" :
           (RdWr == MPU_REGION_WRITEONLY) ? "write only" : "no read write"));
}