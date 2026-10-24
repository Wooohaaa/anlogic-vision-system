#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################


#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################
SDK_ROOT   ?= ../../../../../../../../

CHIP            ?= dr1v90
ARMv8_STATE     ?= 64


#####################################################
# select toolchain by CHIP
include $(SDK_ROOT)/tools/make/app.inc
#####################################################

DOWNLOAD = tcm

#########################################################################
# 2. define SRC_DIR, INC_DIR, LD_LIBS, LIB_DIR
#    LD_LIBS: External library files that the app depends on
#    LIB_DIR: The path where the external library file resides
#    C_SRCS:   c sources for application
#    CXX_SRCS: cpp sources for application
#    ASM_SRCS: asm sources for application
#########################################################################
SRC_DIR  = ./

INC_DIR += ./


LD_LIBS  =
LIB_DIR  =

C_SRCS   :=

CXX_SRCS :=
ASM_SRCS :=

#########################################################################
# 3. CFLAGS
#########################################################################
CFLAGS := -O2 -g

#########################################################################
# 4. PINMUX_MODE: sdk internal define, pinmux setting need to remove;
#    Fixme: where to add board init source files and headers files
#########################################################################
# PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
#PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v20
# PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_hpf_v20



#########################################################################
# 5. define build target
#########################################################################
TARGET := riscv_svm_example


# include rules.mk
include $(SDK_ROOT)/tools/make/rules.mk

# vim: syntax=make
