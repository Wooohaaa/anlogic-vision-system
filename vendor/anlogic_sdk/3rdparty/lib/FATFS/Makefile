ifneq ($(MAKELEVEL),0)

# (1.1) add submodule resource file
SRC_DIR += ./ \
           ./portable


LIBNAME := fatfs
include $(AL_SDK_ROOT)/tools/make/rules.mk


else
# (1.2) add submodule include
EXPORT_INC := ./


MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
$(eval PUBLIC_INC_DIR += $(MODULE_DIR))

endif
