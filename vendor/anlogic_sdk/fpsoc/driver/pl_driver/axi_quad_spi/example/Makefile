#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..


CHIP        ?= dr1v90
#CHIP		?= 	softcore
ELF         ?= X1_3BYTE_INTR_EXAMPLE
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
ifeq ($(ELF), X1_INTR_EXAMPLE)
C_SRCS += al_axi_qspi_x1_intr_example.c
else ifeq ($(ELF), X1_POLLED_EXAMPLE)
C_SRCS += al_axi_qspi_x1_polled_example.c
else ifeq ($(ELF), X1_3BYTE_INTR_EXAMPLE)
C_SRCS += al_axi_qspi_x1_3byte_unit_intr_example.c
else ifeq ($(ELF), X1_3BYTE_POLLED_EXAMPLE)
C_SRCS += al_axi_qspi_x1_3byte_unit_polled_example.c
else ifeq ($(ELF), X1_4BYTE_INTR_EXAMPLE)
C_SRCS += al_axi_qspi_x1_4byte_unit_intr_example.c
else ifeq ($(ELF), X1_4BYTE_POLLED_EXAMPLE)
C_SRCS += al_axi_qspi_x1_4byte_unit_polled_example.c
else ifeq ($(ELF), X2_3BYTE_POLLED_EXAMPLE)
C_SRCS += al_axi_qspi_x2_3byte_unit_polled_example.c
else ifeq ($(ELF), X4_3BYTE_POLLED_EXAMPLE)
C_SRCS += al_axi_qspi_x4_3byte_unit_polled_example.c
else
C_SRCS += al_axi_qspi_x1_intr_example.c
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

#########################################################################
# 4. PINMUX_MODE: sdk internal define, pinmux setting need to remove;
#    Fixme: where to add board init source files and headers files
#########################################################################
# PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
ifeq ($(CHIP), dr1m90)
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
else ifeq ($(CHIP), softcore)
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/softcore_demo_ahb
else
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
endif
#########################################################################
# put these option to board_dr1x90_emulation Makefile
## Available choices:
## PINMUX_MODE1, PINMUX_MODE2, PINMUX_MODE3, PINMUX_MODE_SD1
#########################################################################
PINMUX_MODE ?= PINMUX_MODE1

#########################################################################
# 5. define build target
#########################################################################
TARGET := al_axi_qspi_example

ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(CHIP)_$(ARMv8_STATE)_$(PINMUX_MODE)
endif


include $(SDK_ROOT)/tools/make/rules.mk
