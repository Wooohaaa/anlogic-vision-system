.globl crtStart
.globl main
.globl irqCallback
.globl _premain_init
.globl board_init
.globl components_init

.section	.start_jump,"ax",@progbits
crtStart:
  //long jump to allow crtInit to be anywhere
  //do it always in 12 bytes
  lui x2,       %hi(crtInit)
  addi x2, x2,  %lo(crtInit)
  jalr x1,x2
  nop


crtInit:
  .option push
  .option norelax
  fence.i
  nop
  la gp, __global_pointer$
  .option pop
  la sp, _stack_start

  //mret 
bss_init:
  la a0, _bss_start
  la a1, _bss_end
bss_loop:
  beq a0,a1,bss_done
  sw zero,0(a0)
  add a0,a0,4
  j bss_loop
bss_done:

ctors_init:
  la a0, _ctors_start
  addi sp,sp,-4
ctors_loop:
  la a1, _ctors_end
  beq a0,a1,ctors_done
  lw a3,0(a0)
  add a0,a0,4
  sw a0,0(sp)
  jalr  a3
  lw a0,0(sp)
  j ctors_loop
ctors_done:
  addi sp,sp,4

  lui a1,       %hi(trap_entry)
  addi a1, a1,  %lo(trap_entry) 
  csrw mtvec,a1 //Load trap entry address into MTVEC
  li a0, 0x888     //880 enable timer + external interrupts
  csrs mie,a0       // use set , not write
                  //here don't use same register since the data hazard happenin read and write !!!
  li t0, 0x1808     //1800 , for safe reason the MIE will be opened in main 
  csrs mstatus,t0
  
  call _premain_init
  call board_init
  // this init the al_log
  call components_init

  call main
infinitLoop:
  j infinitLoop

.section .text
.global  trap_entry
.align 5
trap_entry:
  addi sp,sp,-16*4 // here the point is first set sp avoid out boud write, aligned 32 bit not in ABI 64 bit standard
  sw x1,  0*4(sp)
  sw x5,  1*4(sp)
  sw x6,  2*4(sp)
  sw x7,  3*4(sp)
  sw x10, 4*4(sp)
  sw x11, 5*4(sp)
  sw x12, 6*4(sp)
  sw x13, 7*4(sp)
  sw x14, 8*4(sp)
  sw x15, 9*4(sp)
  sw x16, 10*4(sp)
  sw x17, 11*4(sp)
  sw x28, 12*4(sp)
  sw x29, 13*4(sp)
  sw x30, 14*4(sp)
  sw x31, 15*4(sp)
  //addi sp,sp,-16*4
  call irqCallback
  lw x1 , 0*4(sp)
  lw x5,  1*4(sp)
  lw x6,  2*4(sp)
  lw x7,  3*4(sp)
  lw x10, 4*4(sp)
  lw x11, 5*4(sp)
  lw x12, 6*4(sp)
  lw x13, 7*4(sp)
  lw x14, 8*4(sp)
  lw x15, 9*4(sp)
  lw x16, 10*4(sp)
  lw x17, 11*4(sp)
  lw x28, 12*4(sp)
  lw x29, 13*4(sp)
  lw x30, 14*4(sp)
  lw x31, 15*4(sp)
  addi sp,sp,16*4
  mret
  .text

.global board_init
.weak board_init
board_init:
    nop
    ret
