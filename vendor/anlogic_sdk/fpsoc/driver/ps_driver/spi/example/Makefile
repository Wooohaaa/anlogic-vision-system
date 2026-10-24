#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..

CHIP            ?= dr1m90
ARMv8_STATE     ?= 64

ELF         ?= SPI_NOR_POLL

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
ifeq ($(ELF), SPI_NOR)
C_SRCS += al_spi_nor.c
else ifeq ($(ELF), SPI_NOR_POLL)
C_SRCS += al_spi_nor_polling.c
else ifeq ($(ELF), SPI_MASTER)
C_SRCS += al_spi_master.c
else ifeq ($(ELF), SPI_MASTER_POLL)
C_SRCS += al_spi_master_polling.c
else ifeq ($(ELF), SPI_DMA_NOR)
C_SRCS += al_spi_dma_nor.c
else ifeq ($(ELF), SPI_SLAVE)
C_SRCS += al_spi_slave.c
else
C_SRCS += al_spi_master.c
endif

INC_DIR     += ./

LD_LIBS     :=
LIB_DIR     :=

CXX_SRCS    :=
ASM_SRCS    :=

#########################################################################
# 3. CFLAGS
#########################################################################
CFLAGS := -O2 -g -DAL_TEST_SPI
# CFLAGS += -DAL_BRINGUP -DAL_OSC_33 -DAL_CLK_CONFIG
# CFLAGS += -DUSE_RTOS
# CFLAGS += -DRTOS_RTTHREAD

#########################################################################
# 4. PINMUX_MODE: sdk internal define, pinmux setting need to remove;
#    Fixme: where to add board init source files and headers files
#########################################################################
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
#PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10

#########################################################################
# put these option to board_dr1x90_emulation Makefile
## Available choices:
## PINMUX_MODE1, PINMUX_MODE2, PINMUX_MODE3, PINMUX_MODE_SD1
#########################################################################
PINMUX_MODE ?= PINMUX_MODE1

#########################################################################
# 5. define build target
#########################################################################
ifeq ($(ELF), SPI_NOR)
TARGET := fpsoc_spi_nor_example
else ifeq ($(ELF), SPI_NOR_POLL)
TARGET := fpsoc_spi_nor_poll_example
else ifeq ($(ELF), SPI_MASTER)
TARGET := fpsoc_spi_master_example
else ifeq ($(ELF), SPI_MASTER_POLL)
TARGET := fpsoc_spi_master_poll_example
else ifeq ($(ELF), SPI_DMA_NOR)
TARGET := fpsoc_spi_dma_nor_example
else ifeq ($(ELF), SPI_SLAVE)
TARGET := fpsoc_spi_slave_example
else
TARGET := fpsoc_spi_master_example
endif

ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(CHIP)_$(PINMUX_MODE)
endif


include $(SDK_ROOT)/tools/make/rules.mk
