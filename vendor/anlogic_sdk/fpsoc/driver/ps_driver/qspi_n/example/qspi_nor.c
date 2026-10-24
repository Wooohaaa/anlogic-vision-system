#include <stdio.h>
#include <string.h>
#include "al_qspi_hal.h"
#include "al_misc_ll.h"

/* flash operation cmd instruction */
#define FLASH_WriteEnable               0x06
#define FLASH_WriteDisable              0x04
#define FLASH_ReadStatusReg1		    0x05
#define FLASH_ReadStatusReg2		    0x35
#define FLASH_ReadStatusReg3		    0x15
#define FLASH_WriteStatusReg1           0x01
#define FLASH_WriteStatusReg2           0x31
#define FLASH_WriteStatusReg3           0x11
#define FLASH_ReadData                  0x03
#define FLASH_FastReadData              0x0B
#define FLASH_FastReadDual              0x3B
#define FLASH_FastReadQuad              0x6B
#define FLASH_PageProgram               0x02
#define FLASH_BlockErase                0xD8
#define FLASH_SectorErase               0x20
#define FLASH_ChipErase                 0xC7
#define FLASH_PowerDown                 0xB9
#define FLASH_ReleasePowerDown          0xAB
#define FLASH_DeviceID                  0xAB
#define FLASH_ManufactDeviceID          0x90
#define FLASH_JedecDeviceID             0x9F
#define FLASH_Enable4ByteAddr           0xB7
#define FLASH_Exit4ByteAddr             0xE9

/* WIP(busy) flag */
#define WIP_Flag                  0x01
#define Dummy_Byte                0xFF

#define TEST_BUFFER_SIZE         256
AL_U8 TxBuffer[TEST_BUFFER_SIZE] = {0};
AL_U8 RxBuffer[TEST_BUFFER_SIZE] = {0};

AL_QSPI_HalStruct *QspiHandle;

static AL_QSPI_InitStruct QspiInitConfigs = {
    .SckDiv              = 16,
    .DevMode             = AL_QSPI_MASTER,
    .ProtocolMode        = AL_QSPI_PROTOCOL_MODE_SINGLE,
    .FrameLen            = AL_QSPI_FRAMELEN_8BIT,
    .CSMode              = AL_QSPI_CS_MODE_AUTO,
    .CPOL                = AL_QSPI_CLK_LOW_LEVLE,
    .CPHA                = AL_QSPI_CLK_EDGE1,
    .Endian              = AL_QSPI_ENDIAN_MSB,
    .DmaModeEn           = AL_FALSE,
    .TxDmaEn             = AL_FALSE,
    .RxDmaEn             = AL_FALSE,
    .TxDmaContinousEn    = AL_FALSE,
    .RxDmaContinousEn    = AL_FALSE,
};

AL_VOID SPI_ReadJEDEC(AL_VOID) {
    AL_U8 Cmd = FLASH_JedecDeviceID;
    AL_U8 DummyByte = Dummy_Byte;
    AL_U8 JedecDeviceID[3] = {0};

    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_HOLD);
    AlQspi_Hal_SendDataPolling(QspiHandle, &Cmd, 1);
    AlQspi_Hal_RecvDataPolling(QspiHandle, JedecDeviceID, 3);
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_OFF);

    for (AL_U32 i = 0; i < 3; i++) {
        printf("JedecDeviceID[%d]:%#x\r\n", i, (JedecDeviceID[i] & 0xff));
    }
}

AL_VOID SPI_Wip(AL_VOID)
{
    AL_U8 Cmd = FLASH_ReadStatusReg1;
    AL_U8 RecvData;
    AL_U8 temp = 0;
    AL_U32 status = 0;

    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_HOLD);
    AlQspi_Hal_SendDataPolling(QspiHandle, &Cmd, 1);
    do {
        AlQspi_Hal_RecvDataPolling(QspiHandle, &RecvData, 1);
        temp = RecvData & WIP_Flag;
    } while (temp);

    do {
        status = AlQspi_ll_GetStatus(QspiHandle->Dev.BaseAddr);
        temp = status & (1<<0);
    } while (temp);

    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_OFF);
}

AL_VOID SPI_WriteEnable(AL_VOID)
{
    AL_U8 Cmd = FLASH_WriteEnable;

    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_HOLD);
    AlQspi_Hal_SendDataPolling(QspiHandle, &Cmd, 1);
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_OFF);
}

AL_VOID SPI_Quad(AL_VOID)
{
    AL_U8 Cmd = FLASH_WriteStatusReg2;
    AL_U8 Temp = 0x2;
    AlQspi_ll_SetProtocolMode(QspiHandle->Dev.BaseAddr, AL_QSPI_PROTOCOL_MODE_SINGLE);
    SPI_WriteEnable();
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_HOLD);
    AlQspi_Hal_SendDataPolling(QspiHandle, &Cmd, 1);
    AlQspi_Hal_SendDataPolling(QspiHandle, &Temp, 1);
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_OFF);
    SPI_Wip();
}

AL_VOID SPI_Erase(AL_U8 Cmd, AL_U32 Addr)
{
    AL_U8 SendData[4] = {(Cmd & 0xff), ((Addr >> 16) & 0xff), ((Addr >> 8) & 0xff), (Addr & 0xff)};
    SPI_WriteEnable();
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_HOLD);
    AlQspi_Hal_SendDataPolling(QspiHandle, SendData, 4);
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_OFF);
    SPI_Wip();
}

