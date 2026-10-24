#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..


CHIP        ?= dr1m90

DOWNLOAD = ocm

ELF ?= axi_iic_eeprom

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
# ifeq ($(ELF), loop_master_rx_slave_tx)
# C_SRCS += loop_master_rx_slave_tx.c
# else ifeq ($(ELF), loop_master_tx_slave_rx)
# C_SRCS += loop_master_tx_slave_rx.c
# else ifeq ($(ELF), master_periphral)
# C_SRCS += master_periphral.c
# else ifeq ($(ELF), axi_iic_eeprom)
# C_SRCS += axi_iic_eeprom.c
# else ifeq ($(ELF), axi_iic_loop)
# C_SRCS += axi_iic_loop.c
# else
# C_SRCS += loop_master_rx_slave_tx.c
# endif

C_SRCS += $(ELF).c
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
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v20

#########################################################################
# put these option to board_dr1x90_emulation Makefile
## Available choices:
## PINMUX_MODE1, PINMUX_MODE2, PINMUX_MODE3, PINMUX_MODE_SD1
#########################################################################
PINMUX_MODE ?= PINMUX_MODE1
# DOWNLOAD = ocm
#########################################################################
# 5. define build target
#########################################################################
# ifeq ($(ELF), loop_master_rx_slave_tx)
# TARGET := loop_master_rx_slave_tx
# else ifeq ($(ELF), loop_master_tx_slave_rx)
# TARGET := loop_master_tx_slave_rx
# else ifeq ($(ELF), master_periphral)
# TARGET := master_periphral
# else ifeq ($(ELF), axi_iic_eeprom)
# TARGET := axi_iic_eeprom
# else ifeq ($(ELF), axi_iic_loop)
# TARGET := axi_iic_loop
# else
# TARGET := master_periphral
# endif

TARGET := $(ELF)


ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(CHIP)_$(PINMUX_MODE)
endif


include $(SDK_ROOT)/tools/make/rules.mk
