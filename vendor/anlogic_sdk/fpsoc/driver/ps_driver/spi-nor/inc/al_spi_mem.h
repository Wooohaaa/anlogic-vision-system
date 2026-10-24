#ifndef __AL_SPI_MEM_H__
#define __AL_SPI_MEM_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "al_type.h"

#define SPI_MEM_OP_CMD(__OpCode, __BusWidth)                \
    {                                                       \
        .BusWidth = __BusWidth,                             \
        .OpCode = __OpCode,                                 \
        .NumBytes = 1,                                      \
    }

#define SPI_MEM_OP_ADDR(__NumBytes, __Val, __BusWidth)      \
    {                                                       \
        .NumBytes = __NumBytes,                             \
        .Val = __Val,                                       \
        .BusWidth = __BusWidth,                             \
    }

#define SPI_MEM_OP_NO_ADDR                                  \
    {                                                       \
        .NumBytes = 0,                                      \
    }

#define SPI_MEM_OP_DUMMY(__NumCycles, __BusWidth)           \
    {                                                       \
        .NumCycles = __NumCycles,                           \
        .BusWidth = __BusWidth,                             \
    }

#define SPI_MEM_OP_NO_DUMMY                                 \
    {                                                       \
        .NumCycles = 0,                                     \
    }

#define SPI_MEM_OP_DATA_IN(__NumBytes, __Buf, __BusWidth)   \
    {                                                       \
        .Dir = AL_SPI_MEM_DIR_IN,                           \
        .NumBytes = __NumBytes,                             \
        .Buf.In = __Buf,                                    \
        .BusWidth = __BusWidth,                             \
    }

#define SPI_MEM_OP_DATA_OUT(__NumBytes, __Buf, __BusWidth)  \
    {                                                       \
        .Dir = AL_SPI_MEM_DIR_OUT,                          \
        .NumBytes = __NumBytes,                             \
        .Buf.Out = __Buf,                                   \
        .BusWidth = __BusWidth,                             \
    }

#define SPI_MEM_OP_NO_DATA                                  \
    {                                                       \
        .Dir = AL_SPI_MEM_NO_DATA,                          \
        .NumBytes = 0,                                      \
    }

#define SPI_MEM_OP(__Cmd, __Addr, __Dummy, __Data)          \
    {                                                       \
        .Cmd = __Cmd,                                       \
        .Addr = __Addr,                                     \
        .Dummy = __Dummy,                                   \
        .Data = __Data,                                     \
    }

typedef enum {
    AL_SPI_MEM_NO_DATA,
    AL_SPI_MEM_DIR_IN,
    AL_SPI_MEM_DIR_OUT,
} AlSpiMemDir;

typedef struct {
    struct {
        AL_U8 NumBytes;
        AL_U8 BusWidth;
        AL_U8 Dtr : 1;
        AL_U16 OpCode;
    } Cmd;

    struct {
        AL_U8 NumBytes;
        AL_U8 BusWidth;
        AL_U8 Dtr : 1;
        AL_U64 Val;
    } Addr;

    struct {
        AL_U8 NumCycles;
        AL_U8 BusWidth;
        AL_U8 Dtr : 1;
    } Dummy;

    struct {
        AL_U8 BusWidth;
        AL_U8 Dtr : 1;
        AlSpiMemDir Dir;
        AL_U32 NumBytes;
        union {
            void *In;
            const void *Out;
        } Buf;
    } Data;

} AlSpiMemOp;

#ifdef __cplusplus
}
#endif

#endif /* __AL_SPI_MEM_H__ */