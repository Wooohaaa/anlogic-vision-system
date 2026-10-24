ifneq ($(MAKELEVEL),0)

# (0) include config file

ifeq ($(CHIP_ARCH),armv8-a)

    ifeq ($(ARMv8_EL),EL1)
        CFLAGS += -DGUEST
    endif

    # (1.1) add submodule resource file
    SRC_DIR += ./ \
               portable/GCC/ARM_CA53_64_BIT_SRE \
               FreeRTOS-Plus-CLI

    C_SRCS	+= portable/MemMang/heap_4.c

    # (1.2) add submodule include
    INC_DIR += ./ \
               include \
               FreeRTOS-Plus-CLI \
               portable/GCC/ARM_CA53_64_BIT_SRE

    INC_DIR += $(AL_SDK_ROOT)/fpsoc/arch/arm/common/gic_v3/inc \
               $(AL_SDK_ROOT)/fpsoc/arch/arm/armv8/aarch64/cortex-a/inc \
               $(AL_SDK_ROOT)/fpsoc/arch \
               $(AL_SDK_ROOT)/fpsoc/arch/arm/common/gic_v3/inc \
               $(AL_SDK_ROOT)/fpsoc/arch/common/inc \

else
    # (1.1) add submodule resource file
    SRC_DIR += ./ \
               FreeRTOS-Plus-CLI \
               portable/GCC/RISC-V

    C_SRCS	= portable/MemMang/heap_4.c

    # (1.2) add submodule include
    INC_DIR += ./ \
               ./include \
               ./FreeRTOS-Plus-CLI
endif #armv8-a

# (3) set specificity FLAGS
LIBNAME := freertos_smp

include $(AL_SDK_ROOT)/tools/make/rules.mk

else

ifeq ($(CHIP_ARCH),armv8-a)
    EXPORT_INC = ./ \
                 include \
                 FreeRTOS-Plus-CLI \
                 portable/GCC/ARM_CA53_64_BIT_SRE
else
    EXPORT_INC = ./ \
                 include \
                 FreeRTOS-Plus-CLI \
                 portable/GCC/RISC-V
endif

# add submodule public include, abspath, include by top rules.mk
MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
$(eval PUBLIC_INC_DIR += $(addprefix $(MODULE_DIR),$(EXPORT_INC)))

endif
