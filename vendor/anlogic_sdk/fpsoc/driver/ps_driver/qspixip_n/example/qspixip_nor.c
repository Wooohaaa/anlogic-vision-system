#include <stdio.h>
#include <string.h>
#include "al_qspixip_hal.h"
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

#define QSPI_FLASH_BASE                           (0x20000000UL)

#define TEST_BUFFER_SIZE    4
AL_U8 TxBuffer[TEST_BUFFER_SIZE] = {0};
AL_U8 RxBuffer[TEST_BUFFER_SIZE] = {0};

AL_QSPIXIP_HalStruct *QspiXipHandle;

static AL_QSPIXIP_InitStruct QspiXipInitConfigs = {
    .SckDiv              = 16,
    .DevMode             = AL_QSPIXIP_MASTER,
    .ProtocolMode        = AL_QSPIXIP_PROTOCOL_MODE_SINGLE,
    .FrameLen            = AL_QSPIXIP_FRAMELEN_8BIT,
    .CSMode              = AL_QSPIXIP_CS_MODE_AUTO,
    .CPOL                = AL_QSPIXIP_CLK_LOW_LEVLE,
    .CPHA                = AL_QSPIXIP_CLK_EDGE1,
    .Endian              = AL_QSPIXIP_ENDIAN_MSB,
    .DmaModeEn           = AL_FALSE,
    .TxDmaEn             = AL_FALSE,
    .RxDmaEn             = AL_FALSE,
    .TxDmaContinousEn    = AL_FALSE,
    .RxDmaContinousEn    = AL_FALSE,
};

static AL_QSPIXIP_RxStruct QspiXipRxConfig = {
    .CmdEn      = AL_TRUE,
    .AddLen     = 3,
    .PadCnt     = 8,
    .CmdProto   = AL_QSPIXIP_PROTOCOL_MODE_SINGLE,
    .AddrProto  = AL_QSPIXIP_PROTOCOL_MODE_SINGLE,
    .DataProto  = AL_QSPIXIP_PROTOCOL_MODE_SINGLE,  /* Select data transfer protocol */
    .Endina     = AL_QSPIXIP_ENDIAN_MSB,
    .CmdCode    = 0x00,    /* Must be set as a valid instruction  */
    .PadCode    = 0x00,
};

static AL_QSPIXIP_TxStruct QspiXipTxConfig = {
    .QspiXipRxCfg.CmdEn     = 1,
    .QspiXipRxCfg.AddLen    = 3,
    .QspiXipRxCfg.PadCnt    = 0,  /* ??? */
    .QspiXipRxCfg.CmdProto  = AL_QSPIXIP_PROTOCOL_MODE_SINGLE,
    .QspiXipRxCfg.AddrProto = AL_QSPIXIP_PROTOCOL_MODE_SINGLE,
    .QspiXipRxCfg.DataProto = AL_QSPIXIP_PROTOCOL_MODE_SINGLE, /* Select data transfer protocol */
    .QspiXipRxCfg.Endina    = AL_QSPIXIP_ENDIAN_MSB,
    .QspiXipRxCfg.CmdCode   = 0x03,
    .QspiXipRxCfg.PadCode   = 0x00,
    .WcmdCode   = 0x00,     /* Must be set as a valid instruction  */
    .WpadCnt    = 0,
    .PadCntH    = 0,
    .DdrEn      = 0,
    .ModeProto  = AL_QSPIXIP_PROTOCOL_MODE_SINGLE,
    .ModeCode   = 0,
    .ModeCnt    = 0,
};

AL_VOID SPI_ReadJEDEC(AL_VOID) {
    AL_U8 Cmd = FLASH_JedecDeviceID;
    AL_U32 JedecDeviceID[3] = {0};

    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_HOLD);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, &Cmd, 1);
    AlQspiXip_Hal_RecvDataPolling(QspiXipHandle, JedecDeviceID, 3);
    for (AL_U32 i = 0; i < 3; i++) {
        printf("JedecDeviceID[%d]:%#x\r\n", i, (JedecDeviceID[i] & 0xff));
    }

    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_OFF);
}