AL_VOID SPI_PageWrite(AL_U8 Cmd, AL_U8* Buf, AL_U32 Addr)
{
    AL_U8 SendData[4] = {(Cmd & 0xff), ((Addr >> 16) & 0xff), ((Addr >> 8) & 0xff), (Addr & 0xff)};
    SPI_WriteEnable();
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_HOLD);
    AlQspi_Hal_SendDataPolling(QspiHandle, SendData, 4);
    AlQspi_Hal_SendDataPolling(QspiHandle, Buf, TEST_BUFFER_SIZE);
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_OFF);
    SPI_Wip();
}

AL_VOID SPI_PageRead(AL_U8 Cmd, AL_U8* Buf, AL_U32 Addr)
{
    AL_U8 SendData[4] = {(Cmd & 0xff), ((Addr >> 16) & 0xff), ((Addr >> 8) & 0xff), (Addr & 0xff)};
    AL_U8 DummyByte = Dummy_Byte;
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_HOLD);
    AlQspi_Hal_SendDataPolling(QspiHandle, SendData, 4);
    AlQspi_Hal_SendDataPolling(QspiHandle, &DummyByte, 1);
    if (Cmd == FLASH_FastReadDual) {
        AlQspi_ll_SetProtocolMode(QspiHandle->Dev.BaseAddr, AL_QSPI_PROTOCOL_MODE_DUAL);
    }
    if (Cmd == FLASH_FastReadQuad) {
        AlQspi_ll_SetProtocolMode(QspiHandle->Dev.BaseAddr, AL_QSPI_PROTOCOL_MODE_QUAD);
    }
    AlQspi_Hal_RecvDataPolling(QspiHandle, Buf, TEST_BUFFER_SIZE);
    AlQspi_Hal_SetCsMode(QspiHandle, AL_QSPI_CS_MODE_OFF);
}

AL_VOID PrintData(AL_U8* Data)
{
    for (AL_U32 i = 0; i < TEST_BUFFER_SIZE; i++) {
        printf("%#x\r\n", (Data[i] & 0xff));
    }
}

AL_U32 CompareArrays(AL_U8* Array1, AL_U8* Array2, AL_U32 size) {
    for (AL_U32 i = 0; i < size; i++) {
        if (Array1[i] != Array2[i]) {
            printf("Array1 %d is %x\r\n", i, Array1[i]);
            printf("Array2 %d is %x\r\n", i, Array2[i]);
        }
    }
    return 0;
}


AL_U32 main()
{
    printf("Qspi nor flash test ...\r\n");

    AL_S32 Ret = AlQspi_Hal_Init(&QspiHandle, 0, &QspiInitConfigs, AL_NULL);
    if (Ret != AL_OK) {
        printf("AlQspi_Hal_Init error\r\n");
        return Ret;
    }

    /* tmp setting for qspi0*/
    AlQspi_ll_SetFlashEn(QspiHandle->Dev.BaseAddr, 0);

    /* tmp setting for qspi0*/
    // *(volatile unsigned int*)0x1104000c=0x0;

    SPI_ReadJEDEC();

    for (AL_U32 i = 0; i < TEST_BUFFER_SIZE; i++) {
        TxBuffer[i] = i;
    }

    SPI_Erase(FLASH_SectorErase, 0xe10000);
    SPI_PageWrite(FLASH_PageProgram, TxBuffer, 0xe10000);
    SPI_PageRead(FLASH_FastReadData, RxBuffer, 0xe10000);
    if (0 == CompareArrays(TxBuffer, RxBuffer, TEST_BUFFER_SIZE)) {
        printf("1 line data cmp pass\r\n");
    } else {
        printf("1 line data cmp error\r\n");
        printf("TxBuffer\r\n");
        PrintData(TxBuffer);
        printf("RxBuffer\r\n");
        PrintData(RxBuffer);
        printf("Qspi nor flash test failed...\r\n");
        return -1;
    }

    memset(RxBuffer, 0x00, TEST_BUFFER_SIZE);
    SPI_PageRead(FLASH_FastReadDual, RxBuffer, 0xe10000);
    if (0 == CompareArrays(TxBuffer, RxBuffer, TEST_BUFFER_SIZE)) {
        printf("2 line data cmp pass\r\n");
    } else {
        printf("2 line data cmp error\r\n");
        printf("TxBuffer\r\n");
        PrintData(TxBuffer);
        printf("RxBuffer\r\n");
        PrintData(RxBuffer);
        printf("Qspi nor flash test failed...\r\n");
        return -1;
    }


    memset(RxBuffer, 0x00, TEST_BUFFER_SIZE);
    SPI_Quad();
    AlQspi_ll_SetOutputEnable(QspiHandle->Dev.BaseAddr, AL_FALSE);
    SPI_PageRead(FLASH_FastReadQuad, RxBuffer, 0xe10000);
    if (0 == CompareArrays(TxBuffer, RxBuffer, TEST_BUFFER_SIZE)) {
        printf("4 line data cmp pass\r\n");
    } else {
        printf("4 line data cmp error\r\n");
        printf("TxBuffer\r\n");
        PrintData(TxBuffer);
        printf("RxBuffer\r\n");
        PrintData(RxBuffer);
        printf("Qspi nor flash test failed...\r\n");
        return -1;
    }

    printf("Qspi nor flash test success...\r\n");

    /* tmp setting for qspi0*/
    AlQspi_ll_SetFlashEn(QspiHandle->Dev.BaseAddr, 1);
    return 0;
}
