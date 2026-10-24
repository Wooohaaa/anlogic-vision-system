ifneq ($(MAKELEVEL),0)

# (0) include config file

ifeq ($(RTOS), freertos)
C_SRCS += $(wildcard ./lib/*.c) \
		    $(wildcard ./lib/system/freertos/*.c) \
			$(wildcard ./lib/system/freertos/anlogic_common/*.c) \
			$(wildcard ./lib/system/freertos/dr1m90/*.c)
else
C_SRCS += $(wildcard ./lib/*.c) \
		    $(wildcard ./lib/system/generic/*.c) \
			$(wildcard ./lib/system/generic/anlogic_common/*.c) \
			$(wildcard ./lib/system/generic/dr1m90/*.c)
endif

# (1.2) add submodule include file to /bsp/inc for calling
INC_DIR += include/lib/include \
			$(SDK_ROOT)/fpsoc/inc/

CFLAGS += -DMACHINE="dr1m90" \
			-DDEFAULT_LOGGER_ON \
			-DMETAL_INTERNAL

# (3) set specificity FLAGS
LIBNAME := metal

# (2) compile and return obj-y
include $(AL_SDK_ROOT)/tools/make/rules.mk

else

EXPORT_INC := include/lib/include

# add submodule public include, abspath, include by top rules.mk
MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

$(eval PUBLIC_INC_DIR += $(addprefix $(MODULE_DIR),$(EXPORT_INC)))

endif