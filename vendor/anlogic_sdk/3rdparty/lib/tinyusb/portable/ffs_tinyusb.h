/*
 * Copyright (c) 2024 anlogic
 *
 * SPDX-License-Identifier: BSD-3-Clause
 *
 */

#ifndef FFS_TINYUSB_H
#define FFS_TINYUSB_H

#ifdef TINYUSB_FAT

#include "diskio.h"
#include "tusb.h"
#include "tusb_config.h"

#if defined(__cplusplus)
extern "C" {
#endif /* __cplusplus */

DSTATUS tinyusb_disk_initialize(BYTE pdrv);
DSTATUS tinyusb_disk_deinitialize(BYTE pdrv);
DSTATUS tinyusb_disk_status(BYTE pdrv);
DRESULT tinyusb_disk_read(BYTE pdrv, BYTE *buff, DWORD sector, BYTE count);
DRESULT tinyusb_disk_write(BYTE pdrv, const BYTE *buff, DWORD sector, BYTE count);
DRESULT tinyusb_disk_ioctl(BYTE pdrv, BYTE cmd, void *buff);

#if defined(__cplusplus)
}
#endif /* __cplusplus */
#endif /* TINYUSB */
#endif /* FFS_TINYUSB_H */
