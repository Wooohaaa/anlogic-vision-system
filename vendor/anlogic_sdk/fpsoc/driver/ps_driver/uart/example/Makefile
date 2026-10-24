#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..
TARGET_PATH	:= $(CURDIR)
CHIP        ?= dr1m90

ELF         ?= UART_POLL_NONBLOCK

#####################################################
# select toolchain by CHIP
include $(SDK_ROOT)/tools/make/app.inc
#####################################################

DOWNLOAD = ocm

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
ifeq ($(ELF), UART_POLL_BLOCK)
C_SRCS += al_uart_poll_block.c
else ifeq ($(ELF), UART_INTR_BLOCK)
C_SRCS += al_uart_intr_block.c
else ifeq ($(ELF), UART_POLL_NONBLOCK)
C_SRCS += al_uart_poll_nonblock.c
else ifeq ($(ELF), UART_ECHO)
C_SRCS += al_uart_echo.c
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
# CFLAGS += -DUSE_RTOS
# CFLAGS += -DRTOS_RTTHREAD


#########################################################################
# 4. PINMUX_MODE: sdk internal define, pinmux setting need to remove;
#    Fixme: where to add board init source files and headers files
#########################################################################
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
ifeq ($(ELF), UART_POLL_BLOCK)
TARGET := fpsoc_uart_poll_block
else ifeq ($(ELF), UART_INTR_BLOCK)
TARGET := fpsoc_uart_intr_block
else ifeq ($(ELF), UART_POLL_NONBLOCK)
TARGET := fpsoc_uart_poll_nonblock
endif

ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(CHIP)_$(PINMUX_MODE)
endif


include $(SDK_ROOT)/tools/make/rules.mk
