ifneq ($(MAKELEVEL),0)

# (1.1) add submodule resource file
C_SRCS += ./class/cdc/usbd_cdc_acm.c   \
          ./class/msc/usbh_msc.c       \
          ./class/hub/usbh_hub.c       \
          ./core/usbh_core.c           \
          ./core/usbd_core.c           \
          ./osal/al_usb_osal.c         \
          ./port/dwc2/usb_dc_dwc2.c    \
          ./port/dwc2/usb_hc_dwc2.c    \
          ./fs/fatfs/ffs_cherryusb.c

LIBNAME := cherryusb_driver
include $(AL_SDK_ROOT)/tools/make/rules.mk


else
# (1.2) add submodule include
EXPORT_INC := common      \
              port/dwc2   \
              core        \
              class/cdc   \
              class/video \
              class/hid   \
              class/hub   \
              class/msc   \
              class/audio \
              osal

MODULE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
$(eval PUBLIC_INC_DIR += $(addprefix $(MODULE_DIR),$(EXPORT_INC)))

endif
