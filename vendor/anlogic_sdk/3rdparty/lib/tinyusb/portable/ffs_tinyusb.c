/*
 * Copyright (c) 2024 anlogic
 *
 * SPDX-License-Identifier: BSD-3-Clause
 *
 */

#include "al_hal.h"

#ifdef HAVE_USBPS_DRIVER

#include "diskio.h"
#include "tusb.h"
#include "tusb_config.h"

#if CFG_TUH_MSC

static DSTATUS tinyusb_disk_stat[CFG_TUH_DEVICE_MAX];
static volatile bool tinyusb_xfer_busy[CFG_TUH_DEVICE_MAX];

static bool usb_disk_io_complete_cb(uint8_t dev_addr, tuh_msc_complete_data_t const *cb_data)
{
    (void)dev_addr;
    *(bool *)cb_data->user_arg = false;

    return true;
}

static void tinyusb_wait_for_disk_io(BYTE pdrv)
{
    while (tinyusb_xfer_busy[pdrv]) {
#if CFG_TUSB_OS == OPT_OS_NONE
        tuh_task();
#else
        osal_task_delay(10);
#endif
    }
}

DSTATUS usb_disk_status(BYTE pdrv)
{
    uint8_t usb_addr = pdrv + 1;

    /* set the default status as STA_NOINIT */
    tinyusb_disk_stat[pdrv] = STA_NOINIT;

    if (tuh_msc_mounted(usb_addr) == true) {
        tinyusb_disk_stat[pdrv] &= ~STA_NOINIT;
    } else {
        tinyusb_disk_stat[pdrv] |= STA_NODISK;
    }

    return tinyusb_disk_stat[pdrv];
}

DSTATUS usb_disk_deinitialize(BYTE pdrv)
{
    /* set the default status as STA_NOINIT */
    tinyusb_disk_stat[pdrv] = STA_NOINIT;

    return RES_OK;
}

DSTATUS usb_disk_initialize(BYTE pdrv)
{
    uint8_t usb_addr = pdrv + 1;

    /* set the default status as STA_NOINIT */
    tinyusb_disk_stat[pdrv] = STA_NOINIT;

    if (tuh_msc_mounted(usb_addr) == true) {
        tinyusb_disk_stat[pdrv] &= ~STA_NOINIT;
    } else {
        tinyusb_disk_stat[pdrv] |= STA_NODISK;
    }

    return tinyusb_disk_stat[pdrv];
}

DSTATUS usb_disk_ioctl(BYTE pdrv, BYTE cmd, void *buff)
{
    uint8_t const dev_addr = pdrv + 1;
    uint8_t const lun = 0;

    switch (cmd) {
        // nothing to do since we do blocking
        case CTRL_SYNC:
            return RES_OK;

        case GET_SECTOR_COUNT:
            *((DWORD*)buff) = (WORD)tuh_msc_get_block_count(dev_addr, lun);
            return RES_OK;

        case GET_SECTOR_SIZE:
            *((DWORD*)buff) = (WORD)tuh_msc_get_block_size(dev_addr, lun);
            return RES_OK;

        case GET_BLOCK_SIZE:
            *((DWORD*)buff) = 1;
            return RES_OK;

        default:
            return RES_PARERR;
    }

    return RES_OK;

}

DSTATUS usb_disk_read(BYTE pdrv, BYTE *buff, DWORD sector, BYTE count)
{
    uint8_t usb_addr = pdrv + 1;
    uint32_t sector_size = 0;
    bool result;

    tinyusb_xfer_busy[pdrv] = true;

    usb_disk_ioctl(pdrv, GET_SECTOR_SIZE, &sector_size);
    AlCache_InvalidateDcacheRange((AL_UINTPTR)buff, (AL_UINTPTR)(buff + (sector_size * count)));

    result = tuh_msc_read10(usb_addr, 0, buff, sector, count, usb_disk_io_complete_cb, (uintptr_t)&tinyusb_xfer_busy[pdrv]);
    if (result) {
        tinyusb_wait_for_disk_io(pdrv);
    }

    return result ? RES_OK : RES_ERROR;
}

DSTATUS usb_disk_write(BYTE pdrv, const BYTE *buff, DWORD sector, BYTE count)
{
    uint8_t usb_addr = pdrv + 1;
    uint32_t sector_size = 0;
    bool result;

    tinyusb_xfer_busy[pdrv] = true;

    usb_disk_ioctl(pdrv, GET_SECTOR_SIZE, &sector_size);
    AlCache_FlushDcacheRange((AL_UINTPTR)buff, (AL_UINTPTR)(buff + (sector_size * count)));

    result = tuh_msc_write10(usb_addr, 0, buff, sector, count, usb_disk_io_complete_cb, (uintptr_t)&tinyusb_xfer_busy[pdrv]);
    if (result) {
        tinyusb_wait_for_disk_io(pdrv);
    }

    return result ? RES_OK : RES_ERROR;
}

#endif

#endif
