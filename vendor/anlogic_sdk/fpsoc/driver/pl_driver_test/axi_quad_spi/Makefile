#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../..

DOWNLOAD    := ddr

CHIP        ?= dr1m90
ELF         ?= FREERTOS_AXI_QSPI_TEST
ARMv8_STATE ?= 64

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

C_SRCS += freertos_axi_spi_test.c
RTOS   := freertos


INC_DIR     += ./

LD_LIBS     :=
LIB_DIR     :=

CXX_SRCS    :=
ASM_SRCS    :=

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

#########################################################################
# put these option to board_dr1x90_emulation Makefile
## Available choices:
## PINMUX_MODE1, PINMUX_MODE2, PINMUX_MODE3, PINMUX_MODE_SD1
#########################################################################
PINMUX_MODE ?= PINMUX_MODE1

#########################################################################
# 5. define build target
#########################################################################
TARGET := freertos_axi_spi_test

ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(CHIP)_$(ARMv8_STATE)_$(PINMUX_MODE)
endif


include $(SDK_ROOT)/tools/make/rules.mk
