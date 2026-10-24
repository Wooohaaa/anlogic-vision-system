#include <stdio.h>
#include "al_i2c_hal.h"
#include "al_misc_ll.h"

#define TEST_BUFFER_SIZE            (16)

static AL_I2C_InitStruct I2CInitConfigs = {
    .WorkMode  = AL_I2C_CPU_MODE,
    .RoleMode  = AL_I2C_SLAVE_MODE,
    .ClkSpeed  = AL_I2C_STANDARD_MODE,
    .SclDuty   = AL_I2C_SCL_DUTY_50,
    .SclPull   = AL_TRUE,
    .SdaPull   = AL_TRUE,
    .SlaveAddr = 0x50,
};

AL_S32 main()
{
    printf("I2c slave polling test...\r\n");

    AL_I2C_HalStruct *I2cHandle;
    AL_S32 Ret;
    AL_U8 ReadBuffer[TEST_BUFFER_SIZE] = {0};
    AL_U32 TimeOut = 0xffffffff;

    AlMisc_ll_SetClkEn(AL_MISC_I2C, 1);
    AlMisc_ll_SetReset(AL_MISC_I2C, 0);
    AlMisc_ll_SetReset(AL_MISC_I2C, 1);

    Ret = AlI2c_Hal_Init(&I2cHandle, 0, &I2CInitConfigs, AL_NULL);
    if (Ret != AL_OK) {
        AL_LOG(AL_LOG_LEVEL_ERROR, "AlI2c_Hal_Init error\r\n");
        return Ret;
    }

    do {
        Ret = AlI2c_Hal_SlaveRecvDataPolling(I2cHandle, ReadBuffer, TEST_BUFFER_SIZE, TimeOut);
    } while (Ret != AL_OK);

    for (int i = 0; i < TEST_BUFFER_SIZE; i++) {
        printf("ReadBuffer is %#X\r\n", ReadBuffer[i]);
    }

    do {
        Ret = AlI2c_Hal_SlaveSendDataPolling(I2cHandle, ReadBuffer, TEST_BUFFER_SIZE, TimeOut);
    } while (Ret != AL_OK);

    return AL_OK;

}