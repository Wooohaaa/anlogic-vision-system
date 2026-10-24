# (0) include config file
ifneq ($(MAKELEVEL),0)

# (1.1) add submodule resource file
SRC_DIR += ./src/core \
           ./src/core/ipv4 \
           ./src/core/ipv6 \
           ./src/api \
           ./ports/netif/netif_gbe \
           ./ports/netif/netif_ethlite \
           ./ports/OS

# (1.2) add submodule private include

C_SRCS += ./src/netif/ethernet.c

# (3) set specificity FLAGS
LIBNAME := lwip

include $(AL_SDK_ROOT)/tools/make/rules.mk

else

EXPORT_INC := src/include/ \
              src/include/compat/posix \
              ports \
              ports/netif/netif_gbe \
              ports/netif/netif_ethlite

# add submodule public include, abspath, include by top rules.mk
MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))

$(eval PUBLIC_INC_DIR += $(addprefix $(MODULE_DIR),$(EXPORT_INC)))

endif