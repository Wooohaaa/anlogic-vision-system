#include "al_core.h"
#include "al_hal.h"

#define ADS1015_ADDR 0x48
#define ADS1015_CONVERSION_REG 0x00
#define ADS1015_CONFIG_REG 0x01
#define BUF_SIZE 32

int main()
{
    AlAxiIic_HalStruct *IicHandle;
    AlAxiIic_InitStruct IicConfig = {
        .IIC_Mode = AL_AXI_IIC_MASTER, // Adjust as necessary
        .IIC_AddressMode = AL_AXI_IIC_7BIT,
        .SpeedMode = AL_AXI_IIC_STANDARD_MODE,
        .SlaveAddr = 0x48,
        .SetupTime          = 300,
        .HoldTime           = 300,
    };

    Al_AxiUartLite_HalStruct *UartHandle;
    AL_S32 Status;
    AL_U8 ConfigData[3];
    AL_U8 ConversionData[2];
    AL_U16 ConversionValue;
    AL_U8 Data[BUF_SIZE] = {0};

    // Initialize I2C
    Status = AlAxiIic_Hal_Init(&IicHandle, 0, &IicConfig, NULL);
    if (Status != 0) {
        return -1;
    }

    // Initialize UART
    Status = AlAxiUartLite_Hal_Init(&UartHandle, 0, AL_NULL);
    if (Status != 0) {
        return -1;
    }

    // Configure ADS1015 for single-ended input (AIN0) and start conversion
    ConfigData[0] = ADS1015_CONFIG_REG;
    ConfigData[1] = 0xC3; // 1100 0011: Single-shot mode, AIN0 selected, 4.096V range
    ConfigData[2] = 0x83; // 1000 0011: 1600 SPS, disable comparator

    Status = AlAxiIic_Hal_MasterSendDataPolling(IicHandle, ADS1015_ADDR, ConfigData, 3, AL_AXI_IIC_STOP);
    if (Status != 0) {
        return -1;
    }

    // Wait conversion complete (typical ~1ms at 1600 SPS)
    AlOsDelay(2);

    // Set register pointer to conversion register
    ConfigData[0] = ADS1015_CONVERSION_REG;
    Status = AlAxiIic_Hal_MasterSendDataPolling(IicHandle, ADS1015_ADDR, ConfigData, 1, AL_AXI_IIC_STOP);
    if (Status != 0) {
        return -1;
    }

    // Read conversion value (2 bytes)
    Status = AlAxiIic_Hal_MasterRecvDataPolling(IicHandle, ADS1015_ADDR, ConversionData, 2, AL_AXI_IIC_STOP);
    if (Status != 0) {
        return -1;
    }

    // Combine data bytes into a single integer
    ConversionValue = (ConversionData[0] << 8 | ConversionData[1]) >> 4;

    // Send ADC Conversion result over UART
    snprintf((char*)Data, BUF_SIZE, "ADC Value: %u\r\n", ConversionValue);
    AlAxiUartLite_Hal_SendDataPolling(UartHandle, Data, BUF_SIZE);

    return 0;
}