AL_VOID SPI_Wip(AL_VOID)
{
    AL_U8 Cmd = FLASH_ReadStatusReg1;
    AL_U32 RecvData;
    AL_U32 temp = 0;

    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_HOLD);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, &Cmd, 1);
    do {
        AlQspiXip_Hal_RecvDataPolling(QspiXipHandle, &RecvData, 1);
        temp = RecvData & WIP_Flag;
    } while (temp);
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_OFF);
}

AL_VOID SPI_WriteEnable(AL_VOID)
{
    AL_U8 Cmd = FLASH_WriteEnable;

    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_HOLD);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, &Cmd, 1);
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_OFF);
}

AL_VOID SPI_Quad(AL_VOID)
{
    AL_U8 Cmd = FLASH_WriteStatusReg2;
    AL_U8 Temp = 0x2;
    SPI_WriteEnable();
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_HOLD);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, &Cmd, 1);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, &Temp, 1);
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_OFF);
    SPI_Wip();
}

AL_VOID SPI_Erase(AL_U8 Cmd, AL_U32 Addr)
{
    AL_U32 SendData[4] = {(Cmd & 0xff),((Addr >> 16) & 0xff), ((Addr >> 8) & 0xff), (Addr & 0xff)};
    SPI_WriteEnable();
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_HOLD);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, SendData, 4);
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_OFF);
    SPI_Wip();
}

AL_VOID SPI_PageWrite(AL_U8 Cmd, AL_U32* Buf, AL_U32 Addr)
{
    AL_U32 SendData[4] = {(Cmd & 0xff),((Addr >> 16) & 0xff), ((Addr >> 8) & 0xff), (Addr & 0xff)};
    SPI_WriteEnable();
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_HOLD);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, SendData, 4);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, Buf, 256);
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_OFF);
    SPI_Wip();
}

AL_VOID SPI_PageRead(AL_U8 Cmd, AL_U32* Buf, AL_U32 Addr)
{
    AL_U32 SendData[4] = {(Cmd & 0xff),((Addr >> 16) & 0xff), ((Addr >> 8) & 0xff), (Addr & 0xff)};
    AL_U8 DummyByte = Dummy_Byte;
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_HOLD);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, SendData, 4);
    AlQspiXip_Hal_SendDataPolling(QspiXipHandle, &DummyByte, 1);
    if (Cmd == FLASH_FastReadDual) {
        AlQspiXip_ll_SetProtocolMode(QspiXipHandle->Dev.BaseAddr, AL_QSPIXIP_PROTOCOL_MODE_DUAL);
    }
    if (Cmd == FLASH_FastReadQuad) {
        AlQspiXip_ll_SetProtocolMode(QspiXipHandle->Dev.BaseAddr, AL_QSPIXIP_PROTOCOL_MODE_QUAD);
    }
    AlQspiXip_Hal_RecvDataPolling(QspiXipHandle, Buf, 4);
    AlQspiXip_Hal_SetCsMode(QspiXipHandle, AL_QSPIXIP_CS_MODE_OFF);
}

AL_VOID PrintData(AL_U32* Data)
{
    for (AL_U32 i = 0; i < 10; i++) {
        printf("%#x\r\n", (Data[i] & 0xff));
    }
}

AL_U32 CompareArrays(AL_U8* Array1, AL_U8* Array2, AL_U32 size) {
    for (AL_U32 i = 0; i < size; i++) {
        if (Array1[i] != Array2[i]) {
            return -1;
        }
    }
    return 0;
}

