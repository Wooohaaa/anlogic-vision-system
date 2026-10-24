#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..

CHIP        ?= ph1p35

ELF         ?= GPIO_OUTPUT

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

ifeq ($(ELF), GPIO_INPUT)
C_SRCS += gpio_input.c
else ifeq ($(ELF), GPIO_OUTPUT)
C_SRCS += gpio_output.c
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

ifeq ($(ELF), GPIO_INPUT)
TARGET := $(CHIP)_gpio_input
else ifeq ($(ELF), GPIO_OUTPUT)
TARGET := $(CHIP)_gpio_output
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
