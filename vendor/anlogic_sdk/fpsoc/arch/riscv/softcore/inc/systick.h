

#ifndef SYSTICK_H_
#define SYSTICK_H_

#include <stdint.h>
#define MTIME_CMPL  *((volatile uint32_t*)(CLSIC_BASE+0x4000))
#define MTIME_CNTL  *((volatile uint32_t*)(CLSIC_BASE+0xBFF8))


static inline void SetSystickCfg(uint32_t data,uint8_t enable)
{
  MTIME_CMPL=(data&0xEFFFFFFF) | ((enable!=0)<<31);
}
static inline uint32_t GetSystickCfg()
{
  return MTIME_CMPL;
}

static void ClrSystickInt()
{
  MTIME_CNTL=0x00000000;
  return;
}
#endif