AL_S32 main()
{
    printf("QspiXip nor flash test ...\r\n");

    for (AL_U32 i = 0; i < TEST_BUFFER_SIZE; i++) {
        TxBuffer[i] = 'A' + i;
    }

    AlMisc_ll_SetClkEn(AL_MISC_QSPIXIP0, 1);
    AlMisc_ll_SetReset(AL_MISC_QSPIXIP0, 0);
    AlMisc_ll_SetReset(AL_MISC_QSPIXIP0, 1);

    AL_S32 Ret = AlQspiXip_Hal_Init(&QspiXipHandle, 0, &QspiXipInitConfigs, AL_NULL);
    if (Ret != AL_OK) {
        printf("AlQspiXip_Hal_Init error\r\n");
        return Ret;
    }

    AlQspiXip_Hal_EnableXip(QspiXipHandle, AL_FALSE);

    SPI_ReadJEDEC();

    AlQspiXip_ll_SetOutputEnable(QspiXipHandle->Dev.BaseAddr, 1);
    AlQspiXip_ll_SetWriteProtect(QspiXipHandle->Dev.BaseAddr, 1);

    SPI_Erase(FLASH_SectorErase, 0x0);

    SPI_WriteEnable();
    QspiXipTxConfig.WcmdCode = FLASH_PageProgram;
    AlQspiXip_Hal_SetXipTxCfg(QspiXipHandle, QspiXipTxConfig);
    AlQspiXip_Hal_EnableXip(QspiXipHandle, AL_TRUE);
    memcpy((AL_VOID*)QSPI_FLASH_BASE, TxBuffer, TEST_BUFFER_SIZE);
    AlQspiXip_Hal_EnableXip(QspiXipHandle, AL_FALSE);
    SPI_Wip();

    QspiXipRxConfig.CmdCode = FLASH_FastReadData;
    AlQspiXip_Hal_SetXipRxCfg(QspiXipHandle, QspiXipRxConfig);
    AlQspiXip_Hal_EnableXip(QspiXipHandle, AL_TRUE);
    memcpy(RxBuffer, (AL_VOID*)QSPI_FLASH_BASE, TEST_BUFFER_SIZE);

    if (0 == CompareArrays(TxBuffer, RxBuffer, TEST_BUFFER_SIZE)) {
        printf("1 line XIP read data cmp pass\r\n");
    } else {
        printf("1 line XIP read data cmp error\r\n");
        printf("TxBuffer\r\n");
        PrintData(TxBuffer);
        printf("RxBuffer\r\n");
        PrintData(RxBuffer);
        while (1) {}
    }


    memset(RxBuffer, 0x00, TEST_BUFFER_SIZE);
    QspiXipRxConfig.CmdCode = FLASH_FastReadDual;
    QspiXipRxConfig.DataProto = AL_QSPIXIP_PROTOCOL_MODE_DUAL;
    AlQspiXip_Hal_SetXipRxCfg(QspiXipHandle, QspiXipRxConfig);
    memcpy(RxBuffer, (AL_VOID*)QSPI_FLASH_BASE, TEST_BUFFER_SIZE);
    if (0 == CompareArrays(TxBuffer, RxBuffer, TEST_BUFFER_SIZE)) {
        printf("2 line XIP read data cmp pass\r\n");
    } else {
        printf("2 line XIP read data cmp error\r\n");
        printf("TxBuffer\r\n");
        PrintData(TxBuffer);
        printf("RxBuffer\r\n");
        PrintData(RxBuffer);
        while (1) {}
    }

    AlQspiXip_Hal_EnableXip(QspiXipHandle, AL_FALSE);
    SPI_Quad();
    AlQspiXip_ll_SetOutputEnable(QspiXipHandle->Dev.BaseAddr, 0);
    memset(RxBuffer, 0x00, TEST_BUFFER_SIZE);
    QspiXipRxConfig.CmdCode = FLASH_FastReadQuad;
    QspiXipRxConfig.DataProto = AL_QSPIXIP_PROTOCOL_MODE_QUAD;
    AlQspiXip_Hal_SetXipRxCfg(QspiXipHandle, QspiXipRxConfig);
    AlQspiXip_Hal_EnableXip(QspiXipHandle, AL_TRUE);
    memcpy(RxBuffer, (AL_VOID*)QSPI_FLASH_BASE, TEST_BUFFER_SIZE);
    if (0 == CompareArrays(TxBuffer, RxBuffer, TEST_BUFFER_SIZE)) {
        printf("4 line XIP read data cmp pass\r\n");
    } else {
        printf("4 line XIP read data cmp error\r\n");
        printf("TxBuffer\r\n");
        PrintData(TxBuffer);
        printf("RxBuffer\r\n");
        PrintData(RxBuffer);
        while (1) {}
    }

    return 0;
}