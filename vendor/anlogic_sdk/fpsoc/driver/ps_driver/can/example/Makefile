#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..


CHIP        ?= dr1m90
ELF         ?= IN_LOOPBACK_IOCTL
ARMv8_STATE ?= 64
DOWNLOAD    ?= ocm

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
ifeq ($(ELF), EX_LOOPBACK)
C_SRCS += al_can_ex_loopback_blocked.c
else ifeq ($(ELF), FD_DMA)
C_SRCS += al_can_fd_dma_nonblock.c
else ifeq ($(ELF), FD_DMA_LLP)
C_SRCS += al_can_fd_dma_llp_nonblock.c
else ifeq ($(ELF), FD_STB_FIFO)
C_SRCS += al_can_fd_stb_fifo_blocked.c
else ifeq ($(ELF), FD_STB_PRIO)
C_SRCS += al_can_fd_stb_priority_blocked.c
else ifeq ($(ELF), STD_STB)
C_SRCS += al_can_std_stb.c
else ifeq ($(ELF), STD_PTB_BLOCK)
C_SRCS += al_can_std_ptb_blocked.c
else ifeq ($(ELF), IN_LOOPBACK_POLLING)
C_SRCS += al_can_in_loopback_polling.c
else ifeq ($(ELF), IN_LOOPBACK_IOCTL)
C_SRCS += al_can_in_loopback_ioctl.c
else
C_SRCS += al_can_in_loopback_blocked.c
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
CFLAGS += -DCAN_DEBUG
# CFLAGS += -DUSE_RTOS
# CFLAGS += -DRTOS_RTTHREAD

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
ifeq ($(ELF), EX_LOOPBACK)
TARGET := fpsoc_can_example_ex_loopback_block
else ifeq ($(ELF), FD_DMA)
TARGET := fpsoc_can_example_fd_dma_nonblock
else ifeq ($(ELF), FD_DMA_LLP)
TARGET := fpsoc_can_example_fd_dma_llp_nonblock
else ifeq ($(ELF), FD_STB_FIFO)
TARGET := fpsoc_can_example_fd_stb_fifo_block
else ifeq ($(ELF), FD_STB_PRIO)
TARGET := fpsoc_can_example_fd_stb_priority_block
else ifeq ($(ELF), STD_PTB_BLOCK)
TARGET := fpsoc_can_example_std_ptb_block
else ifeq ($(ELF), STD_STB)
TARGET := fpsoc_can_example_std_stb
else ifeq ($(ELF), IN_LOOPBACK_POLLING)
TARGET := fpsoc_can_example_in_loopback_polling
else ifeq ($(ELF), IN_LOOPBACK_IOCTL)
TARGET := fpsoc_can_example_in_loopback_ioctl
else
TARGET := fpsoc_can_example_in_loopback_block
endif

ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(CHIP)_$(ARMv8_STATE)_$(PINMUX_MODE)
endif


include $(SDK_ROOT)/tools/make/rules.mk
