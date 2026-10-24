#########################################################################
# Copyright (c) 2023, Anlogic Inc. and Contributors. All rights reserved.

# SPDX-License-Identifier: BSD-3-Clause
#########################################################################

#########################################################################
# 1. define SDK_ROOT, BOARD info, CHIP, COMPILE_PREFIX
#########################################################################

SDK_ROOT    ?= ../../../../..

CHIP        ?= softcore

ELF         ?= USART_INTR


#####################################################
# select toolchain by CHIP
include $(SDK_ROOT)/tools/make/app.inc
#####################################################


ifeq ($(CHIP), softcore)
    OUTPUT_DEV=NONE
endif

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

ifeq ($(ELF), USART_POLLING)
C_SRCS += al_axi_uart_lite_poll_block.c
else ifeq ($(ELF), AXI_UART_LITE_POLL_BLOCK)
C_SRCS += al_axi_uart_lite_poll_block.c
else ifeq ($(ELF), USART_INTR)
C_SRCS += al_axi_uart_lite_intr_block.c
else ifeq ($(ELF), AXI_UART_LITE_INTR_BLOCK)
C_SRCS += al_axi_uart_lite_intr_block.c
endif


INC_DIR     += ./



LD_LIBS     :=
LIB_DIR     :=

CXX_SRCS    :=
ASM_SRCS    :=

#########################################################################
# 3. CFLAGS
#########################################################################
CFLAGS := -O0 -g3
# CFLAGS += -DUSE_RTOS
# CFLAGS += -DRTOS_RTTHREAD

#########################################################################
# 4. PINMUX_MODE: sdk internal define, pinmux setting need to remove;
#    Fixme: where to add board init source files and headers files
#########################################################################
# PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_ph1p35_emulation
ifeq ($(CHIP),  dr1m90)
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
else ifeq ($(CHIP), softcore)
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards//softcore_demo_ahb
else
PLAT_DIR  ?= $(SDK_ROOT)/solutions/boards/board_dr1x90_ad101_v10
endif
#########################################################################
# put these option to board_dr1x90_emulation Makefile
## Available choices:
## PINMUX_MODE1, PINMUX_MODE2, PINMUX_MODE3, PINMUX_MODE_SD1
#########################################################################
ifeq ($(CHIP),  dr1m90)
PINMUX_MODE ?= PINMUX_MODE1
endif
#########################################################################
# 5. define build target
#########################################################################
ifeq ($(ELF), AXI_UART_LITE_POLL_BLOCK)
TARGET := fpsoc_axi_uart_lite_poll_block
else ifeq ($(ELF), AXI_UART_LITE_INTR_BLOCK)
TARGET := fpsoc_axi_uart_lite_intr_block
else ifeq ($(ELF), USART_POLLING)
TARGET := $(CHIP)_uart_polling
else ifeq ($(ELF), USART_INTR)
TARGET := $(CHIP)_uart_intr
else ifeq ($(ELF), USART_DMA)
TARGET := $(CHIP)_uart_dma
endif

ifneq ($(PINMUX_MODE),)
CFLAGS += -DENABLE_$(PINMUX_MODE)=1
TARGET:=$(TARGET)_$(CHIP)_$(PINMUX_MODE)
endif

all: $(TARGET)
	@$(ECHO) COMPILE_PREFIX = $(COMPILE_PREFIX)

cleanapp:
	$(RM) $(foreach subdir, $(SRC_DIR), $(wildcard $(subdir)/*.d $(subdir)/*.o))

clean:
	ifeq ($(CHIP), dr1m90)
	make clean CHIP=dr1m90
	make clean CHIP=dr1v90
	else
	make clean CHIP=softcore
	make clean CHIP=softcore
	endif

cleanelf:
	rm -rf *.bin *.dasm *.dump *.elf *.hex *.map *.verilog

include $(SDK_ROOT)/tools/make/rules.mk
