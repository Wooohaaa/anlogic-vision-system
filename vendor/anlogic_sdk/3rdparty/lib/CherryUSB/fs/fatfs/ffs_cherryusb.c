#include "al_hal.h"

#ifdef HAVE_USBPS_DRIVER

#include "ff.h"
#include "diskio.h"
#include "usbh_core.h"
#include "usbh_msc.h"

struct usbh_msc *active_msc_class;

DSTATUS usb_disk_status(BYTE pdrv)
{
    return RES_OK;
}

DSTATUS usb_disk_initialize(BYTE pdrv)
{
    active_msc_class = (struct usbh_msc *)usbh_find_class_instance("/dev/sda");
    if (active_msc_class == NULL) {
        printf("do not find /dev/sda\r\n");
        return RES_NOTRDY;
    }

    if (usbh_msc_scsi_init(active_msc_class) < 0) {
        return RES_NOTRDY;
    }

    return RES_OK;
}

DSTATUS usb_disk_read(BYTE pdrv, BYTE *buff, LBA_t sector, UINT count)
{
    return usbh_msc_scsi_read10(active_msc_class, sector, buff, count);
}

DSTATUS usb_disk_write(BYTE pdrv, const BYTE *buff, LBA_t sector, UINT count)
{
    return usbh_msc_scsi_write10(active_msc_class, sector, buff, count);
}

DSTATUS usb_disk_ioctl(BYTE pdrv, BYTE cmd, void *buff)
{
    int result = 0;

    switch (cmd) {
        case CTRL_SYNC:
            result = RES_OK;
            break;

        case GET_SECTOR_SIZE:
            *(WORD *)buff = active_msc_class->blocksize;
            result = RES_OK;
            break;

        case GET_BLOCK_SIZE:
            *(DWORD *)buff = 1;
            result = RES_OK;
            break;

        case GET_SECTOR_COUNT:
            *(DWORD *)buff = active_msc_class->blocknum;
            result = RES_OK;
            break;

        default:
            result = RES_PARERR;
            break;
    }

    return result;
}

#endif
