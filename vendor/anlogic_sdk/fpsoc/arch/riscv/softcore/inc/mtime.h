


#ifndef MTIME_H_
#define MTIME_H_
#include <stdint.h>
#define MTIME_CMPL  *((volatile uint32_t*)(CLSIC_BASE+0x4000))
#define MTIME_CMPH  *((volatile uint32_t*)(CLSIC_BASE+0x4004))
#define MTIME_CNTL  *((volatile uint32_t*)(CLSIC_BASE+0xBFF8))
#define MTIME_CNTH  *((volatile uint32_t*)(CLSIC_BASE+0xBFFC))




static uint64_t GetMTimeCnt()
{
  while (1)
  {
    uint32_t hi=MTIME_CNTH;
    uint32_t lo=MTIME_CNTL;
    if(hi==MTIME_CNTH)
      return ((uint64_t) hi<<32 | lo);
  }
}

static inline uint64_t GetMTimeCmp()
{
  uint32_t hi=MTIME_CMPH;
  uint32_t lo=MTIME_CMPL;
  return ((uint64_t) hi<<32 | lo);
}
static inline void SetMTimeCmp(uint64_t value)
{
  MTIME_CMPL=0xffffffff;
  MTIME_CMPH=(uint32_t)(value >> 32);
  MTIME_CMPL=(uint32_t)value;
  return;
}

#endif

