#ifndef __AL_SPI_CONTROLLER_H__
#define __AL_SPI_CONTROLLER_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "al_core.h"
#include "al_spi_mem.h"
#include "al_spi_nor.h"

#define AL_CONTROLLER_PS_QSPI        0
#define AL_CONTROLLER_PS_SPI         1
#define AL_CONTROLLER_PL_QSPI        2


#define AL_SPI_CONTROLLER_DUAL              BIT(0)
#define AL_SPI_CONTROLLER_QUAD              BIT(1)

typedef AL_S32 (*SpiNorInitOp)(AL_VOID *);
typedef AL_S32 (*SpiNorExecOp)(AL_VOID *, const AlSpiMemOp *);
typedef AL_S32 (*SpiNorSetCs)(AL_VOID *, AL_U32);

typedef struct {
    const AL_U32 ControllerType;
    const AL_U32 DevId;
    AL_U32 Flags;
    AL_VOID *HalHandle;
    SpiNorInitOp Init;
    SpiNorExecOp ExecOp;
    SpiNorSetCs  SetCs;
} AlSpiController;

#ifdef __cplusplus
}
#endif

#endif /* __AL_SPI_CONTROLLER_H__ */
