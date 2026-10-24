//THIS IS JUST A TEMPLATE OF USER INTERRUPT CONTROL
//MOVE THIS FILE FROM BSP TO YOU PROJECT INCLUDE FOLDER FIRST!
/*
 * Anlogic Softcore Interrupt Controller
 * For Anlogic Softcore BSP
 * Engineer: Xiaoyu HONG
 */

#ifndef INTERRUPT_H_
#define INTERRUPT_H_
#include "soc_plat.h"
#include <stdint.h>
#include "al_rv32_core.h"
#define CLSIC_BASE 0xFFF00000
#define SIC_TRIG    *((volatile uint32_t*)(CLSIC_BASE+0x0000))
#define INT_EVENT   *((volatile uint32_t*)(CLSIC_BASE+0x2000))
#define INT_MASK    *((volatile uint32_t*)(CLSIC_BASE+0x2004))

void CLSIC_Init();
void ExceptionHandler(uint32_t *current_sp);
AL_S32 AlIntr_SetLocalInterrupt(AL_FUNCTION State);
AL_S32 AlIntr_SetInterrupt(AL_U32 IntrId, AL_FUNCTION State);
static inline void TurnOnInterrupt(uint32_t int_sel)
{
  asm volatile(
    "csrw mie, %[src]"
	:
    :[src]"r"(int_sel)
);
}
static inline uint32_t TurnOffInterrupt()
{
  uint32_t temp;
  asm volatile(
		"csrrwi %[temp],mie, 0x00000" 
    :[temp]"=r"(temp));
  return temp;
}
// todo: find CLSIC R/W hw hang problem in simulation 
 static inline  void ClrIntEvent(uint32_t data)
{
  INT_EVENT=data;
}
static inline uint32_t GetIntEvent()
{
  return INT_EVENT;
}
static inline void SetIntMask(uint32_t data)
{
  INT_MASK=data;
}
static inline uint32_t GetIntMask()
{
  return INT_MASK; 
}


#endif /* INTERRUPT_H_ */
