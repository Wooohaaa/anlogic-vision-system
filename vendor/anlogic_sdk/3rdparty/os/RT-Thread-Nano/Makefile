ifneq ($(MAKELEVEL),0)

# (0) include config file
include config.mk
include src.mk

# (1.1) add submodule resource file
SRC_DIR = ./

# (1.2) add submodule include
INC_DIR += ./


# (3) set specificity FLAGS
LIBNAME := rtthread_nano
CFLAGS += $(DEFINES)


include $(AL_SDK_ROOT)/tools/make/rules.mk

else

EXPORT_INC := rt-thread/ \
	rt-thread/include

MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

$(eval PUBLIC_INC_DIR += $(addprefix $(MODULE_DIR),$(EXPORT_INC)))


endif