SDK_ROOT := C:/Anlogic/workspaces/ph1p35_terminal_demo
CHIP := ph1p35
COMPILE_PREFIX := C:/Anlogic/FD_Release_2026.2/toolchain/gcc/riscv/ph1p35/bin/riscv64-unknown-elf-
TARGET_PATH := $(CURDIR)
DOWNLOAD := tcm
PLAT_DIR := $(SDK_ROOT)/platform
SRC_DIR := ./
INC_DIR := ./ ../aruco_app ../stepper_app
CFLAGS := -Os -g -fstack-usage
LDFLAGS += -Wl,--defsym=__STACK_SIZE=2048 -Wl,--wrap=al_simp_printf -Wl,--wrap=printf -Wl,--wrap=puts
PFLOAT := 0
TARGET := mcu_stepper_v69
include $(SDK_ROOT)/tools/make/rules.mk
