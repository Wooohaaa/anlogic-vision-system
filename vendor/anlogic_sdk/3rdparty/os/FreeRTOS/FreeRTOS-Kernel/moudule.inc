
ifeq ($(AL_CHIP),dr1m90)
sub_module +=   $(CHIP_DIR)/../../../arch/arm/armv8/aarch64/cortex-a/inc \
                $(AL_SDK_ROOT)/3rdparty/os/FreeRTOS/FreeRTOS-Kernel/portable/GCC/ARM_CA53_64_BIT_SRE \
                $(CHIP_DIR)/../../../arch/common/inc \
                $(CHIP_DIR)/../../../arch/arm/common/gic_v3/inc \
                $(AL_SDK_ROOT)/3rdparty/os/FreeRTOS/FreeRTOS-Kernel/include \
                $(AL_SDK_ROOT)/3rdparty/os/FreeRTOS/FreeRTOS-Kernel \
                $(CHIP_DIR)/../../../arch/riscv/ext-nuclei/inc

else ifeq ($(AL_CHIP), dr1v90)

sub_module +=   $(AL_SDK_ROOT)/fpsoc/arch/riscv/rv64/inc \
                $(AL_SDK_ROOT)/fpsoc/arch/riscv/ext-nuclei/inc \
                $(CHIP_DIR)/../../../arch/common/inc \
                $(AL_SDK_ROOT)/3rdparty/os/FreeRTOS/FreeRTOS-Kernel/portable/GCC/RISC-V \
                $(AL_SDK_ROOT)/3rdparty/os/FreeRTOS/FreeRTOS-Kernel/include \
                $(AL_SDK_ROOT)/3rdparty/os/FreeRTOS/FreeRTOS-Kernel \
                $(CHIP_DIR)/../../../arch/riscv/ext-nuclei/inc \
                $(CHIP_DIR)/../../../arch/riscv/rv64/inc

CFLAGS += -D__SYSTIMER_PRESENT=1 -D__Vendor_SysTickConfig=0 -D__ECLIC_PRESENT=1

endif
