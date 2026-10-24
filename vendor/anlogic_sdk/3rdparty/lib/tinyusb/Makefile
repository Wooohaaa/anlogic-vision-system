ifneq ($(MAKELEVEL),0)

# (1.1) add submodule resource file
SRC_DIR += portable/synopsys/dwc2 \
           portable

C_SRCS += tusb.c \
          common/tusb_fifo.c \
          device/usbd.c \
          device/usbd_control.c \
          typec/usbc.c \
          class/audio/audio_device.c \
          class/cdc/cdc_device.c \
          class/dfu/dfu_device.c \
          class/dfu/dfu_rt_device.c \
          class/hid/hid_device.c \
          class/midi/midi_device.c \
          class/msc/msc_device.c \
          class/net/ecm_rndis_device.c \
          class/net/ncm_device.c \
          class/usbtmc/usbtmc_device.c \
          class/video/video_device.c \
          class/vendor/vendor_device.c \
          host/usbh.c \
          host/hub.c \
          class/cdc/cdc_host.c \
          class/hid/hid_host.c \
          class/msc/msc_host.c \
          class/vendor/vendor_host.c

LIBNAME := tinyusb
include $(AL_SDK_ROOT)/tools/make/rules.mk


else
# (1.2) add submodule include
EXPORT_INC := ./ \
           class/audio \
           class/bth \
           class/dfu \
           class/hid \
           class/midi \
           class/msc \
           class/net \
           class/usbtmc \
           class/vendor \
           class/video \
           common \
           device \
           host \
           osal \
           portable \
           portable/synopsys/dwc2 \
           typec

# add submodule public include, abspath, include by top rules.mk
MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
$(eval PUBLIC_INC_DIR += $(addprefix $(MODULE_DIR),$(EXPORT_INC)))

endif
