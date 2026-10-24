ifneq ($(MAKELEVEL),0)

# (0) include config file

# (1.1) add submodule resource file
C_SRCS += $(wildcard ./lib/*.c) \
		    $(wildcard ./lib/rpmsg/*.c) \
			$(wildcard ./lib/virtio/*.c) \
			$(wildcard ./lib/remoteproc/*.c) \
			$(wildcard ./lib/service/rpmsg/rpc/*.c)

# (1.2) add submodule include file to /bsp/inc for calling
CFLAGS += -DMACHINE=$(AL_CHIP) \
			-DCMAKE_SYSTEM_PROCESSOR="arm" \
			-DCMAKE_SYSTEM_NAME="Generic" \
			-DCMAKE_C_COMPILER_FORCED=ON \
			-DWITH_APPS=OFF \
			-DWITH_DCACHE_VRINGS=ON \
			-DVIRTIO_CACHED_VRINGS \
			-DVIRTIO_CACHED_BUFFERS

WITH_PROXY ?= 0
ifeq ($(WITH_PROXY),1)
C_SRCS += $(wildcard ./lib/proxy/*.c)
CFLAGS += -DWITH_PROXY=ON
else

endif


# (3) set specificity FLAGS
LIBNAME := openamp

# (2) compile and return obj-y
include $(AL_SDK_ROOT)/tools/make/rules.mk

else

EXPORT_INC := lib/include \
			lib/rpmsg \
			include/include/generated \
			apps/machine/$(AL_CHIP)

# add submodule public include, abspath, include by top rules.mk
MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

$(eval PUBLIC_INC_DIR += $(addprefix $(MODULE_DIR),$(EXPORT_INC)))


endif