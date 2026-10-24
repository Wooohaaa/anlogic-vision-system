/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2021, Ha Thach (tinyusb.org)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * This file is part of the TinyUSB stack.
 */

#ifndef _TUSB_DWC2_DR1X_H_
#define _TUSB_DWC2_DR1X_H_

#ifdef __cplusplus
 extern "C" {
#endif

#include "al_hal.h"

#ifndef CFG_DWC2_USB_EP_MAX
  #define CFG_DWC2_USB_EP_MAX                16
#endif

#define DWC2_EP_MAX         CFG_DWC2_USB_EP_MAX

#ifndef CFG_DWC2_USB0_EP_FIFO_SIZE
  #define CFG_DWC2_USB0_EP_FIFO_SIZE      16384
#endif

#ifndef CFG_DWC2_USB1_EP_FIFO_SIZE
  #define CFG_DWC2_USB1_EP_FIFO_SIZE      16384
#endif

static const dwc2_controller_t _dwc2_controller[] =
{
#ifdef USB0PS_ENABLE
  { .reg_base = USB0__BASE_ADDR, .irqnum = SOC_USB0_IRQn, .ep_count = CFG_DWC2_USB_EP_MAX, .ep_fifo_size = CFG_DWC2_USB0_EP_FIFO_SIZE },
#else
  {},
#endif

#ifdef USB1PS_ENABLE
  { .reg_base = USB1__BASE_ADDR, .irqnum = SOC_USB1_IRQn, .ep_count = CFG_DWC2_USB_EP_MAX, .ep_fifo_size = CFG_DWC2_USB1_EP_FIFO_SIZE },
#else
  {},
#endif
};

TU_ATTR_ALWAYS_INLINE static inline void dwc2_int_set(uint8_t rhport, tusb_role_t role, bool enabled)
{
  if (enabled) {
    AlIntr_SetInterrupt(_dwc2_controller[rhport].irqnum, AL_FUNC_ENABLE);
  } else {
    /* Even if the USB interrupt is turned off, this action is not transient.
     * If the USB generates another interrupt at this moment, it will enter the interrupt function of GIC,
     * and the action of turning off the USB interrupt will take effect. Reading the interrupt number in GIC will fail.
     * So you can turn off the total interrupt first, because turning off the total interrupt is an atomic operation.
     */
    AlIntr_SetLocalInterrupt(AL_FUNC_DISABLE);
    AlIntr_SetInterrupt(_dwc2_controller[rhport].irqnum, AL_FUNC_DISABLE);
    AlIntr_SetLocalInterrupt(AL_FUNC_ENABLE);
  }
}

#define dwc2_dcd_int_enable(_rhport)  dwc2_int_set(_rhport, TUSB_ROLE_DEVICE, AL_FUNC_ENABLE)
#define dwc2_dcd_int_disable(_rhport) dwc2_int_set(_rhport, TUSB_ROLE_DEVICE, AL_FUNC_DISABLE)

static inline void dwc2_remote_wakeup_delay(void)
{
  // try to delay for 1 ms
  AlSys_MDelay(1);
}

// MCU specific PHY init, called BEFORE core reset
static inline void dwc2_phy_init(dwc2_regs_t * dwc2, uint8_t hs_phy_type)
{
  (void) dwc2;
  (void) hs_phy_type;

  // nothing to do
}

// MCU specific PHY update, it is called AFTER init() and core reset
static inline void dwc2_phy_update(dwc2_regs_t * dwc2, uint8_t hs_phy_type)
{
  (void) dwc2;
  (void) hs_phy_type;

  // nothing to do
}

//--------------------------------------------------------------------+
// Data Cache
//--------------------------------------------------------------------+
#if CFG_TUD_DWC2_DMA_ENABLE || CFG_TUH_DWC2_DMA_ENABLE

#include "al_compiler.h"

// Check for cache line size configuration
#if CFG_TUD_MEM_DCACHE_LINE_SIZE != CACHE_LINE_SIZE || \
    CFG_TUH_MEM_DCACHE_LINE_SIZE != CACHE_LINE_SIZE
    #error "CFG_TUD/TUH_MEM_DCACHE_LINE_SIZE must match CACHE_LINE_SIZE"
#endif

// Function to round up to the nearest cache line size
TU_ATTR_ALWAYS_INLINE static inline uint32_t round_up_to_cache_line_size(uint32_t size)
{
    if (size & (CACHE_LINE_SIZE - 1)) {
        size = (size & ~(CACHE_LINE_SIZE - 1)) + CACHE_LINE_SIZE;
    }
    return size;
}

// Function to clean data cache
TU_ATTR_ALWAYS_INLINE static inline bool dwc2_dcache_clean(const void* addr, uint32_t data_size)
{
    uint32_t adjusted_size = round_up_to_cache_line_size(data_size);
    AlCache_FlushDcacheRange((AL_UINTPTR)addr, (AL_UINTPTR)(addr + adjusted_size));
    return true;
}

// Function to invalidate data cache
TU_ATTR_ALWAYS_INLINE static inline bool dwc2_dcache_invalidate(const void* addr, uint32_t data_size)
{
    uint32_t adjusted_size = round_up_to_cache_line_size(data_size);
    AlCache_InvalidateDcacheRange((AL_UINTPTR)addr, (AL_UINTPTR)(addr + adjusted_size));
    return true;
}

// Function to clean and invalidate data cache
TU_ATTR_ALWAYS_INLINE static inline bool dwc2_dcache_clean_invalidate(const void* addr, uint32_t data_size)
{
    uint32_t adjusted_size = round_up_to_cache_line_size(data_size);
    AlCache_FlushDcacheRange((AL_UINTPTR)addr, (AL_UINTPTR)(addr + adjusted_size));
    AlCache_InvalidateDcacheRange((AL_UINTPTR)addr, (AL_UINTPTR)(addr + adjusted_size));
    return true;
}

#endif // CFG_TUD_DWC2_DMA_ENABLE || CFG_TUH_DWC2_DMA_ENABLE


#ifdef __cplusplus
 }
#endif

#endif
