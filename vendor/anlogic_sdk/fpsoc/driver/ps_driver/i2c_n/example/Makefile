#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..


CHIP        ?= ph1p35

ELF         ?= I2C_MASTER_POLLING

DOWNLOAD=xip_dlm

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

ifeq ($(ELF), I2C_AT24C04)
C_SRCS += i2c_at24c04.c
else ifeq ($(ELF), I2C_MASTER_POLLING)
C_SRCS += i2c_master_polling.c
else ifeq ($(ELF), I2C_MASTER_DMA)
C_SRCS += i2c_master_dma.c
else ifeq ($(ELF), I2C_MASTER_INTR)
C_SRCS += i2c_master_intr.c
else ifeq ($(ELF), I2C_SLAVE_POLLING)
C_SRCS += i2c_slave_polling.c
else ifeq ($(ELF), I2C_SLAVE_DMA)
C_SRCS += i2c_slave_dma.c
else ifeq ($(ELF), I2C_SLAVE_INTR)
C_SRCS += i2c_slave_intr.c
endif


INC_DIR     += ./

LD_LIBS     :=
LIB_DIR     :=

CXX_SRCS    :=
ASM_SRCS    :=

#########################################################################
# 3. CFLAGS
#########################################################################
CFLAGS := -O2 -g3
# CFLAGS += -DUSE_RTOS
# CFLAGS += -DRTOS_RTTHREAD

#########################################################################
# 4. PINMUX_MODE: sdk internal define, pinmux setting need to remove;
#    Fixme: where to add board init source files and headers files
#########################################################################
# PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_ph1p35_emulation

PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_ph1p35_emulation

#########################################################################
# put these option to board_dr1x90_emulation Makefile
## Available choices:
## PINMUX_MODE1, PINMUX_MODE2, PINMUX_MODE3, PINMUX_MODE_SD1
#########################################################################
# PINMUX_MODE ?= PINMUX_MODE1

#########################################################################
# 5. define build target
#########################################################################

ifeq ($(ELF), I2C_AT24C04)
TARGET := $(CHIP)_i2c_at24c04
else ifeq ($(ELF), I2C_MASTER_POLLING)
TARGET := $(CHIP)_master_polling
else ifeq ($(ELF), I2C_MASTER_DMA)
TARGET := $(CHIP)_master_dma
else ifeq ($(ELF), I2C_MASTER_INTR)
TARGET := $(CHIP)_master_intr
else ifeq ($(ELF), I2C_SLAVE_POLLING)
TARGET := $(CHIP)_slave_polling
else ifeq ($(ELF), I2C_SLAVE_DMA)
TARGET := $(CHIP)_slave_dma
else ifeq ($(ELF), I2C_SLAVE_INTR)
TARGET := $(CHIP)_slave_intr
endif


all: $(TARGET)
	@$(ECHO) COMPILE_PREFIX = $(COMPILE_PREFIX)

cleanapp:
	$(RM) $(foreach subdir, $(SRC_DIR), $(wildcard $(subdir)/*.d $(subdir)/*.o))

clean:
	make clean CHIP=ph1p35
	make clean CHIP=ph1p35

cleanelf:
	rm -rf *.bin *.dasm *.dump *.elf *.hex *.map *.verilog

include $(SDK_ROOT)/tools/make/rules.mk
