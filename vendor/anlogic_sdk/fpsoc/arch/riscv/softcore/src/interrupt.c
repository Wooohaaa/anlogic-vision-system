#include <stdint.h>
#include "soc_plat.h"
#include "al_rv32_core.h"
#include "al_intr.h"
#include "al_core.h"
#include "interrupt.h"
#include "al_softcore_systimer.h"
void DummyISP(uint32_t ISR_num);

typedef AL_VOID (*AL_INTR_Func)(AL_VOID *Param);

static AL_INTR_HandlerStruct IsrTbl[SOFTCORE_INTR_NUM];
static AL_INTR_HandlerStruct SoftHandle={DummyISP,AL_NULL};
static AL_INTR_HandlerStruct ExceptionHandle={DummyISP,AL_NULL};

void DummyISP(uint32_t ISR_num){
    //al_simp_printf("Unregistered Interrupt %d! Invoke debugger!\r\n",ISR_num);
    asm("ebreak");
}

void CLSIC_Init(AL_VOID){
	for(int i =0;i<SOFTCORE_INTR_NUM;i=i+1)
		{
			IsrTbl[i].Func=DummyISP;
			IsrTbl[i].Param=(AL_VOID *) i;
		}
}
void isrHandler(){
    uint32_t i,j,k;
      /* enter interrupt */
    j=GetIntEvent();
    k=j;
    for(i=0;i<SOFTCORE_INTR_NUM;i++)
    {
        if(j & 0x01){
            if(IsrTbl[i].Func!= AL_NULL)
                IsrTbl[i].Func(IsrTbl[i].Param);
            else{
                asm volatile("ebreak");
            }
            ClrIntEvent((1<<i)); //Assume we have dealt with input intr
        }
        j=j>>1;
        if(j==0)
            break;
    }
    /* leave interrupt */
}
int AlIntr_RegHandler(AL_U32 IntrId, AL_INTR_AttrStrct *IntrAttr, AL_INTR_Func Func, AL_VOID *Param){
  //AL_ASSERT(IntrAttr!=AL_NULL | IntrId>SOFTCORE_INTR_NUM);
  uint32_t int_mask;
  int_mask = GetIntMask();
  if (Func != AL_NULL)
  {
      IsrTbl[IntrId].Func = Func;
      IsrTbl[IntrId].Param = Param;
      int_mask = int_mask | (1 << IntrId);
      SetIntMask(int_mask); 
      return 0;
  }
  return -1;
}
uint32_t AlExceptionNested=0;
void irqCallback()
{
  uint32_t temp,current_sp;
  asm(
      "csrr %[dest] , mcause"
      :[dest]"=r"(temp)
      );  
  asm(
      "add %[dest] ,sp,x0"
      :[dest]"=r"(current_sp)
      );
    if(temp&0x80000000)
    {
      if(temp==0x80000003)
        SoftHandle.Func(SoftHandle.Param);
      else if(temp==0x80000007)//filter out timer int
        SysTimer_IntrHandler();
      else if(temp==0x8000000B)//filter out External int
        isrHandler();
    }
    else if(AlExceptionNested==0){
        AlExceptionNested=1;
        ExceptionHandle.Func(ExceptionHandle.Param);
        AlExceptionNested=0;
    }else{
        //Hang when system enters nested exception(system blowup)
        asm volatile("ebreak");
    }
};

AL_S32 AlIntr_SetInterrupt(AL_U32 IntrId, AL_FUNCTION State)
{
    AL_S32 Ret = AL_OK;
    if(IntrId > SOFTCORE_INTR_NUM)
        return AL_INTR_ERR_ILLEGAL_PARAM;
        
    uint32_t int_mask;
    int_mask = GetIntMask();
    switch (State) {
    case AL_FUNC_DISABLE:
        int_mask = int_mask & (~(1 << IntrId));
        SetIntMask(int_mask); 
        break;

    case AL_FUNC_ENABLE:
        int_mask = int_mask | (1 << IntrId);
        SetIntMask(int_mask); 
        Ret = AL_OK;
        break;

    default:
        Ret = AL_INTR_ERR_ILLEGAL_PARAM;
        break;
    }

    return Ret;
}

AL_S32 AlIntr_SetLocalInterrupt(AL_FUNCTION State)
{
    AL_S32 Ret = AL_OK;
    static AL_U32 Intr_status=0x800;
    switch (State) {
    case AL_FUNC_DISABLE:
        Intr_status=TurnOffInterrupt();
        Ret = AL_OK;
        break;

    case AL_FUNC_ENABLE:
        TurnOnInterrupt(Intr_status |0x800);
        break;

    default:
        Ret = AL_INTR_ERR_ILLEGAL_PARAM;
        break;
    }
    return Ret;
}

void SysException_RegHandler(AL_INTR_Func Func, AL_VOID *Param)
{
    ExceptionHandle.Func = Func;
    ExceptionHandle.Param = Param;
}
