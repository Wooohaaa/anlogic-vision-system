#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..


CHIP        ?= dr1m90
ELF         ?= NONDMA
IP        	?= MMC0
ARMv8_STATE ?= 64
DOWNLOAD    ?= ddr

#####################################################
# select toolchain by CHIP
include $(SDK_ROOT)/tools/make/app.inc
#####################################################

#########################################################################
# 2. define SRC_DIR, INC_DIR, LD_LIBS, LIB_DIR
#    SRC_DIR: application source path
#    INC_DIR  application header path
#    LD_LIBS: External library files that the app depends on
#    LIB_DIR: The path where the external library file resides
#    C_SRCS:   c sources for application
#    CXX_SRCS: cpp sources for application
#    ASM_SRCS: asm sources for application
#########################################################################
ifeq ($(ELF), NONDMA)
C_SRCS += al_mmc_non_dma_blocked.c
else ifeq ($(ELF), SDMA)
C_SRCS += al_mmc_sdma_blocked.c
else ifeq ($(ELF), SDMA_BYTE)
C_SRCS += al_mmc_sdma_byte_blocked.c
else ifeq ($(ELF), TUNING)
C_SRCS += al_mmc_tuning_phase.c
else
C_SRCS += al_mmc_adma2_blocked.c
endif

INC_DIR     += ./

LD_LIBS     :=
LIB_DIR     :=

CXX_SRCS    :=
ASM_SRCS    :=

#########################################################################
# 3. CFLAGS
#########################################################################
CFLAGS := -O2 -g
ifeq ($(IP), MMC0)
CFLAGS += -DDEVICE_ID=0
else ifeq ($(IP), MMC1)
CFLAGS += -DDEVICE_ID=1
else
CFLAGS += -DDEVICE_ID=0
endif

ifeq ($(ELF), TUNING)
CFLAGS += -DAL_MMC_AUTOTUNING_ENABLE
endif

#########################################################################
# 4. PINMUX_MODE: sdk internal define, pinmux setting need to remove;
#    Fixme: where to add board init source files and headers files
#########################################################################
# PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v20

#########################################################################
# put these option to board_dr1x90_emulation Makefile
## Available choices:
## PINMUX_MODE1, PINMUX_MODE2, PINMUX_MODE3, PINMUX_MODE_SD1
#########################################################################
PINMUX_MODE ?= PINMUX_MODE1

#########################################################################
# 5. define build target
#########################################################################
ifeq ($(ELF), NONDMA)
TARGET := fpsoc_mmc_example_non_dma_block
else ifeq ($(ELF), SDMA)
TARGET := fpsoc_mmc_example_sdma_block
else ifeq ($(ELF), SDMA_BYTE)
TARGET := fpsoc_mmc_example_sdma_byte_block
else ifeq ($(ELF), TUNING)
TARGET := fpsoc_mmc_example_tuning_phase
else
TARGET := fpsoc_mmc_example_adma2_block
endif

ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(IP)_$(CHIP)_$(ARMv8_STATE)_$(PINMUX_MODE)
endif


include $(SDK_ROOT)/tools/make/rules.mk
